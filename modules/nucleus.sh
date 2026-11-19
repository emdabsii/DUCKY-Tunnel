# DUCKY Tunnel Suite v1.0 - Module 1: Nucleus (Hardened Paths, Black/White/Yellow Theme, 62 Protocols, Hardware Telemetry)
VER="1.0.0"
ROOT="${DUCKY_ROOT:-}"
APP="${DUCKY_DIR:-/opt/.ducky-core}"
VAULT="$ROOT/etc/.ducky-vault"
MESH="$VAULT/mesh"
EXEC="$VAULT/exec"
SPEC="$VAULT/specs"
CIPHER="$VAULT/cipher"
SNAP="$VAULT/vault-snap"
JOBS="$VAULT/jobs"
LOG="${DUCKY_LOG:-/var/log/ducky-core.log}"
UNITDIR="$ROOT/etc/systemd/system"

# Luxury Black / Pure White / Electric Yellow ANSI Palette (Zero Red)
Y=$'\e[1;33m'       # Electric Yellow
DY=$'\e[0;33m'      # Warm Gold
BY=$'\e[43;30;1m'   # Yellow Badge + Black Bold Text
BW=$'\e[47;30;1m'   # White Badge + Black Bold Text
W=$'\e[1;97m'       # Pure Crisp White
G=$'\e[1;33m'       # Online Emerald
D=$'\e[2;37m'       # Muted Silver
N=$'\e[0m'          # Reset

nap(){ [ -n "${DUCKY_DEMO:-}" ] || sleep "$1"; }
sysd(){ [ -n "${DUCKY_NOSYS:-}" ] || systemctl "$@"; }
die(){ printf '\n  %s[ ERROR ]%s %s%s%s\n\n' "$BY" "$N" "$W" "$*" "$N"; exit 1; }
ARCH_G=$(case $(uname -m) in x86_64) echo amd64;; aarch64) echo arm64;; *) echo unsupported;; esac)
ARCH_X=$(uname -m)

# Real-time Persian Aquarium Stream Logger (used by Web Panel Frosted Glass Drawer)
aq_log(){
  [ -n "${DUCKY_JOB:-}" ] && printf '%s|%s\n' "$1" "$(printf %s "$2" | tr -d '\r\n|')" >>"$DUCKY_JOB"
  return 0
}

