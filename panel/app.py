#!/usr/bin/env python3
# DUCKY Luxury Minimalist Web Panel v1.0 (Obsidian Black • Pure White • Electric Yellow)
import os, sys, json, hashlib, hmac, secrets, subprocess, time, re, string, urllib.parse, csv, io
VAULT = os.environ.get("DUCKY_VAULT", "/etc/.ducky-vault")
CFGF = os.path.join(VAULT, "panel.dkcfg")
BIN = os.environ.get("DUCKY_BIN", "/usr/local/bin/ducky")

def load():
    try: return json.load(open(CFGF))
    except Exception: return {}

def save(c):
    os.makedirs(VAULT, exist_ok=True)
    json.dump(c, open(CFGF, "w"), indent=2)
    os.chmod(CFGF, 0o600)

def phash(p, salt=None):
    salt = salt or secrets.token_hex(8)
    return salt + "$" + hashlib.pbkdf2_hmac("sha256", p.encode(), salt.encode(), 200000).hex()

def pcheck(p, h):
    try: return hmac.compare_digest(phash(p, h.split("$")[0]), h)
    except Exception: return False

def url(ip):
    c = load(); ssl = bool(c.get("cert"))
    bp = c.get("basepath", "").strip("/")
    suf = f"/{bp}/" if bp else "/"
    return "%s://%s:%s%s" % ("https" if ssl else "http", c.get("domain") or ip, c.get("port", 8443), suf)

