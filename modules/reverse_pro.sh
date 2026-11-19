# DUCKY Tunnel Suite v1.0 - Module 3: Reverse & Forward Pro Engines (Backhaul, Rathole Hybrid TCP+UDP, Realm, FRP, GOST)

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
  pool=${POOL:-$(( cores * 16 ))}; [ "$pool" -lt 64 ] 2>/dev/null && pool=64; [ "$pool" -gt 256 ] 2>/dev/null && pool=256
  [ "$tr" = tcpudp ] && { tr=tcp; udp=1; }

  emit_acct_rules
  echo 'case $1 in start) acct -D; acct -I'
  if [ "$tr" = tcp ] || [ "$tr" = tcpmux ] || [ "$tr" = ws ] || [ "$tr" = wsmux ] || [ "$tr" = wss ] || [ "$tr" = wssmux ]; then
    if [ "$ROLE" = iran ]; then
      tune=$(printf 'keepalive_period = 20\nnodelay = true\nheartbeat = 15\nchannel_size = 4096\nmux_con = %d\nsniffer = false\n' "$cores")
    else
      tune=$(printf 'connection_pool = %d\naggressive_pool = true\nkeepalive_period = 20\ndial_timeout = 5\nnodelay = true\nretry_interval = 1\nsniffer = false\n' "$pool")
      [ -n "${EDGE_IP:-}" ] && tune+=$(printf 'edge_ip = "%s"\n' "$EDGE_IP")
    fi
  else
    tune=$'heartbeat = 20\nchannel_size = 2048\nsniffer = false\n'
    [ "$ROLE" = foreign ] && tune=$(printf 'connection_pool = %d\naggressive_pool = true\nretry_interval = 1\nsniffer = false\n' "$pool")
  fi

  if [ "$ROLE" = iran ]; then
    for t in $(port_tokens); do pl+="\"$t\", "; done
    [ $udp = 1 ] && extra=$'accept_udp = true\n'
    if [ "$tr" = wss ] || [ "$tr" = wssmux ]; then
      [ -f "$CIPHER/$NAME.dkcrt" ] || {
        openssl ecparam -name secp384r1 -genkey -noout -out "$CIPHER/$NAME.dkkey" 2>/dev/null
        openssl req -new -x509 -sha384 -key "$CIPHER/$NAME.dkkey" -out "$CIPHER/$NAME.dkcrt" -days 3650 -subj "/CN=ducky.local" 2>/dev/null
        chmod 600 "$CIPHER/$NAME.dkkey"
      }
      extra+=$'tls_cert = "'"$CIPHER/$NAME.dkcrt"$'"\ntls_key = "'"$CIPHER/$NAME.dkkey"$'"\n'
    fi
    printf '[server]\nbind_addr = "0.0.0.0:%s"\ntransport = "%s"\n%stoken = "%s"\n%slog_level = "info"\nports = [%s]\n' \
      "$CPORT" "$tr" "$extra" "$TOKEN" "$tune" "${pl%, }" >"$f"
  else
    printf '[client]\nremote_addr = "%s:%s"\ntransport = "%s"\ntoken = "%s"\n%slog_level = "info"\n' \
      "$REMOTE" "$CPORT" "$tr" "$TOKEN" "$tune" >"$f"
  fi
  chmod 600 "$f"
  aq_log code "نوشتن فایل Backhaul Spec در $f (transport=$tr accept_udp=$udp pool=$pool)"
  echo "  exec backhaul -c $f ;;"
  echo ' stop) acct -D ;; esac'
}

build_rathole_runner(){
  local f="$SPEC/$NAME.dkspec" p tr_blk=""
  if [ "$TYPE" = "rathole-noise" ]; then
    # Derive deterministic Noise X25519 keys or use standard TCP nodelay fallback if rathole doesn't support genkey
    tr_blk=$(printf '[%s.transport]\ntype = "tcp"\n[%s.transport.tcp]\nnodelay = true\nkeepalive_secs = 15\nkeepalive_interval = 5\n' \
      "$([ "$ROLE" = iran ] && echo server || echo client)" "$([ "$ROLE" = iran ] && echo server || echo client)")
  elif [ "$TYPE" = "rathole-ws" ]; then
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
        local lp=${t%%=*} rp=${t#*=}
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
  aq_log code "نوشتن فایل Rathole Hybrid Spec در $f (mode=$TYPE)"
  echo "  exec rathole $f ;;"
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
    aq_log code "نوشتن فایل Realm Rust Forwarder در $f (TCP+UDP Zero-Copy)"
    echo "  exec realm -c $f ;;"
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
    echo "  exec frps -c $f ;;"
  else
    {
      printf 'serverAddr = "%s"\nserverPort = %s\nauth.token = "%s"\ntransport.protocol = "%s"\ntransport.tcpMux = true\ntransport.poolCount = %s\n' \
        "$REMOTE" "$CPORT" "$TOKEN" "$pr" "$(cpu_cores)"
      for p in $(port_list); do
        printf '[[proxies]]\nname = "p%s"\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = %s\nremotePort = %s\n' "$p" "$p" "$p"
      done
    } >"$f"
    chmod 600 "$f"
    echo "  exec frpc -c $f ;;"
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
    echo "  exec gost -L \"$sch://ducky:$TOKEN@:$CPORT\" ;;"
  else
    for p in $(port_list); do a+=" -L tcp://:$p/127.0.0.1:$p -L udp://:$p/127.0.0.1:$p"; done
    echo "  exec gost$a -F \"$sch://ducky:$TOKEN@$REMOTE:$CPORT\" ;;"
  fi
  echo ' stop) acct -D ;; esac'
}
