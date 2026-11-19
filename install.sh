#!/usr/bin/env bash
# DUCKY Tunnel Suite v2.0 — One-Line Installer  |  t.me/Em4dloverS  |  @KaMr4ng
GH="${DUCKY_GH:-emdabsii/DUCKY-Tunnel}"; BR="${DUCKY_BRANCH:-main}"
FILES="ducky.sh modules/nucleus.sh modules/kernel_gre.sh modules/reverse_pro.sh modules/preflight.sh modules/sentinel.sh modules/cli_ui.sh modules/proxy.py panel/app.py bot/tgbot.py"
APP="${DUCKY_DIR:-/opt/.ducky-core}"
Y=$'\e[1;33m'; W=$'\e[1;97m'; D=$'\e[2;37m'; N=$'\e[0m'

[ -n "${DUCKY_TEST:-}" ] || clear
printf '\n'
printf '  %s/====\\%s  %s||  ||%s   %s/====%s  %s||  //%s  %s\\\\  //%s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N"
printf '  %s||   ||%s %s||  ||%s  %s||    %s  %s|| // %s   %s\\\\// %s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N"
printf '  %s||   ||%s %s||  ||%s  %s||    %s  %s||<<  %s    %s||  %s   %s══╦══ ╦  ╦ ╔═╗ ╔═╗ ╔══ ╦  %s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"
printf '  %s||   ||%s %s||  ||%s  %s||    %s  %s|| \\\\ %s    %s||  %s   %s  ║   ║  ║ ║ ║ ║ ║ ╠═  ║  %s\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"
printf '  %s\\====/%s  %s\\====/%s   %s\\====%s  %s||  \\\\%s    %s||  %s   %s  ╩   ╚══╝ ╩ ╩ ╩ ╩ ╚══ ╚══%s\n\n' "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N" "$Y" "$N" "$W" "$N"

[ -n "${DUCKY_TEST:-}" ] || [ "$(id -u)" = 0 ] || { printf '  %sRun as root: sudo -i%s\n' "$Y" "$N"; exit 1; }
PCT=0; T0=$SECONDS
draw(){ local p=$1 f=$(( $1 * 36 / 100 )); [ "$p" -gt "$PCT" ] && PCT=$p
  printf '\r\e[K  %s▐%s%s▌%s %s%3d%%%s  %s%s%s' "$Y" "$(printf '%.0s█' $(seq 1 $f 2>/dev/null))" "$(printf '%.0s░' $(seq 1 $((36-f)) 2>/dev/null))" "$N" "$W" "$p" "$N" "$D" "$2" "$N"; }
ok(){ draw "$1" "$2"; printf '\n  %s[ OK ]%s %s%s%s\n' "$Y" "$N" "$W" "$3" "$N"; }
fail(){ printf '\n  %s[FAIL]%s %s\n' "$Y" "$N" "$1"; [ -s "${2:-/dev/null}" ] && tail -5 "$2" | sed 's/^/    /'; exit 1; }

draw 5 "Checking OS"; sleep 0.2
. /etc/os-release 2>/dev/null
case "${ID:-}:${VERSION_ID:-}" in
  ubuntu:20.04|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04|debian:11|debian:12|debian:13) ok 12 "${PRETTY_NAME}" "System: ${PRETTY_NAME}" ;;
  *) fail "Unsupported OS: ${PRETTY_NAME:-unknown} (Ubuntu 20.04-26.04 or Debian 11-13)" ;;
esac

if ! command -v curl >/dev/null || ! command -v python3 >/dev/null || ! command -v ip >/dev/null; then
  draw 20 "Installing curl, python3, iproute2, iptables"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq >/tmp/dky_i.log 2>&1 || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates python3 iproute2 iptables kmod >>/tmp/dky_i.log 2>&1 || fail "Package install failed" /tmp/dky_i.log
fi
ok 26 "Dependencies" "Core dependencies ready"

SRC=("${DUCKY_BASE:-https://raw.githubusercontent.com/$GH/$BR}" "https://cdn.jsdelivr.net/gh/$GH@$BR")
TMP=$(mktemp -d); nf=$(echo $FILES | wc -w); k=0
for f in $FILES; do
  base=$((26 + k * 66 / nf)); top=$((26 + (k + 1) * 66 / nf)); got=0; mkdir -p "$TMP/$(dirname "$f")"
  for si in 0 1; do
    for try in 1 2; do
      curl -fsSL --connect-timeout 8 --max-time 45 "${SRC[$si]}/$f" -o "$TMP/$f" 2>/tmp/dky_c.log && [ -s "$TMP/$f" ] && { got=1; break 2; }
    done
  done
  [ $got = 1 ] || fail "Could not download $f from $GH" /tmp/dky_c.log
  ok "$top" "$f" "Fetched $f"; k=$((k+1))
done

draw 96 "Deploying DUCKY Core"
mkdir -p "$APP/modules" "$APP/panel" "$APP/bot" /etc/.ducky-vault/{mesh,exec,specs,cipher,vault-snap,jobs}
for f in $FILES; do cp "$TMP/$f" "$APP/$f"; done
chmod +x "$APP/ducky.sh" "$APP/panel/app.py" "$APP/bot/tgbot.py" "$APP/modules/proxy.py"
rm -rf "$TMP" "$APP/panel/__pycache__"
[ -n "${DUCKY_TEST:-}" ] || ln -sf "$APP/ducky.sh" /usr/local/bin/ducky
ok 100 "Done in $((SECONDS-T0))s" "Installed! Launch anytime with: ducky"
[ -n "${DUCKY_TEST:-}" ] && exit 0
systemctl is-active --quiet dky-panel 2>/dev/null && systemctl restart dky-panel
systemctl is-active --quiet dky-tgbot 2>/dev/null && systemctl restart dky-tgbot
exec ducky
