#!/usr/bin/env bash
# Make the laptop AP impersonate the HOME wifi (ssid/pass from esphome/secrets.yaml)
# so a freshly-flashed ESPHome plug connects HERE and we can verify it without
# being at home. Renders run/hostapd-home.conf; you restart hostapd with it.
source "$(dirname "$0")/lib/common.sh"
S="$HERE/esphome/secrets.yaml"
[ -f "$S" ] || { echo "no esphome/secrets.yaml"; exit 1; }
getq(){ sed -nE "s/^$1:[[:space:]]*\"?([^\"#]*[^\"#[:space:]])\"?.*/\1/p" "$S"; }
HS=$(getq wifi_ssid); HP=$(getq wifi_password)
if [ -z "$HS" ] || [ "${#HP}" -lt 8 ]; then
  echo "wifi_ssid/password missing or pass < 8 chars"; exit 1
fi
sed -e "s|__WIFI_IF__|$WIFI_IF|g" -e "s|__AP_SSID__|$HS|g" \
    -e "s|__AP_CHANNEL__|$AP_CHANNEL|g" -e "s|__AP_PASS__|$HP|g" \
    "$HERE/templates/hostapd.conf" > "$RUN/hostapd-home.conf"
chmod 600 "$RUN/hostapd-home.conf"   # contains the home wifi password
echo "Rendered run/hostapd-home.conf for SSID '$HS'."
echo "In the hostapd terminal: Ctrl-C, then:  sudo hostapd $RUN/hostapd-home.conf"
echo "The plug should associate within a minute (watch for its MAC)."
