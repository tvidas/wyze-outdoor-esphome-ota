#!/usr/bin/env bash
# Toggle the DNS spoof of the firmware host:  sudo ./spoof.sh on|off|status
source "$(dirname "$0")/lib/common.sh"
case "${1:-status}" in
  on|off) need_root "./spoof.sh $1"; render_dnsmasq "$1"; restart_dnsmasq
          say "DNS spoof is now $1";;
  status) echo "spoof: $(cat "$RUN/spoof.state" 2>/dev/null || echo unknown)";;
  *) echo "usage: $0 on|off|status"; exit 1;;
esac
