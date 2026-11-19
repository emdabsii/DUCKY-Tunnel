# DUCKY Tunnel Suite v1.0 - Module 5: Sentinel Watchdog (Anti-Loop + Tunnel-to-Tunnel Failover + Telegram Alerts + Backup)

send_tg_alert(){
  local text=$1
  [ -f "$VAULT/panel.dkcfg" ] || return 0
  python3 -c 'import json,sys,urllib.request,urllib.parse
try:
  c=json.load(open(sys.argv[1]))
  tk,ch=c.get("tg_token",""),c.get("tg_chat","")
  if tk and ch:
    u="https://api.telegram.org/bot"+tk+"/sendMessage?"+urllib.parse.urlencode({"chat_id":ch,"text":sys.argv[2],"parse_mode":"Markdown"})
    urllib.request.urlopen(u,timeout=5)
except Exception: pass' "$VAULT/panel.dkcfg" "$text" 2>/dev/null
}

manual_failover(){
  local primary=$1
  load_node "$primary" 2>/dev/null
  [ -n "${BACKUP_NODE:-}" ] && [ -f "$MESH/$BACKUP_NODE.dknode" ] || { echo "ERR no backup tunnel configured for $primary"; return 1; }
  sysd stop "dky-mesh-$primary" >/dev/null 2>&1
  sysd enable --now "dky-mesh-$BACKUP_NODE" >/dev/null 2>&1
  sysd restart "dky-mesh-$BACKUP_NODE" >/dev/null 2>&1
  send_tg_alert "⚡ *DUCKY Failover Activated*
Primary: \`$primary\` (Stopped)
Active Backup: \`$BACKUP_NODE\` (Running)"
  echo "OK Switched traffic from $primary to backup tunnel $BACKUP_NODE"
}

sentinel_loop(){
  local interval=${1:-40} slog="/var/log/ducky-sentinel.log"
  mkdir -p "$(dirname "$slog")" "$VAULT/state"
  echo "$(date -Iseconds) | DUCKY Sentinel started (interval=${interval}s)" >>"$slog"
  while true; do
    for f in "$MESH"/*.dknode; do
      [ -f "$f" ] || continue
      (
        BACKUP_NODE=""; QUOTA_GB="0"
        . "$f"
        systemctl is-enabled --quiet "dky-mesh-$NAME" 2>/dev/null || exit 0
        local fail_file="$VAULT/state/${NAME}.fails"
        local fails=$(cat "$fail_file" 2>/dev/null || echo 0)

        # 1. Quota Check
        if [ "${QUOTA_GB:-0}" -gt 0 ] 2>/dev/null && [ -d "/sys/class/net/dky$IDX" ]; then
          local rx=$(cat "/sys/class/net/dky$IDX/statistics/rx_bytes" 2>/dev/null || echo 0)
          local tx=$(cat "/sys/class/net/dky$IDX/statistics/tx_bytes" 2>/dev/null || echo 0)
          local used_gb=$(( (rx + tx) / 1073741824 ))
          if [ "$used_gb" -ge "$QUOTA_GB" ]; then
            systemctl stop "dky-mesh-$NAME" 2>/dev/null
            echo "$(date -Iseconds) | QUOTA | $NAME reached ${used_gb}/${QUOTA_GB}GB" >>"$slog"
            send_tg_alert "⚠️ *DUCKY Quota Reached*
Tunnel \`$NAME\` reached *${used_gb}GB / ${QUOTA_GB}GB* and was paused."
            exit 0
          fi
        fi

        # 2. Real Packet & Socket Health Check
        local st=$(systemctl is-active "dky-mesh-$NAME" 2>/dev/null)
        local broken=0 reason=""
        if [ "$st" != "active" ]; then
          broken=1; reason="service=$st"
        elif [[ $TYPE =~ $KERNEL_RX ]]; then
          local pip="10.88.$IDX.$([ "$ROLE" = iran ] && echo 2 || echo 1)"
          ping -c 3 -W 1 -q "$pip" >/dev/null 2>&1 || { broken=1; reason="peer $pip no reply"; }
        elif [[ $TYPE =~ $REVERSE_RX ]] && [ -n "${CPORT:-}" ] && [ "$CPORT" != "0" ]; then
          if [ "$ROLE" = foreign ]; then
            ss -Htn state established "( dport = :$CPORT )" 2>/dev/null | grep -q . || { broken=1; reason="no active handshake on :$CPORT"; }
          fi
        fi

        if [ "$broken" = 0 ]; then
          echo 0 >"$fail_file"
          exit 0
        fi

        # 3. Anti-Loop Escalation: Attempt 1 -> Restart | Attempt 2 -> Failover to Backup Tunnel!
        fails=$((fails + 1))
        echo "$fails" >"$fail_file"
        if [ "$fails" -eq 1 ]; then
          systemctl restart "dky-mesh-$NAME" 2>/dev/null
          echo "$(date -Iseconds) | HEAL_TRY_1 | $NAME ($TYPE) | $reason -> Restarted" >>"$slog"
          send_tg_alert "🔄 *DUCKY Auto-Heal*
Tunnel \`$NAME\` (\`$TYPE\`) dropped (\`$reason\`). Restarted automatically."
        elif [ "$fails" -eq 2 ] && [ -n "${BACKUP_NODE:-}" ] && [ -f "$MESH/$BACKUP_NODE.dknode" ]; then
          systemctl stop "dky-mesh-$NAME" 2>/dev/null
          systemctl restart "dky-mesh-$BACKUP_NODE" 2>/dev/null
          echo "$(date -Iseconds) | FAILOVER | $NAME -> $BACKUP_NODE | $reason" >>"$slog"
          send_tg_alert "🚨 *DUCKY Automatic Failover*
Primary tunnel \`$NAME\` failed after restart (\`$reason\`).
✅ Switched automatically to backup tunnel: \`$BACKUP_NODE\`"
        elif [ "$fails" -ge 5 ]; then
          # Cooldown reset after 5 cycles to prevent endless restart loops
          echo 0 >"$fail_file"
        fi
      )
    done
    sleep "$interval"
  done
}

sentinel_ctl(){
  local cmd=${1:-status} interval=${2:-40} u="$UNITDIR/dky-sentinel.service"
  case $cmd in
    enable|start)
      mkdir -p "$UNITDIR"
      cat >"$u" <<EOF
[Unit]
Description=DUCKY Sentinel Anti-Loop Watchdog & Auto-Failover
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ducky sentinel-run $interval
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      sysd daemon-reload; sysd enable --now dky-sentinel >/dev/null 2>&1
      echo "OK DUCKY Sentinel enabled (${interval}s check + Auto-Failover)"
      ;;
    disable|stop)
      sysd disable --now dky-sentinel >/dev/null 2>&1; rm -f "$u"; sysd daemon-reload
      echo "OK DUCKY Sentinel disabled"
      ;;
    logs) tail -n 30 /var/log/ducky-sentinel.log 2>/dev/null || echo "No Sentinel events yet." ;;
    *) systemctl is-active --quiet dky-sentinel 2>/dev/null && echo "ACTIVE" || echo "INACTIVE" ;;
  esac
}

tgbot_ctl(){
  local cmd=${1:-status} u="$UNITDIR/dky-tgbot.service"
  case $cmd in
    enable|start)
      mkdir -p "$UNITDIR"
      cat >"$u" <<EOF
[Unit]
Description=DUCKY Interactive Telegram Control Bot
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $APP/bot/tgbot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
      sysd daemon-reload; sysd enable --now dky-tgbot >/dev/null 2>&1
      echo "OK DUCKY Telegram Bot service started"
      ;;
    disable|stop)
      sysd disable --now dky-tgbot >/dev/null 2>&1; rm -f "$u"; sysd daemon-reload
      echo "OK DUCKY Telegram Bot service stopped"
      ;;
    *) systemctl is-active --quiet dky-tgbot 2>/dev/null && echo "ACTIVE" || echo "INACTIVE" ;;
  esac
}

# ---------- Vault Backup, Restore & Setup Links ----------
backup_vault(){
  mkdir -p "$SNAP"
  local out="${1:-$SNAP/ducky-vault-$(date +%Y%m%d-%H%M%S).tar.gz}"
  tar -czf "$out" -C "$VAULT" mesh exec specs cipher panel.dkcfg 2>/dev/null || tar -czf "$out" -C "$VAULT" . 2>/dev/null
  chmod 600 "$out" 2>/dev/null
  echo "OK $out"
}

restore_vault(){
  local arch=$1
  [ -f "$arch" ] || { echo "ERR archive not found"; return 1; }
  mkdir -p "$VAULT"; tar -xzf "$arch" -C "$VAULT" 2>/dev/null || { echo "ERR bad archive"; return 1; }
  for f in "$MESH"/*.dknode; do
    [ -f "$f" ] || continue
    ( . "$f"; build_runner; write_service_unit; sysd enable --now "dky-mesh-$NAME" >/dev/null 2>&1 )
  done
  sysd daemon-reload
  echo "OK Vault restored and all tunnels restarted"
}

make_link(){
  load_node "$1"; [ -n "${TYPE:-}" ] || { echo "ERR not found"; return 1; }
  local tr="foreign"; [ "$ROLE" = foreign ] && tr="iran"
  local j=$(python3 -c 'import json,sys;print(json.dumps({"n":sys.argv[1],"t":sys.argv[2],"l":sys.argv[3],"r":sys.argv[4],"i":int(sys.argv[5]),"c":int(sys.argv[6] or 0),"k":sys.argv[7],"p":sys.argv[8],"rl":sys.argv[9],"nt":sys.argv[10],"m":sys.argv[11]}))' \
    "$NAME" "$TYPE" "$REMOTE" "$LOCAL" "$IDX" "${CPORT:-0}" "${TOKEN:-}" "${PORTS:-1}" "$tr" "${NOTE:-}" "${TMTU:-}")
  echo "ducky://$(printf %s "$j" | base64 -w0)"
}

export_all_links(){
  for f in "$MESH"/*.dknode; do [ -f "$f" ] && make_link "$(basename "$f" .dknode)"; done
}

apply_link(){
  local raw=$1 j
  raw=${raw#ducky://}; raw=${raw//[[:space:]]/}
  j=$(printf %s "$raw" | base64 -d 2>/dev/null) || { echo "ERR invalid ducky:// link"; return 1; }
  eval "$(printf %s "$j" | python3 -c 'import json,sys,shlex
d=json.load(sys.stdin)
m={"NAME":d["n"],"TYPE":d["t"],"LOCAL":d["l"],"REMOTE":d["r"],"IDX":d["i"],"CPORT":d["c"],"TOKEN":d["k"],"PORTS":d.get("p","1"),"ROLE":d.get("rl","foreign"),"NOTE":d.get("nt","Linked via ducky://"),"TMTU":d.get("m","")}
for k,v in m.items(): print(k+"="+shlex.quote(str(v)))' 2>/dev/null)" || { echo "ERR corrupted link"; return 1; }
  [ "$ROLE" = foreign ] && PORTS=1
  PEER=""; BACKUP_NODE=""; QUOTA_GB="0"; EDGE_IP=""; POOL=""
  deploy_node
}

apply_batch_links(){
  local raw=$1 line ok=0 fail=0
  while IFS= read -r line; do
    line=$(echo "$line" | tr -d '\r ')
    [[ $line == ducky://* ]] || continue
    apply_link "$line" | grep -q '^OK' && ok=$((ok+1)) || fail=$((fail+1))
  done <<<"$raw"
  echo "OK Imported $ok tunnel(s) ($fail skipped)"
}