# ---------- 62 Battle-Tested Protocols Across 7 Core Families ----------
CATALOG='backhaul-tcp|Backhaul TCP|Reverse pooled TCP tunnel (Musixal official)|Backhaul
backhaul-tcpudp|Backhaul TCP+UDP|Unified TCP & UDP over single pooled TCP (accept_udp=true)|Backhaul
backhaul-tcpmux|Backhaul TCPMux|SMUX multiplexed streams over pooled TCP|Backhaul
backhaul-udp|Backhaul Native UDP|Direct low-latency UDP reverse tunnel|Backhaul
backhaul-ws|Backhaul WS|WebSocket reverse tunnel (supports CDN edge_ip)|Backhaul
backhaul-wsmux|Backhaul WSMux|Multiplexed WebSocket reverse tunnel|Backhaul
backhaul-wss|Backhaul WSS|Encrypted TLS WebSocket (ECDSA P-384 auto-cert)|Backhaul
backhaul-wssmux|Backhaul WSSMux|Multiplexed TLS WebSocket with aggressive pool|Backhaul
rathole-hybrid|Rathole TCP+UDP Hybrid|Simultaneous TCP & UDP blocks inside one TOML channel|Rathole
rathole-tcp|Rathole TCP|Ultra-lightweight Rust TCP reverse tunnel|Rathole
rathole-udp|Rathole UDP|Ultra-lightweight Rust UDP reverse tunnel|Rathole
rathole-noise|Rathole Noise X25519|Noise Protocol encrypted reverse tunnel (auto keygen)|Rathole
rathole-ws|Rathole WebSocket|Rathole reverse tunnel over WebSocket transport|Rathole
gre|GRE L3 Kernel|Fast kernel L3 tunnel (IP proto 47, zero CPU)|GRE & Kernel
gre-key|GRE Keyed L3|Key-authenticated kernel GRE tunnel|GRE & Kernel
gretap|GRE-TAP L2|Kernel Layer-2 Ethernet bridge over GRE|GRE & Kernel
ipip|IPIP L3 Kernel|Lightweight IPv4-in-IPv4 encapsulation|GRE & Kernel
6to4-sit|6to4 SIT Tunnel|Creates private IPv6 over IPv4 without Native IPv6|GRE & Kernel
6to4-gre|6to4 + GRE6 Dual-Layer|SIT carrier + IP6GRE inside (Iran datacenter bypass)|GRE & Kernel
gre6|GRE6 (ip6gre)|GRE over Native IPv6 endpoints|GRE & Kernel
gre6tap|GRE6-TAP L2|Layer-2 Ethernet GRE over IPv6|GRE & Kernel
ipip6|IPIP6 (ip6tnl)|IPv4/IPv6 over IPv6 kernel tunnel|GRE & Kernel
gre-fou|GRE over FOU (UDP)|Wraps GRE inside UDP port to bypass proto-47 blocks|GRE & Kernel
gre-gue|GRE over GUE (UDP)|Generic UDP Encapsulation for NAT traversal|GRE & Kernel
gretap-fou|GRE-TAP over FOU|Layer-2 GRE wrapped inside UDP|GRE & Kernel
ipip-fou|IPIP over FOU|IPIP wrapped in UDP port|GRE & Kernel
vxlan|VXLAN L2 UDP|Virtual Extensible LAN over UDP|GRE & Kernel
geneve|GENEVE L2 UDP|Generic Network Virtualization over UDP|GRE & Kernel
dnat|Direct Kernel DNAT|Zero-overhead iptables NAT port forward|GRE & Kernel
wg|WireGuard Kernel|ChaCha20 kernel tunnel (Table=off, SSH-safe)|WireGuard
wg-psk|WireGuard + PSK|WireGuard with SHA-256 Pre-Shared Key|WireGuard
wg-1320|WireGuard MTU-1320|WireGuard tuned for PPPoE/mobile MTU|WireGuard
wg-1280|WireGuard Low-MTU|WireGuard tuned for strict networks (MTU 1280)|WireGuard
realm-tcp|Realm Rust TCP+UDP|Ultra-fast Rust zero-copy TCP+UDP forwarder|Realm
realm-tls|Realm Rust TLS|Encrypted TLS Rust forwarder (SNI mimicry)|Realm
realm-ws|Realm Rust WS|WebSocket Rust forwarder|Realm
frp-tcp|FRP TCP|Fast Reverse Proxy over TCP with tcpMux|FRP
frp-kcp|FRP KCP|ARQ UDP reverse proxy for high packet-loss links|FRP
frp-quic|FRP QUIC|QUIC multiplexed UDP reverse proxy|FRP
frp-ws|FRP WebSocket|HTTP WebSocket reverse proxy|FRP
gost-tcp|GOST Relay TCP|GOST relay chain over TCP|GOST Relay
gost-tls|GOST Relay+TLS|Encrypted TLS relay tunnel|GOST Relay
gost-mtls|GOST Relay+MTLS|Multiplexed TLS relay tunnel|GOST Relay
gost-ws|GOST Relay+WS|WebSocket relay tunnel|GOST Relay
gost-mws|GOST Relay+MWS|Multiplexed WebSocket relay tunnel|GOST Relay
gost-wss|GOST Relay+WSS|TLS WebSocket relay tunnel|GOST Relay
gost-mwss|GOST Relay+MWSS|Multiplexed TLS WebSocket relay tunnel|GOST Relay
gost-h2|GOST Relay+H2|HTTP/2 TLS multiplexed relay tunnel|GOST Relay
gost-h2c|GOST Relay+H2C|HTTP/2 cleartext relay tunnel|GOST Relay
gost-quic|GOST Relay+QUIC|QUIC UDP encrypted relay tunnel|GOST Relay
gost-kcp|GOST Relay+KCP|KCP ARQ UDP relay tunnel|GOST Relay
gost-grpc|GOST Relay+gRPC|gRPC transport relay tunnel|GOST Relay
gosts-tcp|GOST SOCKS5 TCP|SOCKS5 proxy chain over TCP|GOST SOCKS5
gosts-tls|GOST SOCKS5+TLS|SOCKS5 proxy chain over TLS|GOST SOCKS5
gosts-mtls|GOST SOCKS5+MTLS|SOCKS5 proxy chain over MTLS|GOST SOCKS5
gosts-ws|GOST SOCKS5+WS|SOCKS5 proxy chain over WS|GOST SOCKS5
gosts-mws|GOST SOCKS5+MWS|SOCKS5 proxy chain over MWS|GOST SOCKS5
gosts-wss|GOST SOCKS5+WSS|SOCKS5 proxy chain over WSS|GOST SOCKS5
gosts-mwss|GOST SOCKS5+MWSS|SOCKS5 proxy chain over MWSS|GOST SOCKS5
gosts-h2|GOST SOCKS5+H2|SOCKS5 proxy chain over HTTP/2|GOST SOCKS5
gosts-h2c|GOST SOCKS5+H2C|SOCKS5 proxy chain over H2C|GOST SOCKS5
gosts-quic|GOST SOCKS5+QUIC|SOCKS5 proxy chain over QUIC|GOST SOCKS5'

