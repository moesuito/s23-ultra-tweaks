#!/usr/bin/env bash
# s23-ultra-tweaks installer. Runs on your computer (macOS or Linux) with the phone on USB:
#   curl -fsSL https://raw.githubusercontent.com/dtechterminal/s23-ultra-tweaks/main/install.sh | bash
# It asks which tweaks you want, then pushes them to the phone and applies them. Everything it
# does on the phone is undone by a reboot. Run it again after each reboot (it offers your last picks).
set -euo pipefail
# The whole script is inside main(), so a partial download can't run half a script and nothing
# below can read the rest of the script from stdin (curl | bash).
main() {
REPO=dtechterminal/s23-ultra-tweaks
VERSION=v1.8.0
AIRDROP_KBASE=5.15.197-android13-8-34343818-ab; AIRDROP_FW="S918WVLU8GZIF S918BXXUAGZIF S918U1UEU8GZIF S918USQU8GZIF S918NKSU8GZIF"   # as in device/tweaks.sh
PHONE_DIR=/data/adb/s23tweaks          # state (and the code, when the module isn't installed)
MODULE_DIR=/data/adb/modules/s23_ultra_tweaks

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }
# A closed input (EOF) must not count as Enter, which means "all tweaks" and "yes"
ask()  { local a; read -r -p "$1" a </dev/tty || die "no answer (input closed)"; printf '%s' "$a"; }

command -v adb >/dev/null || die "adb not found. Install Android platform-tools: https://developer.android.com/tools/releases/platform-tools"
command -v curl >/dev/null || die "curl not found"
command -v tar >/dev/null || die "tar not found"
if command -v sha256sum >/dev/null; then sha() { sha256sum "$1" | cut -d' ' -f1; }; else sha() { shasum -a 256 "$1" | cut -d' ' -f1; }; fi
[ -r /dev/tty ] || die "needs an interactive terminal (it asks questions)"

