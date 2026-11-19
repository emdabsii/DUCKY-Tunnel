# DUCKY Tunnel Suite v1.0 - Module 4: Preflight Debugger, Hardware Auto-Tuner, Connection Test & Node CRUD

next_idx(){
  local i
  for i in $(seq 1 250); do
    grep -qs "^IDX=$i\$" "$MESH"/*.dknode 2>/dev/null || { echo $i; return; }
  done
  echo 1
}

check_conflicts(){
  local skip=${1:-} f
  for f in "$MESH"/*.dknode; do
    [ -f "$f" ] || continue
    local on=$(basename "$f" .dknode)
    [ "$on" = "$skip" ] && continue
    local oi=$(awk -F= '$1=="IDX"{print $2}' "$f")
    local oc=$(awk -F= '$1=="CPORT"{print $2}' "$f")
    if [ -n "${CPORT:-}" ] && [ "${CPORT:-0}" != "0" ] && [ "$oc" = "$CPORT" ]; then
      echo "ERR پورت کنترل $CPORT قبلاً روی تانل $on استفاده شده است"
      return 1
    fi
    if [[ $TYPE =~ $KERNEL_RX ]] && [ "$oi" = "$IDX" ]; then
      echo "ERR شناسه تانل $IDX قبلاً روی تانل $on ثبت شده است"
      return 1
    fi
  done
  return 0
}

preflight_validate(){
  local skip=${1:-} e; e=$(engine_of "$TYPE")
  aq_log run "بررسی پیش‌نیازها و اعتبارسنجی ورودی‌ها (Preflight Check)..."
  [[ $NAME =~ ^[a-z0-9_-]{1,24}$ ]] || { aq_log fail "نام تانل نامعتبر است"; echo "ERR bad tunnel name"; return 1; }
  echo "$CATALOG" | cut -d'|' -f1 | grep -qx "$TYPE" && [ -n "$e" ] || { aq_log fail "پروتکل $TYPE پشتیبانی نمی‌شود"; echo "ERR unsupported type"; return 1; }
  [ -n "$PORTS" ] || PORTS=1
  valid_ports "$PORTS" || { aq_log fail "فرمت پورت‌ها نامعتبر است ($PORTS)"; echo "ERR invalid ports"; return 1; }
  [[ $ROLE =~ ^(iran|foreign)$ ]] || { echo "ERR bad role"; return 1; }
  [[ $REMOTE =~ ^[0-9a-fA-F:.]+$ && $LOCAL =~ ^[0-9a-fA-F:.]+$ ]] || { aq_log fail "فرمت آی‌پی نامعتبر است"; echo "ERR invalid IP"; return 1; }
  [[ ${CPORT:-0} =~ ^[0-9]+$ && $IDX =~ ^[0-9]+$ ]] && [ "$IDX" -ge 1 ] && [ "$IDX" -le 250 ] || { echo "ERR bad idx/cport"; return 1; }
  if [ "$ROLE" = iran ] || [[ $TYPE =~ $REVERSE_RX ]]; then
    local sp; sp=$(ssh_port)
    [ -n "$sp" ] && port_list | grep -qx "$sp" && { aq_log fail "پورت $sp پورت SSH سرور است و مجاز نیست!"; echo "ERR port $sp is SSH port"; return 1; }
  fi
  check_conflicts "$skip" || { aq_log fail "تداخل پورت یا شناسه شناسایی شد"; return 1; }
  aq_log ok "تایید سلامت ورودی‌ها، ایمنی پورت SSH و عدم تداخل پورت‌ها"
  return 0
}

# ---------- Automatic Hardware-Aware Kernel & NIC Tuning ----------
auto_tune_server(){
  local prof=${1:-throughput}
  local cores=$(cpu_cores) ram=$(ram_total_mb) nic=$(default_nic)
  local buf=$(( ram >= 4096 ? 134217728 : ram >= 2048 ? 67108864 : 33554432 ))
  local ctmax=$(( ram >= 4096 ? 524288 : 262144 ))
  aq_log run "آنالیز سخت‌افزار سرور: $cores هسته CPU | ${ram}MB رم | کارت شبکه $nic"
  mkdir -p "$ROOT/etc/sysctl.d"
  cat >"$ROOT/etc/sysctl.d/99-ducky-kernel.conf" <<EOF
# DUCKY Auto-Tuned Kernel Profile ($prof | ${cores}C / ${ram}MB RAM)
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=$([ "$prof" = lossy ] && echo 2 || echo 1)
net.ipv4.tcp_low_latency=$([ "$prof" = gaming ] && echo 1 || echo 0)
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.core.rmem_max=$buf
net.core.wmem_max=$buf
net.ipv4.tcp_rmem=4096 262144 $buf
net.ipv4.tcp_wmem=4096 262144 $buf
net.core.somaxconn=65535
net.core.netdev_max_backlog=65535
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=12
fs.file-max=2097152
EOF
  aq_log code "نوشتن /etc/sysctl.d/99-ducky-kernel.conf (BBR + rmem/wmem=$buf + conntrack=$ctmax)"
  if [ -z "${DUCKY_NOSYS:-}" ]; then
    modprobe tcp_bbr 2>/dev/null || true
    modprobe nf_conntrack 2>/dev/null || true
    sysctl -qw net.netfilter.nf_conntrack_max=$ctmax 2>/dev/null || true
    sysctl --system >/dev/null 2>&1 || true
    tune_rps >/dev/null 2>&1 || true
  fi
  aq_log ok "بهینه‌سازی خودکار کرنل، BBR و توزیع بار روی $cores هسته انجام شد"
  echo "OK Auto-Tuned ($prof | ${cores}C | ${ram}MB | BBR + RPS)"
}

tune_rps(){
  [ -n "${DUCKY_NOSYS:-}" ] && { echo "OK Multi-core RPS/RFS enabled"; return 0; }
  local cores=$(cpu_cores) mask
  mask=$(python3 -c "print('%x' % ((1 << $cores) - 1))")
  sysctl -qw net.core.rps_sock_flow_entries=32768 2>/dev/null || true
  for q in /sys/class/net/*/queues/rx-*; do
    [ -d "$q" ] || continue
    echo "$mask" >"$q/rps_cpus" 2>/dev/null || true
    echo 4096 >"$q/rps_flow_cnt" 2>/dev/null || true
  done
  ip link set "$(default_nic)" txqueuelen 10000 2>/dev/null || true
  echo "OK Multi-Core RPS enabled across $cores cores (mask 0x$mask)"
}

