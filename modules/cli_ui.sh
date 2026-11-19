# DUCKY Tunnel Suite v1.0 - Module 6: Black/White/Yellow Terminal Command Center & Panel Manager

banner(){
  [ -n "${DUCKY_DEMO:-}" ] || clear
  myip
  local tc=0 ac=0 f
  for f in "$MESH"/*.dknode; do [ -f "$f" ] || continue; tc=$((tc+1)); systemctl is-active --quiet "dky-mesh-$(basename "$f" .dknode)" 2>/dev/null && ac=$((ac+1)); done
  printf '\n  %s╔══════════════════════════════════════════════════════════════════════════╗%s\n' "$Y" "$N"
  printf '  %s║%s  %s██████╗ ██╗   ██╗ ██████╗██╗  ██╗██╗   ██╗%s   %sTUNNEL SUITE v%s%s         %s║%s\n' "$Y" "$N" "$W" "$N" "$Y" "$VER" "$N" "$Y" "$N"
  printf '  %s║%s  %s██╔══██╗██║   ██║██╔════╝██║ ██╔╝╚██╗ ██╔╝%s   %sOBSIDIAN • WHITE • GOLD%s  %s║%s\n' "$Y" "$N" "$W" "$N" "$D" "$N" "$Y" "$N"
  printf '  %s║%s  %s██║  ██║██║   ██║██║     █████╔╝  ╚████╔╝%s    %st.me/Em4dloverS%s          %s║%s\n' "$Y" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N"
  printf '  %s║%s  %s██████╔╝╚██████╔╝╚██████╗██║  ██╗   ██║%s      %sSupport: @KaMr4ng%s        %s║%s\n' "$Y" "$N" "$Y" "$N" "$D" "$N" "$Y" "$N"
  printf '  %s╠══════════════════════════════════════════════════════════════════════════╣%s\n' "$Y" "$N"
  printf '  %s║%s %sOS:%s %-15s %sIP:%s %-15s %sCPU:%s %-7s %sRAM:%s %-12s %s║%s\n' \
    "$Y" "$N" "$Y" "$N" "${OS_NAME} ${OS_VER}" "$Y" "$N" "$MYIP" "$Y" "$N" "$(cpu_cores)C/$(cpu_load)" "$Y" "$N" "$(ram_usage)" "$Y" "$N"
  printf '  %s║%s %sNODES:%s %s%d/%d UP%s       %sBBR:%s %-14s %sSENTINEL:%s %-7s %sVIRT:%s %-7s %s║%s\n' \
    "$Y" "$N" "$Y" "$N" "$W" "$ac" "$tc" "$N" "$Y" "$N" "$(bbr_state)" "$Y" "$N" "$(sentinel_state)" "$Y" "$N" "$(virt_type)" "$Y" "$N"
  printf '  %s╚══════════════════════════════════════════════════════════════════════════╝%s\n' "$Y" "$N"
}

hdr(){
  printf '\n  %s━━━[ %s%s%s ]━━━%s\n\n' "$Y" "$W" "$1" "$Y" "$N"
}
ask(){ local v; printf '  %s▸%s %s%s%s%s: ' "$Y" "$N" "$W" "$1" "${2:+ ${D}[$2]${N}}" "$N"; read -r v; REPLY=${v:-${2:-}}; }
pause(){ printf '\n  %s[ Press Enter to return to DUCKY Command Center ]%s' "$D" "$N"; read -r _; }

panel_cfg(){ python3 "$APP/panel/app.py" set "$@"; }
panel_url(){ python3 "$APP/panel/app.py" url "$MYIP"; }

panel_install(){
  hdr "Deploy DUCKY Web Panel (Black / White / Yellow)"
  apt_i python3 python3-flask curl tcpdump >>"$LOG" 2>&1
  local fresh=1 port pass bpath apikey
  [ -f "$VAULT/panel.dkcfg" ] && fresh=0
  if [ $fresh = 1 ]; then
    port=$(rand_port); pass=$(rand_str 12); bpath="ducky-$(rand_str 8)"; apikey=$(rand_str 28)
    panel_cfg "port=$port" "user=admin" "pass=$pass" "basepath=$bpath" "apikey=$apikey" "title=DUCKY-NODE"
  else
    port=$(python3 "$APP/panel/app.py" get port)
  fi
  cat >"$UNITDIR/dky-panel.service" <<EOF
[Unit]
Description=DUCKY Luxury Web Panel
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 $APP/panel/app.py run
Restart=always
RestartSec=2
OOMScoreAdjust=-300

[Install]
WantedBy=multi-user.target
EOF
  sysd daemon-reload; sysd enable --now dky-panel >/dev/null 2>&1; sysd restart dky-panel >/dev/null 2>&1
  command -v ufw >/dev/null && ufw allow "$port/tcp" >/dev/null 2>&1
  printf '\n  %s[ OK ]%s Web Panel Ready!\n' "$G" "$N"
  printf '  %s▸ Secret URL :%s %s%s%s\n' "$Y" "$N" "$W" "$(panel_url)" "$N"
  [ $fresh = 1 ] && printf '  %s▸ Username   :%s %sadmin%s\n  %s▸ Password   :%s %s%s%s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$pass" "$N"
}

tgbot_wizard(){
  hdr "Configure DUCKY Interactive Telegram Control Bot"
  [ -f "$VAULT/panel.dkcfg" ] || { echo "  Install Web Panel (option 6) first to initialize vault config."; return; }
  ask "Telegram Bot Token (from @BotFather)"; local tk=$REPLY
  ask "Your Admin Telegram Numeric ID"; local ch=$REPLY
  [ -n "$tk" ] && [ -n "$ch" ] || { echo "  Cancelled."; return; }
  panel_cfg "tg_token=$tk" "tg_chat=$ch"
  tgbot_ctl enable
  printf '  %s[ OK ]%s Open your bot in Telegram and send /start!\n' "$G" "$N"
}

live_monitor(){
  trap 'return 0' INT
  while :; do
    clear
    printf '\n  %sDUCKY LIVE MESH MONITOR%s  %s(2s refresh | Ctrl+C to exit)%s\n\n' "$BY" "$N" "$D" "$N"
    printf '  %s%-14s %-20s %-8s %-16s %-10s %-10s%s\n' "$Y" "NODE" "PROTOCOL" "ROLE" "PEER IP" "STATE" "PING" "$N"
    for f in "$MESH"/*.dknode; do
      [ -f "$f" ] || continue
      (
        . "$f"
        st=$(sysd is-active "dky-mesh-$NAME" 2>/dev/null || echo stopped)
        pip=$REMOTE; [[ $TYPE =~ $KERNEL_RX ]] && pip="10.88.$IDX.$([ "$ROLE" = iran ] && echo 2 || echo 1)"
        rtt="-"
        [ "$st" = active ] && { rtt=$(ping -c 1 -W 1 "$pip" 2>/dev/null | grep -oE 'time=[0-9.]+' | cut -d= -f2); [ -n "$rtt" ] && rtt="${rtt}ms" || rtt="timeout"; }
        printf '  %s%-14s%s %-20s %-8s %-16s %s%-10s%s %s%-10s%s\n' "$W" "$NAME" "$N" "$(type_name "$TYPE")" "$ROLE" "$pip" "$([ "$st" = active ] && echo "$G" || echo "$D")" "$st" "$N" "$Y" "$rtt" "$N"
      )
    done
    sleep 2
  done
}

deploy_wizard(){
  hdr "Deploy New DUCKY Tunnel (62 Protocols)"
  printf '  %s[1]%s Interactive Tunnel Setup   %s[2]%s Paste ducky:// Setup Link\n\n' "$Y" "$N" "$Y" "$N"
  ask "Mode" 1
  if [ "$REPLY" = 2 ]; then
    ask "Paste ducky:// link"; printf '\n  Result: %s%s%s\n' "$W" "$(apply_link "$REPLY")" "$N"; return
  fi
  local i=0 t n d g last=""
  while IFS='|' read -r t n d g; do
    [ -n "$t" ] || continue; i=$((i+1))
    [ "$g" != "$last" ] && { printf '\n  %s %s %s\n' "$BY" "$g" "$N"; last=$g; }
    printf '   %s[%2d]%s %s%-22s%s %s%s%s\n' "$Y" "$i" "$N" "$W" "$n" "$N" "$D" "$d" "$N"
  done <<<"$CATALOG"
  echo; ask "Protocol Number" 2
  TYPE=$(echo "$CATALOG" | sed -n "${REPLY}p" | cut -d'|' -f1); [ -n "$TYPE" ] || return
  ask "Tunnel Name" "dky$(next_idx)"; NAME=$REPLY
  printf '  Role: %s[1]%s Iran (Entry)   %s[2]%s Foreign (Exit)\n' "$Y" "$N" "$Y" "$N"
  ask "Role" 1; [ "$REPLY" = 2 ] && ROLE=foreign || ROLE=iran
  myip; ask "This Server IP" "$MYIP"; LOCAL=$REPLY
  ask "Remote Server IP"; REMOTE=$REPLY
  ask "Tunnel ID (1-250)" "$(next_idx)"; IDX=$REPLY
  PORTS="1"; CPORT="0"; TOKEN=$(rand_token); PEER=""; NOTE=""; TMTU=""; BACKUP_NODE=""; QUOTA_GB="0"; EDGE_IP=""; POOL=""
  if [ "$ROLE" = iran ] || [[ $TYPE =~ $REVERSE_RX ]]; then
    ask "Ports (e.g. 443,80,2053=8443,2000-2100)" "443"; PORTS=$REPLY
  fi
  if [[ $(engine_of "$TYPE") =~ ^(backhaul|rathole|frp|gost)$ ]]; then
    ask "Control Port" "$((34000+IDX))"; CPORT=$REPLY
    [ "$ROLE" = foreign ] && { ask "Paste Token from Iran"; TOKEN=$REPLY; }
  fi
  ask "Optional Backup Tunnel Name for Auto-Failover" ""; BACKUP_NODE=$REPLY
  ask "Optional Server Note" ""; NOTE=$REPLY
  printf '\n  Result: %s%s%s\n' "$W" "$(deploy_node)" "$N"
  [ "$ROLE" = iran ] && printf '\n  %s 1-SECOND FOREIGN COMMAND %s\n  %sducky apply-link '\''%s'\''%s\n' "$BY" "$N" "$W" "$(make_link "$NAME")" "$N"
}

manage_mesh(){
  hdr "DUCKY Active Mesh Nodes"
  local i=0 names=() n t r rem p s idx note tmtu bn qgb
  while IFS='|' read -r n t r rem p s idx note tmtu bn qgb; do
    [ -n "$n" ] || continue; i=$((i+1)); names+=("$n")
    printf '  %s[%2d]%s %s%-14s%s %-20s %-8s %-15s %s%s%s\n' "$Y" "$i" "$N" "$W" "$n" "$N" "$(type_name "$t")" "$r" "$rem" "$([ "$s" = active ] && echo "$G" || echo "$D")" "$s" "$N"
  done < <(list_nodes)
  [ $i -eq 0 ] && { echo "  No tunnels yet."; return; }
  echo; ask "Select node number (0=back)" 0; [ "$REPLY" = 0 ] && return
  local sel=${names[$((REPLY-1))]:-}; [ -n "$sel" ] || return
  printf '  %s[s]%s Start  %s[x]%s Stop  %s[r]%s Restart  %s[m]%s Auto-MTU  %s[h]%s Port-Hop  %s[f]%s Failover  %s[i]%s Link  %s[d]%s Delete\n' "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N"
  ask "Action" 0
  case $REPLY in
    s) node_act start "$sel" ;; x) node_act stop "$sel" ;; r) node_act restart "$sel" ;;
    m) mtu_probe "$sel" apply ;; h) hop_cport "$sel" ;; f) manual_failover "$sel" ;;
    i) echo "  $(make_link "$sel")" ;;
    d) ask "Type YES to delete $sel" no; [ "$REPLY" = YES ] && node_act delete "$sel" ;;
  esac
}

self_update(){ bash <(curl -fsSL "https://raw.githubusercontent.com/${DUCKY_GH:-emdabsii/DUCKY-Tunnel}/main/install.sh"); }

main_menu(){
  while :; do
    banner
    printf '\n  %s╔═══════════════════════════════════╦═══════════════════════════════════╗%s\n' "$Y" "$N"
    printf '  %s║%s %s[ 1]%s %-28s %s│%s %s[ 6]%s %-28s %s║%s\n' "$Y" "$N" "$Y" "$N" "Install Tunnel Engines" "$DY" "$N" "$Y" "$N" "DUCKY Web Panel (B/W/Y)" "$Y" "$N"
    printf '  %s║%s %s[ 2]%s %-28s %s│%s %s[ 7]%s %-28s %s║%s\n' "$Y" "$N" "$Y" "$N" "Deploy New Tunnel (62)" "$DY" "$N" "$Y" "$N" "Telegram Control Bot" "$Y" "$N"
    printf '  %s║%s %s[ 3]%s %-28s %s│%s %s[ 8]%s %-28s %s║%s\n' "$Y" "$N" "$Y" "$N" "Manage Mesh & Failover" "$DY" "$N" "$Y" "$N" "Sentinel Watchdog & Backup" "$Y" "$N"
    printf '  %s║%s %s[ 4]%s %-28s %s│%s %s[ 9]%s %-28s %s║%s\n' "$Y" "$N" "$Y" "$N" "Live Traffic Monitor (Top)" "$DY" "$N" "$Y" "$N" "Connection Test & Doctor" "$Y" "$N"
    printf '  %s║%s %s[ 5]%s %-28s %s│%s %s[ 0]%s %-28s %s║%s\n' "$Y" "$N" "$Y" "$N" "Auto-Tune Kernel, RPS & DNS" "$DY" "$N" "$Y" "$N" "Exit DUCKY Suite" "$Y" "$N"
    printf '  %s╚═══════════════════════════════════╩═══════════════════════════════════╝%s\n\n' "$Y" "$N"
    ask "Command"
    case $REPLY in
      1) for e in kernel wg backhaul rathole realm frp gost; do install_engine "$e"; done ;;
      2) deploy_wizard ;;
      3) manage_mesh ;;
      4) live_monitor; continue ;;
      5) auto_tune_server throughput; fw_shield enable; set_dns shecan ;;
      6) panel_install ;;
      7) tgbot_wizard ;;
      8) sentinel_ctl enable 40; backup_vault ;;
      9) run_doctor; echo "  Test link: $(conntest_server)" ;;
      0) printf '\n  %s[ DUCKY ]%s  t.me/Em4dloverS\n\n' "$BY" "$N"; exit 0 ;;
    esac
    pause
  done
}
