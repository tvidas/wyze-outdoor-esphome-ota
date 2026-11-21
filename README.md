# wyze-outdoor-esphome-ota

**Automated, no-solder OTA flash of Wyze Outdoor Plugs to ESPHome; the plug never touches your Wi-Fi.**

Scripts that automate reflashing a **Wyze Outdoor Plug (WLPPO / WLPPO1, ESP32)**
from stock Wyze firmware to [ESPHome](https://esphome.io), over the air, from a
Linux laptop:

- **No soldering.** The plug stays sealed. No serial adapter is needed.
- **Never on your Wi-Fi.** Neither the plug nor the phone running the Wyze app
  ever joins your existing network. Both use a temporary access point the laptop
  creates, so the stock firmware never sees your network or your Wi-Fi password.
  The first network the plug joins with your credentials is your home Wi-Fi,
  and by then it's running ESPHome.

One honest limit: Wyze's "update now" command only comes through Wyze's cloud,
so the plug and the app do talk to Wyze during setup. That traffic goes over
the laptop's own network and internet connection (a phone USB tether), never
through your home network, and a throwaway Wyze account is enough.

How it works: the laptop becomes the access point. The plug is added in the
Wyze app on that access point, downgraded to an old Wyze firmware, and then sent
ESPHome, which joins your home Wi-Fi and Home Assistant.

> **Tested:** 4 plugs, stock firmware 1.2.0.86 → ESPHome, November 2026.
> Fedora 42 laptop (Intel Wi-Fi), phone USB tether for internet, ESPHome 2026.11.

## ⚠️ Before you start

- **This can brick a plug.** A bad over-the-air flash can only be recovered over
  serial (3.3 V USB-serial adapter, triangle-bit screwdriver). The scripts check
  firmware hashes and stop at every irreversible step, but you use this at your
  own risk.
- **Roku Outdoor Smart Plug SE:** same hardware, but Secure Boot, encrypted flash
  and no UART. **It can't be flashed by any method.** Check the branding first.
- **You need a Wyze account.** The "update now" command is only delivered through
  Wyze's cloud, so the plug must be added in the Wyze app (on the laptop's
  access point) and the laptop needs internet. A throwaway account is fine.
