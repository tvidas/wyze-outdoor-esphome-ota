#!/usr/bin/env bash
# Turn this laptop into an isolated AP: DHCP + spoofed DNS + NAT out the uplink.
source "$(dirname "$0")/lib/common.sh"
need_root "./2-setup-network.sh"

for c in hostapd dnsmasq iptables; do
  command -v $c >/dev/null || { echo "Install: sudo dnf install hostapd dnsmasq iptables   (Debian: apt)"; exit 1; }
done

# --nat-only: just re-point NAT at the current uplink (tether reconnected) without touching the AP
if [ "${1:-}" = --nat-only ]; then nat_up; exit; fi

if systemctl is-active -q firewalld; then
  say "Stopping firewalld for the session (restored by 5-teardown.sh)"
  systemctl stop firewalld; touch "$RUN/firewalld.was-active"
fi

say "Freeing $WIFI_IF from NetworkManager / wpa_supplicant"
nmcli dev set "$WIFI_IF" managed no 2>/dev/null || true
systemctl stop wpa_supplicant 2>/dev/null || true
rfkill unblock wifi 2>/dev/null || true
ip link set "$WIFI_IF" down; ip addr flush dev "$WIFI_IF"
ip addr add "$AP_CIDR" dev "$WIFI_IF"; ip link set "$WIFI_IF" up

say "Rendering configs"
sed -e "s|__WIFI_IF__|$WIFI_IF|g" -e "s|__AP_SSID__|$AP_SSID|g" \
    -e "s|__AP_CHANNEL__|$AP_CHANNEL|g" -e "s|__AP_PASS__|$AP_PASS|g" \
    "$HERE/templates/hostapd.conf" > "$RUN/hostapd.conf"
render_dnsmasq off   # spoof starts OFF; ./spoof.sh on just before the ESPHome push

say "Enabling IP forwarding + NAT"
nat_up

say "Starting dnsmasq + hostapd (foreground logs in $RUN/)"
restart_dnsmasq
echo "dnsmasq up. Tail logs:  journalctl -f | grep dnsmasq   (or run dnsmasq with -d in another shell)"
echo
echo "Now start the AP in ITS OWN terminal (leave it open to watch associations):"
echo "    sudo ./3-start-ap.sh wyze"
echo
warn "AP '$AP_SSID' is being served on $WIFI_IF ($AP_IP). Onboard the plug to THIS SSID in the Wyze app."
