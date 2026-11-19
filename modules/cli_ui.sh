# DUCKY Tunnel Suite v2.0 - Module 6: Ultra-Clean Minimalist Black/White/Yellow CLI
# Strictly ONLY Black, Pure White (\e[1;97m), and Electric Yellow (\e[1;33m) — ZERO other colors!

banner(){
  [ -n "${DUCKY_DEMO:-}" ] || clear
  # Custom slanted geometric blade font:
  # DUCKY = Large (6 lines), alternating Yellow & White letters (D=Y, U=W, C=Y, K=W, Y=Y)
  # TUNNEL = Half-size (3 lines), aligned right next to DUCKY in Pure White
  printf '\n'
  printf '  %s/====\\%s  %s||  ||%s   %s/====%s  %s||  //%s  %s\\\\  //%s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N"
  printf '  %s||   ||%s %s||  ||%s  %s||    %s  %s|| // %s   %s\\\\// %s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N"
  printf '  %s||   ||%s %s||  ||%s  %s||    %s  %s||<<  %s    %s||  %s   %s══╦══ ╦  ╦ ╔═╗ ╔═╗ ╔══ ╦  %s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"
  printf '  %s||   ||%s %s||  ||%s  %s||    %s  %s|| \\\\ %s    %s||  %s   %s  ║   ║  ║ ║ ║ ║ ║ ╠═  ║  %s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"
  printf '  %s\\====/%s  %s\\====/%s   %s\\====%s  %s||  \\\\%s    %s||  %s   %s  ╩   ╚══╝ ╩ ╩ ╩ ╩ ╚══ ╚══%s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"
  printf '\n'
}

hdr(){
  printf '\n  %s▸%s %s%s%s\n\n' "$Y" "$N" "$W" "$1" "$N"
}
ask(){ local v; printf '  %s▸%s %s%s%s%s: ' "$Y" "$N" "$W" "$1" "${2:+ ${D}[$2]${N}}" "$N"; read -r v; REPLY=${v:-${2:-}}; }
pause(){ printf '\n  %sPress Enter to continue...%s' "$D" "$N"; read -r _; }

panel_cfg(){ python3 "$APP/panel/app.py" set "$@"; }
panel_url(){ python3 "$APP/panel/app.py" url "$MYIP"; }

panel_install(){
  hdr "DUCKY Web Panel"
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
  myip
  printf '  %sURL      :%s %s%s%s\n' "$Y" "$N" "$W" "$(panel_url)" "$N"
  [ $fresh = 1 ] && printf '  %sUsername :%s %sadmin%s\n  %sPassword :%s %s%s%s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$pass" "$N"
}

proxy_ctl(){
  hdr "Built-in SOCKS5 / HTTP Proxy"
  ask "Proxy Port (binds to 127.0.0.1 only)" "10800"; local pp=$REPLY
  ask "Username (Enter = no auth)" ""; local pu=$REPLY
  local pw=""; [ -n "$pu" ] && { ask "Password"; pw=$REPLY; }
  mkdir -p "$VAULT"
  printf '{"port":%s,"user":"%s","pass":"%s","bind":"127.0.0.1"}\n' "$pp" "$pu" "$pw" >"$VAULT/proxy.dkcfg"
  chmod 600 "$VAULT/proxy.dkcfg"
  cat >"$UNITDIR/dky-proxy.service" <<EOF
[Unit]
Description=DUCKY Built-in SOCKS5/HTTP Proxy
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 $APP/modules/proxy.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  sysd daemon-reload; sysd enable --now dky-proxy >/dev/null 2>&1; sysd restart dky-proxy >/dev/null 2>&1
  printf '  %s[ OK ]%s Proxy active on 127.0.0.1:%s (forward port %s=%s from Iran)\n' "$Y" "$N" "$pp" "$pp" "$pp"
}

tgbot_wizard(){
  hdr "Telegram Control Bot"
  [ -f "$VAULT/panel.dkcfg" ] || panel_install
  ask "Telegram Bot Token (from @BotFather)"; local tk=$REPLY
  ask "Your Admin Telegram Numeric ID"; local ch=$REPLY
  [ -n "$tk" ] && [ -n "$ch" ] || return
  panel_cfg "tg_token=$tk" "tg_chat=$ch"
  tgbot_ctl enable
  printf '  %s[ OK ]%s Send /start to your bot in Telegram.\n' "$Y" "$N"
}