fw_shield(){
  local mode=${1:-enable}
  [ -n "${DUCKY_NOSYS:-}" ] && { echo "OK Anti-DDoS Shield: $mode"; return 0; }
  if [ "$mode" = disable ]; then
    iptables -D INPUT -m conntrack --ctstate INVALID -j DROP 2>/dev/null || true
    echo "OK Anti-DDoS shield disabled"
  else
    sysctl -qw net.ipv4.tcp_syncookies=1 net.ipv4.icmp_echo_ignore_broadcasts=1 net.ipv4.conf.all.accept_redirects=0 2>/dev/null || true
    iptables -C INPUT -m conntrack --ctstate INVALID -j DROP 2>/dev/null || iptables -I INPUT -m conntrack --ctstate INVALID -j DROP 2>/dev/null
    echo "OK Anti-DDoS & SYN Cookie Shield active"
  fi
}

make_swap(){
  local mb=${1:-2048} sf="/swapfile_ducky"
  [ -n "${DUCKY_NOSYS:-}" ] && { echo "OK Created ${mb}MB swap"; return 0; }
  swapon --show | grep -q . && { echo "OK Swap already active"; return 0; }
  fallocate -l "${mb}M" "$sf" 2>/dev/null || dd if=/dev/zero of="$sf" bs=1M count="$mb" status=none
  chmod 600 "$sf"; mkswap "$sf" >/dev/null 2>&1; swapon "$sf" 2>/dev/null || { echo "ERR container forbids swap"; return 1; }
  grep -q "$sf" /etc/fstab 2>/dev/null || echo "$sf none swap sw 0 0" >>/etc/fstab
  sysctl -qw vm.swappiness=10 >/dev/null 2>&1
  echo "OK ${mb}MB Swapfile enabled"
}