# ---- pick the phone ----
devs=(); while read -r d; do devs+=("$d"); done < <(adb devices </dev/null | awk 'NR>1 && $2=="device" {print $1}')
[ ${#devs[@]} -gt 0 ] || die "no phone found. Plug it in over USB, enable USB debugging and accept the prompt on the phone."
if [ ${#devs[@]} -gt 1 ]; then
  say "Several devices are connected:"; for i in "${!devs[@]}"; do info "$((i+1))) ${devs[$i]}"; done
  n=$(ask "Which one? "); [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#devs[@]} ] || die "no device picked"
  SERIAL=${devs[$((n-1))]}
else SERIAL=${devs[0]}; fi
a() { adb -s "$SERIAL" "$@" </dev/null; }
sh_() { a shell "$@" | tr -d '\r'; }

model=$(sh_ getprop ro.product.model); build=$(sh_ getprop ro.build.PDA); csc=$(sh_ getprop ro.csc.sales_code)
kernel=$(sh_ uname -r); android=$(sh_ getprop ro.build.version.release)
say "Phone: $model, firmware $build ($csc), Android $android"
case "$model" in SM-S918*) ;; *) die "this is for the Galaxy S23 Ultra (SM-S918*), not $model" ;; esac

# ---- root ----
root_ok() { [ "$(sh_ 'su -c id -u' 2>/dev/null)" = 0 ]; }
if ! root_ok; then
  info "No root for adb yet. Restarting adb on the phone (a shell started before KernelSU never gets root)..."
  a usb >/dev/null 2>&1 || true; sleep 3; a wait-for-device; sleep 2
fi
root_ok || die "no root. On the phone: open DFRoot and tap LAUNCH ROOT, then in KernelSU > Superuser allow Shell. Then run this again. See https://github.com/$REPO#before-you-start"

# ---- what can this phone take? ----
gms=$(sh_ 'dumpsys package com.google.android.gms | grep -m1 versionCode' | grep -oE 'versionCode=[0-9]+' | cut -d= -f2)
can_airdrop=1; why_airdrop=""
k_ok=0; for f in $AIRDROP_FW; do [ "$kernel" = "$AIRDROP_KBASE$f" ] && k_ok=1; done
# the custom-kernel opt-in (kernel_override in device/tweaks.sh)
case "$kernel" in 5.15.*-android13-*) [ "$(sh_ 'su -c "[ -f /data/adb/s23tweaks/allow-any-kernel ] && echo y"')" = y ] && [[ " $AIRDROP_FW " == *" $build "* ]] && k_ok=1 ;; esac
[ $k_ok = 1 ] || { can_airdrop=0; why_airdrop="needs firmware ${AIRDROP_FW// /, } (this phone runs $build)"; }
[ "${gms:-0}" -ge 261125000 ] || { can_airdrop=0; why_airdrop="needs Google Play services 26.11 or newer"; }
# callrec edits the phone's own carrier config (any sales code); india swaps in the INS files of One UI 9
can_rec=1; why_rec=""
can_csc=1; why_csc=""; oneui=$(sh_ getprop ro.build.version.oneui)
[ "${oneui:0:1}" = 9 ] || { can_csc=0; why_csc="needs One UI 9 (the INS files come from One UI 9 firmware)"; }
[ "$csc" = INS ] && { can_csc=0; why_csc="this phone's sales code is INS already"; }
can_ct=1; why_ct=""; case "$build" in S918WVLU8GZIF|S918BXXUAGZIF) ;; *) can_ct=0; why_ct="needs firmware S918WVLU8GZIF or S918BXXUAGZIF (it patches that build's Settings app)" ;; esac   # SETTINGS_EAD in device/tweaks.sh
# cam24fps goes by the Camera APK, not the firmware: stock and patched md5s as in CAMERA_24FPS (device/tweaks.sh)
CAM24_MD5="174e38e111f53c92eea54fd8b9a8c1c6 b22942b22ec14896bc02277d319b7623 e7c89df10d6607ea1ddeedceee961903 650dc854741a92f54be455fc19cd4c89"
cam_md5=$(sh_ md5sum /system/priv-app/SamsungCamera/SamsungCamera.apk 2>/dev/null | cut -d' ' -f1)
can_c24=0; why_c24="this phone's Samsung Camera isn't one the 24 fps patch was made for (Camera 17.0.00.43 of S918BXXUAGZIF or S918WVLU8GZIF)"
case " $CAM24_MD5 " in *" ${cam_md5:-none} "*) can_c24=1; why_c24="" ;; esac
# hideksu goes by the framework file, not the firmware: stock and patched services.jar md5s as in HIDEKSU_JARS (device/tweaks.sh)
HKS_MD5="30d17f5d60b0d42585b97a94412f6e12 f4c5966939637df194bb465478234fc3 7dc62286f9f0675f84459943cdc397b6 a5449f73103be635f03fb6fdaf9f7d98 c438dd27a76486855d01e74379e13b5d f4918c7454965788ecc0c9003cbea941"
jar_md5=$(sh_ md5sum /system/framework/services.jar 2>/dev/null | cut -d' ' -f1)
can_ksu=0; why_ksu="this phone's services.jar isn't one a patch was made from (S918W S918WVLU8GZIF, S918B INS, S918U1)"
case " $HKS_MD5 " in *" ${jar_md5:-none} "*) can_ksu=1; why_ksu="" ;; esac
# an Indian SIM (MCC 404/405) makes the carrier picks take the India config instead of plain call recording
sim=$(sh_ getprop gsm.sim.operator.numeric | cut -d, -f1); sim_india=0; carrier_skip=india
case "$sim" in 404*|405*) sim_india=1; carrier_skip=callrec ;; esac

# Language Core for callscreen: a 3.1 GB download, so the phone needs about 7 GB free while it installs
can_lc=1; why_lc=""
free_kb=$(sh_ "df -k /data | tail -n 1" | awk '{print $4}')
lc_have=$(sh_ "dumpsys package com.samsung.android.offline.languagemodel 2>/dev/null | grep -m1 -oE 'versionCode=4[0-9]{8}'")
[ -z "$lc_have" ] && [ "${free_kb:-0}" -lt 7340032 ] && { can_lc=0; why_lc="needs about 7 GB free on the phone for its 3.1 GB download"; }

