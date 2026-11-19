# DUCKY Tunnel Suite v2.0 - Module 3: Strictly Compliant Backhaul, Rathole Hybrid, Realm, FRP, GOST + MikroTik RouterOS 7

emit_acct_rules(){
  local cp=${CPORT:-0}
  echo 'acct(){ local o=$1'
  if [ -n "$cp" ] && [ "$cp" != "0" ]; then
    echo "  iptables -t mangle \$o INPUT -p tcp --sport $cp -m comment --comment \"dky-rx-$NAME\" 2>/dev/null || true"
    echo "  iptables -t mangle \$o INPUT -p tcp --dport $cp -m comment --comment \"dky-rx-$NAME\" 2>/dev/null || true"
    echo "  iptables -t mangle \$o OUTPUT -p tcp --sport $cp -m comment --comment \"dky-tx-$NAME\" 2>/dev/null || true"
    echo "  iptables -t mangle \$o OUTPUT -p tcp --dport $cp -m comment --comment \"dky-tx-$NAME\" 2>/dev/null || true"
  fi
  echo '}'
}

build_backhaul_runner(){
  local f="$SPEC/$NAME.dkspec" tr=${TYPE#backhaul-} t pl="" extra="" tune="" udp=0 cores pool
  cores=$(cpu_cores)
  pool=${POOL:-$(( cores * 8 ))}; [ "$pool" -lt 8 ] 2>/dev/null && pool=8; [ "$pool" -gt 128 ] 2>/dev/null && pool=128
  [ "$tr" = tcpudp ] && { tr=tcp; udp=1; }

  emit_acct_rules
  echo 'case $1 in start) acct -D; acct -I'

  # Strictly valid Musixal/Backhaul TOML fields per transport (no invalid keys!)
  if [ "$ROLE" = iran ]; then
    for t in $(port_tokens); do pl+="\"$t\", "; done
    if [ "$tr" = tcp ]; then
      tune=$(printf 'accept_udp = %s\nkeepalive_period = 75\nnodelay = true\nheartbeat = 40\nchannel_size = 2048\nsniffer = false\n' "$([ $udp = 1 ] && echo true || echo false)")
    elif [ "$tr" = tcpmux ] || [ "$tr" = wsmux ] || [ "$tr" = wssmux ]; then
      tune=$(printf 'keepalive_period = 75\nnodelay = true\nheartbeat = 40\nchannel_size = 2048\nmux_con = %d\nmux_version = 1\nmux_framesize = 32768\nmux_recievebuffer = 4194304\nmux_streambuffer = 65536\nsniffer = false\n' "$cores")
    elif [ "$tr" = ws ] || [ "$tr" = wss ]; then
      tune=$'keepalive_period = 75\nnodelay = true\nheartbeat = 40\nchannel_size = 2048\nsniffer = false\n'
    else
      # native udp
      tune=$'heartbeat = 20\nchannel_size = 2048\nsniffer = false\n'
    fi
    if [ "$tr" = wss ] || [ "$tr" = wssmux ]; then
      [ -f "$CIPHER/$NAME.dkcrt" ] || {
        openssl ecparam -name secp384r1 -genkey -noout -out "$CIPHER/$NAME.dkkey" 2>/dev/null
        openssl req -new -x509 -sha384 -key "$CIPHER/$NAME.dkkey" -out "$CIPHER/$NAME.dkcrt" -days 3650 -subj "/CN=ducky.local" 2>/dev/null
        chmod 600 "$CIPHER/$NAME.dkkey"
      }
      extra=$(printf 'tls_cert = "%s"\ntls_key = "%s"\n' "$CIPHER/$NAME.dkcrt" "$CIPHER/$NAME.dkkey")
    fi
    printf '[server]\nbind_addr = "0.0.0.0:%s"\ntransport = "%s"\ntoken = "%s"\n%s%slog_level = "info"\nports = [%s]\n' \
      "$CPORT" "$tr" "$TOKEN" "$extra" "$tune" "${pl%, }" >"$f"
  else
    if [ "$tr" = udp ]; then
      tune=$(printf 'connection_pool = %d\naggressive_pool = false\nretry_interval = 3\nsniffer = false\n' "$pool")
    else
      tune=$(printf 'connection_pool = %d\naggressive_pool = false\nkeepalive_period = 75\ndial_timeout = 10\nnodelay = true\nretry_interval = 3\nsniffer = false\n' "$pool")
      [ -n "${EDGE_IP:-}" ] && tune+=$(printf 'edge_ip = "%s"\n' "$EDGE_IP")
      if [ "$tr" = tcpmux ] || [ "$tr" = wsmux ] || [ "$tr" = wssmux ]; then
        tune+=$'mux_version = 1\nmux_framesize = 32768\nmux_recievebuffer = 4194304\nmux_streambuffer = 65536\n'
      fi
    fi
    printf '[client]\nremote_addr = "%s:%s"\ntransport = "%s"\ntoken = "%s"\n%slog_level = "info"\n' \
      "$REMOTE" "$CPORT" "$tr" "$TOKEN" "$tune" >"$f"
  fi
  chmod 600 "$f"
  aq_log code "نوشتن فایل استاندارد Backhaul در $f (transport=$tr accept_udp=$udp)"
  echo "  exec /usr/local/bin/backhaul -c $f ;;"
  echo ' stop) acct -D ;; esac'
}

build_rathole_runner(){
  local f="$SPEC/$NAME.dkspec" p tr_blk=""
  if [ "$TYPE" = "rathole-ws" ]; then
    tr_blk=$(printf '[%s.transport]\ntype = "websocket"\n' "$([ "$ROLE" = iran ] && echo server || echo client)")
  else
    tr_blk=$(printf '[%s.transport]\ntype = "tcp"\n[%s.transport.tcp]\nnodelay = true\nkeepalive_secs = 15\n' \
      "$([ "$ROLE" = iran ] && echo server || echo client)" "$([ "$ROLE" = iran ] && echo server || echo client)")
  fi

  emit_acct_rules
  echo 'case $1 in start) acct -D; acct -I'
  if [ "$ROLE" = iran ]; then
    {
      printf '[server]\nbind_addr = "0.0.0.0:%s"\ndefault_token = "%s"\nheartbeat_interval = 15\n%s\n' "$CPORT" "$TOKEN" "$tr_blk"
      for t in $(port_tokens); do
        local lp=${t%%=*}
        if [[ $t == *-* ]]; then
          for p in $(seq "${t%-*}" "${t#*-}"); do
            if [ "$TYPE" = "rathole-hybrid" ]; then
              printf '[server.services.p%s_tcp]\nbind_addr = "0.0.0.0:%s"\ntype = "tcp"\nnodelay = true\n\n[server.services.p%s_udp]\nbind_addr = "0.0.0.0:%s"\ntype = "udp"\n\n' "$p" "$p" "$p" "$p"
            elif [ "$TYPE" = "rathole-udp" ]; then
              printf '[server.services.p%s_udp]\nbind_addr = "0.0.0.0:%s"\ntype = "udp"\n\n' "$p" "$p"
            else
              printf '[server.services.p%s_tcp]\nbind_addr = "0.0.0.0:%s"\ntype = "tcp"\nnodelay = true\n\n' "$p" "$p"
            fi
          done
        else
          if [ "$TYPE" = "rathole-hybrid" ]; then
            printf '[server.services.p%s_tcp]\nbind_addr = "0.0.0.0:%s"\ntype = "tcp"\nnodelay = true\n\n[server.services.p%s_udp]\nbind_addr = "0.0.0.0:%s"\ntype = "udp"\n\n' "$lp" "$lp" "$lp" "$lp"
          elif [ "$TYPE" = "rathole-udp" ]; then
            printf '[server.services.p%s_udp]\nbind_addr = "0.0.0.0:%s"\ntype = "udp"\n\n' "$lp" "$lp"
          else
            printf '[server.services.p%s_tcp]\nbind_addr = "0.0.0.0:%s"\ntype = "tcp"\nnodelay = true\n\n' "$lp" "$lp"
          fi
        fi
      done
    } >"$f"
  else
    {
      printf '[client]\nremote_addr = "%s:%s"\ndefault_token = "%s"\nheartbeat_timeout = 30\nretry_interval = 1\n%s\n' "$REMOTE" "$CPORT" "$TOKEN" "$tr_blk"
      for t in $(port_tokens); do
        local lp=${t%%=*} rp=${t#*=}
        if [[ $t == *-* ]]; then
          for p in $(seq "${t%-*}" "${t#*-}"); do
            if [ "$TYPE" = "rathole-hybrid" ]; then
              printf '[client.services.p%s_tcp]\nlocal_addr = "127.0.0.1:%s"\ntype = "tcp"\nnodelay = true\n\n[client.services.p%s_udp]\nlocal_addr = "127.0.0.1:%s"\ntype = "udp"\n\n' "$p" "$p" "$p" "$p"
            elif [ "$TYPE" = "rathole-udp" ]; then
              printf '[client.services.p%s_udp]\nlocal_addr = "127.0.0.1:%s"\ntype = "udp"\n\n' "$p" "$p"
            else
              printf '[client.services.p%s_tcp]\nlocal_addr = "127.0.0.1:%s"\ntype = "tcp"\nnodelay = true\n\n' "$p" "$p"
            fi
          done
        else
          if [ "$TYPE" = "rathole-hybrid" ]; then
            printf '[client.services.p%s_tcp]\nlocal_addr = "127.0.0.1:%s"\ntype = "tcp"\nnodelay = true\n\n[client.services.p%s_udp]\nlocal_addr = "127.0.0.1:%s"\ntype = "udp"\n\n' "$lp" "$rp" "$lp" "$rp"
          elif [ "$TYPE" = "rathole-udp" ]; then
            printf '[client.services.p%s_udp]\nlocal_addr = "127.0.0.1:%s"\ntype = "udp"\n\n' "$lp" "$rp"
          else
            printf '[client.services.p%s_tcp]\nlocal_addr = "127.0.0.1:%s"\ntype = "tcp"\nnodelay = true\n\n' "$lp" "$rp"
          fi
        fi
      done
    } >"$f"
  fi
  chmod 600 "$f"
  aq_log code "نوشتن فایل Rathole در $f (mode=$TYPE)"
  echo "  exec /usr/local/bin/rathole $f ;;"
  echo ' stop) acct -D ;; esac'
}

build_realm_runner(){
  local f="$SPEC/$NAME.dkspec"
  emit_acct_rules
  echo 'case $1 in start) acct -D; acct -I'
  if [ "$ROLE" = iran ]; then
    {
      printf '[log]\nlevel = "warn"\n\n[network]\nno_tcp = false\nuse_udp = true\ntcp_timeout = 5\nudp_timeout = 30\n\n'
      for t in $(port_tokens); do
        local lp=${t%%=*} rp=${t#*=}
        if [[ $t == *-* ]]; then
          for p in $(seq "${t%-*}" "${t#*-}"); do
            printf '[[endpoints]]\nlisten = "0.0.0.0:%s"\nremote = "%s:%s"\n\n' "$p" "$REMOTE" "$p"
          done
        else
          printf '[[endpoints]]\nlisten = "0.0.0.0:%s"\nremote = "%s:%s"\n\n' "$lp" "$REMOTE" "$rp"
        fi
      done
    } >"$f"
    chmod 600 "$f"
    echo "  exec /usr/local/bin/realm -c $f ;;"
  else
    echo "  exec sleep infinity ;;"
  fi
  echo ' stop) acct -D ;; esac'
}

build_frp_runner(){
  local pr=${TYPE#frp-} f="$SPEC/$NAME.dkspec" p
  [ "$pr" = ws ] && pr=websocket
  emit_acct_rules
  echo 'case $1 in start) acct -D; acct -I'
  if [ "$ROLE" = iran ]; then
    {
      printf 'bindPort = %s\nauth.token = "%s"\ntransport.tcpMux = true\n' "$CPORT" "$TOKEN"
      [ "$pr" = kcp ] && echo "kcpBindPort = $CPORT"
      [ "$pr" = quic ] && echo "quicBindPort = $CPORT"
    } >"$f"
    chmod 600 "$f"
    echo "  exec /usr/local/bin/frps -c $f ;;"
  else
    {
      printf 'serverAddr = "%s"\nserverPort = %s\nauth.token = "%s"\ntransport.protocol = "%s"\ntransport.tcpMux = true\ntransport.poolCount = %s\n' \
        "$REMOTE" "$CPORT" "$TOKEN" "$pr" "$(cpu_cores)"
      for p in $(port_list); do
        printf '[[proxies]]\nname = "p%s"\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = %s\nremotePort = %s\n' "$p" "$p" "$p"
      done
    } >"$f"
    chmod 600 "$f"
    echo "  exec /usr/local/bin/frpc -c $f ;;"
  fi
  echo ' stop) acct -D ;; esac'
}

build_gost_runner(){
  local fam=${TYPE%%-*} t=${TYPE#*-} base=relay sch a="" p
  [ "$fam" = gosts ] && base=socks5
  sch="$base+$t"; [ "$t" = tcp ] && sch=$base
  emit_acct_rules
  echo 'case $1 in start) acct -D; acct -I'
  if [ "$ROLE" = foreign ]; then
    echo "  exec /usr/local/bin/gost -L \"$sch://ducky:$TOKEN@:$CPORT\" ;;"
  else
    for p in $(port_list); do a+=" -L tcp://:$p/127.0.0.1:$p -L udp://:$p/127.0.0.1:$p"; done
    echo "  exec /usr/local/bin/gost$a -F \"$sch://ducky:$TOKEN@$REMOTE:$CPORT\" ;;"
  fi
  echo ' stop) acct -D ;; esac'
}

# ---------- Ready-to-Paste MikroTik RouterOS 7 Generator ----------
mikrotik_snippet(){
  load_node "$1" 2>/dev/null; [ -n "${TYPE:-}" ] || return 0
  case $TYPE in
    gre)
      printf '/interface gre add name=dky%s local-address=%s remote-address=%s mtu=%s\n/ip address add address=10.88.%s.2/30 interface=dky%s\n' "$IDX" "$REMOTE" "$LOCAL" "${TMTU:-1420}" "$IDX" "$IDX" ;;
    ipip)
      printf '/interface ipip add name=dky%s local-address=%s remote-address=%s mtu=%s\n/ip address add address=10.88.%s.2/30 interface=dky%s\n' "$IDX" "$REMOTE" "$LOCAL" "${TMTU:-1440}" "$IDX" "$IDX" ;;
    6to4-sit)
      printf '/interface 6to4 add name=dky%s local-address=%s remote-address=%s mtu=%s\n/ipv6 address add address=fd88:%s::2/64 interface=dky%s\n' "$IDX" "$REMOTE" "$LOCAL" "${TMTU:-1420}" "$IDX" "$IDX" ;;
    vxlan)
      printf '/interface vxlan add name=dky%s vni=%s port=%s mtu=%s\n/interface vxlan vteps add interface=dky%s remote-ip=%s\n/ip address add address=10.88.%s.2/30 interface=dky%s\n' "$IDX" "$IDX" "$((4789+IDX))" "${TMTU:-1380}" "$IDX" "$LOCAL" "$IDX" "$IDX" ;;
    wg|wg-*)
      local pub=$(cat "$CIPHER/$NAME.dkpub" 2>/dev/null || echo "<IRAN_PUBLIC_KEY>")
      printf '/interface wireguard add name=dky%s listen-port=%s mtu=%s\n/interface wireguard peers add interface=dky%s public-key="%s" endpoint-address=%s endpoint-port=%s allowed-address=10.88.%s.0/30 persistent-keepalive=15s\n/ip address add address=10.88.%s.2/30 interface=dky%s\n' "$IDX" "$((51800+IDX))" "${TMTU:-1380}" "$IDX" "$pub" "$LOCAL" "$((51800+IDX))" "$IDX" "$IDX" "$IDX" ;;
  esac
}
