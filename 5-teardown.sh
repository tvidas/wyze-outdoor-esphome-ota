#!/usr/bin/env bash
source "$(dirname "$0")/lib/common.sh"
need_root "./5-teardown.sh"
say "Stopping services"
pkill -F "$RUN/dnsmasq.pid" 2>/dev/null || true
pkill hostapd 2>/dev/null || true
say "Removing NAT rules"
nat_down
sysctl -w net.ipv4.ip_forward=0 >/dev/null
say "Returning $WIFI_IF to NetworkManager"
ip addr flush dev "$WIFI_IF" 2>/dev/null || true
nmcli dev set "$WIFI_IF" managed yes 2>/dev/null || true
systemctl start wpa_supplicant 2>/dev/null || true
if [ -f "$RUN/firewalld.was-active" ]; then
  say "Restarting firewalld"; systemctl start firewalld; rm -f "$RUN/firewalld.was-active"
fi
echo "Done. Normal Wi-Fi restored."