# Tweaks, grouped in categories. A category letter picks every available tweak in it.
ids=(airdrop wifi7 hotspot6g
     logvideo camextras camerahdr hdr2023 autoframe tenbit cam24fps wideflash prowbtint zoomrocker videosoftening afcontrol aelimit slowmoaf extstorage anamorphic profps slowmo4k120 dofadapter mirror8k longrec
     display colortone vulkan weather
     galaxyai audioeraser settingssearch callscreen bargein
     battery features hideksu
     callrec india dual5g)
cat=(A A A B B B B B B B B B B B B B B B B B B B B B C C C C D D D D D E E E F F F)
cats=(A B C D E F)
catname=("Connectivity" "Camera" "Display and graphics" "Galaxy AI and Samsung apps" "Battery and settings" "Carrier")
desc=("AirDrop: Quick Share > Share with Apple devices (S24 Wi-Fi driver + Google's Mosey; 20 MB download)"
      "Wi-Fi 7 multi-link (MLO) with Wi-Fi 7 routers: S24 wpa_supplicant + driver MLO settings (adds AirDrop)"
      "6 GHz hotspot: Mobile Hotspot > Band offers 6 GHz (Wi-Fi 6E, 160 MHz); the country isn't changed, so Samsung Wallet keeps working"
      "Log video: Log recording in Camera > Pro video"
      "Camera extras: Director's view (front + back at once) and Super steady horizontal lock"
      "Camera HDR processing: puts back the multi-frame and low-light HDR steps One UI 9 removed (untested; 21 MB download)"
      "2023 ArcSoft HDR: the HDR engines of One UI 6 instead of today's (hybrid + bracketed HDR; 28 MB download; pick it by number)"
      "4K auto framing: the S24's UHD auto framing in video (reported to make the camera fail; pick it by number)"
      "Front-camera 10-bit: apps can record 10-bit HDR (HLG10) video with the selfie cameras (patches a copy of the camera driver)"
      "24 FPS in standard Video: adds 24 fps to FHD, UHD and 8K in standard Video (patches a copy of Samsung Camera)"
      "Flash on 0.6x ultrawide: Photo flash and Video torch on the ultrawide lens, plus its Camera Assistant menu"
      "White-balance tint in Pro: the Tint slider next to the colour temperature in Pro and Pro video"
      "Video zoom rocker: the smooth zoom rocker/slider in the standard Video mode"
      "Video softening: Camera Assistant's Off / Medium / High video softening, which reduces over-sharpening"
      "Autofocus controls: Camera Assistant's AF speed and AF sensitivity"
      "Auto exposure limit: Camera Assistant's cap on how far the camera raises ISO or slows the shutter"
      "Touch focus in Slow motion: tap the viewfinder to focus while recording a slow-motion video"
      "Record to USB-C storage: record straight to a USB-C SSD or drive in every video mode"
      "Anamorphic desqueeze: Camera Assistant's 1.33x / 1.55x / 2.0x anamorphic lens desqueeze"
      "Extra Pro video frame rates: 4K 25/48/50/100/120 (120 on Wide and Ultrawide), FHD 25/48/50/100, 8K 25, 21:9 Cinema 25/48/50/100/120, and the 10x super tele at 25/48/50 with the patched Camera APK"
      "4K120 in Slow motion: adds 4K120 and FHD120 to Slow motion and rebuilds the FHD240 menu entry"
      "DOF adapter in Camera Assistant: the DOF (depth-of-field) adapter option for manual-focus adapters"
      "8K while mirroring: records in 8K while the phone is mirrored to a display over HDMI or Smart View"
      "Longer recording limits: the overheat recording cap and the low-power-mode delay go from 5 minutes to 1 hour"
      "Always On Display: lock screen wallpaper, and AOD brightness that follows the room light"
      "Adaptive color tone: Settings > Display, the screen's colour follows the room light (1 MB download)"
      "Vulkan rendering: apps draw with Vulkan instead of OpenGL"
      "Lock screen weather effect: rain, snow, fog or sun over the lock screen wallpaper, following Samsung Weather (installs a 12 KB AI Core stub app)"
      "Galaxy AI apps: the S24's Now Brief, Creative Studio and Call Assist (219 MB download)"
      "Audio Eraser: remove wind, noise, music or voices from videos in Gallery (34 MB download)"
      "Settings search: the S24's new Settings search bar; natural-language answers stay off (10 MB download)"
      "Call screening: installs Samsung Language Core; screening and voice messages work, the AI summary doesn't (persistent; 3.1 GB download)"
      "Bixby barge-in: talk over Bixby while it answers (untested)"
      "Battery health page: Settings > Battery > Battery information shows health and cycles"
      "Extra settings: Auto power on/off schedule, louder VoIP calls"
      "HideKSU: hide the KernelSU root manager from apps, so root-aware apps like CRED stop crashing (patched services.jar; 12 MB download; needs the KernelSU manager installed)"
      "Call recording in the Samsung Phone app"
      "India carrier config for Airtel/Jio SIMs: 'Use 5G standalone networks' switch, call recording, Smart IVR, message cards, plus Samsung Wallet India (UPI, DigiLocker, transit) and the 6 GHz hotspot by reporting the phone as the Indian model; reverts on reboot, the sales code on disk is untouched"
      "Dual SIM 5G: 5G standalone on both SIMs at once instead of only the data SIM (adds your SIMs' country to the modem's 5G+5G list; stays until un-picked; the original is backed up first)")
