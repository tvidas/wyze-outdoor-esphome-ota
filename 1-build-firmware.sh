#!/usr/bin/env bash
# Compile the ESPHome image you'll flash onto the plug.
source "$(dirname "$0")/lib/common.sh"
cd "$HERE/esphome"
[ -f secrets.yaml ] || { echo "Create secrets.yaml first (cp secrets.yaml.example secrets.yaml)"; exit 1; }
command -v esphome >/dev/null || { echo "Install ESPHome:  pipx install esphome   (or: python3 -m pip install esphome)"; exit 1; }

say "Validating config"
esphome config wyze-outdoor-plug.yaml >/dev/null && echo "config OK"

say "Compiling (first run downloads the toolchain; takes a few minutes)"
esphome compile wyze-outdoor-plug.yaml

# Wyze's updater wants the OTA (app-only) image, NOT factory.bin. Newer ESPHome
# names it firmware.ota.bin; older builds call it firmware.bin.
BIN=$(find .esphome/build -name 'firmware.ota.bin' 2>/dev/null | head -1)
[ -n "$BIN" ] || BIN=$(find .esphome/build -path '*.pioenvs*' -name 'firmware.bin' 2>/dev/null | head -1)
echo
if [ -n "$BIN" ]; then
  cp "$BIN" "$HERE/run/esphome-ota.bin"
  echo "OTA image ready: $HERE/run/esphome-ota.bin  (from $BIN)"
  head -c1 "$HERE/run/esphome-ota.bin" | xxd -p | grep -qx e9 || warn "image does not start with ESP32 magic 0xE9 - check it"
else
  warn "Could not locate the OTA image; search with:  find .esphome -name 'firmware*.bin'"
  exit 1
fi