if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] in ("set", "url", "get"):
    if sys.argv[1] == "get": print(load().get(sys.argv[2], "")); sys.exit(0)
    if sys.argv[1] == "url": print(url(sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1")); sys.exit(0)
    c = load()
    for kv in sys.argv[2:]:
        if "=" not in kv: continue
        k, v = kv.split("=", 1)
        if k == "pass": c["pass"] = phash(v)
        elif k in ("port", "user", "domain", "cert", "key", "basepath", "apikey", "title", "tg_token", "tg_chat", "allow_ips"):
            c[k] = int(v) if k == "port" else v
    c.setdefault("secret", secrets.token_hex(32))
    c.setdefault("apikey", secrets.token_hex(16))
    c.setdefault("title", "DUCKY-NODE")
    save(c); sys.exit(0)

import glob, shutil, socket, threading
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from flask import Flask, request, session, redirect, render_template_string, abort, jsonify, send_file, Response

app = Flask(__name__)
_c = load()
app.secret_key = _c.get("secret", secrets.token_hex(32))
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax", SESSION_COOKIE_SECURE=bool(_c.get("cert")))

FAILS, AUDIT = {}, deque(maxlen=40)
MESH = os.path.join(VAULT, "mesh")
KERNEL = {"gre", "gre-key", "gretap", "ipip", "6to4-sit", "6to4-gre", "gre6", "gre6tap", "ipip6", "gre-fou", "gre-gue", "gretap-fou", "ipip-fou", "vxlan", "geneve", "wg", "wg-psk", "wg-1320", "wg-1280"}

def ducky(*a, t=300):
    try: return subprocess.run(["bash", BIN, "api", *map(str, a)], capture_output=True, text=True, timeout=t).stdout.strip()
    except Exception as e: return "ERR " + str(e)

def sh(*a, t=6):
    try: return subprocess.run(list(a), capture_output=True, text=True, timeout=t).stdout
    except Exception: return ""

def sys_metrics():
    try:
        cores = os.cpu_count() or 1
        load_avg = float(open("/proc/loadavg").read().split()[0])
        cpu_pct = min(100.0, round(load_avg * 100.0 / max(1, cores), 1))
        mt = ma = 0
        for l in open("/proc/meminfo"):
            if l.startswith("MemTotal:"): mt = int(l.split()[1]) // 1024
            elif l.startswith("MemAvailable:"): ma = int(l.split()[1]) // 1024
        mu = max(0, mt - ma)
        bbr = "bbr" in (open("/proc/sys/net/ipv4/tcp_congestion_control").read().strip().lower() if os.path.exists("/proc/sys/net/ipv4/tcp_congestion_control") else "")
        wd = sh("systemctl", "is-active", "dky-sentinel").strip() == "active"
        bot = sh("systemctl", "is-active", "dky-tgbot").strip() == "active"
        return {"cores": cores, "cpu_pct": cpu_pct, "ram_used": mu, "ram_total": mt, "ram_pct": round(mu * 100.0 / max(1, mt), 1), "bbr": bbr, "sentinel": wd, "bot": bot}
    except Exception:
        return {"cores": 2, "cpu_pct": 0, "ram_used": 0, "ram_total": 0, "ram_pct": 0, "bbr": False, "sentinel": False, "bot": False}

def csrf():
    if "t" not in session: session["t"] = secrets.token_hex(16)
    return session["t"]

def nconf(name):
    d = {"NOTE": "", "TMTU": "", "PEER": "", "BACKUP_NODE": "", "QUOTA_GB": "0", "EDGE_IP": "", "POOL": ""}
    try:
        for l in open(os.path.join(MESH, name + ".dknode")):
            if "=" in l: k, v = l.rstrip("\n").split("=", 1); d[k] = v.strip('"')
    except Exception: return None
    return d if "NAME" in d else None

def nlist(): return [c for c in (nconf(os.path.basename(f)[:-7]) for f in sorted(glob.glob(MESH + "/*.dknode"))) if c]
def svc(n): return sh("systemctl", "is-active", "dky-mesh-" + n).strip() or "unknown"
def default_nic():
    m = sh("ip", "route", "show", "default").split()
    return m[m.index("dev") + 1] if "dev" in m else "eth0"

def counters(c):
    i = "dky" + c.get("IDX", "0")
    if c["TYPE"] in KERNEL and os.path.exists("/sys/class/net/" + i):
        try: return int(open(f"/sys/class/net/{i}/statistics/rx_bytes").read()), int(open(f"/sys/class/net/{i}/statistics/tx_bytes").read())
        except Exception: pass
    nic = default_nic()
    try: return int(open(f"/sys/class/net/{nic}/statistics/rx_bytes").read()), int(open(f"/sys/class/net/{nic}/statistics/tx_bytes").read())
    except Exception: return 0, 0

def peer_ip(c): return ("10.88.%s.%s" % (c["IDX"], 2 if c["ROLE"] == "iran" else 1)) if c["TYPE"] in KERNEL else c["REMOTE"]
def ping(ip, n=1):
    o = sh("ping", "-c", str(n), "-W", "1", "-n", "-q" if n > 1 else "-n", ip, t=n * 2 + 3)
    m = re.search(r"= [\d.]+/([\d.]+)/", o) or re.search(r"time=([\d.]+)", o)
    l = re.search(r"([\d.]+)% packet loss", o)
    return (float(m.group(1)) if m else None), (float(l.group(1)) if l else (0.0 if m else 100.0))

HIST, LAST = {}, {}
def sampler():
    while True:
        t0 = time.time()
        try:
            nl = nlist()
            def probe(c): return ping(peer_ip(c))[0] if svc(c["NAME"]) == "active" else None
            with ThreadPoolExecutor(6) as ex: rtts = list(ex.map(probe, nl))
            for c, rtt in zip(nl, rtts):
                n = c["NAME"]; rx, tx = counters(c); now = time.time(); up = down = 0.0
                if n in LAST and now > LAST[n][0] and rx >= LAST[n][1]:
                    dt = now - LAST[n][0]; down = (rx - LAST[n][1]) / dt; up = (tx - LAST[n][2]) / dt
                LAST[n] = (now, rx, tx)
                HIST.setdefault(n, deque(maxlen=120)).append(dict(t=now, rtt=rtt, up=up, down=down, on=svc(n) == "active", tot=rx+tx))
        except Exception: pass
        time.sleep(max(0.5, 2.0 - (time.time() - t0)))
threading.Thread(target=sampler, daemon=True).start()

def live_payload(name="all"):
    nl = nlist() if name == "all" else [c for c in [nconf(name)] if c]
    sysm = sys_metrics()
    series = {"up": [], "down": [], "rtt": []}
    L = max([len(HIST.get(c["NAME"], [])) for c in nl] + [0])
    for k in range(L):
        u = d = 0.0; rs = []
        for c in nl:
            h = list(HIST.get(c["NAME"], []))
            if len(h) - L + k < 0: continue
            p = h[len(h) - L + k]; u += p["up"]; d += p["down"]
            if p["rtt"] is not None: rs.append(p["rtt"])
        series["up"].append(u); series["down"].append(d); series["rtt"].append(round(sum(rs)/len(rs), 1) if rs else None)
    nodes_out = []
    tu = td = 0; ok_cnt = 0
    for c in nl:
        h = HIST.get(c["NAME"]); rtt = h[-1]["rtt"] if h else None
        rx, tx = counters(c); td += rx; tu += tx
        on = svc(c["NAME"]) == "active"
        if on: ok_cnt += 1
        nodes_out.append({
            "name": c["NAME"], "type": c["TYPE"], "role": c["ROLE"], "remote": c["REMOTE"],
            "ports": c["PORTS"], "backup": c.get("BACKUP_NODE", ""), "note": c.get("NOTE", ""),
            "on": on, "rtt": rtt, "spd": round(((h[-1]["up"] + h[-1]["down"]) / 1048576) if h else 0, 2),
            "tot": rx + tx
        })
    stab = round(100.0 * ok_cnt / max(1, len(nl)), 1) if nl else 100.0
    cur_up = series["up"][-1] if series["up"] else 0.0
    cur_dn = series["down"][-1] if series["down"] else 0.0
    return {"sys": sysm, "nodes": nodes_out, "up": cur_up, "down": cur_dn, "tot": tu + td, "stab": stab, "series": series, "ip": ducky("ip")}

@app.before_request
def guard():
    if request.endpoint in ("login", "static", "api_v1_status", "secret_entry"): return
    if not session.get("u"): return redirect("/login")
    if request.method == "POST" and not hmac.compare_digest(request.form.get("t", ""), session.get("t", "x")): abort(400)

app.jinja_env.globals.update(csrf=csrf)
app.jinja_env.globals["LOGO"] = "data:image/png;base64,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"

CSS = """
:root{
  --bg:#09090C;--bg2:#0E0E13;--card:#121218;--card2:#181822;--tx:#FFFFFF;--tx2:#9A9AA8;--tx3:#5E5E6E;
  --yl:#FFD600;--yl2:#FACC15;--yl-glow:rgba(255,214,0,0.22);--bd:rgba(255,255,255,0.08);--bd2:rgba(255,255,255,0.14);--ok:#22C55E;
}
html[data-theme="light"]{
  --bg:#F7F7F9;--bg2:#FFFFFF;--card:#FFFFFF;--card2:#F1F1F5;--tx:#09090C;--tx2:#525260;--tx3:#868696;
  --yl:#EAB308;--yl2:#CA8A04;--yl-glow:rgba(234,179,8,0.18);--bd:#E5E5EC;--bd2:#D4D4DF;--ok:#16A34A;
}
*{box-sizing:border-box}
body{margin:0;font:14px/1.55 "Inter",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--tx);overflow-x:hidden}
a{color:inherit;text-decoration:none}
.mono{font-family:ui-monospace,"JetBrains Mono",Menlo,Consolas,monospace}
.shell{display:grid;grid-template-columns:236px 1fr;min-height:100vh}
.rail{background:#07070A;color:#fff;padding:24px 16px;display:flex;flex-direction:column;gap:18px;position:sticky;top:0;height:100vh;border-right:1px solid var(--bd)}
.brand{display:flex;align-items:center;gap:12px;padding:2px 6px 16px;border-bottom:1px solid var(--bd)}
.brand img{width:40px;height:40px;border-radius:11px;border:1.5px solid var(--yl);box-shadow:0 0 18px var(--yl-glow)}
.brand b{font-size:20px;letter-spacing:2px;font-weight:800}.brand b em{color:var(--yl);font-style:normal}
.rail nav{display:flex;flex-direction:column;gap:4px}
.rail nav a{display:flex;align-items:center;gap:11px;padding:10px 14px;border-radius:12px;color:#9A9AA8;font-weight:500;transition:all .16s;border:1px solid transparent}
.rail nav a:hover{background:#121218;color:#fff}
.rail nav a.on{background:rgba(255,214,0,0.12);color:var(--yl);border-color:rgba(255,214,0,0.32);font-weight:600}
.rail .sp{flex:1}
main{padding:24px 36px 48px;max-width:1480px;width:100%;margin:0 auto}
.topbar{display:flex;justify-content:space-between;align-items:center;gap:14px;flex-wrap:wrap;padding:12px 18px;background:var(--card);border:1px solid var(--bd);border-radius:16px;margin-bottom:22px}
.pills{display:flex;gap:8px;flex-wrap:wrap}
.pill{display:inline-flex;align-items:center;gap:7px;padding:5px 12px;background:var(--card2);border:1px solid var(--bd);border-radius:99px;font-size:12px;font-weight:600;color:var(--tx2)}
.dot{width:7px;height:7px;border-radius:50%;background:var(--yl);box-shadow:0 0 8px var(--yl)}.dot.ok{background:var(--ok);box-shadow:0 0 8px var(--ok)}.dot.off{background:var(--tx3);box-shadow:none}
.card{background:var(--card);border:1px solid var(--bd);border-radius:20px;padding:22px;margin-bottom:18px}
.hero-flow{padding:24px;position:relative;overflow:hidden;background:radial-gradient(circle at 50% 45%,rgba(255,214,0,0.08),transparent 60%),var(--card)}
.hero-flow svg{width:100%;height:260px;display:block}
.flow-y{stroke:var(--yl);stroke-width:2.5;fill:none;stroke-dasharray:12 16;animation:fl 1.6s linear infinite;filter:drop-shadow(0 0 6px var(--yl))}
.flow-w{stroke:#FFFFFF;stroke-width:2;fill:none;stroke-dasharray:10 18;animation:fl 2.2s linear infinite;opacity:.85}
@keyframes fl{to{stroke-dashoffset:-56}}
.bento{display:grid;grid-template-columns:1.55fr repeat(3,1fr);gap:16px}
.kpi{background:var(--card);border:1px solid var(--bd);border-radius:20px;padding:20px 14px;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center}
.ring{position:relative;width:110px;height:110px}.ring svg{width:110px;height:110px;transform:rotate(-90deg)}.ring circle{fill:none;stroke-width:6}
.ring .tr{stroke:rgba(255,255,255,0.08)}.ring .fg{stroke:var(--yl);stroke-linecap:round;stroke-dasharray:290;stroke-dashoffset:65;transition:stroke-dashoffset .8s}
.ring .v{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:18px}
.kpi .lbl{margin-top:12px;font-size:20px;font-weight:700}.kpi .sub{font-size:12.5px;color:var(--tx2);margin-top:2px}
canvas{width:100%;height:175px;display:block}
.btn{font:600 13.5px/1.2 inherit;cursor:pointer;border:1px solid var(--bd2);background:var(--card2);color:var(--tx);padding:9px 15px;border-radius:11px;transition:all .15s;display:inline-flex;gap:7px;align-items:center}
.btn:hover{border-color:var(--yl);color:var(--yl)}
.btn.yel{background:var(--yl);border-color:var(--yl);color:#09090C;box-shadow:0 6px 22px var(--yl-glow);font-weight:700}
.btn.yel:hover{background:#FFE033;color:#09090C}
.btn.sm{padding:6px 11px;font-size:12.5px;border-radius:9px}
.row{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px}
label{display:block;font-size:12px;font-weight:600;color:var(--tx2);margin-bottom:6px;text-transform:uppercase;letter-spacing:.4px}
input,select,textarea{width:100%;font:inherit;padding:11px 13px;border:1px solid var(--bd2);border-radius:11px;background:var(--bg2);color:var(--tx)}
input:focus,select:focus,textarea:focus{outline:none;border-color:var(--yl);box-shadow:0 0 0 3px var(--yl-glow)}
table{width:100%;border-collapse:collapse}
th{text-align:left;font-size:11.5px;color:var(--tx2);text-transform:uppercase;padding:12px 10px;border-bottom:1px solid var(--bd2)}
td{padding:13px 10px;border-bottom:1px solid var(--bd)}
.note{border-left:3px solid var(--yl);padding:12px 16px;background:rgba(255,214,0,0.08);border-radius:12px;margin-bottom:18px;font-weight:500}

/* Right-Side Frosted Glass Persian Aquarium Drawer */
.aq-bg{position:fixed;inset:0;background:rgba(0,0,0,.45);display:none;z-index:90}
.aquarium{position:fixed;top:14px;right:-480px;bottom:14px;width:440px;max-width:92vw;z-index:100;
  background:rgba(14,14,20,0.72);backdrop-filter:blur(26px);-webkit-backdrop-filter:blur(26px);
  border:1.5px solid rgba(255,214,0,0.55);border-radius:22px;box-shadow:-12px 0 50px rgba(0,0,0,.65),0 0 32px rgba(255,214,0,0.14);
  display:flex;flex-direction:column;transition:right .38s cubic-bezier(.2,.8,.2,1);direction:rtl;font-family:Vazirmatn,Tahoma,system-ui,sans-serif}
.aquarium.open{right:14px}
.aq-hdr{padding:18px 20px;border-bottom:1px solid rgba(255,255,255,0.09);display:flex;justify-content:space-between;align-items:center}
.aq-hdr b{font-size:15.5px;color:#fff}.aq-live{padding:3px 10px;border-radius:99px;background:rgba(255,214,0,0.16);color:var(--yl);font-size:11.5px;font-weight:700}
.aq-body{flex:1;overflow-y:auto;padding:16px 18px;display:flex;flex-direction:column;gap:10px}
.aq-item{padding:10px 13px;border-radius:12px;background:rgba(255,255,255,0.04);border:1px solid rgba(255,255,255,0.07);font-size:13px;line-height:1.7;animation:fadeUp .25s ease}
.aq-item.code{direction:ltr;text-align:left;font-family:ui-monospace,Consolas,monospace;font-size:11.5px;color:var(--yl);background:rgba(0,0,0,0.55);border-color:rgba(255,214,0,0.22)}
.aq-item.ok{border-right:3px solid var(--ok);color:#e6ffed}
.aq-item.fail{border-right:3px solid #f59e0b;color:#fef3c7}
.aq-ftr{padding:14px 18px;border-top:1px solid rgba(255,255,255,0.08);display:flex;flex-direction:column;gap:10px}
.aq-bar{height:5px;background:rgba(255,255,255,0.08);border-radius:99px;overflow:hidden}
.aq-bar i{display:block;height:100%;width:15%;background:linear-gradient(90deg,var(--yl),#fff);transition:width .4s}
@keyframes fadeUp{from{opacity:0;transform:translateY(6px)}to{opacity:1;transform:none}}
@media(max-width:960px){.shell{grid-template-columns:1fr}.rail{position:static;height:auto;flex-direction:row;flex-wrap:wrap}.bento{grid-template-columns:1fr}}
"""

BASE = """<!doctype html><html lang="en" data-theme="dark"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>DUCKY TUNNEL — {{title}}</title><link rel="icon" href="{{LOGO}}">
<link href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css" rel="stylesheet">
<style>""" + CSS + """</style>
<script>
(function(){document.documentElement.setAttribute('data-theme',localStorage.getItem('dky_theme')||'dark')})();
function flipTheme(){const h=document.documentElement,n=h.getAttribute('data-theme')==='light'?'dark':'light';h.setAttribute('data-theme',n);localStorage.setItem('dky_theme',n)}
</script></head><body><div class="shell">
<aside class="rail">
  <div class="brand"><img src="{{LOGO}}" alt="DUCKY"><div><b>DUCK<em>Y</em></b><div class="mono" style="font-size:11px;color:#787888">{{title}}</div></div></div>
  <nav>
    <a href="/" class="{{'on' if page=='dash'}}">◈ Overview</a>
    <a href="/tun" class="{{'on' if page=='tun'}}">⇄ Tunnels</a>
    <a href="/new" class="{{'on' if page=='new'}}">＋ Create Tunnel</a>
    <a href="/tools" class="{{'on' if page=='tools'}}">⚡ Debugger & Kernel</a>
    <a href="/set" class="{{'on' if page=='set'}}">⚙ Settings & Bot</a>
  </nav>
  <div class="sp"></div>
  <button type="button" class="btn sm" onclick="flipTheme()" style="width:100%;justify-content:center">◐ Dark / White</button>
  <a class="btn sm" href="https://t.me/Em4dloverS" target="_blank" style="width:100%;justify-content:center">✈ t.me/Em4dloverS</a>
  <form method="post" action="/logout"><input type="hidden" name="t" value="{{csrf()}}"><button class="btn sm" style="width:100%;justify-content:center;color:#9A9AA8">Sign out</button></form>
</aside>
<main>
  <div class="topbar">
    <div style="font-weight:700;font-size:16px;letter-spacing:.5px">DUCKY <span style="color:var(--yl)">TUNNEL</span></div>
    <div class="pills">
      <span class="pill"><span class="dot"></span>CPU <b id="tb_cpu" style="color:var(--tx)">-</b></span>
      <span class="pill">RAM <b id="tb_ram" style="color:var(--tx)">-</b></span>
      <span class="pill"><span class="dot ok" id="tb_bbr_d"></span>BBR <b id="tb_bbr" style="color:var(--tx)">-</b></span>
      <span class="pill"><span class="dot ok" id="tb_wd_d"></span>Sentinel <b id="tb_wd" style="color:var(--tx)">-</b></span>
      <button type="button" class="btn sm" onclick="openAquarium('آماده دریافت دستورات زنده سرور...')">✦ آکواریوم زنده</button>
    </div>
  </div>
  {% if msg %}<div class="note">{{msg}}</div>{% endif %}
  {{body|safe}}
</main></div>

<!-- Right-Side Frosted Glass Persian Aquarium Drawer -->
<div class="aq-bg" id="aqbg" onclick="closeAquarium()"></div>
<aside class="aquarium" id="aq">
  <div class="aq-hdr"><b>✦ آکواریوم عملیات زنده DUCKY</b><span class="aq-live" id="aqst">● LIVE</span></div>
  <div class="aq-body" id="aqbody"></div>
  <div class="aq-ftr">
    <div class="aq-bar"><i id="aqprog"></i></div>
    <div style="display:flex;justify-content:space-between;align-items:center">
      <small id="aqpct" style="color:#9A9AA8">در حال آماده‌سازی...</small>
      <button type="button" class="btn sm" onclick="closeAquarium()">بستن پنجره</button>
    </div>
  </div>
</aside>
<script>
function openAquarium(initMsg){
  document.getElementById('aqbg').style.display='block';
  document.getElementById('aq').classList.add('open');
  if(initMsg){document.getElementById('aqbody').innerHTML='<div class="aq-item">'+initMsg+'</div>';}
}
function closeAquarium(){
  document.getElementById('aqbg').style.display='none';
  document.getElementById('aq').classList.remove('open');
}
function pollAquariumJob(jid){
  openAquarium('در حال اتصال به هسته DUCKY و آنالیز سخت‌افزار سرور...');
  let seen=0;
  async function step(){
    try{
      const d=await (await fetch('/api/job/'+jid,{cache:'no-store'})).json();
      const b=document.getElementById('aqbody');
      if(d.steps.length>seen){
        if(seen===0) b.innerHTML='';
        for(let i=seen;i<d.steps.length;i++){
          const s=d.steps[i];
          const div=document.createElement('div');
          div.className='aq-item '+s.s;
          div.textContent=(s.s==='ok'?'✓ ':s.s==='fail'?'⚠ ':s.s==='code'?'$ ':'● ')+s.m;
          b.appendChild(div);
        }
        seen=d.steps.length;
        b.scrollTop=b.scrollHeight;
      }
      const pct=d.done?100:Math.min(92,18+seen*12);
      document.getElementById('aqprog').style.width=pct+'%';
      document.getElementById('aqpct').textContent=d.done?(d.result.startsWith('OK')?'عملیات با موفقیت کامل شد!':'نتیجه: '+d.result):'در حال نوشتن و تنظیم خودکار... '+pct+'%';
      if(!d.done) setTimeout(step,550);
      else document.getElementById('aqst').textContent=d.result.startsWith('OK')?'✓ DONE':'⚠ CHECK';
    }catch(e){setTimeout(step,1000);}
  }
  step();
}
async function refreshTop(){
  try{
    const d=await (await fetch('/api/live',{cache:'no-store'})).json();
    if(d.sys){
      document.getElementById('tb_cpu').textContent=d.sys.cpu_pct+'%';
      document.getElementById('tb_ram').textContent=(d.sys.ram_used/1024).toFixed(1)+'/'+(d.sys.ram_total/1024).toFixed(1)+'GB';
      document.getElementById('tb_bbr').textContent=d.sys.bbr?'Active':'Off';
      document.getElementById('tb_wd').textContent=d.sys.sentinel?'On':'Off';
    }
    if(window.renderDash) window.renderDash(d);
  }catch(e){}
}
refreshTop(); setInterval(refreshTop,2000);
</script></body></html>"""

LOGIN = """<!doctype html><html lang="en" data-theme="dark"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sign in — DUCKY TUNNEL</title><link rel="icon" href="{{LOGO}}"><style>""" + CSS + """
body{display:flex;align-items:center;justify-content:center;min-height:100vh;background:radial-gradient(circle at 50% 25%,rgba(255,214,0,0.12),transparent 55%),#07070A;padding:20px}
.lcard{width:100%;max-width:380px;background:#111117;border:1px solid rgba(255,214,0,0.28);border-radius:22px;padding:34px 30px;box-shadow:0 30px 70px rgba(0,0,0,.7)}
.lcard img{width:64px;height:64px;border-radius:16px;border:2px solid var(--yl);margin-bottom:14px;box-shadow:0 0 24px var(--yl-glow)}
</style></head><body>
<form method="post" class="lcard">
  <div style="text-align:center;margin-bottom:22px">
    <img src="{{LOGO}}" alt="DUCKY"><h1 style="margin:0;font-size:26px;letter-spacing:3px">DUCK<span style="color:var(--yl)">Y</span></h1>
    <div style="color:var(--tx2);font-size:13px;margin-top:4px">Modular Tunnel Command Panel</div>
  </div>
  {% if err %}<div class="note" style="font-size:13px">{{err}}</div>{% endif %}
  <div style="margin-bottom:14px"><label>Username</label><input name="u" required autofocus></div>
  <div style="margin-bottom:20px"><label>Password</label><input name="p" type="password" required></div>
  <button class="btn yel" style="width:100%;justify-content:center;padding:12px">Unlock DUCKY Panel</button>
</form></body></html>"""

def page(p, body, msg=""): return render_template_string(BASE, page=p, body=body, msg=msg, title=load().get("title", "DUCKY-NODE"))
def R(tpl, **k): return render_template_string(tpl, **k)
def catalog(): return [l.split("|")[:4] for l in ducky("catalog").splitlines() if l.count("|") >= 3]

def start_job(*cmd_args):
    jid = "j" + secrets.token_hex(6); jdir = os.path.join(VAULT, "jobs"); os.makedirs(jdir, exist_ok=True)
    jf = os.path.join(jdir, jid + ".log"); open(jf, "w").write("run|شروع ارتباط با هسته DUCKY...\n")
    subprocess.Popen(["bash", BIN, "api"] + [str(x) for x in cmd_args], env=dict(os.environ, DUCKY_JOB=jf), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return jid

@app.route("/<bp>/")
def secret_entry(bp):
    if bp == load().get("basepath", ""): return redirect("/" if session.get("u") else "/login")
    abort(404)

@app.route("/login", methods=["GET", "POST"])
def login():
    ip = request.remote_addr; f = FAILS.get(ip, (0, 0)); err = ""
    if request.method == "POST":
        c = load()
        if f[0] >= 5 and time.time() - f[1] < 300: err = "Locked for 5 minutes after 5 failed attempts."
        elif hmac.compare_digest(request.form.get("u", ""), c.get("user", "")) and pcheck(request.form.get("p", ""), c.get("pass", "")):
            session.clear(); session["u"] = 1; FAILS.pop(ip, None); return redirect("/")
        else: FAILS[ip] = (f[0] + 1 if time.time() - f[1] < 300 else 1, time.time()); err = "Invalid credentials."
    return R(LOGIN, err=err)

@app.route("/logout", methods=["POST"])
def logout(): session.clear(); return redirect("/login")

@app.route("/api/live")
def api_live(): return jsonify(live_payload(request.args.get("name", "all")))

@app.route("/api/job/<jid>")
def api_job(jid):
    if not re.fullmatch(r"j[0-9a-f]{12}", jid): abort(404)
    f = os.path.join(VAULT, "jobs", jid + ".log")
    if not os.path.exists(f): abort(404)
    steps, done, res = [], False, ""
    for l in open(f, encoding="utf-8", errors="replace").read().splitlines():
        if "|" not in l: continue
        s, m = l.split("|", 1)
        if s == "done": done, res = True, m
        else: steps.append({"s": s, "m": m})
    return jsonify(steps=steps, done=done, result=res)

@app.route("/api/v1/status")
def api_v1_status():
    c = load(); key = request.args.get("key") or request.headers.get("X-API-Key", "")
    if not c.get("apikey") or not hmac.compare_digest(key, c.get("apikey", "")): return jsonify(error="unauthorized"), 401
    return jsonify(live_payload("all"))

@app.route("/")
def dash():
    body = """
<div class="card hero-flow">
  <svg id="topo_svg" viewBox="0 0 1100 260">
    <defs><radialGradient id="cg" cx="50%" cy="50%" r="50%"><stop offset="0%" stop-color="#FFD600" stop-opacity="0.35"/><stop offset="100%" stop-color="#FFD600" stop-opacity="0"/></radialGradient></defs>
    <circle cx="510" cy="130" r="65" fill="url(#cg)"/>
    <g id="topo_paths"></g>
    <rect x="28" y="96" width="215" height="68" rx="16" fill="#14141C" stroke="rgba(255,214,0,0.45)" stroke-width="1.4"/>
    <text x="50" y="124" fill="#FFFFFF" font-size="13.5" font-weight="700">IRAN ENTRY HUB</text>
    <text x="50" y="146" fill="#9A9AA8" font-size="12" font-family="monospace" id="hub_ip">Loading IP...</text>
    <circle cx="510" cy="130" r="32" fill="#0B0B10" stroke="#FFD600" stroke-width="3.5"/>
    <circle cx="510" cy="130" r="18" fill="none" stroke="#FFFFFF" stroke-opacity="0.25" stroke-width="1.5"/>
    <g id="topo_nodes"></g>
  </svg>
</div>

<div class="bento">
  <div class="card" style="margin:0"><div style="display:flex;justify-content:space-between;margin-bottom:10px;font-size:12.5px;color:var(--tx2)"><b>Live Throughput Waveform</b><span><span style="color:var(--yl)">● Upload</span> &nbsp; <span style="color:#fff">● Download</span></span></div><canvas id="wf"></canvas></div>
  <div class="kpi"><div class="ring"><svg viewBox="0 0 100 100"><circle class="tr" cx="50" cy="50" r="44"/><circle class="fg" id="kr1" cx="50" cy="50" r="44"/></svg><div class="v" id="kv1">0 GB</div></div><div class="lbl" id="kl1">0 GB</div><div class="sub">Total Traffic</div></div>
  <div class="kpi"><div class="ring"><svg viewBox="0 0 100 100"><circle class="tr" cx="50" cy="50" r="44"/><circle class="fg" id="kr2" cx="50" cy="50" r="44" style="stroke:#FFFFFF"/></svg><div class="v" id="kv2">0 MB/s</div></div><div class="lbl" id="kl2">0 MB/s</div><div class="sub">Live Speed</div></div>
  <div class="kpi"><div class="ring"><svg viewBox="0 0 100 100"><circle class="tr" cx="50" cy="50" r="44"/><circle class="fg" id="kr3" cx="50" cy="50" r="44"/></svg><div class="v" id="kv3">100%</div></div><div class="lbl" id="kl3">100%</div><div class="sub">Link Stability</div></div>
</div>

<script>
const fb=b=>b<1048576?(b/1024).toFixed(1)+' KB':b<1073741824?(b/1048576).toFixed(1)+' MB':b<1099511627776?(b/1073741824).toFixed(2)+' GB':(b/1099511627776).toFixed(2)+' TB';
window.renderDash=function(d){
  document.getElementById('hub_ip').textContent='● '+(d.ip||'-');
  const ns=d.nodes&&d.nodes.length?d.nodes.slice(0,3):[{name:'No Tunnels Yet',type:'Click + Create Tunnel',rtt:null,spd:0,tot:0,on:false}];
  const ys=ns.length===1?[130]:ns.length===2?[68,192]:[44,130,216];
  let ph='<path d="M 243 130 C 340 130, 390 130, 478 130" class="flow-y"/>';
  let nd='';
  ns.forEach((n,i)=>{
    const y=ys[i], cls=i%2===0?'flow-y':'flow-w';
    ph+=`<path d="M 542 130 C 640 130, 670 ${y}, 770 ${y}" class="${cls}"/>`;
    nd+=`<g transform="translate(770,${y-32})" style="cursor:pointer" onclick="location='/tun'">
      <rect width="300" height="64" rx="15" fill="#14141C" stroke="${n.on?'rgba(255,214,0,0.45)':'rgba(255,255,255,0.12)'}" stroke-width="1.3"/>
      <text x="16" y="25" fill="#FFFFFF" font-size="13.5" font-weight="700">${n.name} (${n.type})</text>
      <text x="16" y="46" fill="#9A9AA8" font-size="11.5" font-family="monospace">${n.rtt!=null?n.rtt+' ms':'idle'}  •  ${n.spd} MB/s  •  ${fb(n.tot)}</text>
    </g>`;
  });
  document.getElementById('topo_paths').innerHTML=ph;
  document.getElementById('topo_nodes').innerHTML=nd;
  const totStr=fb(d.tot||0), spdStr=((d.up+d.down)/1048576).toFixed(1)+' MB/s', stStr=(d.stab||100)+'%';
  document.getElementById('kv1').textContent=totStr; document.getElementById('kl1').textContent=totStr;
  document.getElementById('kv2').textContent=spdStr; document.getElementById('kl2').textContent=spdStr;
  document.getElementById('kv3').textContent=stStr; document.getElementById('kl3').textContent=stStr;
  const cv=document.getElementById('wf'), dpr=devicePixelRatio||1, w=cv.clientWidth, h=cv.clientHeight;
  cv.width=w*dpr; cv.height=h*dpr; const x=cv.getContext('2d'); x.scale(dpr,dpr);
  const s=d.series||{up:[0,0],down:[0,0]};
  const drawWave=(arr,col,fill)=>{
    if(!arr||arr.length<2)return;
    const mx=Math.max(1024,...arr)*1.25;
    x.beginPath(); arr.forEach((v,i)=>{const px=i/(arr.length-1)*w, py=h-12-(h-26)*(v/mx); i?x.lineTo(px,py):x.moveTo(px,py)});
    x.strokeStyle=col; x.lineWidth=2.4; x.stroke();
    if(fill){x.lineTo(w,h);x.lineTo(0,h);x.closePath();const g=x.createLinearGradient(0,0,0,h);g.addColorStop(0,fill);g.addColorStop(1,'rgba(0,0,0,0)');x.fillStyle=g;x.fill();}
  };
  drawWave(s.down,'#FFFFFF','rgba(255,255,255,0.12)');
  drawWave(s.up,'#FFD600','rgba(255,214,0,0.28)');
};
</script>"""
    return page("dash", body)

@app.route("/tun")
def tun():
    rows = nlist()
    body = R("""<div class="row" style="justify-content:space-between;margin-bottom:18px">
  <div><h1 style="margin:0;font-size:26px">Tunnel Mesh ({{rows|length}})</h1><div style="color:var(--tx2);font-size:13px">Manage active nodes, failover targets, and instant ducky:// setup links.</div></div>
  <div class="row">
    <form method="post" action="/bulk/restart"><input type="hidden" name="t" value="{{csrf()}}"><button class="btn sm">Restart All</button></form>
    <a class="btn yel" href="/new">＋ Create Tunnel</a>
  </div>
</div>
<div class="card" style="padding:10px 18px">
{% if not rows %}<div style="padding:20px;color:var(--tx2)">No tunnels configured yet.</div>{% else %}
<table><tr><th>Node</th><th>Protocol</th><th>Role</th><th>Remote IP</th><th>Ports</th><th>Backup</th><th>Actions</th></tr>
{% for c in rows %}
<tr>
  <td><b>{{c.NAME}}</b>{% if c.NOTE %}<div style="font-size:11.5px;color:var(--tx2)">{{c.NOTE}}</div>{% endif %}</td>
  <td><span class="pill" style="color:var(--yl)">{{c.TYPE}}</span></td>
  <td class="mono">{{c.ROLE|upper}} #{{c.IDX}}</td>
  <td class="mono">{{c.REMOTE}}</td>
  <td class="mono">{{c.PORTS[:18]}}</td>
  <td class="mono">{{c.BACKUP_NODE or '-'}}</td>
  <td class="row">
    <button class="btn sm" onclick="copyLnk('{{c.NAME}}')">Link</button>
    <form method="post" action="/act/{{c.NAME}}/restart"><input type="hidden" name="t" value="{{csrf()}}"><button class="btn sm">Restart</button></form>
    {% if c.BACKUP_NODE %}<form method="post" action="/failover/{{c.NAME}}"><input type="hidden" name="t" value="{{csrf()}}"><button class="btn sm">Failover</button></form>{% endif %}
    <form method="post" action="/act/{{c.NAME}}/delete" onsubmit="return confirm('Delete {{c.NAME}}?')"><input type="hidden" name="t" value="{{csrf()}}"><button class="btn sm">Delete</button></form>
  </td>
</tr>
{% endfor %}</table>{% endif %}
</div>
<script>
async function copyLnk(n){
  const r=await (await fetch('/api/link/'+n)).json();
  navigator.clipboard.writeText("ducky apply-link '"+r.link+"'");
  openAquarium('لینک راه‌اندازی سریع تانل '+n+' کپی شد! روی سرور خارج اجرا کنید:\\n'+r.link);
}
</script>""", rows=rows)
    return page("tun", body, request.args.get("m", ""))

@app.route("/api/link/<n>")
def api_link(n): return jsonify(link=ducky("link", n))

@app.route("/bulk/<a>", methods=["POST"])
def dobulk(a): return redirect("/tun?m=" + urllib.parse.quote(ducky("bulk", a)))

@app.route("/act/<n>/<a>", methods=["POST"])
def doact(n, a): return redirect("/tun?m=" + urllib.parse.quote(f"{n}: {a} -> " + ducky("act", a, n)))

@app.route("/failover/<n>", methods=["POST"])
def dofail(n): return redirect("/tun?m=" + urllib.parse.quote(ducky("failover", n)))

@app.route("/new", methods=["GET", "POST"])
def new():
    if request.method == "POST":
        f = request.form; g = lambda k, d="": f.get(k, d).strip()
        if g("mode") == "link":
            jid = start_job("apply-link", g("dky_link"))
            return jsonify(jid=jid)
        jid = start_job("deploy", g("name"), g("type"), g("role"), g("local"), g("remote"), g("ports") or "1", g("cport") or "0", g("token"), g("idx"), g("peer"), g("note"), g("tmtu"), g("backup_node"), g("quota_gb", "0"), g("edge_ip"), g("pool"))
        return jsonify(jid=jid)
    cat = catalog()
    groups = []
    for c in cat:
        if c[3] not in groups: groups.append(c[3])
    nxt = len(nlist()) + 1
    body = R("""<h1 style="margin:0 0 6px;font-size:26px">Create Tunnel</h1>
<div style="color:var(--tx2);font-size:13.5px;margin-bottom:20px">Deploy any of 62 specialized protocols — live Persian deployment stream opens in the right glass aquarium.</div>
<form id="df" class="card grid">
  <input type="hidden" name="t" value="{{csrf()}}">
  <div><label>Mode</label><select name="mode" id="md" onchange="sw()"><option value="single">Standard Tunnel (62 Protocols)</option><option value="link">Paste ducky:// Link</option></select></div>
  <div id="lkw" style="display:none;grid-column:1/-1"><label>Paste ducky:// Setup Link</label><input name="dky_link" class="mono" placeholder="ducky://eyJuIjoi..."></div>
  <div class="std" style="grid-column:1/-1"><label>Protocol Family</label><select name="type">{% for g in groups %}<optgroup label="{{g}}">{% for c in cat if c[3]==g %}<option value="{{c[0]}}">{{c[1]}} — {{c[2]}}</option>{% endfor %}</optgroup>{% endfor %}</select></div>
  <div class="std"><label>Tunnel Name</label><input name="name" value="dky{{nxt}}" required></div>
  <div class="std"><label>Server Role</label><select name="role"><option value="iran">Iran (Entry)</option><option value="foreign">Foreign (Exit)</option></select></div>
  <div class="std"><label>This Server IP</label><input name="local" value="{{ip}}"></div>
  <div class="std"><label>Remote Server IP</label><input name="remote" placeholder="45.82.x.x"></div>
  <div class="std"><label>Ports (443, 2053=8443, 2000-2100)</label><input name="ports" value="443"></div>
  <div class="std"><label>Tunnel ID (1-250)</label><input name="idx" type="number" value="{{nxt}}"></div>
  <div class="std"><label>Control Port</label><input name="cport" type="number" value="{{34000+nxt}}"></div>
  <div class="std"><label>Auth Token</label><input name="token" class="mono" value="{{tok}}"></div>
  <div class="std"><label>Backup Tunnel (Auto-Failover)</label><input name="backup_node" placeholder="Optional standby tunnel name"></div>
  <div class="std"><label>CDN Edge IP (Backhaul WS/WSS)</label><input name="edge_ip" placeholder="Optional e.g. 188.114.96.0"></div>
  <div class="std"><label>Bandwidth Quota GB (0=Unlimited)</label><input name="quota_gb" type="number" value="0"></div>
  <div class="std"><label>Server Note</label><input name="note" placeholder="e.g. DE-Hetzner-01"></div>
  <div style="grid-column:1/-1"><button type="submit" class="btn yel" style="padding:12px 26px">⚡ Deploy Tunnel & Open Live Aquarium</button></div>
</form>
<script>
function sw(){const lk=document.getElementById('md').value==='link';document.getElementById('lkw').style.display=lk?'':'none';document.querySelectorAll('.std').forEach(e=>e.style.display=lk?'none':'')}
document.getElementById('df').onsubmit=async e=>{
  e.preventDefault();
  const r=await (await fetch('/new',{method:'POST',body:new FormData(e.target)})).json();
  if(r.jid) pollAquariumJob(r.jid);
};
</script>""", cat=cat, groups=groups, ip=ducky("ip"), nxt=nxt, tok="".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(40)))
    return page("new", body)

@app.route("/tools", methods=["GET", "POST"])
def tools():
    msg = ""
    if request.method == "POST":
        a = request.form.get("action", "")
        if a == "tune":
            jid = start_job("tune", request.form.get("prof", "throughput"))
            return jsonify(jid=jid)
        elif a == "sentinel": msg = ducky("sentinel", request.form.get("cmd", "enable"), "40")
        elif a == "dns": msg = ducky("dns", request.form.get("dns", "shecan"))
        elif a == "shield": msg = ducky("shield", "enable")
        elif a == "swap": msg = ducky("swap", "2048")
    body = R("""<h1 style="margin:0 0 6px;font-size:26px">Debugger, Kernel & Network Center</h1>
<div style="color:var(--tx2);font-size:13.5px;margin-bottom:20px">Auto-tune Linux kernel to your exact CPU/RAM specs, enable Sentinel Watchdog, and run connection tests.</div>
<div class="card row">
  <button class="btn yel" onclick="runTune('throughput')">⚡ Auto-Tune Kernel (Throughput BBR + RPS)</button>
  <button class="btn" onclick="runTune('gaming')">🎮 Gaming Low-Latency Profile</button>
  <form method="post"><input type="hidden" name="t" value="{{csrf()}}"><input type="hidden" name="action" value="sentinel"><input type="hidden" name="cmd" value="enable"><button class="btn">🛡 Enable Sentinel Failover</button></form>
  <form method="post"><input type="hidden" name="t" value="{{csrf()}}"><input type="hidden" name="action" value="shield"><button class="btn">Anti-DDoS Shield</button></form>
  <form method="post"><input type="hidden" name="t" value="{{csrf()}}"><input type="hidden" name="action" value="swap"><button class="btn">+ 2GB Swap</button></form>
  <form method="post"><input type="hidden" name="t" value="{{csrf()}}"><input type="hidden" name="action" value="dns"><input type="hidden" name="dns" value="shecan"><button class="btn">DNS: Shecan</button></form>
</div>
<div class="card">
  <h3 style="margin-top:0">Sentinel Auto-Heal & Failover Logs</h3>
  <pre class="mono" style="background:#07070A;padding:14px;border-radius:12px;color:var(--yl);overflow:auto;max-height:220px">{{logs}}</pre>
</div>
<script>
async function runTune(p){
  const fd=new FormData();fd.append('t','{{csrf()}}');fd.append('action','tune');fd.append('prof',p);
  const r=await (await fetch('/tools',{method:'POST',body:fd})).json();
  if(r.jid) pollAquariumJob(r.jid);
}
</script>""", logs=ducky("sentinel", "logs"))
    return page("tools", body, msg)

@app.route("/set", methods=["GET", "POST"])
def settings():
    msg = ""; c = load()
    if request.method == "POST":
        sec = request.form.get("sec", "")
        if sec == "tg":
            c["title"] = request.form.get("title", "DUCKY-NODE").strip()
            c["tg_token"] = request.form.get("tg_token", "").strip()
            c["tg_chat"] = request.form.get("tg_chat", "").strip()
            save(c)
            ducky("tgbot", "enable" if (c["tg_token"] and c["tg_chat"]) else "disable")
            msg = "Node identity & Telegram Control Bot saved and restarted!"
        elif sec == "backup":
            msg = ducky("backup")
    body = R("""<h1 style="margin:0 0 6px;font-size:26px">Settings, Telegram Bot & Vault Backup</h1>
<div style="color:var(--tx2);font-size:13.5px;margin-bottom:20px">REST API: <code class="mono">/api/v1/status?key={{c.get('apikey','')}}</code></div>
<form method="post" class="card grid">
  <input type="hidden" name="t" value="{{csrf()}}"><input type="hidden" name="sec" value="tg">
  <div><label>Node Alias</label><input name="title" value="{{c.get('title','DUCKY-NODE')}}"></div>
  <div><label>Telegram Bot Token (@BotFather)</label><input name="tg_token" value="{{c.get('tg_token','')}}" placeholder="123456:ABC..."></div>
  <div><label>Admin Telegram Numeric ID</label><input name="tg_chat" value="{{c.get('tg_chat','')}}" placeholder="8497005009"></div>
  <div style="align-self:end"><button class="btn yel">Save & Start Telegram Bot</button></div>
</form>
<div class="card row">
  <form method="post"><input type="hidden" name="t" value="{{csrf()}}"><input type="hidden" name="sec" value="backup"><button class="btn">💾 Create Instant Vault Backup (.tar.gz)</button></form>
</div>""", c=c)
    return page("set", body, msg)

if __name__ == "__main__":
    c = load(); kw = {}
    if c.get("cert") and os.path.exists(c["cert"]): kw["ssl_context"] = (c["cert"], c["key"])
    app.run(host=os.environ.get("DUCKY_HOST", "0.0.0.0"), port=int(os.environ.get("DUCKY_PORT", c.get("port", 8443))), threaded=True, **kw)
