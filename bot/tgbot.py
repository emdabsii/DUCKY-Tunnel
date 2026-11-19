#!/usr/bin/env python3
# DUCKY Interactive Telegram Control Bot (Zero Extra Dependencies — Pure Python Stdlib)
import os, json, time, subprocess, urllib.request, urllib.parse

VAULT = os.environ.get("DUCKY_VAULT", "/etc/.ducky-vault")
CFGF = os.path.join(VAULT, "panel.dkcfg")
BIN = os.environ.get("DUCKY_BIN", "/usr/local/bin/ducky")

def cfg():
    try: return json.load(open(CFGF))
    except Exception: return {}

def ducky(*args):
    try: return subprocess.run(["bash", BIN, "api", *map(str, args)], capture_output=True, text=True, timeout=60).stdout.strip()
    except Exception as e: return "ERR: " + str(e)

def tg_call(token, method, data=None):
    url = f"https://api.telegram.org/bot{token}/{method}"
    payload = json.dumps(data or {}).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.loads(r.read().decode("utf-8"))

def main_keyboard():
    return {"inline_keyboard": [
        [{"text": "📊 وضعیت سرور و تانل‌ها", "callback_data": "status"}, {"text": "⚡ بهینه‌سازی کرنل (BBR+RPS)", "callback_data": "tune"}],
        [{"text": "🛡 وضعیت نگهبان (Sentinel)", "callback_data": "sentinel"}, {"text": "🔄 ری‌استارت همه تانل‌ها", "callback_data": "restart_all"}],
        [{"text": "💾 بکاپ فوری Vault", "callback_data": "backup"}, {"text": "🩺 عیب‌یابی سیستم (Doctor)", "callback_data": "doctor"}]
    ]}

def nodes_keyboard():
    rows = []
    for line in ducky("list").splitlines():
        if "|" not in line: continue
        p = line.split("|")
        name, typ, st = p[0], p[1], p[5]
        icon = "🟢" if st == "active" else "⚪"
        rows.append([
            {"text": f"{icon} {name} ({typ})", "callback_data": f"info:{name}"},
            {"text": "🔄", "callback_data": f"restart:{name}"},
            {"text": "🔀 Failover", "callback_data": f"failover:{name}"}
        ])
    rows.append([{"text": "🔙 منوی اصلی", "callback_data": "home"}])
    return {"inline_keyboard": rows}

def build_status_text():
    sysj = {}
    try: sysj = json.loads(ducky("sysinfo"))
    except Exception: pass
    nodes = [l.split("|") for l in ducky("list").splitlines() if "|" in l]
    lines = [
        f"🟡 *DUCKY Control Center* — `{cfg().get('title', 'DUCKY-NODE')}`",
        f"🖥 CPU: `{sysj.get('cpu_pct', 0)}%` ({sysj.get('cores', 1)}C) | RAM: `{sysj.get('ram_pct', 0)}%` | BBR: `{'ON' if sysj.get('bbr') else 'OFF'}`",
        f"🌐 IP: `{sysj.get('ip', '-')}` | Active Nodes: *{len(nodes)}*",
        ""
    ]
    for p in nodes:
        st_icon = "🟢" if p[5] == "active" else "⚪"
        lines.append(f"{st_icon} *{p[0]}* (`{p[1]}`) → `{p[3]}` | Ports: `{p[4]}`")
    if not nodes:
        lines.append("_هنوز تانلی ساخته نشده است._")
    return "\n".join(lines)