avail=($can_airdrop $can_airdrop 1 1 1 1 1 1 1 $can_c24 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 $can_ct 1 1 1 1 1 $can_lc 1 1 1 $can_ksu $can_rec $can_csc 1)
why=("$why_airdrop" "$why_airdrop" "" "" "" "" "" "" "" "$why_c24" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "$why_ct" "" "" "" "" "" "$why_lc" "" "" "" "$why_ksu" "$why_rec" "$why_csc" "")

# pre-release builds lived in /data/local/tmp/s23tweaks: carry the picks and the Play services backup over
sh_ "su -c '[ -d /data/local/tmp/s23tweaks ] && [ ! -e $PHONE_DIR/choices ] && mkdir -p $PHONE_DIR && cp -r /data/local/tmp/s23tweaks/choices /data/local/tmp/s23tweaks/backup $PHONE_DIR/ 2>/dev/null; true'" >/dev/null
# With the KernelSU module installed (and active), drive its copy instead of installing a second one
TW=$PHONE_DIR/tweaks.sh; use_module=0
if [ "$(sh_ "su -c '[ -f $MODULE_DIR/tweaks.sh ] && [ ! -e $MODULE_DIR/remove ] && [ ! -e $MODULE_DIR/disable ] && echo yes'")" = yes ]; then
  TW=$MODULE_DIR/tweaks.sh; use_module=1
  info "The S23 Ultra Tweaks KernelSU module is installed; using it (no download needed)."
fi
# This script (from main) can list tweaks newer than the tweaks.sh that will run (the module's, or $VERSION's):
# offer only the ones that tweaks.sh knows, or apply would stop at "unknown tweak"
if [ $use_module = 1 ]; then known=$(sh_ "su -c 'grep -m1 ^TWEAK_IDS= $TW'"); from="the installed module"
elif [ -n "${S23T_SRC:-}" ]; then known=$(grep -m1 ^TWEAK_IDS= "$S23T_SRC/device/tweaks.sh"); from="$S23T_SRC"
else known=$(curl -fsL "https://raw.githubusercontent.com/$REPO/$VERSION/device/tweaks.sh" 2>/dev/null | grep -m1 ^TWEAK_IDS=); from=$VERSION; fi
known=${known#*=}; known=${known//\"/}
if [ -n "$known" ]; then
  for i in "${!ids[@]}"; do
    case " $known " in *" ${ids[$i]} "*) ;; *) avail[$i]=0; why[$i]="not in $from yet (comes with the next release)" ;; esac
  done
fi
last=$(sh_ "su -c 'cat $PHONE_DIR/choices 2>/dev/null'" || true)
picked=""
if [ -n "$last" ]; then
  r=$(ask "Apply your last picks again ($last)? [Y/n] ")
  [[ "$r" =~ ^[Nn] ]] || picked=$last