- **Wyze can break this at any time** by changing their update API. It has
  happened before. If it stops working, check
  [WyzeUpdater issue #9](https://github.com/HclX/WyzeUpdater/issues/9).
- This project isn't affiliated with Wyze or ESPHome.

If you have a USB-serial adapter, serial flashing is more reliable and needs no
Wyze account. See [digiblur's serial guide](https://digiblur.com/2021/03/27/how-to-flash-the-wyze-outdoor-plug-esphome-or-tasmota-local-control/).
The ESPHome config in `esphome/` works for either method.

## How it works

```
                 ┌── Wyze cloud (sends "update now" + a URL) ──┐
                 │                                             ▼
 Wyze app ──► Wyze cloud            laptop: AP + DHCP + DNS + NAT ◄── plug
                                      │            │
                         USB tether ──┘      DNS spoof (ESPHome step only):
                         (internet)          s3-us-west-2.amazonaws.com → laptop
```

1. **Downgrade.** The DNS spoof is **off**. The plug downloads Wyze's own old
   firmware 1.2.0.73 from Amazon S3 over HTTPS.
2. **ESPHome.** The DNS spoof is **on**. Wyze's cloud sends the same S3 URL, but
   on our network that hostname resolves to the laptop. The laptop serves the
   ESPHome image over HTTPS, and 1.2.0.73 accepts the self-signed certificate.
3. ESPHome reboots and joins your home Wi-Fi.

Wyze's API only accepts firmware URLs on a few Amazon hostnames, and only over
HTTPS. That's why the ESPHome step reuses the real 1.2.0.73 URL and redirects it
with DNS.

## Requirements

**Hardware**
- A Linux laptop whose Wi-Fi card supports **AP mode** (`iw list` → "Supported
  interface modes" includes `AP`). The Wi-Fi card is taken over by the access
  point while you work.
- A **second internet connection** for the laptop: a phone USB tether or
  ethernet.
- A phone with the Wyze app.

**Software** (Fedora shown; Debian/Ubuntu package names in brackets, untested)
```bash
sudo dnf install hostapd dnsmasq iptables bind-utils git python3 python3-requests pipx
#   [apt: hostapd dnsmasq iptables dnsutils git python3 python3-requests pipx]
pipx install esphome
```
[WyzeUpdater](https://github.com/gtxaspec/WyzeUpdater) is cloned into `vendor/`
on first use.

**Wyze account**
- Create an account in the Wyze app. **Turn off 2FA and Passkeys**, because
  WyzeUpdater can't handle them.
- Create an API key at <https://developer-api-console.wyze.com/> (Key ID + API Key).

## Setup

```bash
git clone https://github.com/<you>/wyze-outdoor-esphome-ota.git && cd wyze-outdoor-esphome-ota
git config core.hooksPath .githooks             # enable the secret-check hook

cp esphome/secrets.yaml.example esphome/secrets.yaml   # home Wi-Fi + keys
cp wyze.env.example wyze.env                           # Wyze account + API key
openssl rand -base64 32                                # paste as api_key
```
Each line in both example files explains why it's needed. Both real files are
gitignored.

`config.env` normally needs no changes. The Wi-Fi and uplink interfaces are
detected automatically. Change `AP_PASS` if you like.

## Steps

The step numbers match the script names. Use two terminals: **A** keeps the
access point running in the foreground, **B** runs everything else.

### Step 1: build the firmware (`1-build-firmware.sh`)
Do this first, while the laptop still has its normal internet. It only needs
doing once: one image works for every plug, because each plug names itself
`wyze-outdoor-<last 6 of MAC>`.
```bash
./1-build-firmware.sh             # → run/esphome-ota.bin (about 10 min the first time)
```

### Step 2: set up the network (`2-setup-network.sh`)
Plug in the phone USB tether first. The laptop's Wi-Fi is about to become the
access point.
```bash
sudo ./2-setup-network.sh         # B: frees Wi-Fi, sets up NAT and DHCP/DNS (spoof OFF)
```

### Step 3: start the access point (`3-start-ap.sh`)
```bash
sudo ./3-start-ap.sh wyze         # A: "WyzeFlash" AP in the foreground; leave it open
```
Optional check: connect your phone to WyzeFlash. It should have internet.

### Step 4: flash the plugs (`4-flash.sh`)

**4a. Add the plugs in the Wyze app.** Keep your phone on **WyzeFlash**, add
each plug, and give it the WyzeFlash SSID and password. In each plug's
settings, **turn off automatic firmware updates**. Then get the MACs:
```bash
./4-flash.sh list                 # B: note each "OutdoorPlug (WLPPO)" MAC
```
Use the main MAC, not the `-0001` / `-0002` outlet entries.

**4b. Downgrade to 1.2.0.73.** Spoof off. You can do several plugs at once.
```bash
sudo ./4-flash.sh downgrade MAC1 MAC2 MAC3
```
Answer **y** for each plug, wait for `SUCCESS` for each one, then press Ctrl-C.
Wait about 5 minutes, then run `./4-flash.sh list` until every plug shows
**1.2.0.73**.

**4c. Push ESPHome.** Spoof on, **one plug per run.**
```bash
sudo ./spoof.sh on
sudo ./4-flash.sh esphome MAC1    # wait for "Successfully served firmware file", then Ctrl-C
sudo ./4-flash.sh esphome MAC2    # ...repeat for each plug
sudo ./spoof.sh off
```
When the download finishes, the plug drops off the access point. That means it
rebooted into ESPHome.

### Step 5: tear down (`5-teardown.sh`)
```bash
# Ctrl-C in terminal A, then in B:
sudo ./5-teardown.sh              # restores NetworkManager, firewalld, NAT
```

## Checking it worked

- **At home:** the plugs join your Wi-Fi, and Home Assistant shows them as
  discovered ESPHome devices (Settings → Devices & Services). Add each one with
  the `api_key` from `secrets.yaml`.
- **Away from home:** if a plug can't find your Wi-Fi, ESPHome starts a
  **`wyze-outdoor fallback`** hotspot with a setup page. Only ESPHome creates
  that hotspot, so seeing it proves the flash worked.
- **On the bench:** `./ap-as-home.sh && sudo ./3-start-ap.sh home` makes the laptop
  pretend to be your home Wi-Fi, so a flashed plug connects to it. Look for
  `wyze-outdoor-XXXXXX` in `run/dnsmasq.leases`. ESPHome uses a different Wi-Fi
  MAC from the Wyze one. ESP32 station mode can be picky about laptop access
  points, so a plug that won't connect here is not necessarily broken.
- Wyze's `list` keeps showing a flashed plug's **old** firmware version, because
  the plug stops reporting to Wyze. Ignore it.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `3005 unauthorized operation` on the ESPHome push | The URL was HTTP. Wyze now requires HTTPS. `4-flash.sh` already uses `--ssl` on :443. Older guides that use `http -p 18080` no longer work. |
| Only one `Successfully served` when pushing several plugs | WyzeUpdater's server handles one download at a time. Push ESPHome one plug per run. |
| hostapd: `Match already configured` / segfault | Another hostapd is still running. `sudo ./3-start-ap.sh wyze` kills stray copies and resets the interface. |
| Phone joins WyzeFlash but has no internet | The tether reconnected under a new interface name. Run `sudo ./2-setup-network.sh --nat-only`. |
| No DHCP on the AP after switching modes | dnsmasq stopped when the interface was reset. `3-start-ap.sh` restarts it. |
| Wyze login fails | Turn off 2FA/Passkeys, check `wyze.env`, delete `run/.wyze_token`, then run `./4-flash.sh list`. |
| Plug stays on 1.2.0.86 after the downgrade | Spoof must be **off** for the downgrade, and the plug needs internet through the tether. Check with `./spoof.sh status`. |

## Customizing the ESPHome config

`esphome/wyze-outdoor-plug.yaml` includes:
- two outlets, which restore their previous state after a power cut
- power, voltage, current and energy readings
- a light-level sensor and a "Daylight" sensor
- Wi-Fi signal, uptime and free-memory readings
- a Bluetooth proxy for Home Assistant
- a password-protected web page (user `admin`, password `web_password`)
- an **overload cut-off**: both outlets switch off above `max_power` (1500 W).
  This runs on the plug itself.

The power readings use community calibration values. Check them against a known
load and adjust `current_res`, `voltage_div` and the `calibrate_linear` points.
After the first flash, copy the YAML and your secrets into the Home Assistant
ESPHome add-on and do future updates from there.

## Afterwards

- Remove the plugs from the Wyze app, then delete the account or turn 2FA back
  on and change the password. The cached token in `run/.wyze_token` works until
  you do.
- Keep a backup of `esphome/secrets.yaml`. Without `ota_password`, updating a
  plug needs the serial adapter.

## Secrets

Real secrets only go in gitignored files: `esphome/secrets.yaml`, `wyze.env`,
and `run/` (Wyze token, built firmware, the home-Wi-Fi hostapd config). The
pre-commit hook blocks a commit that contains any of those files, any of their
values, or anything that looks like an ESPHome API key. Enable it after cloning
with `git config core.hooksPath .githooks`.

## Files

```
1-build-firmware.sh     compile the ESPHome OTA image → run/esphome-ota.bin
2-setup-network.sh      laptop → NAT + DHCP/DNS; --nat-only re-points NAT at a new uplink
3-start-ap.sh           start the AP cleanly: wyze (onboarding) or home (verify a plug)
4-flash.sh              list | downgrade MAC... | esphome MAC   (drives WyzeUpdater)
5-teardown.sh           restore normal networking
spoof.sh                helper: DNS spoof of the firmware host (on | off | status)
ap-as-home.sh           helper: write an AP config that impersonates your home Wi-Fi
config.env              settings (interfaces auto-detected; AP SSID/password, subnet)
esphome/                ESPHome YAML + secrets.yaml.example
wyze.env.example        Wyze account + API key template
templates/              hostapd / dnsmasq templates
lib/common.sh           shared helpers
.githooks/pre-commit    secret check
```

## Credits

This kit wraps and automates other people's work:

- **[WyzeUpdater](https://github.com/HclX/WyzeUpdater)** by HclX (MIT), the
  tool that sends Wyze's cloud the "update to this URL" command. This kit uses
  the **[gtxaspec fork](https://github.com/gtxaspec/WyzeUpdater)**, which added
  the API-key login Wyze has required since 2025. WyzeUpdater is cloned into
  `vendor/` at run time, not bundled.
- **[inlimbo.org: Wyze Outdoor Plug → ESPHome](https://www.inlimbo.org/2025/06/wyze-outdoor-plug-esphome/)**
  by Blaž (June 2025), which worked out the route: downgrade to 1.2.0.73, reuse
  the allow-listed S3 URL, redirect it with DNS. This kit adds the isolated
  access point, the HTTPS fix for the ESPHome step, and the automation.
- **[ESPHome devices: Wyze Outdoor Plug](https://devices.esphome.io/devices/wyze-outdoor-plug/)**,
  the source of the pinout and the base config in `esphome/`.
- **[digiblur](https://digiblur.com/2021/03/27/how-to-flash-the-wyze-outdoor-plug-esphome-or-tasmota-local-control/)**,
  who did the original teardown and serial flashing of this plug.
- Contributors to **[WyzeUpdater issue #9](https://github.com/HclX/WyzeUpdater/issues/9)**,
  who kept the method working through Wyze's API changes.
- **[ESPHome](https://esphome.io)**, **hostapd** and **dnsmasq**, which do the
  real work underneath.

Wyze firmware is never stored in this repo. It's downloaded from Wyze's own
servers and checked against a known MD5.

## License

MIT. See [LICENSE](LICENSE). Third-party tools fetched at run time keep their
own licenses.
