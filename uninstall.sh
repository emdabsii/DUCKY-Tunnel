#!/usr/bin/env bash
# DUCKY Tunnel Suite v2.0 — One-Line Complete Uninstaller
# Usage: bash <(curl -Ls https://raw.githubusercontent.com/emdabsii/DUCKY-Tunnel/main/uninstall.sh)
Y=$'\e[1;33m'; W=$'\e[1;97m'; D=$'\e[2;37m'; N=$'\e[0m'

printf '\n  %sDUCKY%s %sTUNNEL — COMPLETE UNINSTALLER%s\n\n' "$Y" "$N" "$W" "$N"
[ "$(id -u)" = 0 ] || { printf '  %sRun as root: sudo -i%s\n\n' "$Y" "$N"; exit 1; }

printf '  %s[1/5]%s Stopping all active DUCKY mesh tunnels & cleaning iptables...\n' "$Y" "$N"
for s in /etc/.ducky-vault/exec/*.dkrun; do
  [ -f "$s" ] && bash "$s" stop >/dev/null 2>&1 || true
done

printf '  %s[2/5]%s Disabling & removing systemd services (mesh, panel, sentinel, proxy, bot)...\n' "$Y" "$N"
for u in /etc/systemd/system/dky-*.service; do
  [ -f "$u" ] || continue
  bn=$(basename "$u")
  systemctl disable --now "$bn" >/dev/null 2>&1 || true
  rm -f "$u"
done

printf '  %s[3/5]%s Removing virtual tunnel interfaces (dky*, dkysit*)...\n' "$Y" "$N"
for i in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^dky(sit)?[0-9]+' | cut -d@ -f1); do
  ip link del "$i" >/dev/null 2>&1 || true
  ip tunnel del "$i" >/dev/null 2>&1 || true
done

printf '  %s[4/5]%s Purging DUCKY vault, core files, cron jobs, sysctl & logs...\n' "$Y" "$N"
rm -rf /opt/.ducky-core /etc/.ducky-vault /usr/local/bin/ducky \
       /etc/sysctl.d/99-ducky-kernel.conf /etc/cron.d/ducky-refresh \
       /var/log/ducky-*.log /tmp/dky_*
if [ -f /swapfile_ducky ]; then
  swapoff /swapfile_ducky >/dev/null 2>&1 || true
  rm -f /swapfile_ducky
  sed -i '\|/swapfile_ducky|d' /etc/fstab 2>/dev/null || true
fi

printf '  %s[5/5]%s Reloading systemd & kernel parameters...\n' "$Y" "$N"
systemctl daemon-reload >/dev/null 2>&1 || true
sysctl --system >/dev/null 2>&1 || true

printf '\n  %s[ OK ]%s %sDUCKY Tunnel has been completely removed from this server.%s\n\n' "$Y" "$N" "$W" "$N"