fi
if [ -z "$picked" ]; then
  say "Which tweaks do you want?"
  for c in "${!cats[@]}"; do
    say "  ${cats[$c]}) ${catname[$c]}"
    for i in "${!ids[@]}"; do
      [ "${cat[$i]}" = "${cats[$c]}" ] || continue
      if [ "${avail[$i]}" = 1 ]; then info "  $((i+1))) ${desc[$i]}"; else info "  $((i+1))) (unavailable: ${why[$i]}) ${desc[$i]}"; fi
    done
  done
  info "Pick whole categories by letter and single tweaks by number, e.g. \"A B 16\"."
  if [ $sim_india = 1 ]; then info "Indian SIM: category F picks ${#ids[@]} (India config, includes call recording)."
  else info "Category F picks call recording only; ${#ids[@]} (India config, for Indian SIMs) already includes it."; fi
  r=$(ask "Letters/numbers separated by spaces, Enter for all available: ")
  add() { case " $picked " in *" $1 "*) ;; *) picked="$picked $1" ;; esac; }
  if [ -z "$r" ]; then
    for i in "${!ids[@]}"; do [ "${avail[$i]}" = 1 ] && [ "${ids[$i]}" != $carrier_skip ] && [ "${ids[$i]}" != autoframe ] && [ "${ids[$i]}" != hdr2023 ] && add "${ids[$i]}"; done
  fi
  for n in $r; do
    n=$(printf '%s' "$n" | tr '[:lower:]' '[:upper:]')
    if [[ "$n" =~ ^[A-F]$ ]]; then
      for i in "${!ids[@]}"; do
        [ "${cat[$i]}" = "$n" ] && [ "${avail[$i]}" = 1 ] && [ "${ids[$i]}" != $carrier_skip ] && [ "${ids[$i]}" != autoframe ] && [ "${ids[$i]}" != hdr2023 ] && add "${ids[$i]}"
      done
      continue
    fi
    [[ "$n" =~ ^[1-9][0-9]?$ ]] && [ "$n" -le ${#ids[@]} ] || die "not an option: $n"
    i=$((n-1)); [ "${avail[$i]}" = 1 ] || die "${ids[$i]} is unavailable on this phone: ${why[$i]}"
    add "${ids[$i]}"
  done
  case " $picked " in *" india "*) picked=$(echo "$picked" | sed 's/ callrec//') ;; esac
  case " $picked " in *" wifi7 "*) case " $picked " in *" airdrop "*) ;; *) info "wifi7 runs on the AirDrop Wi-Fi driver, so airdrop is added too."; picked="airdrop $picked" ;; esac ;; esac
  picked=$(echo $picked)
fi
[ -n "$picked" ] || die "nothing picked"
say "Applying: $picked"
case " $picked " in *" airdrop "*) info "Wi-Fi (and the hotspot) drop for ~30 s while the driver is swapped." ;; esac
case " $picked " in *" callscreen "*) info "Call screening installs Samsung Language Core as an app update; unlike the rest, a reboot doesn't remove it." ;; esac
case " $picked " in *" airdrop "*|*" wifi7 "*|*" camerahdr "*|*" hdr2023 "*|*" audioeraser "*|*" colortone "*|*" galaxyai "*|*" settingssearch "*|*" callscreen "*) info "The phone downloads the files of the tweaks that need them from GitHub first (needs internet; Wi-Fi recommended)." ;; esac
info "The screen goes black for ~30 s while Android restarts its framework. Don't unplug the phone."
r=$(ask "Continue? [Y/n] "); [[ "$r" =~ ^[Nn] ]] && exit 0
r=$(ask "Re-apply these automatically at every boot, with no computer? [Y/n] "); [[ "$r" =~ ^[Nn] ]] && auto=off || auto=on

# ---- download ----
if [ $use_module = 0 ]; then
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
say "Downloading $VERSION..."
mkdir "$W/src"
if [ -n "${S23T_SRC:-}" ]; then cp -R "$S23T_SRC/device" "$W/src/"     # development: local checkout
else
  curl -fsSL "https://github.com/$REPO/archive/refs/tags/$VERSION.tar.gz" -o "$W/src.tar.gz"
  tar -xzf "$W/src.tar.gz" -C "$W/src" --strip-components=1
fi

