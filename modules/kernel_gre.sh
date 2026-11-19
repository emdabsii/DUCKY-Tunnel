# DUCKY Tunnel Suite v1.0 - Module 2: Kernel GRE, 6to4-SIT, 6to4-GRE, FOU/GUE, VXLAN, GENEVE, WireGuard & DNAT
# Supports Port Mapping (443 or 2053=8443), Isolated Subnets (10.88.N.0/30), TCPMSS Clamp & Clean Teardown.

valid_ports(){
  local t a b; [ -n "$1" ] || return 1
  for t in ${1//,/ }; do
    if [[ $t =~ ^([0-9]+)=([0-9]+)$ ]]; then
      a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
      [ "$a" -ge 1 ] && [ "$a" -le 65535 ] && [ "$b" -ge 1 ] && [ "$b" -le 65535 ] || return 1
    elif [[ $t =~ ^([0-9]+)-([0-9]+)$ ]]; then
      a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
      [ "$a" -ge 1 ] && [ "$b" -le 65535 ] && [ "$a" -le "$b" ] || return 1
    elif [[ $t =~ ^[0-9]+$ ]]; then
      [ "$t" -ge 1 ] && [ "$t" -le 65535 ] || return 1
    else return 1; fi
  done
}
port_tokens(){ echo "${PORTS//,/ }"; }
port_list(){
  local t
  for t in $(port_tokens); do
    if [[ $t == *=* ]]; then echo "${t%%=*}"
    elif [[ $t == *-* ]]; then seq "${t%-*}" "${t#*-}"
    else echo "$t"; fi
  done
}

build_kernel_runner(){
  local a=1 b=2 ifn="dky$IDX" mk="" pre="" post="" inp="" MTU=1420 fp=$((31000+IDX)) extra="" wa=""
  [ "$ROLE" = foreign ] && { a=2; b=1; }
  case $TYPE in
    gre)      MTU=1420; mk="ip tunnel add $ifn mode gre local $LOCAL remote $REMOTE ttl 255"; inp="-p gre" ;;
    gre-key)  MTU=1416; mk="ip tunnel add $ifn mode gre local $LOCAL remote $REMOTE key $((2000+IDX)) ttl 255"; inp="-p gre" ;;
    gretap)   MTU=1400; mk="ip link add $ifn type gretap local $LOCAL remote $REMOTE ttl 255"; inp="-p gre" ;;
    ipip)     MTU=1440; mk="ip tunnel add $ifn mode ipip local $LOCAL remote $REMOTE ttl 255"; inp="-p ipencap" ;;
    6to4-sit)
      MTU=1420
      mk="ip tunnel add $ifn mode sit local $LOCAL remote $REMOTE ttl 255"
      inp="-p ipv6"
      ;;
    6to4-gre)
      # Dual-layer: SIT creates private IPv6 link (fd88:IDX::1 <-> fd88:IDX::2), IP6GRE rides inside it!
      MTU=1360
      local sitn="dkysit$IDX"
      pre="ip tunnel del $sitn 2>/dev/null; ip tunnel add $sitn mode sit local $LOCAL remote $REMOTE ttl 255 && ip addr add fd88:${IDX}::${a}/64 dev $sitn && ip link set $sitn mtu 1420 up"
      post="ip tunnel del $sitn 2>/dev/null"
      mk="ip link add $ifn type ip6gre local fd88:${IDX}::${a} remote fd88:${IDX}::${b} ttl 255"
      inp="-p ipv6"
      ;;
    gre6)     MTU=1380; mk="ip link add $ifn type ip6gre local $LOCAL remote $REMOTE ttl 255" ;;
    gre6tap)  MTU=1360; mk="ip link add $ifn type ip6gretap local $LOCAL remote $REMOTE ttl 255" ;;
    ipip6)    MTU=1380; mk="ip link add $ifn type ip6tnl mode ipip6 local $LOCAL remote $REMOTE" ;;
    *-fou|*-gue)
      MTU=1380; local k=${TYPE%%-*} e=${TYPE##*-} ipp=47
      [ "$k" = ipip ] && ipp=4
      pre="modprobe fou 2>/dev/null; ip fou del port $fp 2>/dev/null; ip fou add port $fp $([ "$e" = gue ] && echo gue || echo "ipproto $ipp")"
      post="ip fou del port $fp 2>/dev/null"
      mk="ip link add $ifn type $k local $LOCAL remote $REMOTE ttl 255 encap $e encap-sport auto encap-dport $fp"
      inp="-p udp --dport $fp"
      ;;
    vxlan)    MTU=1380; mk="ip link add $ifn type vxlan id $IDX local $LOCAL remote $REMOTE dstport $((4789+IDX)) nolearning"; inp="-p udp --dport $((4789+IDX))" ;;
    geneve)   MTU=1380; mk="ip link add $ifn type geneve id $IDX remote $REMOTE dstport $((6081+IDX))"; inp="-p udp --dport $((6081+IDX))" ;;
    wg|wg-*)
      MTU=1380; [ "$TYPE" = wg-1320 ] && MTU=1320; [ "$TYPE" = wg-1280 ] && MTU=1280
      mk="ip link add $ifn type wireguard"; inp="-p udp --dport $((51800+IDX))"
      ;;
  esac
  [ -n "${TMTU:-}" ] && [ "${TMTU:-0}" -ge 1200 ] 2>/dev/null && MTU=$TMTU

  aq_log code "sysctl -w net.ipv4.ip_forward=1 rp_filter=0 (ifn=$ifn mtu=$MTU)"
  echo "sysctl -qw net.ipv4.ip_forward=1 net.ipv6.conf.all.forwarding=1 net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0"
  echo 'rules(){ local o=$1 i=$1; [ "$o" = -A ] && i=-I'
  if [ "$TYPE" != dnat ]; then
    echo "  iptables \$i INPUT -i $ifn -m comment --comment \"dky-$NAME\" -j ACCEPT"
    echo "  iptables \$i FORWARD -i $ifn -m comment --comment \"dky-$NAME\" -j ACCEPT"
    echo "  iptables \$i FORWARD -o $ifn -m comment --comment \"dky-$NAME\" -j ACCEPT"
    echo "  iptables -t mangle \$o POSTROUTING -o $ifn -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $((MTU-40))"
    echo "  iptables -t mangle \$o FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu"
  fi
  [ -n "$inp" ] && echo "  iptables \$i INPUT $inp -s $REMOTE -m comment --comment \"dky-$NAME\" -j ACCEPT"

  if [ "$ROLE" = iran ]; then
    local dst="10.88.$IDX.2"; [ "$TYPE" = dnat ] && dst=$REMOTE
    for tok in $(port_tokens); do
      for pr in tcp udp; do
        if [[ $tok == *=* ]]; then
          local lp=${tok%%=*} rp=${tok#*=}
          echo "  iptables -t nat \$o PREROUTING -p $pr --dport $lp -m comment --comment \"dky-$NAME\" -j DNAT --to-destination $dst:$rp"
        else
          echo "  iptables -t nat \$o PREROUTING -p $pr --dport ${tok/-/:} -m comment --comment \"dky-$NAME\" -j DNAT --to-destination $dst"
        fi
      done
    done
    if [ "$TYPE" = dnat ]; then
      echo "  iptables -t nat \$o POSTROUTING -d $REMOTE -m comment --comment \"dky-$NAME\" -j MASQUERADE"
      echo "  iptables \$i FORWARD -d $REMOTE -m comment --comment \"dky-$NAME\" -j ACCEPT"
      echo "  iptables \$i FORWARD -s $REMOTE -m comment --comment \"dky-$NAME\" -j ACCEPT"
    else
      echo "  iptables -t nat \$o POSTROUTING -o $ifn -m comment --comment \"dky-$NAME\" -j MASQUERADE"
    fi
  fi
  echo '  :'; echo '}'
  echo 'case $1 in'
  echo ' start)'
  if [ "$TYPE" = dnat ]; then
    echo "  rules -D 2>/dev/null; rules -A ;;"
    echo " stop) rules -D 2>/dev/null ;;"
  else
    [ -n "$pre" ] && echo "  $pre"
    echo "  ip link del $ifn 2>/dev/null; $mk || exit 1"
    if [[ $TYPE == wg* ]]; then
      wa="private-key $CIPHER/$NAME.dkkey listen-port $((51800+IDX))"
      if [ "$TYPE" = wg-psk ]; then
        printf "$(printf %s "$(printf %s "$TOKEN" | sha256sum | cut -d' ' -f1)" | sed 's/../\\x&/g')" | base64 >"$CIPHER/$NAME.dkpsk"
        chmod 600 "$CIPHER/$NAME.dkpsk"
        extra=" preshared-key $CIPHER/$NAME.dkpsk"
      fi
      if [ -n "${PEER:-}" ]; then
        wa+=" peer $PEER$extra allowed-ips 10.88.$IDX.0/30"
        [ "$ROLE" = iran ] && wa+=" endpoint $REMOTE:$((51800+IDX)) persistent-keepalive 15"
      fi
      echo "  wg set $ifn $wa"
    fi
    if [ "$TYPE" = "6to4-sit" ]; then
      echo "  ip addr add fd88:${IDX}::${a}/64 dev $ifn; ip addr add 10.88.$IDX.$a/30 dev $ifn 2>/dev/null || true"
    else
      echo "  ip addr add 10.88.$IDX.$a/30 dev $ifn"
    fi
    echo "  ip link set $ifn txqueuelen 10000 mtu $MTU up"
    echo "  command -v ufw >/dev/null && ufw allow in on $ifn >/dev/null 2>&1"
    echo "  rules -D 2>/dev/null; rules -A ;;"
    echo " stop) rules -D 2>/dev/null; ip link del $ifn 2>/dev/null; $post ;;"
  fi
  echo 'esac'
}
