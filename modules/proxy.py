#!/usr/bin/env python3
# DUCKY Built-in Lightweight SOCKS5 / HTTP Proxy (binds ONLY to 127.0.0.1 & tunnel IPs — never public IP)
import os, sys, json, socket, select, struct, threading, base64

VAULT = os.environ.get("DUCKY_VAULT", "/etc/.ducky-vault")
CFGF = os.path.join(VAULT, "proxy.dkcfg")

def load_cfg():
    try: return json.load(open(CFGF))
    except Exception: return {"port": 10800, "user": "", "pass": "", "bind": "127.0.0.1"}

def relay(a, b):
    try:
        while True:
            r, _, _ = select.select([a, b], [], [], 60)
            if not r: break
            for s in r:
                d = s.recv(16384)
                if not d: return
                (b if s is a else a).sendall(d)
    except Exception:
        pass
    finally:
        for s in (a, b):
            try: s.close()
            except Exception: pass

def handle(conn, cfg):
    try:
        first = conn.recv(2)
        if not first: conn.close(); return
        u_req, p_req = cfg.get("user", ""), cfg.get("pass", "")
        if first[0] == 5:  # SOCKS5
            nmethods = first[1]
            methods = conn.recv(nmethods)
            if u_req and p_req:
                if 2 not in methods: conn.sendall(b"\x05\xff"); conn.close(); return
                conn.sendall(b"\x05\x02")
                ver = conn.recv(1)
                ul = conn.recv(1)[0]; user = conn.recv(ul).decode(errors="ignore")
                pl = conn.recv(1)[0]; pw = conn.recv(pl).decode(errors="ignore")
                if user != u_req or pw != p_req: conn.sendall(b"\x01\x01"); conn.close(); return
                conn.sendall(b"\x01\x00")
            else:
                conn.sendall(b"\x05\x00")
            hdr = conn.recv(4)
            if len(hdr) < 4 or hdr[1] != 1: conn.close(); return
            atyp = hdr[3]
            if atyp == 1: addr = socket.inet_ntoa(conn.recv(4))
            elif atyp == 3: al = conn.recv(1)[0]; addr = conn.recv(al).decode()
            elif atyp == 4: addr = socket.inet_ntop(socket.AF_INET6, conn.recv(16))
            else: conn.close(); return
            port = struct.unpack("!H", conn.recv(2))[0]
            rem = socket.create_connection((addr, port), timeout=10)
            conn.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
            relay(conn, rem)
        else:  # HTTP CONNECT
            rest = conn.recv(4096)
            data = (first + rest).decode(errors="ignore")
            lines = data.splitlines()
            if not lines or not lines[0].startswith("CONNECT "): conn.close(); return
            if u_req and p_req:
                want = "Basic " + base64.b64encode(f"{u_req}:{p_req}".encode()).decode()
                if not any(l.lower().startswith("proxy-authorization:") and want in l for l in lines):
                    conn.sendall(b"HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic\r\n\r\n")
                    conn.close(); return
            target = lines[0].split()[1]
            host, port = target.rsplit(":", 1)
            rem = socket.create_connection((host.strip("[]"), int(port)), timeout=10)
            conn.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            relay(conn, rem)
    except Exception:
        try: conn.close()
        except Exception: pass

def main():
    cfg = load_cfg()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((cfg.get("bind", "127.0.0.1"), int(cfg.get("port", 10800))))
    s.listen(256)
    while True:
        c, _ = s.accept()
        threading.Thread(target=handle, args=(c, cfg), daemon=True).start()

if __name__ == "__main__":
    main()