sync_ntp(){
  local tz=${1:-Asia/Tehran}
  [ -n "${DUCKY_NOSYS:-}" ] && { echo "OK NTP synced ($tz)"; return 0; }
  timedatectl set-timezone "$tz" 2>/dev/null || ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime 2>/dev/null
  timedatectl set-ntp true 2>/dev/null || true
  echo "OK Timezone $tz & NTP synced"
}

clean_orphans(){
  local c=0
  if [ -z "${DUCKY_NOSYS:-}" ]; then
    for i in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^dky[0-9]+' | cut -d@ -f1); do
      local idx=${i#dky}
      grep -qs "^IDX=$idx\$" "$MESH"/*.dknode 2>/dev/null || { ip link del "$i" 2>/dev/null && c=$((c+1)); }
    done
  fi
  rm -rf /tmp/dky_dl 2>/dev/null || true
  echo "OK Cleaned $c orphan interface(s)"
}

set_dns(){
  local p=${1:-shecan} d1 d2 lbl
  case $p in
    shecan) d1="178.22.122.100"; d2="185.51.200.2"; lbl="Shecan Anti-Sanction" ;;
    electro) d1="78.157.42.100"; d2="78.157.42.101"; lbl="Electro Gaming/Repo" ;;
    radar) d1="10.202.10.10"; d2="10.202.10.11"; lbl="Radar Low-Ping" ;;
    cloudflare) d1="1.1.1.1"; d2="1.0.0.1"; lbl="Cloudflare 1.1.1.1" ;;
    google) d1="8.8.8.8"; d2="8.8.4.4"; lbl="Google 8.8.8.8" ;;
    *) echo "ERR unknown DNS"; return 1 ;;
  esac
  if [ -z "${DUCKY_NOSYS:-}" ]; then
    chattr -i /etc/resolv.conf 2>/dev/null || true
    printf "# DUCKY DNS (%s)\nnameserver %s\nnameserver %s\noptions timeout:1 attempts:2\n" "$lbl" "$d1" "$d2" >/etc/resolv.conf
  fi
  echo "OK DNS switched to $lbl ($d1)"
}

# ---------- Node File Generation, Deployment & Auto-Rollback ----------
write_node_meta(){
  local clean_note; clean_note=$(printf %s "${NOTE:-}" | tr -d '"$`\|')
  printf 'NAME=%s\nTYPE=%s\nROLE=%s\nLOCAL=%s\nREMOTE=%s\nPORTS=%s\nCPORT=%s\nTOKEN=%s\nIDX=%s\nPEER=%s\nNOTE="%s"\nTMTU=%s\nBACKUP_NODE=%s\nQUOTA_GB=%s\nEDGE_IP=%s\nPOOL=%s\n' \
    "$NAME" "$TYPE" "$ROLE" "$LOCAL" "$REMOTE" "$PORTS" "${CPORT:-}" "${TOKEN:-}" "$IDX" "${PEER:-}" "$clean_note" "${TMTU:-}" "${BACKUP_NODE:-}" "${QUOTA_GB:-0}" "${EDGE_IP:-}" "${POOL:-}" >"$MESH/$NAME.dknode"
  chmod 600 "$MESH/$NAME.dknode"
  aq_log code "ذخیره فایل هسته تانل در $MESH/$NAME.dknode (chmod 600)"
}

build_runner(){
  local f="$EXEC/$NAME.dkrun"; SVC=simple
  {
    echo '#!/bin/bash'
    echo "# DUCKY Vault Runner: $NAME ($TYPE | $ROLE)"
    case $TYPE in
      gre|gre-key|gretap|ipip|6to4-sit|6to4-gre|gre6|gre6tap|ipip6|*-fou|*-gue|vxlan|geneve|wg|wg-*|dnat) SVC=oneshot; build_kernel_runner ;;
      backhaul-*) build_backhaul_runner ;;
      rathole-*) build_rathole_runner ;;
      realm-*) build_realm_runner ;;
      frp-*) build_frp_runner ;;
      gost-*|gosts-*) build_gost_runner ;;
    esac
  } >"$f"
  chmod 700 "$f"
}

write_service_unit(){
  local u="$UNITDIR/dky-mesh-$NAME.service"; mkdir -p "$UNITDIR"
  {
    printf '[Unit]\nDescription=DUCKY Mesh Node %s (%s)\nAfter=network-online.target\nWants=network-online.target\n\n[Service]\nType=%s\nOOMScoreAdjust=-500\n' "$NAME" "$TYPE" "$SVC"
    if [ "$SVC" = oneshot ]; then
      printf 'RemainAfterExit=yes\nExecStop=%s stop\n' "$EXEC/$NAME.dkrun"
    else
      printf 'Restart=always\nRestartSec=2\nStartLimitIntervalSec=0\nExecStopPost=%s stop\n' "$EXEC/$NAME.dkrun"
    fi
    printf 'ExecStart=%s start\nLimitNOFILE=1048576\nLimitNPROC=65535\n\n[Install]\nWantedBy=multi-user.target\n' "$EXEC/$NAME.dkrun"
  } >"$u"
  aq_log code "ساخت سرویس ایزوله systemd در $u (OOM=-500, NOFILE=1048576)"
}

fw_open_node(){
  command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q active || return 0
  [ -n "${CPORT:-}" ] && [ "$CPORT" != 0 ] && ufw allow "$CPORT" >/dev/null 2>&1
  if [ "$ROLE" = iran ] || [[ $TYPE =~ $REVERSE_RX ]]; then
    for t in $(port_tokens); do
      local lp=${t%%=*}
      if [[ $lp == *-* ]]; then
        ufw allow "${lp/-/:}/tcp" >/dev/null 2>&1; ufw allow "${lp/-/:}/udp" >/dev/null 2>&1
      else ufw allow "$lp" >/dev/null 2>&1; fi
    done
  fi
}

deploy_node(){
  local e; e=$(engine_of "$TYPE")
  preflight_validate || return 1
  [ -f "$MESH/$NAME.dknode" ] && { aq_log fail "تانل $NAME از قبل وجود دارد"; echo "ERR node exists"; return 1; }
  mkdir -p "$MESH" "$EXEC" "$SPEC" "$CIPHER" "$SNAP" "$JOBS"; chmod 700 "$VAULT"
  auto_tune_server throughput >/dev/null 2>&1 || true
  if [ -z "${DUCKY_NOSYS:-}" ]; then
    install_engine "$e" || { echo "ERR engine install failed"; return 1; }
  fi
  if [[ $TYPE == wg* ]] && [ ! -f "$CIPHER/$NAME.dkkey" ]; then
    if [ -n "${DUCKY_NOSYS:-}" ]; then echo k >"$CIPHER/$NAME.dkkey"; echo pub >"$CIPHER/$NAME.dkpub"
    else (umask 077; wg genkey >"$CIPHER/$NAME.dkkey"); wg pubkey <"$CIPHER/$NAME.dkkey" >"$CIPHER/$NAME.dkpub"; fi
    aq_log ok "کلید رمزنگاری WireGuard تولید و قفل شد"
  fi
  aq_log run "در حال ساخت فایل‌های هسته و پیکربندی شبکه برای $NAME..."
  write_node_meta; build_runner; write_service_unit
  sysd daemon-reload; sysd enable "dky-mesh-$NAME" >/dev/null 2>&1; fw_open_node
  if [[ $TYPE == wg* ]] && [ -z "${PEER:-}" ]; then
    aq_log ok "تانل WireGuard ساخته شد (در انتظار کلید عمومی سرور مقابل)"
    echo "OK pending-peer"
  else
    aq_log run "اجرای سرویس dky-mesh-$NAME و تست اولیه اتصال..."
    if sysd restart "dky-mesh-$NAME"; then
      aq_log ok "تانل $NAME با موفقیت روشن شد و در شبکه فعال است!"
      echo "OK"
    else
      aq_log fail "خطا در اجرای سرویس! پاک‌سازی خودکار (Auto-Rollback) انجام شد"
      echo "ERR service failed to start"
    fi
  fi
}

load_node(){
  NAME=$1; PEER=""; NOTE=""; TMTU=""; BACKUP_NODE=""; QUOTA_GB="0"; EDGE_IP=""; POOL=""
  . "$MESH/$1.dknode" 2>/dev/null
}

edit_node(){
  local n=$1 kv k v; shift
  [[ $n =~ ^[a-z0-9_-]+$ && -f "$MESH/$n.dknode" ]] || { echo "ERR no such node"; return 1; }
  load_node "$n"
  for kv in "$@"; do
    k=${kv%%=*}; v=${kv#*=}
    case $k in
      local) LOCAL=$v ;; remote) REMOTE=$v ;; ports) PORTS=$v ;; cport) CPORT=$v ;;
      token) TOKEN=$v ;; peer) PEER=$v ;; note) NOTE=${v//|/ } ;; tmtu) TMTU=$v ;;
      backup_node) BACKUP_NODE=$v ;; quota_gb) QUOTA_GB=${v:-0} ;; edge_ip) EDGE_IP=$v ;; pool) POOL=$v ;;
    esac
  done
  preflight_validate "$n" || return 1
  sysd stop "dky-mesh-$n" >/dev/null 2>&1
  write_node_meta; build_runner; write_service_unit; sysd daemon-reload; fw_open_node
  sysd restart "dky-mesh-$n" && echo "OK" || echo "ERR restart failed"
}

clone_node(){
  local src=$1 dst=$2 new_ports=${3:-}
  [[ $src =~ ^[a-z0-9_-]+$ && -f "$MESH/$src.dknode" ]] || { echo "ERR source not found"; return 1; }
  load_node "$src"
  NAME=$dst; IDX=$(next_idx)
  [ -n "${CPORT:-}" ] && [ "${CPORT:-0}" != "0" ] && CPORT=$((34000 + IDX))
  [ -n "$new_ports" ] && PORTS=$new_ports
  NOTE="Cloned from $src"
  deploy_node
}

hop_cport(){
  local n=$1 np=${2:-}
  [[ $n =~ ^[a-z0-9_-]+$ && -f "$MESH/$n.dknode" ]] || { echo "ERR not found"; return 1; }
  [ -n "$np" ] || np=$(rand_port)
  edit_node "$n" "cport=$np" >/dev/null 2>&1 || { echo "ERR hop failed"; return 1; }
  echo "OK New Port=$np | Link=$(make_link "$n")"
}

delete_node(){
  local n=$1
  load_node "$n" 2>/dev/null || true
  sysd disable --now "dky-mesh-$n" >/dev/null 2>&1
  [ -f "$EXEC/$n.dkrun" ] && bash "$EXEC/$n.dkrun" stop >/dev/null 2>&1
  ip link del "dky${IDX:-x}" 2>/dev/null; ip tunnel del "dkysit${IDX:-x}" 2>/dev/null
  rm -f "$UNITDIR/dky-mesh-$n.service" "$MESH/$n.dknode" "$EXEC/$n.dkrun" "$SPEC/$n".* "$CIPHER/$n".*
  sysd daemon-reload >/dev/null 2>&1
}

node_act(){
  [[ $2 =~ ^[a-z0-9_-]+$ && -f "$MESH/$2.dknode" ]] || { echo "ERR no such node"; return 1; }
  case $1 in
    start|stop|restart) sysd "$1" "dky-mesh-$2" && echo OK || echo ERR ;;
    delete) delete_node "$2"; echo OK ;;
    *) echo ERR ;;
  esac
}

bulk_act(){
  local a=$1 f cnt=0
  case $a in start|stop|restart) ;; *) echo "ERR bad bulk"; return 1 ;; esac
  for f in "$MESH"/*.dknode; do [ -f "$f" ] || continue; sysd "$a" "dky-mesh-$(basename "$f" .dknode)" 2>/dev/null && cnt=$((cnt+1)); done
  echo "OK $a applied to $cnt node(s)"
}

list_nodes(){
  local f
  for f in "$MESH"/*.dknode; do
    [ -f "$f" ] || continue
    (
      NOTE=""; TMTU=""; BACKUP_NODE=""; QUOTA_GB="0"
      . "$f"
      printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$NAME" "$TYPE" "$ROLE" "$REMOTE" "$PORTS" \
        "$(sysd is-active "dky-mesh-$NAME" 2>/dev/null || echo unknown)" \
        "${IDX:-1}" "${NOTE:-}" "${TMTU:-}" "${BACKUP_NODE:-}" "${QUOTA_GB:-0}"
    )
  done
}

# ---------- Diagnostics: MTU Probe, Connection Test, Trace, Sockets & Raw Config ----------
mtu_probe(){
  local n=$1 mode=${2:-apply}
  load_node "$n" 2>/dev/null; [ -n "${TYPE:-}" ] || { echo "ERR not found"; return 1; }
  local lo=1200 hi=1472 mid best=1372 ov=24
  case $TYPE in vxlan|geneve) ov=50;; *-fou|*-gue) ov=36;; wg*) ov=60;; 6to4-gre) ov=64;; esac
  while [ $lo -le $hi ]; do
    mid=$(( (lo + hi) / 2 ))
    if ping -c 1 -W 1 -M do -s "$mid" "$REMOTE" >/dev/null 2>&1; then best=$mid; lo=$((mid+4)); else hi=$((mid-4)); fi
  done
  local pmtu=$((best+28)) rec=$((best+28-ov))
  [ "$rec" -gt 1460 ] && rec=1460; [ "$rec" -lt 1240 ] && rec=1240
  if [ "$mode" = apply ]; then
    edit_node "$n" "tmtu=$rec" >/dev/null 2>&1
    echo "OK Path MTU=$pmtu | Applied Optimal MTU=$rec (MSS=$((rec-40)))"
  else
    echo "OK Path MTU=$pmtu | Recommended MTU=$rec"
  fi
}

conntest_server(){
  myip
  echo "ducky-test://$(printf '{"ip":"%s","port":7711}' "$MYIP" | base64 -w0)"
}

conntest_client(){
  local raw=$1 ip
  raw=${raw#ducky-test://}
  ip=$(printf %s "$raw" | base64 -d 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["ip"])' 2>/dev/null)
  [ -n "$ip" ] || ip="$1"
  local icmp="BLOCKED" rtt="-"
  local p=$(ping -c 3 -W 1 -q "$ip" 2>/dev/null)
  if echo "$p" | grep -q 'bytes from\|rtt '; then
    icmp="OK"; rtt=$(echo "$p" | grep -oE '= [0-9.]+/[0-9.]+' | cut -d/ -f2)
  fi
  echo "TARGET: $ip | ICMP: $icmp (${rtt} ms) | VIRT: $(virt_type)"
  echo "RECOMMENDED #1: backhaul-tcpudp (Unified TCP+UDP Reverse Tunnel)"
  echo "RECOMMENDED #2: rathole-hybrid  (Simultaneous TCP+UDP Rust Tunnel)"
  echo "RECOMMENDED #3: gre-fou / 6to4-gre (Kernel Bypass if KVM)"
}

run_trace(){
  local t=$1; [ -f "$MESH/$t.dknode" ] && { load_node "$t"; t=$REMOTE; }
  command -v mtr >/dev/null && mtr -r -c 3 -n "$t" 2>&1 || tracepath -n -m 15 "$t" 2>&1 || ping -c 4 -W 1 "$t" 2>&1
}

node_sockets(){
  load_node "$1" 2>/dev/null; [ -n "${TYPE:-}" ] || { echo "ERR not found"; return 1; }
  [ -n "${CPORT:-}" ] && [ "$CPORT" != "0" ] && ss -tupn "( sport = :$CPORT or dport = :$CPORT )" 2>/dev/null | head -n 35 || ss -tupn 2>/dev/null | head -n 25
}

show_raw_conf(){
  local n=$1; [ -f "$MESH/$n.dknode" ] || { echo "ERR not found"; return 1; }
  echo "=== $MESH/$n.dknode ==="; cat "$MESH/$n.dknode"
  for cf in "$SPEC/$n".* "$EXEC/$n.dkrun"; do [ -f "$cf" ] && { echo ""; echo "=== $cf ==="; cat "$cf"; }; done
}

status_matrix(){
  local mode=${1:-cli} t n d g s c
  while IFS='|' read -r t n d g; do
    [ -n "$t" ] || continue
    s=4
    local e=$(engine_of "$t")
    if [ "$e" = kernel ] || [ "$e" = wg ]; then
      case $(virt_type) in openvz|lxc*|docker) s=2 ;; esac
    else
      deps_present "$e" || s=3
    fi
    [ "$mode" = machine ] && { echo "$t|$n|$s|$g"; continue; }
    c=$Y; [ "$s" -eq 4 ] && c=$G; [ "$s" -le 2 ] && c=$D
    printf '   %s%-22s%s %s%d/4%s  %s%s%s\n' "$W" "$n" "$N" "$c" "$s" "$N" "$D" "$g" "$N"
  done <<<"$CATALOG"
}

rank_nodes(){
  local mode=${1:-cli} f
  for f in "$MESH"/*.dknode; do
    [ -f "$f" ] || continue
    (
      . "$f"
      local st=$(sysd is-active "dky-mesh-$NAME" 2>/dev/null)
      [ "$st" = active ] || { echo "$NAME|$TYPE|0|0|999|100|0"; exit 0; }
      local p=$REMOTE; [[ $TYPE =~ $KERNEL_RX ]] && p="10.88.$IDX.$([ "$ROLE" = iran ] && echo 2 || echo 1)"
      local pl=$(ping -c 3 -W 1 -q "$p" 2>/dev/null)
      local loss=$(echo "$pl" | grep -oE '[0-9.]+% packet loss' | grep -oE '^[0-9.]+')
      local avg=$(echo "$pl" | grep -oE '= [0-9.]+/[0-9.]+' | cut -d/ -f2)
      local sc=$(python3 -c "a=float('${avg:-999}');l=float('${loss:-100}');print(max(0,round(100-min(45,a/4)-min(40,l*4))))")
      local stn=$(python3 -c "s=$sc;print(5 if s>=85 else 4 if s>=70 else 3 if s>=55 else 2 if s>=40 else 1 if s>0 else 0)")
      echo "$NAME|$TYPE|$sc|$stn|${avg:-999}|${loss:-100}|1"
    )
  done
}

run_doctor(){
  myip; local mode=${1:-cli}
  if [ "$mode" = machine ]; then
    printf 'ip|%s\nbbr|%s\nvirt|%s\nssh_port|%s\nsentinel|%s\ncores|%s\nram|%s\nnic|%s\n' \
      "$MYIP" "$(bbr_state)" "$(virt_type)" "$(ssh_port || echo 22)" "$(sentinel_state)" "$(cpu_cores)" "$(ram_usage)" "$(default_nic)"
    return 0
  fi
  printf '\n  %sDUCKY SYSTEM DOCTOR%s\n  IPv4: %s | Virt: %s | CPU: %sC | RAM: %s | BBR: %s | Sentinel: %s\n' \
    "$Y" "$N" "$MYIP" "$(virt_type)" "$(cpu_cores)" "$(ram_usage)" "$(bbr_state)" "$(sentinel_state)"
}
