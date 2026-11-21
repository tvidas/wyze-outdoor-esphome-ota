# shellcheck shell=bash
# shared helpers; sourced by the numbered scripts
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/config.env"
RUN="$HERE/run"          # generated runtime files live here
mkdir -p "$RUN"
# resolve WIFI_IF=auto to the first wireless netdev
if [ "$WIFI_IF" = auto ]; then
  WIFI_IF=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}')
  [ -n "$WIFI_IF" ] || { echo "No wireless interface found (iw dev). Set WIFI_IF in config.env."; exit 1; }
fi
# resolve UPLINK_IF=auto to the interface holding the default route (not the AP)
if [ "$UPLINK_IF" = auto ]; then
  UPLINK_IF=$(ip -4 route show default | awk -v ap="$WIFI_IF" '$5!=ap{print $5; exit}')
fi
need_root(){ [ "$(id -u)" = 0 ] || { echo "Run with sudo: $*"; exit 1; }; }
say(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

# render_dnsmasq on|off — spoof OFF for onboarding + downgrade (plug must reach
# the REAL s3 host over valid HTTPS); spoof ON only for the ESPHome push.
render_dnsmasq(){
  local SPOOF_LINES=""
  if [ "$1" = on ]; then
    for h in "${SPOOF_HOSTS[@]}"; do SPOOF_LINES+="address=/$h/$AP_IP"$'\n'; done
  fi
  sed -e "s|__WIFI_IF__|$WIFI_IF|g" -e "s|__DHCP_START__|$DHCP_START|g" \
      -e "s|__DHCP_END__|$DHCP_END|g" -e "s|__AP_IP__|$AP_IP|g" \
      -e "s|__UPSTREAM_DNS__|$UPSTREAM_DNS|g" \
      -e "s|__SPOOF_LINES__|$(printf '%s' "$SPOOF_LINES" | sed ':a;N;$!ba;s/\n/\\n/g')|" \
      "$HERE/templates/dnsmasq.conf" > "$RUN/dnsmasq.conf"
  echo "$1" > "$RUN/spoof.state"
}
restart_dnsmasq(){
  pkill -F "$RUN/dnsmasq.pid" 2>/dev/null || true; sleep 0.5
  dnsmasq -C "$RUN/dnsmasq.conf" -x "$RUN/dnsmasq.pid" -l "$RUN/dnsmasq.leases"
}

# NAT AP -> uplink. Remembers the uplink used so teardown/refresh removes the right rules.
nat_rules(){  # nat_rules -A|-D <uplink>
  iptables -t nat "$1" POSTROUTING -o "$2" -j MASQUERADE
  iptables "$1" FORWARD -i "$WIFI_IF" -o "$2" -j ACCEPT
  iptables "$1" FORWARD -i "$2" -o "$WIFI_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
}
nat_down(){ local old; old=$(cat "$RUN/uplink.ifname" 2>/dev/null) || return 0
  nat_rules -D "$old" 2>/dev/null || true; rm -f "$RUN/uplink.ifname"; }
nat_up(){
  if [ -z "$UPLINK_IF" ] || ! ip link show "$UPLINK_IF" >/dev/null 2>&1; then
    echo "No uplink found (UPLINK_IF='$UPLINK_IF'). Plug in the USB tether / ethernet."; exit 1
  fi
  [ "$UPLINK_IF" != "$WIFI_IF" ] || { echo "UPLINK_IF must differ from WIFI_IF"; exit 1; }
  nat_down
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  nat_rules -I "$UPLINK_IF"   # -I: ahead of docker/libvirt FORWARD rules
  echo "$UPLINK_IF" > "$RUN/uplink.ifname"
  echo "NAT: $WIFI_IF -> $UPLINK_IF"
}