REVERSE_RX='^(rathole-.*|backhaul-.*|frp-.*)$'
KERNEL_RX='^(gre|gre-key|gretap|ipip|6to4-sit|6to4-gre|gre6|gre6tap|ipip6|.*-fou|.*-gue|vxlan|geneve|wg|wg-psk|wg-1320|wg-1280)$'

engine_of(){
  case $1 in
    gre|gre-key|gretap|ipip|6to4-sit|6to4-gre|gre6|gre6tap|ipip6|*-fou|*-gue|vxlan|geneve|dnat) echo kernel ;;
    wg|wg-*) echo wg ;;
    backhaul-*) echo backhaul ;;
    rathole-*) echo rathole ;;
    realm-*) echo realm ;;
    frp-*) echo frp ;;
    gost-*|gosts-*) echo gost ;;
  esac
}
type_name(){ echo "$CATALOG" | awk -F'|' -v t="$1" '$1==t{print $2}'; }
type_family(){ echo "$CATALOG" | awk -F'|' -v t="$1" '$1==t{print $4}'; }

# ---------- System & Hardware Telemetry ----------
need_root(){ [ -n "${DUCKY_DEMO:-}${DUCKY_NOSYS:-}" ] || [ "$(id -u)" = 0 ] || die "Run as root: sudo ducky"; }
detect_os(){
  [ -n "${DUCKY_DEMO:-}" ] && { OS_NAME=Ubuntu; OS_VER=24.04; return; }
  . /etc/os-release 2>/dev/null; OS_NAME=${NAME:-Linux}; OS_VER=${VERSION_ID:-?}
  case "${ID:-}:${OS_VER}" in
    ubuntu:20.04|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04|debian:11|debian:12|debian:13) ;;
    *) die "Unsupported OS: $OS_NAME $OS_VER" ;;
  esac
}
myip(){
  [ -n "${MYIP:-}" ] && return
  [ -n "${DUCKY_DEMO:-}" ] && { MYIP=185.204.10.25; return; }
  MYIP=$(curl -s4 -m 3 https://api.ipify.org || curl -s4 -m 3 https://ifconfig.me || ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="src")print $(i+1)}' | head -1 || hostname -I | awk '{print $1}')
  [ -n "$MYIP" ] || MYIP="127.0.0.1"
}
myip6(){
  [ -n "${MYIP6:-}" ] && return
  [ -n "${DUCKY_DEMO:-}" ] && { MYIP6="2001:db8::10"; return; }
  MYIP6=$(curl -s6 -m 3 https://api64.ipify.org 2>/dev/null || ip -6 addr show scope global 2>/dev/null | awk '/inet6/{split($2,a,"/");print a[1];exit}')
}
cpu_cores(){ nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 2; }
cpu_load(){ awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0.00"; }
ram_total_mb(){ free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 2048; }
ram_usage(){ free -m 2>/dev/null | awk '/^Mem:/{printf "%d/%dMB", $3, $2}' || echo "-/-"; }
virt_type(){ systemd-detect-virt 2>/dev/null | tr -d '\n' || echo "kvm"; }
bbr_state(){ sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -qi bbr && echo "ON" || echo "OFF"; }
sentinel_state(){ systemctl is-active dky-sentinel 2>/dev/null | grep -qx active && echo "ACTIVE" || echo "OFF"; }
default_nic(){ ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++)if($i=="dev")print $(i+1)}' | head -1 || echo eth0; }

sys_telemetry_json(){
  myip; myip6
  python3 -c 'import os,json,shutil
def rd(p):
  try: return open(p).read().strip()
  except: return ""
cores = os.cpu_count() or 1
load = rd("/proc/loadavg").split()[0] if rd("/proc/loadavg") else "0.0"
mt = ma = st = sf = 0
for l in rd("/proc/meminfo").splitlines():
  if l.startswith("MemTotal:"): mt = int(l.split()[1]) // 1024
  elif l.startswith("MemAvailable:"): ma = int(l.split()[1]) // 1024
  elif l.startswith("SwapTotal:"): st = int(l.split()[1]) // 1024
  elif l.startswith("SwapFree:"): sf = int(l.split()[1]) // 1024
mu = max(0, mt - ma); su = max(0, st - sf)
du = shutil.disk_usage("/")
ct = rd("/proc/sys/net/netfilter/nf_conntrack_count") or "0"
bbr = "bbr" in rd("/proc/sys/net/ipv4/tcp_congestion_control").lower()
print(json.dumps({
  "cores": cores, "load": float(load), "cpu_pct": min(100, round(float(load)*100/max(1,cores), 1)),
  "ram_used": mu, "ram_total": mt, "ram_pct": round(mu*100/max(1,mt), 1),
  "swap_used": su, "swap_total": st,
  "disk_used": round(du.used/1073741824, 1), "disk_total": round(du.total/1073741824, 1), "disk_pct": round(du.used*100/max(1,du.total), 1),
  "conntrack": int(ct) if ct.isdigit() else 0, "bbr": bbr,
  "ip": "'"$MYIP"'", "ip6": "'"${MYIP6:-}"'", "virt": "'"$(virt_type)"'", "nic": "'"$(default_nic)"'"
}))'
}

apt_update(){ DEBIAN_FRONTEND=noninteractive apt-get update -qq; }
apt_i(){ DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"; }
ssh_port(){ ss -tlnp 2>/dev/null | awk '/sshd/{n=split($4,a,":");print a[n];exit}'; }
port_free(){ ! ss -tuln 2>/dev/null | awk '{print $5}' | grep -qE "[:.]$1$"; }
rand_port(){ local p; while :; do p=$(shuf -i 10000-60000 -n1); port_free "$p" && { echo "$p"; return; }; done; }
rand_token(){ tr -dc "A-Za-z0-9" </dev/urandom | head -c 40; }
rand_str(){ tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-16}"; }

# ---------- Binary Engine Installer ----------
deps_present(){
  case $1 in
    kernel) command -v ip >/dev/null && command -v iptables >/dev/null ;;
    wg) command -v wg >/dev/null ;;
    backhaul) [ -x /usr/local/bin/backhaul ] ;;
    rathole) [ -x /usr/local/bin/rathole ] ;;
    realm) [ -x /usr/local/bin/realm ] ;;
    frp) [ -x /usr/local/bin/frps ] && [ -x /usr/local/bin/frpc ] ;;
    gost) [ -x /usr/local/bin/gost ] ;;
    *) return 1 ;;
  esac
}

