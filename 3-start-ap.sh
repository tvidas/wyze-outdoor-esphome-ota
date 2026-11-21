#!/usr/bin/env bash
# Cleanly (re)start the AP, avoiding the "Match already configured" segfault
# from leftover hostapd instances. Runs hostapd in the FOREGROUND of this term.
#   sudo ./3-start-ap.sh home    # impersonate your home wifi to verify a flashed plug
#   sudo ./3-start-ap.sh wyze    # the WyzeFlash onboarding AP
source "$(dirname "$0")/lib/common.sh"
need_root "./3-start-ap.sh ${1:-}"
case "${1:-}" in
  home) CONF="$RUN/hostapd-home.conf"; [ -f "$CONF" ] || { "$HERE/ap-as-home.sh" >/dev/null; }; ;;
  wyze) CONF="$RUN/hostapd.conf"; ;;
  *) echo "usage: sudo $0 home|wyze"; exit 1;;
esac
say "Stopping any running hostapd"
pkill -x hostapd 2>/dev/null || true; sleep 2
say "Resetting $WIFI_IF AP state"
ip link set "$WIFI_IF" down 2>/dev/null || true; sleep 1
ip link set "$WIFI_IF" up;   ip addr replace "$AP_CIDR" dev "$WIFI_IF"
say "Ensuring DHCP/DNS (dnsmasq) is up, spoof=$(cat "$RUN/spoof.state" 2>/dev/null || echo off)"
render_dnsmasq "$(cat "$RUN/spoof.state" 2>/dev/null || echo off)"
restart_dnsmasq
say "Starting hostapd ($(basename "$CONF")) — leave this terminal open"
exec hostapd "$CONF"