# ---- push and run ----
say "Copying to the phone..."
a shell "su -c 'mkdir -p $PHONE_DIR'"
a push "$W/src/device/." /data/local/tmp/s23tweaks_new >/dev/null
a shell "su -c 'cp -r /data/local/tmp/s23tweaks_new/. $PHONE_DIR/ && rm -rf /data/local/tmp/s23tweaks_new && chmod 755 $PHONE_DIR/tweaks.sh'"
fi
# Tweaks with files (AirDrop, the S24 apps, Language Core): the phone downloads them from GitHub while
# applying. Development: S23T_PAYLOADS=<folder of release files> pushes local copies instead.
if [ -n "${S23T_PAYLOADS:-}" ]; then
  a shell "su -c 'mkdir -p $PHONE_DIR/dl'"
  for f in "$S23T_PAYLOADS"/*.tar*; do
    b=$(basename "$f"); case " $picked " in *" ${b%%-*} "*) ;; *) continue ;; esac
    a push "$f" /data/local/tmp/ >/dev/null && a shell "su -c 'mv /data/local/tmp/$(basename "$f") $PHONE_DIR/dl/'"
  done
fi
a shell "su -c 'sh $TW start \"$picked\"'" >/dev/null

say "Applying (2-3 minutes)..."
shown=0; end=$((SECONDS + 420)); case " $picked " in *" galaxyai "*|*" audioeraser "*|*" camerahdr "*|*" hdr2023 "*|*" settingssearch "*|*" airdrop "*) end=$((end + 900)) ;; esac   # downloads
case " $picked " in *" callscreen "*) end=$((end + 2700)) ;; esac   # 3.1 GB download + install
while [ $SECONDS -lt $end ]; do
  sleep 3
  out=$(a shell "su -c 'cat $PHONE_DIR/tweaks.log'" 2>/dev/null | tr -d '\r') || continue
  n=$(printf '%s\n' "$out" | grep -c . || true)
  [ "$n" -gt "$shown" ] && { printf '%s\n' "$out" | tail -n +$((shown+1)) | sed 's/^[0-9.]* /  /'; shown=$n; }
  case "$out" in *DONE*) break ;; *FAILED*) die "see the line above. Rebooting the phone undoes everything." ;; esac
done
case "${out:-}" in *DONE*) ;; *) die "timed out; check $PHONE_DIR/tweaks.log on the phone" ;; esac

say "Done."
a shell "su -c 'sh $TW autostart $auto'" | tr -d '\r' | sed 's/^/  /'
case " $picked " in *" airdrop "*)
  info "AirDrop: on the Apple device set AirDrop to 'Everyone for 10 minutes'. On the S23 share something with"
  info "Quick Share and pick 'Share with Apple devices'." ;; esac
case " $picked " in *" battery "*) info "Battery: Settings > Battery > Battery information." ;; esac
case " $picked " in *" wifi7 "*) info "Wi-Fi 7: multi-link works with Wi-Fi 7 routers that have MLO on. Settings > Wi-Fi > (network) shows Wi-Fi 7." ;; esac
case " $picked " in *" hdr2023 "*) info "2023 ArcSoft HDR: bracketed HDR is tested, hybrid HDR (ordinary daylight) isn't. Turn it off if photos look wrong." ;; esac
case " $picked " in *" camerahdr "*) info "Camera HDR: untested. Shoot a bright backlit scene and compare; turn it off if photos look worse." ;; esac
case " $picked " in *" audioeraser "*) info "Audio Eraser: Gallery > a video > Edit > speaker icon > Audio eraser." ;; esac
case " $picked " in *" colortone "*) info "Adaptive color tone: Settings > Display > Adaptive color tone." ;; esac
case " $picked " in *" galaxyai "*) info "Now Brief: turn on Settings > Galaxy AI > Personal data intelligence. Creative Studio is in the app drawer." ;; esac
case " $picked " in *" camextras "*) info "Camera extras: Camera > More > Director's view; Video > Super steady > Horizontal lock." ;; esac
case " $picked " in *" cam24fps "*) info "24 FPS in standard Video: Camera > Video > resolution/FPS > FHD / UHD / 8K at 24." ;; esac
case " $picked " in *" wideflash "*) info "Flash on ultrawide: Camera > Photo flash and Video torch on the 0.6x lens; Camera Assistant shows the wide-flash option." ;; esac
case " $picked " in *" prowbtint "*) info "White-balance tint: Camera > Pro or Pro video > white balance > Tint slider." ;; esac
case " $picked " in *" zoomrocker "*) info "Zoom rocker: the smooth zoom slider in Camera > Video." ;; esac
case " $picked " in *" videosoftening "*) info "Video softening: Camera > Settings > Camera Assistant > Video softening (Off / Medium / High)." ;; esac
case " $picked " in *" afcontrol "*) info "Autofocus controls: Camera > Settings > Camera Assistant > AF speed and AF sensitivity." ;; esac
case " $picked " in *" aelimit "*) info "Auto exposure limit: Camera > Settings > Camera Assistant > Auto exposure limit." ;; esac
case " $picked " in *" slowmoaf "*) info "Focus in Slow motion: Camera > Slow motion > tap the viewfinder while recording." ;; esac
case " $picked " in *" extstorage "*) info "USB-C storage: plug an exFAT USB-C SSD/drive; Camera > Settings > Storage > USB storage, then record in any mode." ;; esac
case " $picked " in *" anamorphic "*) info "Anamorphic desqueeze: Camera > Settings > Camera Assistant > anamorphic lens desqueeze (1.33x / 1.55x / 2.0x)." ;; esac
case " $picked " in *" profps "*) info "Pro video frame rates: Camera > More > Pro video; 4K 25/48/50/100/120 (120 on Wide and Ultrawide), FHD 25/48/50/100, 8K 25, 21:9 Cinema 25/48/50/100/120. The 10x works on S918BXXUAGZIF with the patched Camera APK; on other firmwares it stays hidden." ;; esac
case " $picked " in *" slowmo4k120 "*) info "4K120 in Slow motion: Camera > Slow motion > 4K120; turn on Log video for the Log profile." ;; esac
case " $picked " in *" dofadapter "*) info "DOF adapter: Camera > Settings > Camera Assistant > DOF adapter." ;; esac
case " $picked " in *" mirror8k "*) info "8K while mirroring: Camera > Settings > Camera Assistant > 8K recording while mirroring." ;; esac
case " $picked " in *" longrec "*) info "Long recording: the overheat recording limit and the low-power-mode delay are now 1 hour instead of 5 minutes." ;; esac
case " $picked " in *" settingssearch "*) info "Settings search: open Settings and tap the search bar." ;; esac
case " $picked " in *" callscreen "*) info "Call screening: Phone > Settings > Call screening. The AI summary shows an error on the S23; screening and voice messages work." ;; esac
case " $picked " in *" autoframe "*) info "4K auto framing was reported to make the camera fail (S918B); turn it off if the camera fails to open." ;; esac
case " $picked " in *" weather "*) info "Weather effect: Wallpaper and style > Lock screen > Weather > Done. It animates only for rain, snow, fog or daytime sun." ;; esac
case " $picked " in *" bargein "*) info "Bixby barge-in is untested; turn it off if anything misbehaves." ;; esac
case " $picked " in *" hotspot6g "*) info "6 GHz hotspot: Settings > Connections > Mobile Hotspot > Band > 6 GHz (security must be WPA3)." ;; esac
case " $picked " in *" dual5g "*) info "Dual SIM 5G: the modem restarts once (~15 s without signal). Original modem file: Download/s23tweaks-modem-backup. Undo: un-pick it and apply." ;; esac
case " $picked " in *" india "*) info "India config: the phone reports itself as the Indian model so Samsung Wallet India (UPI) and the 6 GHz hotspot work. If Samsung Wallet still says 'not supported', clear its storage (Settings > Apps > Samsung Wallet > Storage > Clear data) and reopen it." ;; esac
if [ "$auto" = on ]; then
  info "At each boot DFRoot roots the phone by itself and the tweaks re-apply about a minute later (the screen"
  info "goes black for ~30 s once). A notification says when they're on. To stop: run this again and answer n."
else
  info "All of this lasts until the next reboot. Run this again after a reboot (it offers your last picks)."
fi
}
main "$@"