fetch_bin(){
  local repo=$1 rx=$2 t=/tmp/dky_dl url b f; shift 2; rm -rf $t; mkdir -p $t
  url=$(curl -fsSL --connect-timeout 8 -m 30 "https://api.github.com/repos/$repo/releases/latest" | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 | grep -E "$rx" | head -1)
  [ -n "$url" ] || return 1
  curl -fsSL --connect-timeout 10 -m 120 "$url" -o $t/pkg || return 1
  case $url in
    *.zip) unzip -qo $t/pkg -d $t ;;
    *.tar.gz) tar xzf $t/pkg -C $t ;;
    *.gz) gunzip -c $t/pkg >$t/$1 ;;
    *) cp $t/pkg $t/$1 ;;
  esac
  for b in "$@"; do
    f=$(find $t -type f -name "$b" | head -1)
    [ -n "$f" ] || return 1
    install -m755 "$f" "/usr/local/bin/$b"
  done
  rm -rf $t
}

install_engine(){
  local e=$1
  mkdir -p "$(dirname "$LOG")" "$MESH" "$EXEC" "$SPEC" "$CIPHER" "$SNAP" "$JOBS"
  if deps_present "$e"; then
    aq_log ok "موتور $e از قبل روی سرور نصب و آماده است"
    return 0
  fi
  aq_log run "در حال دانلود و نصب موتور تخصصی $e..."
  apt_update >>"$LOG" 2>&1 || true
  case $e in
    kernel) apt_i iproute2 iptables kmod >>"$LOG" 2>&1 ;;
    wg) apt_i wireguard wireguard-tools iproute2 iptables >>"$LOG" 2>&1 ;;
    *)
      apt_i curl unzip tar gzip ca-certificates openssl >>"$LOG" 2>&1
      case $e in
        backhaul) fetch_bin Musixal/Backhaul "backhaul_linux_${ARCH_G}\.tar\.gz\$" backhaul >>"$LOG" 2>&1 ;;
        rathole) fetch_bin rathole-org/rathole "rathole-${ARCH_X}-unknown-linux-(gnu|musl)\.zip\$" rathole >>"$LOG" 2>&1 ;;
        realm) fetch_bin zhboner/realm "realm-${ARCH_X}-unknown-linux-(gnu|musl)\.tar\.gz\$" realm >>"$LOG" 2>&1 ;;
        frp) fetch_bin fatedier/frp "frp_.*_linux_${ARCH_G}\.tar\.gz\$" frps frpc >>"$LOG" 2>&1 ;;
        gost) fetch_bin ginuerzh/gost "linux[_-]${ARCH_G}[-.][^/]*gz\$" gost >>"$LOG" 2>&1 ;;
      esac
      ;;
  esac
  if deps_present "$e"; then
    aq_log ok "موتور $e با موفقیت در /usr/local/bin نصب شد"
    return 0
  else
    aq_log fail "خطا در نصب موتور $e (لاگ: $LOG)"
    return 1
  fi
}
