#!/usr/bin/env bash
# Drives the OTA flash via gtxaspec/WyzeUpdater, per
# https://www.inlimbo.org/2025/06/wyze-outdoor-plug-esphome/ (verified 2026-11-21).
#   phase 1 (downgrade): spoof OFF, plug fetches REAL 1.2.0.73 from Amazon over HTTPS
#   phase 2 (esphome):   spoof ON, plug fetches our image over HTTPS from this laptop:443
# Usage: ./4-flash.sh list | sudo ./4-flash.sh downgrade MAC... | sudo ./4-flash.sh esphome MAC
source "$(dirname "$0")/lib/common.sh"

WU="$HERE/vendor/WyzeUpdater"
[ -d "$WU" ] || { say "Fetching WyzeUpdater (gtxaspec fork)"; git clone --depth 1 https://github.com/gtxaspec/WyzeUpdater.git "$WU"; }
TOKENS="$RUN/.wyze_token"
# Optional creds file (gitignored). Without it WyzeUpdater prompts interactively.
CREDS=()
if [ -f "$HERE/wyze.env" ] && [ ! -s "$TOKENS" ]; then
  chmod 600 "$HERE/wyze.env"; source "$HERE/wyze.env"
  # blank fields are left off so WyzeUpdater prompts for them (e.g. keep the password out of the file)
  [ -n "${WYZE_USER:-}" ]     && CREDS+=(--user "$WYZE_USER")
  [ -n "${WYZE_PASSWORD:-}" ] && CREDS+=(--password "$WYZE_PASSWORD")
  [ -n "${WYZE_KEY_ID:-}" ]   && CREDS+=(--key-id "$WYZE_KEY_ID")
  [ -n "${WYZE_API_KEY:-}" ]  && CREDS+=(--api-key "$WYZE_API_KEY")
fi
# WU_QUIET=1 drops --debug (debug output includes the login token)
wu(){ local dbg=(--debug); [ -z "${WU_QUIET:-}" ] || dbg=()
      python3 ./wyze_updater.py "${dbg[@]}" --token "$TOKENS" "${CREDS[@]}" "$@"; local rc=$?
      [ -f "$TOKENS" ] && chmod 600 "$TOKENS"; return $rc; }
URL_HOST="s3-us-west-2.amazonaws.com"
URL_PATH="wuv2/upgrade/WLPPO/firmware/1.2.0.73.bin"   # same path both phases (Wyze API allow-list)
DOWNGRADE_FW="$HERE/firmware/WLPPO_1.2.0.73.bin"
DOWNGRADE_MD5="129b8b38b68a5eaafbe8dafb175302b5"       # == S3 ETag of the real file

# list = login check + device/firmware listing; safe, no root, no plug changes
if [ "${1:-}" = list ]; then cd "$WU"; WU_QUIET=1 wu list; exit; fi
need_root "./4-flash.sh $*"

cat <<'TXT'
Before either phase:
  * Unit is a Wyze Outdoor Plug WLPPO1 - NOT a Roku Outdoor Smart Plug SE (unflashable).
  * Wyze account has 2FA and Passkeys DISABLED (the script can't handle them).
  * Auto firmware update for the plug is OFF in the Wyze app.
  * The plug is onboarded and associated to the laptop AP (hostapd terminal / run/dnsmasq.leases).
  * Wyze creds come from wyze.env (see wyze.env.example) or are prompted for.
    Token (incl. API key) cached in run/.wyze_token, mode 600, gitignored.
  * Each push shows device model + current firmware and asks y/N - CHECK IT.
TXT
# MACs may be given as args (sudo ./4-flash.sh downgrade MAC1 MAC2 ...); else prompt for one.
SUB="${1:-}"; shift || true
MACARGS=("$@")
[ ${#MACARGS[@]} -gt 0 ] || { read -r -p "Plug MAC(s), space-separated, no colons/suffix: " -a MACARGS; }
DEV=()
for m in "${MACARGS[@]}"; do
  m="${m//:/}"; m="${m^^}"
  [[ "$m" =~ ^[0-9A-F]{12}$ ]] || { echo "Bad MAC: $m"; exit 1; }
  DEV+=(-d "$m")
done
[ ${#DEV[@]} -gt 0 ] || { echo "No MAC given"; exit 1; }

cd "$WU"   # --ssl loads testcert/ relative to cwd
case "$SUB" in
  downgrade)
    [ "$(cat "$RUN/spoof.state" 2>/dev/null)" = off ] || { warn "Spoof must be OFF: sudo ./spoof.sh off"; exit 1; }
    [ -f "$DOWNGRADE_FW" ] || { mkdir -p "$(dirname "$DOWNGRADE_FW")"
      curl -fsSo "$DOWNGRADE_FW" "https://$URL_HOST/$URL_PATH"; }
    echo "$DOWNGRADE_MD5  $DOWNGRADE_FW" | md5sum -c --quiet || { warn "downgrade image missing/corrupt"; exit 1; }
    say "Phase 1: pushing downgrade to 1.2.0.73 (plug downloads from real Amazon)"
    echo "When the API result says success: Ctrl-C, wait ~5 min, then:"
    echo "  sudo ./4-flash.sh list   -> Firmware Version must be 1.2.0.73"
    # -f is the real file so the md5 sent to the plug matches what it downloads
    # (the guide used /dev/null, which also worked; this is the stricter option).
    wu update "${DEV[@]}" \
      -f "$DOWNGRADE_FW" --url-host "$URL_HOST" --url-path "$URL_PATH" --ssl -a "$AP_IP"
    ;;
  esphome)
    [ "$(cat "$RUN/spoof.state" 2>/dev/null)" = on ] || { warn "Spoof must be ON: sudo ./spoof.sh on"; exit 1; }
    [ -f "$RUN/esphome-ota.bin" ] || { warn "Build first: ./1-build-firmware.sh"; exit 1; }
    got=$(dig +short @"$AP_IP" "$URL_HOST" | tail -1)
    [ "$got" = "$AP_IP" ] || { warn "$URL_HOST resolves to '$got', not $AP_IP - spoof not working"; exit 1; }
    warn "Only continue if 'list' showed the plug on 1.2.0.73."
    # Wyze's API now rejects HTTP firmware URLs with 3005 'unauthorized operation'
    # (the guide's -p 18080 HTTP step is stale). Serve over HTTPS:443 like the
    # downgrade; the 1.2.0.73 plug accepts the self-signed cert in vendor/WyzeUpdater/testcert.
    # WyzeUpdater's web server is single-threaded: if several plugs download at
    # once, only one succeeds. Flash ESPHome ONE plug per run.
    [ ${#DEV[@]} -le 2 ] || warn "Many MACs given; the server serves one at a time - prefer one MAC per run."
    say "Phase 2: pushing ESPHome OTA image over HTTPS :443"
    echo "Watch for 'Successfully served firmware file'; then Ctrl-C. ESPHome boots and joins HOME wifi."
    wu update "${DEV[@]}" \
      -f "$RUN/esphome-ota.bin" --url-host "$URL_HOST" --url-path "$URL_PATH" --ssl -a "$AP_IP"
    ;;
  *) echo "usage: sudo $0 list|downgrade|esphome"; exit 1;;
esac