def handle_cb(token, chat_id, msg_id, data):
    if data == "home":
        tg_call(token, "editMessageText", {"chat_id": chat_id, "message_id": msg_id, "text": "🟡 *پنل مدیریت تلگرام DUCKY*\nاز دکمه‌های زیر سرور و تانل‌ها را کنترل کنید:", "parse_mode": "Markdown", "reply_markup": main_keyboard()})
    elif data == "status":
        tg_call(token, "editMessageText", {"chat_id": chat_id, "message_id": msg_id, "text": build_status_text(), "parse_mode": "Markdown", "reply_markup": nodes_keyboard()})
    elif data == "tune":
        res = ducky("tune", "throughput")
        tg_call(token, "sendMessage", {"chat_id": chat_id, "text": f"⚡ *Kernel Auto-Tune:*\n`{res}`", "parse_mode": "Markdown"})
    elif data == "sentinel":
        st = ducky("sentinel", "status")
        logs = ducky("sentinel", "logs")[-600:]
        tg_call(token, "sendMessage", {"chat_id": chat_id, "text": f"🛡 *Sentinel Watchdog:* `{st}`\n```\n{logs}\n```", "parse_mode": "Markdown"})
    elif data == "restart_all":
        res = ducky("bulk", "restart")
        tg_call(token, "sendMessage", {"chat_id": chat_id, "text": f"🔄 `{res}`", "parse_mode": "Markdown"})
    elif data == "backup":
        res = ducky("backup")
        tg_call(token, "sendMessage", {"chat_id": chat_id, "text": f"💾 *Vault Backup:*\n`{res}`", "parse_mode": "Markdown"})
    elif data == "doctor":
        res = ducky("doctor")
        tg_call(token, "sendMessage", {"chat_id": chat_id, "text": f"🩺 *DUCKY Doctor:*\n```\n{res}\n```", "parse_mode": "Markdown"})
    elif data.startswith("restart:"):
        n = data.split(":", 1)[1]
        res = ducky("act", "restart", n)
        tg_call(token, "sendMessage", {"chat_id": chat_id, "text": f"🔄 Restart `{n}`: `{res}`", "parse_mode": "Markdown"})
    elif data.startswith("failover:"):
        n = data.split(":", 1)[1]
        res = ducky("failover", n)
        tg_call(token, "sendMessage", {"chat_id": chat_id, "text": f"🔀 Failover `{n}`:\n`{res}`", "parse_mode": "Markdown"})
    elif data.startswith("info:"):
        n = data.split(":", 1)[1]
        lnk = ducky("link", n)
        tg_call(token, "sendMessage", {"chat_id": chat_id, "text": f"🔗 *Setup Link for `{n}`:*\n`ducky apply-link '{lnk}'`", "parse_mode": "Markdown"})

def run():
    offset = 0
    while True:
        c = cfg()
        token = c.get("tg_token", "").strip()
        admin = str(c.get("tg_chat", "")).strip()
        if not token or not admin:
            time.sleep(10)
            continue
        try:
            res = tg_call(token, "getUpdates", {"offset": offset, "timeout": 20})
            for upd in res.get("result", []):
                offset = upd["update_id"] + 1
                if "message" in upd:
                    m = upd["message"]
                    cid = str(m["chat"]["id"])
                    if cid != admin: continue
                    txt = m.get("text", "")
                    if txt.startswith("/start") or txt.startswith("/menu"):
                        tg_call(token, "sendMessage", {"chat_id": cid, "text": "🟡 *خوش آمدید به ربات کنترل DUCKY Tunnel*\nتمامی تانل‌ها، Failover و بهینه‌سازی کرنل از اینجا قابل کنترل است:", "parse_mode": "Markdown", "reply_markup": main_keyboard()})
                    elif txt.startswith("/status"):
                        tg_call(token, "sendMessage", {"chat_id": cid, "text": build_status_text(), "parse_mode": "Markdown", "reply_markup": nodes_keyboard()})
                elif "callback_query" in upd:
                    cb = upd["callback_query"]
                    cid = str(cb["message"]["chat"]["id"])
                    if cid != admin: continue
                    handle_cb(token, cid, cb["message"]["message_id"], cb.get("data", ""))
                    tg_call(token, "answerCallbackQuery", {"callback_query_id": cb["id"]})
        except Exception:
            time.sleep(4)

if __name__ == "__main__":
    run()