live_monitor(){
  trap 'return 0' INT
  while :; do
    clear
    printf '\n  %sDUCKY%s %sLIVE MONITOR%s  %s(2s refresh | Ctrl+C to exit)%s\n\n' "$Y" "$N" "$W" "$N" "$D" "$N"
    printf '  %s%-14s %-20s %-8s %-16s %-10s %-10s%s\n' "$Y" "NODE" "PROTOCOL" "ROLE" "PEER IP" "STATE" "PING" "$N"
    for f in "$MESH"/*.dknode; do
      [ -f "$f" ] || continue
      (
        . "$f"
        st=$(sysd is-active "dky-mesh-$NAME" 2>/dev/null || echo stopped)
        pip=$REMOTE; [[ $TYPE =~ $KERNEL_RX ]] && pip="10.88.$IDX.$([ "$ROLE" = iran ] && echo 2 || echo 1)"
        rtt="-"
        [ "$st" = active ] && { rtt=$(ping -c 1 -W 1 "$pip" 2>/dev/null | grep -oE 'time=[0-9.]+' | cut -d= -f2); [ -n "$rtt" ] && rtt="${rtt}ms" || rtt="timeout"; }
        printf '  %s%-14s%s %-20s %-8s %-16s %s%-10s%s %s%-10s%s\n' "$W" "$NAME" "$N" "$(type_name "$TYPE")" "$ROLE" "$pip" "$([ "$st" = active ] && echo "$Y" || echo "$D")" "$st" "$N" "$W" "$rtt" "$N"
      )
    done
    sleep 2
  done
}

deploy_wizard(){
  hdr "Create Tunnel"
  printf '  %s[1]%s New Tunnel   %s[2]%s Paste ducky:// Link\n\n' "$Y" "$N" "$Y" "$N"
  ask "Mode" 1
  if [ "$REPLY" = 2 ]; then
    ask "Paste ducky:// link"; apply_link "$REPLY"; return
  fi
  local i=0 t n d g last=""
  while IFS='|' read -r t n d g; do
    [ -n "$t" ] || continue; i=$((i+1))
    [ "$g" != "$last" ] && { printf '\n  %s%s%s\n' "$Y" "$g" "$N"; last=$g; }
    printf '   %s[%2d]%s %s%-22s%s %s%s%s\n' "$Y" "$i" "$N" "$W" "$n" "$N" "$D" "$d" "$N"
  done <<<"$CATALOG"
  echo; ask "Protocol Number" 2
  TYPE=$(echo "$CATALOG" | sed -n "${REPLY}p" | cut -d'|' -f1); [ -n "$TYPE" ] || return
  ask "Tunnel Name" "dky$(next_idx)"; NAME=$REPLY
  printf '  %s[1]%s Iran (Entry)   %s[2]%s Foreign (Exit)\n' "$Y" "$N" "$Y" "$N"
  ask "Role" 1; [ "$REPLY" = 2 ] && ROLE=foreign || ROLE=iran
  myip; ask "This Server IP" "$MYIP"; LOCAL=$REPLY
  ask "Remote Server IP"; REMOTE=$REPLY
  ask "Tunnel ID (1-250)" "$(next_idx)"; IDX=$REPLY
  PORTS="1"; CPORT="0"; TOKEN=$(rand_token); PEER=""; NOTE=""; TMTU=""; BACKUP_NODE=""; QUOTA_GB="0"; EDGE_IP=""; POOL=""
  if [ "$ROLE" = iran ] || [[ $TYPE =~ $REVERSE_RX ]]; then
    ask "Ports (e.g. 443, 2053=8443, 2000-2100)" "443"; PORTS=$REPLY
  fi
  if [[ $(engine_of "$TYPE") =~ ^(backhaul|rathole|frp|gost)$ ]]; then
    ask "Control Port" "$((34000+IDX))"; CPORT=$REPLY
    [ "$ROLE" = foreign ] && { ask "Paste Token from Iran"; TOKEN=$REPLY; }
  fi
  ask "Backup Tunnel Name for Auto-Failover (Enter = none)" ""; BACKUP_NODE=$REPLY
  ask "Note (Enter = none)" ""; NOTE=$REPLY
  echo
  # Run directly (not hidden in subshell) so user sees live status and any real error immediately
  if deploy_node; then
    sleep 1
    local st=$(sysd is-active "dky-mesh-$NAME" 2>/dev/null || echo active)
    printf '\n  %sStatus:%s %s%s%s\n' "$Y" "$N" "$W" "$st" "$N"
    if [ "$st" != "active" ] && [ -z "${DUCKY_NOSYS:-}" ]; then
      printf '  %sService Log:%s\n' "$Y" "$N"
      journalctl -u "dky-mesh-$NAME" -n 12 --no-pager
    fi
    if [ "$ROLE" = iran ]; then
      printf '\n  %sForeign Server One-Line Setup:%s\n  %sducky apply-link '\''%s'\''%s\n' "$Y" "$N" "$W" "$(make_link "$NAME")" "$N"
      local mk=$(mikrotik_snippet "$NAME")
      [ -n "$mk" ] && printf '\n  %sMikroTik RouterOS 7:%s\n%s\n' "$Y" "$N" "$mk"
    fi
  fi
}

manage_mesh(){
  hdr "Manage Tunnels"
  local i=0 names=() n t r rem p s idx note tmtu bn qgb
  while IFS='|' read -r n t r rem p s idx note tmtu bn qgb; do
    [ -n "$n" ] || continue; i=$((i+1)); names+=("$n")
    printf '  %s[%2d]%s %s%-14s%s %-20s %-8s %-15s %s%s%s\n' "$Y" "$i" "$N" "$W" "$n" "$N" "$(type_name "$t")" "$r" "$rem" "$([ "$s" = active ] && echo "$Y" || echo "$D")" "$s" "$N"
  done < <(list_nodes)
  [ $i -eq 0 ] && { echo "  No tunnels yet."; return; }
  echo; ask "Select number (0=back)" 0; [ "$REPLY" = 0 ] && return
  local sel=${names[$((REPLY-1))]:-}; [ -n "$sel" ] || return
  printf '  %s[s]%s Start  %s[x]%s Stop  %s[r]%s Restart  %s[m]%s Auto-MTU  %s[h]%s Port-Hop  %s[f]%s Failover  %s[l]%s Logs  %s[i]%s Link  %s[d]%s Delete\n' "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N" "$Y" "$N"
  ask "Action" 0
  case $REPLY in
    s) node_act start "$sel" ;; x) node_act stop "$sel" ;; r) node_act restart "$sel" ;;
    m) mtu_probe "$sel" apply ;; h) hop_cport "$sel" ;; f) manual_failover "$sel" ;;
    l) journalctl -u "dky-mesh-$sel" -n 30 --no-pager ;;
    i) echo "  $(make_link "$sel")"; mikrotik_snippet "$sel" ;;
    d) ask "Type YES to delete $sel" no; [ "$REPLY" = YES ] && node_act delete "$sel" ;;
  esac
}

self_update(){ bash <(curl -fsSL "https://raw.githubusercontent.com/${DUCKY_GH:-emdabsii/DUCKY-Tunnel}/main/install.sh"); }

main_menu(){
  while :; do
    banner
    printf '  %s[1]%s %sCreate Tunnel%s               %s[6]%s %sWeb Panel%s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"
    printf '  %s[2]%s %sManage Tunnels%s              %s[7]%s %sTelegram Bot%s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"
    printf '  %s[3]%s %sConnection Test%s             %s[8]%s %sSentinel & Backup%s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"
    printf '  %s[4]%s %sLive Monitor%s                %s[9]%s %sBuilt-in Proxy%s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"
    printf '  %s[5]%s %sOptimize Kernel & DNS%s       %s[0]%s %sExit%s\n\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"
    ask "Select"
    case $REPLY in
      1) deploy_wizard ;;
      2) manage_mesh ;;
      3) hdr "Connection Test"; printf '  %sIran Test Link:%s %s\n' "$Y" "$N" "$(conntest_server)"; ask "Or paste test link / IP to probe (Enter=skip)" ""; [ -n "$REPLY" ] && conntest_client "$REPLY" ;;
      4) live_monitor; continue ;;
      5) auto_tune_server throughput; fw_shield enable; set_dns shecan ;;
      6) panel_install ;;
      7) tgbot_wizard ;;
      8) sentinel_ctl enable 40; backup_vault ;;
      9) proxy_ctl ;;
      0) printf '\n  %sDUCKY%s %sTUNNEL%s\n\n' "$Y" "$N" "$W" "$N"; exit 0 ;;
    esac
    pause
  done
}
