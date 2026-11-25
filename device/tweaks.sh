# s23-ultra-tweaks, phone side. Two ways it gets onto the phone:
#  - the KernelSU module: code in /data/adb/modules/s23_ultra_tweaks (this folder has module.prop)
#  - install.sh (adb): code in /data/adb/s23tweaks
# State (picks, logs, backups) always lives in /data/adb/s23tweaks, so module updates keep it.
# Everything runs as root. "start" runs "apply" detached in init's mount namespace, because the
# framework restart kills the caller (adb shell, KernelSU's WebUI):
#   su -c "sh <this folder>/tweaks.sh start 'airdrop battery'"
# Commands:
#   start "<tweaks>"  apply the listed tweaks in the background; follow tweaks.log in the state folder
#   apply "<tweaks>"  the same in the foreground (what start runs)
#   probe             one line of JSON: phone, which tweaks it can take and why not, what's active
#   status            print what is active
#   report            write a bug report (phone, tweaks, logs, crash summaries; no personal data) to Download
#   unflag            remove the Play services flag overrides that the airdrop tweak adds
#   autostart on|off  re-apply the saved tweaks at every boot. DFRoot roots the phone by itself at
#                     boot, then KernelSU runs the module's service.sh (module) or a script in
#                     /data/adb/service.d (install.sh). Both call "boot".
#   boot              (internal) the automatic apply at boot
#   wifi7page         open Samsung's hidden "Wi-Fi 7 mode" settings page (Wi-Fi Labs)
#   loop | guard      (internal) keep mosey_server running / reboot cleanly on a Wi-Fi firmware crash
# Tweaks: airdrop battery features callrec india hotspot6g wifi7 display logvideo vulkan
#         camerahdr hdr2023 audioeraser colortone galaxyai camextras autoframe settingssearch bargein
#         callscreen tenbit hideksu cam24fps weather wideflash
#         prowbtint zoomrocker videosoftening afcontrol aelimit slowmoaf extstorage
#         anamorphic profps slowmo4k120 dofadapter mirror8k longrec dual5g  (see README.md; the categories they're grouped in are in install.sh and the WebUI)
#
# Nothing here writes to a partition. Every change is a module load, an overlay, a bind mount or a
# runtime setting, so a reboot always returns the phone to stock. The files themselves stay on storage
# (/data/adb/s23tweaks), not in RAM: the kernel won't build an overlay from /data, so each overlay holds
# only empty placeholders in tmpfs and the real file is bind-mounted over its placeholder (pbind). The one exception is
# the airdrop tweak's Play services flag overrides, stored in Play services' own database
# (harmless without the rest; "unflag" removes them), camextras' camera app setting, callscreen,
# which installs Samsung Language Core as an ordinary app (undo: pm uninstall <package>), and weather,
# which installs a 12 KB AI Core stub app and turns Samsung's live wallpaper app back on if it was off.
# dual5g is the one change inside the modem: it edits one policy file in the modem's own storage (EFS),
# which stays across reboots and module removal until it's put back. The original is backed up before
# the first write (state folder and Download/s23tweaks-modem-backup); un-picking dual5g, removing the
# module, or "dual5g-restore" puts it back.
# Never touched: the sales code (mps_code.dat, sales_code.dat, omc.info, persist.sys.matched_code).
# Changing those can factory-reset the phone.

# KernelSU runs boot scripts in BusyBox standalone mode; make sure every tool here is Android's own
unset ASH_STANDALONE; export PATH=/system/bin:/system/xbin:/vendor/bin:$PATH
D=$(cd "$(dirname "$0")" && pwd)            # code: this script and files/
V=${S23T_STATE:-/data/adb/s23tweaks}         # state: choices, logs, backups, autostart flag
mkdir -p $V; L=$V/tweaks.log; R=$V/run
[ -f $D/module.prop ] && MODULE=1 || MODULE=0
APPLY_LOCK=/dev/s23tweaks_apply.lock         # /dev is tmpfs: locks never survive a reboot
STAYS_TILL_REBOOT="airdrop wifi7 battery india callrec vulkan audioeraser hdr2023 colortone tenbit galaxyai settingssearch hideksu cam24fps"
TWEAK_IDS="airdrop battery features callrec india hotspot6g wifi7 display logvideo vulkan camerahdr hdr2023 audioeraser colortone galaxyai camextras autoframe settingssearch bargein callscreen tenbit hideksu cam24fps weather wideflash prowbtint zoomrocker videosoftening afcontrol aelimit slowmoaf extstorage anamorphic profps slowmo4k120 dofadapter mirror8k longrec dual5g"
GMS_MIN=261125000                            # Play services 26.11, the first with Mosey support
# Firmware the AirDrop/Wi-Fi 7 kernel modules are checked against (one line each, read by customize.sh).
# All are One UI 9 build GZIF on GKI kernel 34343818, and their whole Wi-Fi stack (cnss2, mhi, cfg80211,
# mac80211, ipa) has the same code and symbol CRCs as S918WVLU8GZIF, which the modules are built on.
AIRDROP_KBASE=5.15.197-android13-8-34343818-ab
AIRDROP_FW="S918WVLU8GZIF S918BXXUAGZIF S918U1UEU8GZIF S918USQU8GZIF S918NKSU8GZIF"
kernel_stock() { for f in $AIRDROP_FW; do [ "$(uname -r)" = "$AIRDROP_KBASE$f" ] && return 0; done; return 1; }
# Opt-in for custom kernels (issue #10): with the file $V/allow-any-kernel, a 5.15 android13 kernel on one
# of the supported firmwares is let through. The kernel itself still refuses the modules if any symbol CRC
# differs (CONFIG_MODVERSIONS), and airdrop_kernel then puts the stock Wi-Fi driver back.
kernel_override() {
  [ -f $V/allow-any-kernel ] || return 1
  case "$(uname -r)" in 5.15.*-android13-*) ;; *) return 1 ;; esac
  case " $AIRDROP_FW " in *" $(getprop ro.build.PDA) "*) return 0 ;; esac; return 1
}
kernel_supported() { kernel_stock || kernel_override; }
# A custom kernel that ships its own Wi-Fi stack (cfg80211.ko built for that kernel, not the stock GKI one)
# lays out cfg80211's structures differently. The S24 driver's modules still load, but wiphy_new/
# wiphy_register reject it (WARNs at core.c:431/772, err -5) and the phone froze during the driver swap
# (issue #21). The stock module's vermagic names the GKI build the airdrop modules are made for.
CFG80211_KO=/vendor_dlkm/lib/modules/cfg80211.ko
cfg80211_vermagic() { grep -a -o -m1 'vermagic=[^ ]*' $CFG80211_KO 2>/dev/null | head -n 1 | cut -d= -f2; }
cfg80211_stock() { case "$(cfg80211_vermagic)" in "$AIRDROP_KBASE"*) return 0 ;; esac; return 1; }
STOCK_KO=/vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko
FF=/system/etc/floating_feature.xml
CF=/system/cameradata/camera-feature.xml
# Files made on the phone (edited configs) that binds point at, on storage: one folder per boot, since a
# boot's mounts keep using its files. ly_init deletes the earlier boots' folders the first time in a boot.
LY=$V/layers/$(cat /proc/sys/kernel/random/boot_id)
ly_init() { [ -d $LY ] || { rm -rf $V/layers; mkdir -p $LY; }; }
PL=$V/payload; T24=/dev/s23tweaks_layers    # per-tweak downloads (unpacked in payload/<tweak>/); tmpfs for the layers' placeholders
# pbind <file on storage> <target> <SELinux type> [exec]: bind a downloaded file over a path (over its
# placeholder, for a file an overlay adds). A bind keeps /data's nosuid, which would stop a program
# from entering its own SELinux domain, so for programs BusyBox clears it (toybox mount can't).
pbind() {
  if [ -n "$4" ]; then chmod 755 "$1"; else chmod 644 "$1"; fi; chcon u:object_r:$3:s0 "$1"
  mount -o bind,ro "$1" "$2" || fail "bind $2"
  [ -n "$4" ] || return 0
  for bb in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox; do [ -x $bb ] && { $bb mount -o remount,bind,ro,suid "$2"; break; }; done
  grep " $2 " /proc/mounts | grep -q nosuid && { umount "$2"; fail "couldn't clear nosuid on $2"; }
  return 0
}
AIR=$PL/airdrop                              # the airdrop/wifi7 download: kernel modules, firmware, Mosey, tools
# The module zip holds only scripts. Every tweak that needs files downloads them from the GitHub release
# $PAYLOAD_URL when it's picked: tweak, file, SHA-256. A tweak with several lines is one tar split into
# parts (GitHub caps a file at 2 GB), joined on the phone. A copy in $V/dl/ (the installer can push one)
# is used first. "tweak:md5" lines are per stock file: only the one whose md5 matches this phone's is
# fetched (hideksu: one patched services.jar per stock services.jar, see hks_row).
PAYLOAD_URL=https://github.com/dtechterminal/s23-ultra-tweaks/releases/download/payloads-S918WVLU8GZIF
PAYLOADS="airdrop airdrop-S918WVLU8GZIF-2.tar.gz deed1ee54334dbbf6086d2aa0d194183006826913a662900377f3760d7966e1c
logvideo logvideo-luts.tar.gz ed688855d75d9ff964a2f9f904cb7189b6adb897940fb61fe3a4c8049c73ecbe
hideksu:30d17f5d60b0d42585b97a94412f6e12 hideksu-S918WVLU8GZIF.tar.gz 4732e4568d08254b80b60bbeeb1d03673dd259049303e5c43dcda6fe960fa647
hideksu:7dc62286f9f0675f84459943cdc397b6 hideksu-7dc62286.tar.gz 38d5719706ec67331fb9199b0934e9551ac814f5d2970c1cbfc3099dd286d4e2
hideksu:c438dd27a76486855d01e74379e13b5d hideksu-c438dd27.tar.gz 0b3f9991d5cb3e46cd8953d8d4e776005ff1a61b30f222aeb6af9ad919745dbf
camerahdr camerahdr-S918WVLU8GZIF.tar.gz ed4d9be902918d1d014b91d3fd53cec42512f58744a398ec4e0888be04116bcc
hdr2023 hdr2023-S918WVLU8GZIF.tar.gz 0f31937af2f04e2edcf1a2319298dfb97e3493aea558be6f3e0070fdb9b37eba
audioeraser audioeraser-S918WVLU8GZIF.tar.gz a11d2868b3d8ba0121554ea2a31bb65256e0c141c6033c4e6ddb4770f4d11704
colortone colortone-S918WVLU8GZIF.tar.gz 4be28f16e3631f1e377ecec9ad2b5b78d1abf8c6a9b971435c7ac12604f75e40
galaxyai galaxyai-S918WVLU8GZIF.tar.gz 5619aaee7580b985df300dcfca1fadc56bc774f60ebb2af9db975876dfe01c0e
settingssearch settingssearch-S918WVLU8GZIF.tar.gz bddfa32a08def256b7497730a0e7faecf7b1621655ce0cc85bec423843357042
callscreen callscreen-S918WVLU8GZIF.tar.partaa 6a8d141557050e738b3a805d741463aae46b9322732bdd3039d836c0d116af9a
callscreen callscreen-S918WVLU8GZIF.tar.partab 3335ea84794746040513e4297175736d792a19f378187d7b970c4058bc421025"
SETTINGS=/system/priv-app/SecSettings/SecSettings.apk
# colortone: firmware, md5 of its SecSettings.apk, md5 with files/SecSettings-ead-<firmware>.patch applied
# (tools/eadpatch.py makes the patch and prints both for another firmware's APK)
SETTINGS_EAD="S918WVLU8GZIF 5b8afa24f17e090d57380b8ebbd3dcee f499f2e574a47eca0414f470e1ae20e8
S918BXXUAGZIF 5b20b1a68f94d01bba5a776e15ffdc30 de6d142d238849198810dfe70fada8dd"
ead_row() { echo "$SETTINGS_EAD" | awk -v b="$(getprop ro.build.PDA)" '$1 == b'; }
ead_builds() { echo "$SETTINGS_EAD" | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//; s/ / or /g'; }
CAM_APK=/system/priv-app/SamsungCamera/SamsungCamera.apk
# cam24fps, keyed on the Camera APK itself, not the firmware: md5 of a stock SamsungCamera.apk, md5 once
# patched, the patch in files/, and the firmware it came from. Any firmware whose stock Camera APK is listed
# works; tools/cam24patch.py makes the patch and prints both md5s for another APK.
CAMERA_24FPS="174e38e111f53c92eea54fd8b9a8c1c6 b22942b22ec14896bc02277d319b7623 SamsungCamera-24fps-S918BXXUAGZIF.patch S918BXXUAGZIF
e7c89df10d6607ea1ddeedceee961903 650dc854741a92f54be455fc19cd4c89 SamsungCamera-24fps-17.0.00.43.patch S918WVLU8GZIF"
# the row for the Camera APK in place now (stock, or our patched copy bound over it)
cam24_row() { m=$(md5sum $CAM_APK 2>/dev/null | cut -d' ' -f1); echo "$CAMERA_24FPS" | awk -v m="$m" '$1 == m || $2 == m'; }
# the bound Camera APK is one whose patch also unhides the 10x (the patch header says so)
cam24_profps_on() { bound $CAM_APK || return 1; set -- $(cam24_row); [ -n "$1" ] && grep -q BACK_SECOND_TELE $D/files/$3 2>/dev/null; }
cam24_builds() { echo "$CAMERA_24FPS" | awk '{print $4}' | tr '\n' ' ' | sed 's/ $//; s/ / or /g'; }
# Carrier config (callrec, india), on any sales code. SemCscFeature reads <mdc.system.path>/cscfeature.xml
# (on multi-country firmware also that file's FeatureSet for the CSC country); customer_carrier_feature.json
# sits next to it, customer.xml one folder up, and the prism folder (keystrings, regulatory images) mirrors
# the optics path. Stock files are OMC-encoded; files/omcdec (src/omcdec) prints them as plain XML, which
# the parser also accepts.
csc_paths() {
  SC=$(getprop ro.csc.sales_code); CSYS=$(getprop mdc.system.path)
  CSCF=$CSYS/cscfeature.xml; CCF=$CSYS/customer_carrier_feature.json; CUST=${CSYS%/system}/customer.xml
  case "$CSYS" in /optics/configs/carriers/*/conf/system) _p=${CSYS%/conf/system}; PRISM=/prism/etc/carriers/${_p#/optics/configs/carriers/} ;; *) PRISM="" ;; esac
}
csc_paths
OMCDEC=$D/files/omcdec
# india also makes the phone report itself as the Indian S23 Ultra (SM-S918B / INS / country IN), so
# Samsung Wallet's India features (UPI, DigiLocker, transit) and the 6 GHz hotspot work. These are runtime
# resetprop overrides: they revert on reboot and never write the CSC partition files (mps_code.dat,
# sales_code.dat, omc.info), so there is no factory-reset risk. The reported model changes for every app
# while it's on, and adding bank payment cards may still fail (that path checks the real model by hardware).
IN_MODEL=SM-S918B
IN_MODEL_PROPS="ro.product.model ro.product.vendor.model ro.product.system.model ro.product.odm.model ro.product.product.model ro.product.system_ext.model ro.product.bootimage.model ro.product.system_dlkm.model ro.product.vendor_dlkm.model ro.boot.em.model"
IN_SALES_PROPS="ro.csc.sales_code ro.boot.sales_code persist.audio.sales_code ril.sales_code"
NEARBY_FLAGS="45704091 45723015 sharing_package_whitelist_check_bypass"   # Nearby Sharing: enableExternalProviders + provider-registry gate + GMS 26.46+ source-stamp bypass

HIST=/dev/s23tweaks.history   # every apply's lines since boot (tweaks.log holds only the last apply)
log() { m="$(cut -d' ' -f1 /proc/uptime) $*"; echo "$m" >> $L; echo "$m" >> $HIST 2>/dev/null; echo "s23tweaks: $*" > /dev/kmsg; sync; }
fail() { log "FAILED: $*"; exit 1; }
wait_for() { n=$1; shift; while [ $n -gt 0 ]; do "$@" && return 0; n=$((n-1)); sleep 1; done; return 1; }
mounted() { mount | grep -q " $1 type $2"; }
bound() { mount | grep -q " $1 "; }
running() { ps -A -o ARGS | grep -q "[t]weaks.sh $1"; }
has() { case " $TWEAKS " in *" $1 "*) return 0 ;; esac; return 1; }
md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
# The apply lock is a directory holding the owner's pid. A lock whose owner is gone (killed apply)
# counts as free, so a crash can't block every later apply until the next reboot.
lock_alive() { lp=$(cat $APPLY_LOCK/pid 2>/dev/null); [ -n "$lp" ] && kill -0 "$lp" 2>/dev/null; }
take_lock() {
  if ! mkdir $APPLY_LOCK 2>/dev/null; then
    lock_alive && return 1
    rm -rf $APPLY_LOCK; mkdir $APPLY_LOCK 2>/dev/null || return 1
  fi
  echo $$ > $APPLY_LOCK/pid
}
# Started from KernelSU's app (module page, action button), this shell sits in that app's cgroup
# (/apps/uid_N/pid_M). Android freezes or kills that whole group when the app is cached or dies,
# which the framework restart in apply guarantees. Move to the root cgroup first; children follow.
to_root_cgroup() { echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null; }

# kallsyms address of a symbol in a module (kptr_restrict is lowered only for the read)
ksym() {
  o=$(cat /proc/sys/kernel/kptr_restrict); echo 1 > /proc/sys/kernel/kptr_restrict
  # lines are "<address> <type> <name>\t[<module>]": match the name and module fields exactly. A kernel
  # built with ThinLTO may rename a static symbol to "<name>.llvm.<hash>" (issue #10): take that too.
  a=$(awk -v s="$1" -v m="[$2]" '($3 == s || index($3, s ".llvm.") == 1) && $4 == m {print $1; exit}' /proc/kallsyms)
  echo $o > /proc/sys/kernel/kptr_restrict
  [ -n "$a" ] && [ "$a" != 0000000000000000 ] && echo $a
}
# ksect <module> <section>: a module section's address (hidden, like kallsyms, unless kptr_restrict <= 1)
ksect() {
  o=$(cat /proc/sys/kernel/kptr_restrict); echo 1 > /proc/sys/kernel/kptr_restrict
  a=$(cat /sys/module/$1/sections/$2 2>/dev/null)
  echo $o > /proc/sys/kernel/kptr_restrict
  [ -n "$a" ] && [ "$a" != 0x0000000000000000 ] && echo $a
}

# ---------- airdrop: kernel side ----------
wlan_up() { [ -e /sys/class/net/wlan0 ] && [ $(( $(cat /sys/class/net/wlan0/flags) & 1 )) = 1 ]; }
hal_stopped() { [ "$(getprop init.svc.vendor.wifi_hal_legacy)" = stopped ]; }
hostapd_stopped() { [ "$(getprop init.svc.hostapd)" != running ]; }
wifi_off() { cmd wifi status | grep -q "Wifi is disabled"; }
sup_stopped() { [ "$(getprop init.svc.wpa_supplicant)" != running ]; }
wifi_down() {
  # Samsung turns Wi-Fi back on by itself right after a hotspot stops, so stop the hotspot first,
  # let that settle, and make sure Wi-Fi stays off before the driver is unloaded.
  if [ "$(getprop init.svc.hostapd)" = running ]; then
    cmd wifi stop-softap >/dev/null 2>&1; wait_for 15 hostapd_stopped || log "hotspot did not stop"; sleep 5
  fi
  cmd wifi set-scan-always-available disabled
  for i in 1 2 3; do cmd wifi set-wifi-enabled disabled; wait_for 10 wifi_off && sleep 4 && wifi_off && break; done
  wifi_off || { cmd wifi set-wifi-enabled enabled; cmd wifi set-scan-always-available enabled; fail "Wi-Fi keeps turning itself back on"; }
  wait_for 20 sup_stopped || log "wpa_supplicant still running after Wi-Fi off"
  [ -d /sys/module/wonder ] && { rmmod wonder || log "could not unload wonder"; }
  stop wpa_supplicant; stop vendor.wifi_hal_legacy; stop vendor.wifi_hal_ext
  wait_for 20 hal_stopped || log "Wi-Fi HAL did not stop"
  rmmod kiwi_v2 || { wifi_up; fail "could not unload the stock Wi-Fi driver"; }
}
wifi_up() {
  start vendor.wifi_hal_ext; start vendor.wifi_hal_legacy; start wpa_supplicant
  cmd wifi set-wifi-enabled enabled
  wait_for 45 wlan_up && log "Wi-Fi back on" || log "Wi-Fi did not come back by itself"
  cmd wifi set-scan-always-available enabled
}
back_to_stock() {   # the firmware binds sit on the overlay, so they come off first
  for m in $(awk '$2 ~ "^/vendor/firmware/kiwi/" {print $2}' /proc/mounts); do umount $m; done
  mounted /vendor/firmware/kiwi overlay && umount /vendor/firmware/kiwi; insmod $STOCK_KO; wifi_up
}

# wonder's ieee80211_register_hw needs large contiguous allocations (mac80211's per-flow tables).
# After many hours up, memory can be too fragmented and the kernel's own compaction gives up: insmod
# fails with "Failed to register mac80211 hardware. Ret: -12" (issue #7). Then compact all memory and retry.
wonder_load() {
  for i in 1 2 3; do
    insmod $AIR/wonder.ko 2>/dev/null && return 0
    dmesg | tail -n 60 | grep -q 'mac80211 hardware. Ret: -12' || break
    log "airdrop: not enough contiguous memory for wonder (try $i of 3); compacting memory and retrying"
    sync; echo 1 > /proc/sys/vm/drop_caches; echo 1 > /proc/sys/vm/compact_memory; sleep 2
  done
  fail "wonder: $(dmesg | grep -E 'wonder|page allocation failure' | tail -n 3 | tr '\n' ' ')"
}

airdrop_kernel() {
  A=$AIR
  if [ -d /sys/module/wonder ] && [ -d /sys/module/bwfix ]; then log "airdrop: kernel side already loaded"; AK_LOADED=1; return 0; fi
  # An earlier apply in this boot swapped in the S24 driver but wonder didn't load: load just wonder
  if [ -d /sys/module/bwfix ] && [ -d /sys/module/kiwi_v2 ] && mounted /vendor/firmware/kiwi overlay; then
    log "airdrop: S24 Wi-Fi driver already in; loading wonder"
    wonder_load; log "airdrop: kernel side loaded"; return 0
  fi
  kernel_stock || log "airdrop: kernel $(uname -r) isn't Samsung's; trying anyway ($V/allow-any-kernel). If the kernel refuses the modules, the stock Wi-Fi driver goes back"
  log "airdrop: swapping in the S24 Wi-Fi driver and firmware (Wi-Fi drops for ~30 s)"
  wifi_down
  # cnss2/MHI keep buffers sized for the boot-time firmware; mhifix frees them so the bigger S24
  # firmware gets correctly sized ones. It needs the address of cnss2's static plat_env pointer.
  pe=$(ksym plat_env cnss2) || { back_to_stock; fail "plat_env not found in kallsyms"; }
  b=$(ksect cnss2 .bss) || { back_to_stock; fail "cnss2 .bss address not readable"; }; d=$(( 0x$pe - b ))
  [ $d -ge 0 ] && [ $d -lt 1048576 ] || { back_to_stock; fail "plat_env 0x$pe is not in cnss2 .bss"; }
  insmod $A/mhifix.ko mode=1 plat_env=0x$pe; r=$(dmesg | grep mhifix | tail -4 | tr '\n' ' ')
  case "$r" in *"tables freed"*"fw_mem DDR freed"*) ;; *) back_to_stock; fail "mhifix: $r" ;; esac
  # S24 firmware over /vendor/firmware/kiwi: an overlay of placeholders, each bound to the downloaded file
  # (the S23 board file stays)
  T=/dev/s23tweaks_fw; FW="amss20.bin phy_ucode20.elf regdb.bin"
  mkdir -p $T; mounted $T tmpfs || mount -t tmpfs -o mode=755 s23tweaks_fw $T
  for f in $FW; do : > $T/$f; done; chmod 644 $T/*; chcon u:object_r:vendor_firmware_file:s0 $T $T/*
  mount -t overlay s23tweaks_fwov -o ro,lowerdir=$T:/vendor/firmware/kiwi /vendor/firmware/kiwi || { back_to_stock; fail "firmware overlay"; }
  for f in $FW; do chmod 644 $A/fw/$f; chcon u:object_r:vendor_firmware_file:s0 $A/fw/$f
    mount -o bind,ro $A/fw/$f /vendor/firmware/kiwi/$f || { back_to_stock; fail "firmware bind $f"; }; done
  insmod $A/kiwi_v2.ko || { back_to_stock; fail "S24 Wi-Fi driver: $(dmesg | tail -2 | tr '\n' ' ')"; }
  wifi_up; sleep 5
  # Some custom kernels bring the S24 driver up fine alone but not with wifi7's MLO config and S24
  # supplicant (issue #21): drop wifi7 for this boot and retry, so AirDrop still works
  if ! wlan_up && { bound $INI || bound $WPAS; }; then
    log "airdrop: Wi-Fi didn't come up with the wifi7 settings; retrying without them (wifi7 off until a reboot)"
    wifi_down; wifi7_drop
    insmod $A/kiwi_v2.ko || { back_to_stock; fail "S24 Wi-Fi driver: $(dmesg | tail -2 | tr '\n' ' ')"; }
    wifi_up; sleep 5
  fi
  # bwfix: the S24 firmware asks for a PCIe Gen3 link when AirDrop starts; the S23 refuses (Gen2
  # max) and the firmware crashes on the refusal. bwfix sets Gen2 and acknowledges.
  cb=$(ksym cnss_mhi_bw_scale.cfi_jt cnss2)
  [ -d /sys/module/bwfix ] || insmod $A/bwfix.ko ${cb:+orig=0x$cb} || fail "bwfix: $(dmesg | tail -2 | tr '\n' ' ')"
  wonder_load
  log "airdrop: kernel side loaded ($(dmesg | grep -o 'wonder: connected to wlan.*' | tail -1))"
}

# ---------- wifi7: Wi-Fi 7 multi-link (MLO) as a Wi-Fi client ----------
# The S24 driver (airdrop) has MLO built in, but the S23's wpa_supplicant has no 802.11be/MLO code
# and the S23's driver config doesn't turn MLO on. Use the S24's wpa_supplicant (same Samsung HAL
# extensions; it needs one AIDL library the S23 vendor image lacks, added to /vendor/lib64 with a
# read-only RAM overlay) and the S23's own driver config plus the S24's four MLO lines.
W7=$LY/mlo; INI=/vendor/etc/wifi/kiwi_v2/WCNSS_qcom_cfg.ini; WPAS=/vendor/bin/hw/wpa_supplicant
MLO_INI="mlo_support_link_num=2 mlo_5gl_5gh_mlsr=1 oem_eht_mlo_crypto_bitmap=0 epcs_support_enable=1"
W7_FAIL=/dev/s23tweaks_w7fail   # set by wifi7_drop: Wi-Fi didn't come up with wifi7 this boot
wifi7_bind() {   # sets W7_INI_NEW=1 when the driver has to be reloaded to read the config
  A=$AIR/wifi7
  [ -e $W7_FAIL ] && { log "wifi7: skipped: Wi-Fi didn't come up with it earlier in this boot (custom kernel?); a reboot retries it"; W7_OFF=1; return 0; }
  ly_init; mkdir -p $W7
  if ! bound $WPAS; then
    pbind $A/wpa_supplicant $WPAS hal_wifi_supplicant_default_exec exec
  fi
  if ! mounted /vendor/lib64 overlay; then
    WL=/dev/s23tweaks_mlolib; SO=android.hardware.wifi.supplicant-V2-ndk.so
    mkdir -p $WL; mounted $WL tmpfs || mount -t tmpfs -o mode=755 s23tweaks_mlolib $WL
    : > $WL/$SO; chmod 644 $WL/$SO; chcon u:object_r:vendor_file:s0 $WL $WL/$SO
    mount -t overlay s23tweaks_mlolib -o ro,lowerdir=$WL:/vendor/lib64 /vendor/lib64 || { umount $WPAS; fail "wifi7: library overlay"; }
    pbind $A/$SO /vendor/lib64/$SO vendor_file
  fi
  if ! bound $INI; then
    lab=$(ls -Z $INI | cut -d' ' -f1); cp $INI $W7/ini
    for kv in $MLO_INI; do grep -q "^${kv%%=*}=" $W7/ini || sed -i "/^END$/i $kv" $W7/ini; done
    grep -q "^mlo_support_link_num=" $W7/ini || fail "wifi7: no END marker in $INI"
    chmod 644 $W7/ini; chcon $lab $W7/ini; mount --bind $W7/ini $INI || fail "wifi7: bind driver config"
    W7_INI_NEW=1
  fi
  log "wifi7: S24 wpa_supplicant and MLO driver settings in place"
}
wifi7_unbind_sup() { bound $WPAS && umount $WPAS; mounted /vendor/lib64 overlay && umount /vendor/lib64; }
wifi7_drop() {   # undo wifi7's binds, with the supplicant stopped and the driver unloaded
  bound $INI && umount $INI; wifi7_unbind_sup; : > $W7_FAIL; W7_OFF=1; W7_INI_NEW=0
}
wifi7_reload() {   # the AirDrop driver was already loaded before the config was bound
  log "wifi7: reloading the Wi-Fi driver so it reads the MLO settings (Wi-Fi drops for ~15 s)"
  wifi_down
  insmod $AIR/kiwi_v2.ko || { back_to_stock; fail "wifi7: kiwi_v2 reload: $(dmesg | tail -2 | tr '\n' ' ')"; }
  wifi_up
  wonder_load
}
wifi7_check() {
  # If Wi-Fi can't run with the S24 supplicant, go back to the S23's and carry on without MLO
  wait_for 60 wlan_up; wait_for 90 connected
  if [ "$(getprop init.svc.wpa_supplicant)" = running ] && cmd wifi status | grep -q "Wifi is enabled" &&
     [ "$(md5 /proc/$(pidof wpa_supplicant)/exe)" = "$(md5 $AIR/wifi7/wpa_supplicant)" ]; then
    log "wifi7: Wi-Fi running with the S24 supplicant ($(cmd wifi status | grep -oE 'Wi-Fi standard: [^,]*' | head -1))"
  else
    log "wifi7: warning: Wi-Fi didn't come up with the S24 supplicant; switching back to the S23 one (no MLO)"
    cmd wifi set-wifi-enabled disabled; wait_for 15 wifi_off; wait_for 20 sup_stopped; wifi7_unbind_sup
    cmd wifi set-wifi-enabled enabled; wait_for 60 wlan_up
  fi
}
connected() { cmd wifi status | grep -q "Supplicant state: COMPLETED"; }

# ---------- airdrop: Mosey (Google's AirDrop stack from the S24) ----------
airdrop_overlays() {
  bound /system_ext/bin && { log "airdrop: Mosey already in /system_ext"; return 1; }
  M=$AIR/mosey; T=/dev/s23tweaks_mosey
  mkdir -p $T; mounted $T tmpfs || mount -t tmpfs -o mode=755 s23tweaks_mosey $T
  mkdir -p $T/bin $T/lib64 $T/priv-app/MoseyApp $T/perm $T/sysconfig $T/vintf
  # the three big files are placeholders here, bound to the download below; the XMLs are a few KB
  : > $T/bin/mosey_server; : > $T/lib64/libmosey_daemon_ffi.so; : > $T/priv-app/MoseyApp/MoseyApp.apk
  cp $M/privapp-permissions-com.google.android.mosey.xml $T/perm/
  cp $M/preinstalled-packages-com.google.android.mosey.xml $M/hiddenapi-allowlist-mosey.xml $T/sysconfig/
  cp $M/manifest_mosey.xml $T/vintf/
  chmod -R 755 $T; find $T -type f -exec chmod 644 {} +; chmod 755 $T/bin/mosey_server
  chcon -R u:object_r:system_file:s0 $T
  chcon u:object_r:system_lib_file:s0 $T/lib64 $T/lib64/libmosey_daemon_ffi.so
  chcon u:object_r:mosey_server_exec:s0 $T/bin/mosey_server
  for p in "bin /system_ext/bin" "lib64 /system_ext/lib64" "priv-app /system_ext/priv-app" \
           "perm /system_ext/etc/permissions" "sysconfig /system_ext/etc/sysconfig" "vintf /system_ext/etc/vintf/manifest"; do
    set -- $p
    mount -t overlay s23tweaks_$1 -o ro,lowerdir=$T/$1:$2 $2 || fail "overlay on $2"
  done
  pbind $M/mosey_server /system_ext/bin/mosey_server mosey_server_exec exec
  pbind $M/libmosey_daemon_ffi.so /system_ext/lib64/libmosey_daemon_ffi.so system_lib_file
  pbind $M/MoseyApp.apk /system_ext/priv-app/MoseyApp/MoseyApp.apk system_file
  log "airdrop: Mosey added to /system_ext (overlay)"
}

airdrop_post() {
  # On the S24 a default-permissions file pre-grants these; Quick Share only starts Mosey when
  # every dangerous permission Mosey asks for is granted.
  for p in BLUETOOTH_SCAN BLUETOOTH_ADVERTISE NEARBY_WIFI_DEVICES ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION \
           ACCESS_BACKGROUND_LOCATION ACCESS_MEDIA_LOCATION ACCESS_LOCAL_NETWORK READ_MEDIA_VISUAL_USER_SELECTED; do
    pm grant --user 0 com.google.android.mosey android.permission.$p 2>/dev/null
  done
  den=$(dumpsys package com.google.android.mosey | sed -n '/User 0:/,/User [1-9]/p' | grep -c granted=false)
  [ "$den" = 0 ] || log "airdrop: warning: $den Mosey permissions are still denied"
  # libvintf caches the VINTF manifests keyed on this file's mtime; touching it makes servicemanager
  # pick up manifest_mosey.xml (IMoseyService/default). Never restart servicemanager itself: Android
  # then reboots with "checkpoint_commit_failed".
  touch /apex/apex-info-list.xml
  running loop || setsid sh $D/tweaks.sh loop </dev/null >/dev/null 2>&1 &
  running guard || setsid sh $D/tweaks.sh guard </dev/null >/dev/null 2>&1 &
  n=20; until service check com.google.android.moseyservice.IMoseyService/default | grep -q found; do
    n=$((n-1)); [ $n = 0 ] && fail "IMoseyService did not register"; sleep 1; done
  log "airdrop: mosey_server running"
  # Mosey 1.0.980159239 and later check for IMoseyService once, at boot, and disable their own
  # ExternalSharingService when it isn't there, which it never is yet: mosey_server only starts here.
  # Play services then finds no AirDrop provider. Enable it again now that the service is registered.
  pm enable --user 0 com.google.android.mosey/.ExternalSharingService >/dev/null 2>&1 &&
    log "airdrop: Mosey's sharing service enabled" || log "airdrop: warning: could not enable Mosey's sharing service"
  gms_flags
}

# Play services only binds Mosey when server-side Nearby flags are on. Add them as local
# overrides (account 0 = the device) and patch the current flag snapshot so they apply right away.
gms_flags() {
  G=/data/data/com.google.android.gms; DB=$G/databases/phenotype.db
  SNAP=$G/files/phenotype/shared/com.google.android.gms.nearby.pb
  SQ=$AIR/sqlite3; W=$R/gms; rm -rf $W; mkdir -p $W $V/backup
  if [ ! -f $DB ]; then
    # Before the first unlock after a boot, app storage is still encrypted. The overrides set on an
    # earlier run are stored in Play services' database and stay in effect, so nothing is lost.
    if [ "${S23T_BOOT:-0}" = 1 ]; then log "airdrop: Play services storage is locked until first unlock; flags from the earlier run stay on"
    else log "airdrop: Play services database not found; flags not set"; fi
    return
  fi
  # edit a copy (opening the live WAL database as root would leave root-owned -wal/-shm files)
  am force-stop com.google.android.gms
  cp $DB $W/p.db; [ -f $DB-wal ] && cp $DB-wal $W/p.db-wal
  [ -f $V/backup/phenotype.db ] || cp $W/p.db* $V/backup/ 2>/dev/null
  id=$($SQ $W/p.db "select config_package_id from config_packages where name='com.google.android.gms.nearby'")
  [ -n "$id" ] || { log "airdrop: Play services has no Nearby config yet; open Quick Share once and run again"; return; }
  in_list=""; total=0; sql="PRAGMA integrity_check;"
  for f in $NEARBY_FLAGS; do
    in_list="${in_list:+$in_list, }'$f'"
    total=$((total + 1))
    sql="$sql INSERT OR IGNORE INTO flag_overrides (config_package_id, account_id, name, value, type, source) VALUES ($id, 0, '$f', 1, 2, 0);"
  done
  sql="$sql INSERT OR IGNORE INTO experiment_states_to_overrides (experiment_state_id, override_id)
    SELECT s.experiment_state_id, o.override_id FROM experiment_states s, flag_overrides o
    WHERE s.config_package_id=$id AND o.config_package_id=$id AND o.name IN ($in_list);
    PRAGMA wal_checkpoint(TRUNCATE);"
  ok=$($SQ $W/p.db "$sql" | head -1)
  [ "$ok" = ok ] || { log "airdrop: Play services database check failed ($ok); flags not set"; return; }
  n=$($SQ $W/p.db "select count(*) from flag_overrides where config_package_id=$id and name in ($in_list) and value=1")
  am force-stop com.google.android.gms
  cat $W/p.db > $DB && rm -f $DB-wal $DB-shm    # cat keeps the file's owner and SELinux label
  if [ -f $SNAP ]; then
    cp $SNAP $W/s.pb; pb_ok=1
    for f in $NEARBY_FLAGS; do
      if $AIR/pbflag $W/s.pb $W/s.next "$f" 1 >/dev/null 2>&1; then
        mv $W/s.next $W/s.pb
      else
        # Fallback for pre-existing airdrop tarballs whose pbflag binary only accepts numeric names:
        # append a valid protobuf field-5 boolean entry if the string flag isn't already in the snapshot.
        case "$f" in
          *[!0-9]*)
            if ! grep -Fq "$f" $W/s.pb; then
              nl=${#f}; el=$((nl + 4))
              if [ $nl -lt 128 ] && [ $el -lt 128 ]; then
                printf "\\$(printf '%03o' 42)\\$(printf '%03o' $el)\\$(printf '%03o' 10)\\$(printf '%03o' $nl)%s\\030\\001" "$f" >> $W/s.pb
              else
                pb_ok=0; break
              fi
            fi ;;
          *) pb_ok=0; break ;;
        esac
      fi
    done
    [ $pb_ok = 1 ] && cat $W/s.pb > $SNAP
  fi
  rm -rf $W
  log "airdrop: Play services Nearby flags on ($n of $total overrides present)"
}

# ---------- Samsung feature flags (battery, features, display, logvideo) ----------
# ff_tags: tags turned on (TRUE), added if the stock file lacks them or set TRUE if it has them as FALSE.
# ff_set TAG VALUE: set a tag to a value, replacing the stock one (values may contain spaces).
ff_tags=""; ff_kv=""
ff_set() { case "$2" in *'&'*|*'
'*) fail "ff_set $1: value has & or a newline" ;; esac; ff_kv="$ff_kv$1=$2
"; }
ff_apply() {
  [ -z "$ff_tags" ] && [ -z "$ff_kv" ] && return 1
  mkdir -p $R; bound $FF && umount $FF       # rebuild from the stock file each time
  for t in $ff_tags; do grep -q "<SEC_FLOATING_FEATURE_$t>TRUE<" $FF || ff_set $t TRUE; done
  printf '%s' "$ff_kv" > $R/ff.kv
  o=$(for k in $(cut -d= -f1 $R/ff.kv); do grep -m1 -o "<SEC_FLOATING_FEATURE_$k>[^<]*" $FF | sed 's/<SEC_FLOATING_FEATURE_//; s/>/=/'; done | tr '\n' ' ')
  [ -n "$o" ] && log "feature flags: stock values $o"
  # replace the values of tags the file has; add the rest before the closing tag
  awk -v kvf=$R/ff.kv '
    BEGIN { while ((getline l < kvf) > 0) { i = index(l, "="); k = substr(l, 1, i - 1); val[k] = substr(l, i + 1); ord[++n] = k } }
    match($0, /<SEC_FLOATING_FEATURE_[A-Z0-9_]+>/) { k = substr($0, RSTART + 22, RLENGTH - 23)
      if (k in val) { $0 = substr($0, 1, RSTART + RLENGTH - 1) val[k] "</SEC_FLOATING_FEATURE_" k ">"; seen[k] = 1 } }
    /<\/SecFloatingFeatureSet>/ { for (i = 1; i <= n; i++) if (!(ord[i] in seen))
      print "    <SEC_FLOATING_FEATURE_" ord[i] ">" val[ord[i]] "</SEC_FLOATING_FEATURE_" ord[i] ">" }
    { print }' $FF > $R/ff.new
  grep -q '</SecFloatingFeatureSet>' $R/ff.new || fail "floating_feature edit"
  mv $R/ff.new $R/floating_feature.xml; chmod 644 $R/floating_feature.xml
  chcon u:object_r:system_file:s0 $R/floating_feature.xml
  mount --bind $R/floating_feature.xml $FF || fail "floating_feature bind mount"
  log "feature flags on: $(printf '%s' "$ff_kv" | cut -d= -f1 | tr '\n' ' ')"
}

# Camera settings added on top of the phone's own camera-feature.xml (rebuilt from stock each apply):
#  logvideo: the S24's Log recording in Pro video (the S23's sensor/HAL already records 10-bit
#            Log). Not SUPPORT_PREVIEW_LUT: the LUT preview is drawn by the S24 camera HAL (its
#            LogConverter uniplugin); the S23 HAL has none, and the LUT button crashed the camera.
#  camextras: Super steady's horizontal lock (a third Super steady option; hlock_apply makes it level)
#  wideflash: the flash in Photo and the torch in Video on the 0.6x ultrawide, and Camera Assistant's
#             matching wide-flash option. Both are switches in camera-feature.xml; no APK or HAL patch.
#  prowbtint: the Tint slider next to the colour temperature in Pro and Pro video's white balance.
#  zoomrocker: the smooth zoom rocker/slider in the standard Video mode.
#  slowmoaf: tap-to-focus while recording in Slow motion (its Camera Assistant flag is set in apply).
#  extstorage: recording straight to a USB-C SSD/drive, in every video mode (camfeat_apply flips
#              external-storage-support="false" to "true" on the resolution map lines).
#  anamorphic: Camera Assistant's anamorphic lens desqueeze (1.33x / 1.55x / 2.0x).
#  profps: extra Pro video frame rates: 4K 25/48/50, FHD 25/48/50/100 and 8K 25. The 10x tele
#          stays hidden in these modes unless the Camera APK patch is bound (cam24fps/profps).
#  slowmo4k120: 4K120 and FHD120 in Slow motion (slow_motion added to their modes), and the
#          FHD240 entry rebuilt for the Slow motion menu so the resolution list is complete.
#  dofadapter: Camera Assistant's DOF (depth-of-field) adapter option.
#  mirror8k: recording in 8K while the phone is mirrored to a display (HDMI/Smart View).
#  longrec: raises the recording time limit in overheat conditions and the delay before
#           low-power mode from 300 s (5 min) to 3600 s (1 h).
# Never add SUPPORT_BACK_WIDE_NORMAL_DUAL_PORTRAIT_VIDEO, SUPPORT_BACK_PORTRAIT_VIDEO_TELE_DUAL or
# CAMERA_SUPPORT_SEAMLESS_PORTRAITVIDEO: on the S23 they crash the camera ("Zoom is not supported").
CF_LOG='<local name="SUPPORT_LOG_VIDEO" value="true"/>'
CF_HLOCK='<local name="SUPPORT_SUPER_STEADY_HORIZONTAL_LOCK" value="true"/>'
CF_WIDEFLASH='<local name="SUPPORT_FLASH_IN_WIDE_LENS" value="true"/>'
CF_WIDEFLASH_CA='<local name="SUPPORT_CAMERA_ASSISTANT_WIDE_FLASH_MENU" value="true"/>'
CF_PROWBTINT='<local name="SUPPORT_PRO_WHITE_BALANCE_TINT" value="true"/>'
CF_ZOOMROCKER='<local name="SUPPORT_VIDEO_MODE_ZOOM_ROCKER" value="true"/>'
CF_SLOWMOAF='<local name="SUPPORT_SLOW_MOTION_AF_DURING_RECORDING" value="true"/>'
CF_ANAMORPHIC='<local name="SUPPORT_CAMERA_ASSISTANT_ANAMORPHIC_LENS" value="true"/>'
CF_ANAMORPHIC_SCALER='<local name="SUPPORT_CAMERA_ASSISTANT_ANAMORPHIC_LENS_HW_SCALER" value="true"/>'
CF_DOFADAPTER='<local name="SUPPORT_CAMERA_ASSISTANT_DOF_ADAPTER" value="true"/>'
CF_MIRROR8K='<local name="SUPPORT_CAMERA_ASSISTANT_RECORDING_8K_WHEN_MIRRORING" value="true"/>'
CF_LONGREC='<local name="MAX_SEAMLESS_ZOOM_RECORDING_TIME_LIMIT_IN_OVERHEAT_CONDITION" value="3600"/>
<local name="MIN_RECORDING_TIME_TO_ENABLE_LOW_POWER_MODE" value="3600"/>'
CF_SM_240FPS='<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_240FPS" value="true" hdr="true" hdr10="false" snapshot-support="false" snapshot-size="4000x2252" vdis="false" super-vdis="false" effect="false" object-tracking="false" seamless-zoom-support="false" physical-zoom-supported="false" external-storage-support="true" supported-mode="slow_motion"/>'
CF_PROFPS='<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_25FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x2252" vdis="true" super-vdis="false" effect="false" object-tracking="true" seamless-zoom-support="true" physical-zoom-supported="false" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_48FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x2252" vdis="true" super-vdis="false" effect="false" object-tracking="true" seamless-zoom-support="false" physical-zoom-supported="true" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_50FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x2252" vdis="true" super-vdis="false" effect="false" object-tracking="true" seamless-zoom-support="false" physical-zoom-supported="true" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_25FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x2252" vdis="true" super-vdis="true" effect="true" object-tracking="true" seamless-zoom-support="true" physical-zoom-supported="false" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_48FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x2252" vdis="true" super-vdis="true" effect="true" object-tracking="true" seamless-zoom-support="true" physical-zoom-supported="false" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_50FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x2252" vdis="true" super-vdis="true" effect="true" object-tracking="true" seamless-zoom-support="true" physical-zoom-supported="false" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_100FPS" value="true" hdr="true" hdr10="false" snapshot-support="false" snapshot-size="4000x2252" vdis="false" super-vdis="false" effect="false" object-tracking="false" seamless-zoom-support="false" physical-zoom-supported="false" external-storage-support="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_7680X4320_25FPS" value="true" hdr="true" hdr10="false" snapshot-support="true" snapshot-size="4000x2252" vdis="true" super-vdis="false" effect="false" object-tracking="false" seamless-zoom-support="false" physical-zoom-supported="false" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_120FPS" value="true" hdr="true" hdr10="false" snapshot-support="false" snapshot-size="4000x2252" vdis="false" super-vdis="false" effect="false" object-tracking="false" seamless-zoom-support="false" physical-zoom-supported="false" external-storage-support="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_100FPS" value="true" hdr="true" hdr10="false" snapshot-support="false" snapshot-size="4000x2252" vdis="false" super-vdis="false" effect="false" object-tracking="false" seamless-zoom-support="false" physical-zoom-supported="false" external-storage-support="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X1644_25FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x1716" vdis="true" super-vdis="false" effect="false" object-tracking="true" seamless-zoom-support="true" physical-zoom-supported="false" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X1644_48FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x1716" vdis="true" super-vdis="false" effect="false" object-tracking="true" seamless-zoom-support="false" physical-zoom-supported="true" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X1644_50FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x1716" vdis="true" super-vdis="false" effect="false" object-tracking="true" seamless-zoom-support="false" physical-zoom-supported="true" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X1644_100FPS" value="true" hdr="true" hdr10="false" snapshot-support="false" snapshot-size="4000x1716" vdis="false" super-vdis="false" effect="false" object-tracking="false" seamless-zoom-support="false" physical-zoom-supported="false" external-storage-support="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X1644_120FPS" value="true" hdr="true" hdr10="false" snapshot-support="false" snapshot-size="4000x1716" vdis="false" super-vdis="false" effect="false" object-tracking="false" seamless-zoom-support="false" physical-zoom-supported="false" external-storage-support="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X824_25FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x1716" vdis="true" super-vdis="false" effect="true" object-tracking="true" seamless-zoom-support="true" physical-zoom-supported="false" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X824_48FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x1716" vdis="true" super-vdis="false" effect="true" object-tracking="true" seamless-zoom-support="true" physical-zoom-supported="false" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X824_50FPS" value="true" hdr="true" hdr10="true" snapshot-support="true" snapshot-size="4000x1716" vdis="true" super-vdis="false" effect="true" object-tracking="true" seamless-zoom-support="true" physical-zoom-supported="false" external-storage-support="true" touch-af="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X824_100FPS" value="true" hdr="true" hdr10="false" snapshot-support="false" snapshot-size="4000x1716" vdis="false" super-vdis="false" effect="false" object-tracking="false" seamless-zoom-support="false" physical-zoom-supported="false" external-storage-support="true" supported-mode="pro_video"/>
<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_7680X3296_25FPS" value="true" hdr="true" hdr10="false" snapshot-support="true" snapshot-size="4000x1716" vdis="true" super-vdis="false" effect="false" object-tracking="false" seamless-zoom-support="false" physical-zoom-supported="false" external-storage-support="true" supported-mode="pro_video"/>'
cf_add=""; cf_slowmo_modes=""
camfeat_apply() {
  [ -n "$cf_add" ] || [ -n "${cf_video_modes:-}" ] || [ -n "${cf_slowmo_modes:-}" ] || has extstorage || return 1
  mkdir -p $R; bound $CF && umount $CF
  grep -q '</resources>' $CF || { log "camera: $CF has no </resources>; camera settings skipped"; return 1; }
  grep -v '</resources>' $CF > $R/cf.new
  # a setting the stock file already has (possibly value="false" on some models) gets our line instead
  printf '%s\n' "$cf_add" | while read -r l; do
    [ -n "$l" ] || continue
    n=$(echo "$l" | sed 's/.*name="\([^"]*\)".*/\1/')
    o=$(grep -m1 "name=\"$n\"" $CF | sed 's/^ *//'); [ -n "$o" ] && log "camera: stock camera-feature.xml had $o"
    grep -v "name=\"$n\"" $R/cf.new > $R/cf.tmp && mv $R/cf.tmp $R/cf.new
    echo "    $l" >> $R/cf.new
  done
  # preserve all stock attributes (vdis, hdr, hdr10, seamless-zoom-support) when enabling video mode on 24 fps entries
  for n in ${cf_video_modes:-}; do
    o=$(grep -m1 "name=\"$n\"" $R/cf.new || true)
    [ -n "$o" ] || { log "cam24fps: $n not found in $CF; skipped"; continue; }
    m=$(printf '%s' "$o" | sed -n 's/.*supported-mode="\([^"]*\)".*/\1/p')
    case ",$m," in
      *,video,*) nl=$o ;;
      ,,) nl=$(printf '%s' "$o" | sed 's|supported-mode=""|supported-mode="video"|') ;;
      *) nl=$(printf '%s' "$o" | sed "s|supported-mode=\"$m\"|supported-mode=\"video,$m\"|") ;;
    esac
    nl=$(printf '%s' "$nl" | sed 's|value="false"|value="true"|')
    # stock ships seamless-zoom-support="false" on the 24 fps UHD/FHD entries, which leaves Video
    # showing only the 1x lens; 8K stays false (the 10x is hidden there).
    case "$n" in
      BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_24FPS|BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_24FPS)
        nl=$(printf '%s' "$nl" | sed 's|seamless-zoom-support="false"|seamless-zoom-support="true"|') ;;
    esac
    grep -v "name=\"$n\"" $R/cf.new > $R/cf.tmp && mv $R/cf.tmp $R/cf.new
    printf '%s\n' "$nl" >> $R/cf.new
  done
  # Slow motion: add slow_motion to the 4K120 and FHD120 entries in place (keeping their position
  # and stock attributes), then put the rebuilt FHD240 entry last, as the working adb rebuild does.
  if has slowmo4k120; then
    for n in ${cf_slowmo_modes:-}; do
      o=$(grep -m1 "name=\"$n\"" $R/cf.new || true)
      [ -n "$o" ] || { log "slowmo4k120: $n not found in $CF; skipped"; continue; }
      m=$(printf '%s' "$o" | sed -n 's/.*supported-mode="\([^"]*\)".*/\1/p')
      case ",$m," in
        *,slow_motion,*) ;;
        ,,)
          if printf '%s' "$o" | grep -q 'supported-mode="'; then
            sed "/name=\"$n\"/ s|supported-mode=\"\"|supported-mode=\"slow_motion\"|" $R/cf.new > $R/cf.tmp && mv $R/cf.tmp $R/cf.new
          else
            sed "/name=\"$n\"/ s|/>| supported-mode=\"slow_motion\"/>|" $R/cf.new > $R/cf.tmp && mv $R/cf.tmp $R/cf.new
          fi ;;
        *)
          sed "/name=\"$n\"/ s|supported-mode=\"$m\"|supported-mode=\"$m,slow_motion\"|" $R/cf.new > $R/cf.tmp && mv $R/cf.tmp $R/cf.new ;;
      esac
    done
    grep -v 'name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_240FPS"' $R/cf.new > $R/cf.tmp && mv $R/cf.tmp $R/cf.new
    echo "    $CF_SM_240FPS" >> $R/cf.new
    log "slowmo4k120: 4K120 and FHD120 in Slow motion, FHD240 menu entry rebuilt"
  fi
  # USB-C storage: allow recording straight to an external drive in every video mode
  if has extstorage; then
    sed '/<local name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_/ s/external-storage-support="false"/external-storage-support="true"/g' $R/cf.new > $R/cf.tmp &&
      mv $R/cf.tmp $R/cf.new
    sed '/<local name="FRONT_CAMCORDER_RESOLUTION_FEATURE_MAP_/ s/external-storage-support="false"/external-storage-support="true"/g' $R/cf.new > $R/cf.tmp &&
      mv $R/cf.tmp $R/cf.new
  fi
  echo '</resources>' >> $R/cf.new
  mv $R/cf.new $R/camera-feature.xml; chmod 644 $R/camera-feature.xml
  chcon u:object_r:system_file:s0 $R/camera-feature.xml
  mount -o bind,ro $R/camera-feature.xml $CF || fail "camera-feature bind mount"
  log "camera settings on: $(printf '%s\n' "$cf_add" | sed -n 's/.*name="\([^"]*\)".*/\1/p' | tr '\n' ' ')${cf_video_modes:-}$(has extstorage && echo ' external-storage')"
  am force-stop com.sec.android.app.camera 2>/dev/null   # make the camera re-read the file, as the adb rebuild does
}

# Gallery's Log color correction (Edit > LUT, done by Samsung's video editor) reads the S24's LUTs
# from $LV. On the S23 that folder stays empty (init.rc copies them from /system/cameradata/logCubefiles,
# which One UI 9 ships empty for the S23), and its SELinux policy lacks the S24's
# LogVideofilters_data_file type, so the editor (platform_app) can't read vendor_data_file files there
# either: the LUT "loads" with no data and the video stays flat. Bind the S24's LUTs (S928BXXU6EZJB)
# over the folder, labelled system_file, which apps can read.
LV=/data/vendor/LogVideofilters
loglut_bind() {
  LS=$PL/logvideo
  [ -d $LS/preloadfilters ] || { log "logvideo: no LUT download; Log recording only"; return 1; }
  bound $LV && umount $LV
  [ -d $LV ] || { log "logvideo: $LV doesn't exist; LUTs skipped"; return 1; }
  if [ -s $LV/preloadfilters/SamsungLog_to_Rec709_3DLUT_v1.bcube ] &&
     grep -q LogVideofilters_data_file /vendor/etc/selinux/vendor_file_contexts 2>/dev/null; then
    log "logvideo: this firmware has its own LUTs; left alone"; return 1
  fi
  chown -R 1000:1000 $LS; chmod 775 $LS $LS/preloadfilters $LS/Thumbnails
  chmod 674 $LS/preloadfilters/* $LS/Thumbnails/*; chcon -R u:object_r:system_file:s0 $LS
  mount --bind $LS $LV || { log "logvideo: couldn't bind the LUT folder"; return 1; }
  log "logvideo: S24 LUTs for Gallery's Log color correction (Edit > LUT)"
}

# Director's view (front and back camera at once; the S23 had it in 2023). One UI 9 still ships the
# mode but hides it: modes marked enable="false" show only when the camera's own settings hold
# <mode>=1. A camera app setting, kept in its data folder (a reboot doesn't undo it; Camera > More >
# edit can hide the mode again). Not dual_recording_mode: the S24's Dual rec can't open the S23's
# cameras ("Unable to open Camera").
CAM_PREFS=/data/user/0/com.sec.android.app.camera/shared_prefs/com.sec.android.app.camera_preferences.xml
directorsview_pref() {
  if [ ! -f $CAM_PREFS ]; then
    if [ "${S23T_BOOT:-0}" = 1 ]; then log "camextras: app storage is locked until first unlock; Director's view stays as the last apply left it"
    else log "camextras: open the Camera app once, then apply again to show Director's view"; fi
    return
  fi
  grep -q '<string name="directors_view_mode">1</string>' $CAM_PREFS && { log "camextras: Director's view already shown"; return; }
  am force-stop com.sec.android.app.camera
  mkdir -p $R $V/backup $V/undo; [ -f $V/backup/camera_preferences.xml ] || cp $CAM_PREFS $V/backup/camera_preferences.xml
  # for "cleanup": the value before the first change, or "absent"
  [ -f $V/undo/directors_view ] || { v=$(sed -n 's|.*<string name="directors_view_mode">\([^<]*\)</string>.*|\1|p' $CAM_PREFS); echo "${v:-absent}" > $V/undo/directors_view; }
  if grep -q 'name="directors_view_mode"' $CAM_PREFS; then
    sed 's|<string name="directors_view_mode">[^<]*</string>|<string name="directors_view_mode">1</string>|' $CAM_PREFS > $R/camprefs.new
  else
    awk '/<\/map>/ { print "    <string name=\"directors_view_mode\">1</string>" } { print }' $CAM_PREFS > $R/camprefs.new
  fi
  grep -q '<string name="directors_view_mode">1</string>' $R/camprefs.new && grep -q '</map>' $R/camprefs.new ||
    { rm -f $R/camprefs.new; log "camextras: couldn't edit the camera settings; Director's view skipped"; return; }
  cat $R/camprefs.new > $CAM_PREFS; rm -f $R/camprefs.new   # cat keeps the file's owner and label
  log "camextras: Director's view shown (Camera > More)"
}
# wideflash: Samsung Camera reads SUPPORT_FLASH_IN_WIDE_LENS only as the *default* of its own setting
# flash_in_wide_lens (Camera Assistant's wide-flash option toggles it). A camera that has been used saves
# that setting as 0, which keeps the 0.6x flash off however camera-feature.xml says. Turn it on once
# (remembering the value before, for unpicking and cleanup); after that a choice made in Camera
# Assistant is kept.
WF_UNDO=$V/undo/flash_in_wide
wideflash_pref() {
  # no settings file: storage still locked at boot (the last apply's edit stands), or the camera was
  # never opened, so its default comes from camera-feature.xml, which this tweak turns on
  [ -f $CAM_PREFS ] || return 0
  [ -f $WF_UNDO ] && return 0
  v=$(sed -n 's|.*<string name="flash_in_wide_lens">\([^<]*\)</string>.*|\1|p' $CAM_PREFS)
  [ "$v" = 1 ] && return 0
  am force-stop com.sec.android.app.camera
  mkdir -p $R $V/undo; echo "${v:-absent}" > $WF_UNDO
  if [ -n "$v" ]; then
    sed 's|<string name="flash_in_wide_lens">[^<]*</string>|<string name="flash_in_wide_lens">1</string>|' $CAM_PREFS > $R/camprefs.new
  else
    awk '/<\/map>/ { print "    <string name=\"flash_in_wide_lens\">1</string>" } { print }' $CAM_PREFS > $R/camprefs.new
  fi
  grep -q '<string name="flash_in_wide_lens">1</string>' $R/camprefs.new && grep -q '</map>' $R/camprefs.new ||
    { rm -f $R/camprefs.new $WF_UNDO; log "wideflash: couldn't edit the camera settings; turn on the wide-lens flash in Camera Assistant instead"; return; }
  cat $R/camprefs.new > $CAM_PREFS; rm -f $R/camprefs.new   # cat keeps the file's owner and label
  log "wideflash: Camera's wide-lens flash setting turned on (it was ${v:-unset})"
}
# put the setting back the way it was before wideflash_pref changed it
wideflash_unpref() {
  [ -f $WF_UNDO ] && [ -f $CAM_PREFS ] || return 1
  v=$(cat $WF_UNDO); am force-stop com.sec.android.app.camera; mkdir -p $R
  if [ "$v" = absent ]; then grep -v 'name="flash_in_wide_lens"' $CAM_PREFS > $R/camprefs.new
  else sed "s|<string name=\"flash_in_wide_lens\">[^<]*</string>|<string name=\"flash_in_wide_lens\">$v</string>|" $CAM_PREFS > $R/camprefs.new; fi
  grep -q '</map>' $R/camprefs.new && cat $R/camprefs.new > $CAM_PREFS && rm -f $R/camprefs.new $WF_UNDO
}

# ---------- Payload tweaks: camerahdr, hdr2023, audioeraser, colortone, galaxyai (files in $D/payload/<tweak>) ----------
# Linux stacks at most two overlays on a path, so the tweaks don't mount their own. Each one stages the
# files the phone doesn't show yet into $T24/new/<folder> (stage, stage_text); layers_mount then puts one
# overlay per folder on /system/<folder>. Overlays merge subfolders, so etc/permissions rides on the
# /system/etc layer. An overlay hides whatever is mounted inside its folder, so layers_mount puts
# those mounts back on top (keep_mounts), and the tweaks' own single-file binds come after it. Each step checks what the phone shows, not the mount table, so a re-apply only adds what's
# missing.
tlayer() { mkdir -p $T24; mounted $T24 tmpfs || mount -t tmpfs -o mode=755 s23tweaks_layers $T24; }
same_size() { [ "$(stat -c %s "$1" 2>/dev/null)" = "$(stat -c %s "$2" 2>/dev/null)" ]; }
# stage <folder under /system> <source file>: add the file to the next layer unless /system shows it. The
# layer gets an empty placeholder; layers_mount binds the downloaded file over it (no copy in RAM).
stage() {
  [ -e /system/$1/${2##*/} ] && return 1; tlayer; mkdir -p $T24/new/$1
  : > $T24/new/$1/${2##*/} && echo "$2 /system/$1/${2##*/}" >> $T24/new.binds || fail "stage $2"
}
# stage_text <file under /system>: write stdin to the next layer in place of that file
stage_text() { tlayer; mkdir -p $T24/new/${1%/*}; cat > $T24/new/$1; }
# An overlay on a folder hides whatever is mounted inside it (other modules' files, earlier binds).
# keep_mounts parks each such mount on a spare path first; keep_restore mounts it back on top of the
# new layer, parents before children, in the order the kernel lists them.
keep_mounts() {
  K=$T24/keep; rm -rf $K; mkdir -p $K; i=0; : > $T24/keep.ok
  awk -v p="$1/" 'index($2, p) == 1 && $2 !~ /\\/ && !seen[$2]++ {print $2}' /proc/mounts > $T24/keep.list
  while read m; do i=$((i+1))
    if [ -d "$m" ]; then mkdir $K/$i; else : > $K/$i; fi
    if e=$(mount --bind "$m" $K/$i 2>&1); then echo "$i $m" >> $T24/keep.ok; continue; fi
    case "$m" in
      # our own edited copies: camfeat_apply and ff_apply rebuild them from stock after the layers
      # (issue #26: a stale one left by applies of older versions in the same boot couldn't be bound)
      $FF|$CF) umount "$m" 2>/dev/null
        log "note: couldn't keep $m inside the new layer (${e:-mount failed}); it's rebuilt later in this apply" ;;
      *) fail "keep $m: ${e:-mount failed} (a reboot clears it; then apply again)" ;;
    esac
  done < $T24/keep.list
}
keep_restore() {
  n=0
  while read i m; do n=$((n+1))
    e=$(mount --bind $K/$i "$m" 2>&1) || fail "put back $m: ${e:-mount failed}"
    umount $K/$i
  done < $T24/keep.ok
  [ $n = 0 ] || log "kept $n mounts inside the new layer: $(cut -d' ' -f2- $T24/keep.ok | tr '\n' ' ')"
  rm -rf $K $T24/keep.list $T24/keep.ok
}
layers_mount() {
  [ -d $T24/new ] || return 1
  n=1; while [ -e $T24/L$n ]; do n=$((n+1)); done
  mv $T24/new $T24/L$n; LD=$T24/L$n   # not L: that is the log file
  [ -f $T24/new.binds ] && mv $T24/new.binds $LD.binds
  find $LD -type d -exec chmod 755 {} +; find $LD -type f -exec chmod 644 {} +
  chcon -R u:object_r:system_file:s0 $LD; [ -d $LD/lib64 ] && chcon -R u:object_r:system_lib_file:s0 $LD/lib64
  for d in $LD/*; do d=${d##*/}
    [ -d /system/$d ] || fail "no /system/$d"
    keep_mounts /system/$d
    mount -t overlay s23tweaks_$d$n -o ro,lowerdir=$LD/$d:/system/$d /system/$d ||
      { keep_restore; fail "overlay on /system/$d (if tweaks were already added since the last reboot, reboot and apply again)"; }
    keep_restore
    log "layer on /system/$d: $(cd $LD/$d && find . -type f | sed 's|^\./||' | tr '\n' ' ')"
  done
  [ -f $LD.binds ] && while read src dst; do
    case "$dst" in /system/lib64/*) ty=system_lib_file ;; *) ty=system_file ;; esac
    pbind "$src" "$dst" $ty
  done < $LD.binds
  return 0
}
pl_check() {   # pl_check <tweak> <file>...: all present in payload/<tweak>?
  t=$1; shift
  for f in "$@"; do [ -f $PL/$t/$f ] || { log "$t: its download is missing $f; skipped"; return 1; }; done
}
# bind_file <source> <target> <label>: bind one file unless the target already shows the same size
bind_file() {
  same_size "$2" "$1" && return 1
  chmod 644 "$1"; chcon u:object_r:$3:s0 "$1"
  mount -o bind,ro "$1" "$2" || fail "bind $2"
}

# Camera HDR processing (untested; see docs/findings.md). One UI 9 dropped the S23's ArcSoft
# multi-frame HDR and low-light HDR steps: their entries in CAMERA_CONFIG_VENDOR_LIB_INFO and both
# libraries. The camera app still has both steps and, with them unlisted, runs a pass-through dummy
# instead. Put back the 2023 (One UI 6, S918WVLS2BWKA) libraries, their public-library lines and the
# two list entries. The flag file is cached per process, so this goes through the framework restart.
CH_LIBS="libhigh_dynamic_range.arcsoft.so liblow_light_hdr.arcsoft.so"
CH_MD5="c6b7aa034c3704dcfccc87ca32582dc6 656c3c400bb9ebf74a05e23865c334cb"
CH_PUB=public.libraries-arcsoft.txt
CH_KEY=CAMERA_CONFIG_VENDOR_LIB_INFO
camerahdr_stage() {
  set -- $CH_MD5
  for f in $CH_LIBS; do
    [ "$(md5sum $PL/camerahdr/$f 2>/dev/null | cut -d' ' -f1)" = "$1" ] || { log "camerahdr: its download is missing $f (or it's damaged); skipped"; return 1; }
    shift
  done
  v=$(grep -o "<SEC_FLOATING_FEATURE_$CH_KEY>[^<]*" $FF | cut -d'>' -f2)
  [ -n "$v" ] || { log "camerahdr: $FF has no $CH_KEY; skipped"; return 1; }
  case ",$v," in *,mfhdr.arcsoft.v4,*) ;; *) v="$v,mfhdr.arcsoft.v4" ;; esac
  case ",$v," in *,llhdr.arcsoft.v4,*) ;; *) v="$v,llhdr.arcsoft.v4" ;; esac
  ff_set $CH_KEY "$v"
  for f in $CH_LIBS; do stage lib64 $PL/camerahdr/$f; done
  if [ -f /system/etc/$CH_PUB ] && ! grep -q '^liblow_light_hdr.arcsoft.so' /system/etc/$CH_PUB; then
    { cat /system/etc/$CH_PUB; printf '%s\n' $CH_LIBS; } | stage_text etc/$CH_PUB
  fi
  am force-stop com.sec.android.app.camera
  log "camerahdr: One UI 6 multi-frame HDR and low-light HDR on"
  return 0   # the list entry needs the framework restart that follows the flag file
}

# 2023 ArcSoft HDR. The HDR the camera actually picks on One UI 9 is hybrid HDR (most daylight shots)
# and bracketed (AEB) HDR (backlit scenes). Both engines changed since One UI 6: hybrid HDR 4.2 build
# 1423 -> 1790, and bracketed HDR from ArcSoft HDR_ART 4.2 (build 1252) to a new AEBHDR 5.0 engine.
# Swap both engines and their Samsung wrappers (as pairs) for the 2023 S918WVLS2BWKA copies. The 2023
# wrappers export every function today's camera calls. Bracketed HDR was tested on S918WVLU8GZIF
# (engine version 900 runs, no errors); hybrid HDR loads but wasn't triggered in testing.
H23_LIBS="libhybrid_high_dynamic_range.arcsoft.so libae_bracket_hdr.arcsoft.so libhybridHDR_wrapper.camera.samsung.so libAEBHDR_wrapper.camera.samsung.so"
H23_MD5="2af454af1421426ee3ec3ea1462a30cf af98599bd1b23a44834626e60b1057bf dad377ec9ee2020c091fa739f798e597 c460aff39b2b929a804e2ac11ce9af69"
hdr2023_check() {
  set -- $H23_MD5
  for f in $H23_LIBS; do
    [ "$(md5sum $PL/hdr2023/$f 2>/dev/null | cut -d' ' -f1)" = "$1" ] || { log "hdr2023: its download is missing $f (or it's damaged); skipped"; return 1; }
    shift
  done
}
hdr2023_bind() {   # after layers_mount: an overlay on /system/lib64 would hide these binds
  for f in $H23_LIBS; do bind_file $PL/hdr2023/$f /system/lib64/$f system_lib_file; done
  am force-stop com.sec.android.app.camera
  log "hdr2023: 2023 ArcSoft hybrid HDR and bracketed HDR on"
}

# 10-bit HDR video from the front cameras for any app (Camera2 DYNAMIC_RANGE_TEN_BIT, HLG10). The camera
# driver (CamX, /vendor/lib64/hw/camera.qcom.so) builds the 10-bit profile list, the recommended profile
# and the TEN_BIT capability only for rear cameras, so Android refuses 10-bit streams on the selfie
# cameras, though their sensors and pipeline produce them (Samsung Camera records HDR10+ selfie video).
# Make a copy of the phone's own driver with 3 changes, found by their instructions (not fixed offsets,
# so any build with the same CamX code works): the profile list and recommended profile no longer skip
# front cameras, and a jump to 15 new instructions in the zero padding at the end of the code segment
# appends TEN_BIT (18) to a front camera's capability list (not the secure-only cameras, which list one
# capability). Bound from /data with the camera driver stopped. It stays only if the driver keeps
# running and a front camera then really lists TEN_BIT; otherwise the stock driver goes back.
TB_LIB=/vendor/lib64/hw/camera.qcom.so
TB_SVC=sec-camera-provider
# Cave code, in words: if facing ([x29-0xb0]) is front and the list (w10 entries at x19+0x2060) has
# 2..19 entries, append 18; then the replaced "mov w28, w10" (the jump back is added per file)
TB_CAVE="d102c3a9 b9400129 7100053f 54000141 7100095f 54000103 71004d5f 540000c8 91400a69 91018129 5280024b 382a492b 1100054a 2a0a03fc"
tb_pid() { pidof vendor.samsung.hardware.camera.provider-service_64; }
tb_restart() {   # stop the camera driver, run "$@" while it's down, start it, wait until it stays up
  am force-stop com.sec.android.app.camera
  setprop ctl.stop $TB_SVC; n=50; while [ -n "$(tb_pid)" ] && [ $n -gt 0 ]; do n=$((n-1)); sleep 0.1; done
  "$@"
  setprop ctl.start $TB_SVC; sleep 6; p=$(tb_pid); [ -n "$p" ] || return 1
  sleep 4; [ "$(tb_pid)" = "$p" ]
}
tb_unbind() { while bound $TB_LIB; do umount $TB_LIB || return 1; done; }
tb_bind() { tb_unbind && mount -o bind,ro $V/tenbit.so $TB_LIB; }
tb_front10() {   # does a front camera list DYNAMIC_RANGE_TEN_BIT right now?
  dumpsys media.camera | awk '
    function done_cam() { if (front && ten) ok = 1; front = 0; ten = 0 }
    /static information:/ { done_cam() }
    /android\.lens\.facing \(/ { getline l; front = (l ~ /FRONT/) }
    /android\.request\.availableCapabilities \(/ { getline l; ten = (l ~ /DYNAMIC_RANGE_TEN_BIT/) }
    END { done_cam(); exit !ok }'
}
tb_rd() { od -An -v -tx$3 -j $(($2)) -N $3 "$1" | tr -d ' \n'; }   # FILE OFFSET BYTES: little-endian value, hex
tb_wr() {   # FILE OFFSET WORD
  w=$(($3)); printf "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' $((w & 255)) $((w >> 8 & 255)) $((w >> 16 & 255)) $((w >> 24 & 255)))" |
    dd of="$1" bs=1 seek=$(($2)) conv=notrunc 2>/dev/null
}
tb_b() { echo $((0x14000000 | ((($2) - ($1)) / 4 & 0x3ffffff))); }   # FROM TO: "b TO" placed at FROM
# tb_find FILE: the offset of each change, as "A 0x..", "B 0x..", "C 0x..", one line for every match
#  A  ldr w3,[x21]; ldrsw x7,[x27,#0x2674]; cmp w3,#1; str x7,[x19,#0x2060]; b.ne    (recommended profile)
#  B  ldr w8,[x21]; mov w0,wzr; cmp w8,#1; b.eq; ldr w7,[x27,#0x2670]                (profile list)
#  C  mov w11,#8; mov w10,#1; strb w11,[x22]; mov w28,w10; add x2,x19,#2,lsl#12; adrp x4; add x2,x2,#0x60
tb_find() {
  od -An -v -tx4 -w4 "$1" | awk '
    $1 ~ /^54.....1$/ && p1 == "f9103267" && p2 == "7100047f" && p3 == "b9a67767" && p4 == "b94002a3" { printf "A 0x%x\n", (NR - 1) * 4 }
    $1 == "b9667367" && p1 ~ /^54.....0$/ && p2 == "7100051f" && p3 == "2a1f03e0" && p4 == "b94002a8" { printf "B 0x%x\n", (NR - 2) * 4 }
    $1 == "91018042" && p2 == "91400a62" && p3 == "2a0a03fc" && p4 == "390002cb" && p5 == "5280002a" && p6 == "5280010b" { printf "C 0x%x\n", (NR - 4) * 4 }
    { p6 = p5; p5 = p4; p4 = p3; p3 = p2; p2 = p1; p1 = $1 }'
}
# tb_patch STOCK OUT: write the patched copy; says why not on failure
tb_patch() {
  F=$1; O=$2; m=$(tb_find $F)
  for k in A B C; do [ "$(echo "$m" | grep -c "^$k ")" = 1 ] || { echo "its camera driver's code differs (change $k found $(echo "$m" | grep -c "^$k ") times)"; return 1; }; done
  set -- $m; A=$2; B=$4; C=$6
  # the code segment: the PT_LOAD with PF_X. The cave goes right after its file contents, in the zero
  # padding of its last page (mapped executable with it)
  ph=$((0x$(tb_rd $F 0x20 8))); n=$((0x$(tb_rd $F 0x38 2))); sz=$((0x$(tb_rd $F 0x36 2))); X=""
  while [ $n -gt 0 ]; do
    if [ $((0x$(tb_rd $F $ph 4))) = 1 ] && [ $((0x$(tb_rd $F $((ph + 4)) 4) & 1)) = 1 ]; then
      X=$((0x$(tb_rd $F $((ph + 8)) 8))); XE=$((X + 0x$(tb_rd $F $((ph + 0x20)) 8))); break; fi
    ph=$((ph + sz)); n=$((n - 1))
  done
  [ -n "$X" ] || { echo "no code segment found"; return 1; }
  for o in $A $B $C; do [ $((o)) -ge $X ] && [ $((o)) -lt $XE ] || { echo "a change falls outside the code segment"; return 1; }; done
  K=$(((XE + 3) & ~3)); KE=$((K + 60))
  [ $KE -le $(((XE + 4095) & ~4095)) ] && [ "$(od -An -v -tx1 -j $K -N 60 $F | tr -s ' ' '\n' | grep -c '^00$')" = 60 ] ||
    { echo "no free room at the end of its code"; return 1; }
  w=$((0x$(tb_rd $F $A 4))); i=$((w >> 5 & 0x7ffff)); [ $i -ge $((0x40000)) ] && i=$((i - 0x80000))
  cp $F $O || { echo "no room for a copy"; return 1; }
  tb_wr $O $A $(tb_b 0 $((i * 4)))            # b.ne -> b
  tb_wr $O $B 0xd503201f                       # b.eq -> nop
  tb_wr $O $C $(tb_b $C $K)                    # mov w28, w10 -> b cave
  o=$K; for x in $TB_CAVE; do tb_wr $O $o 0x$x; o=$((o + 4)); done
  tb_wr $O $o $(tb_b $o $((C + 4)))            # back
  printf 'changes at 0x%x 0x%x 0x%x, cave 0x%x' $A $B $C $K
}
tenbit_apply() {
  if bound $TB_LIB; then [ "$(md5 $TB_LIB)" = "$(md5 $V/tenbit.so)" ] && { log "tenbit: already on"; return 0; }
    log "tenbit: something else is bound over $TB_LIB; skipped"; return 1; fi
  tb_front10 && { log "tenbit: the front cameras already offer 10-bit; nothing to do"; return 0; }
  s=$(md5 $TB_LIB)
  if [ "$(cat $V/tenbit.src 2>/dev/null)" != "$s" ] || [ ! -f $V/tenbit.so ]; then   # (re)make it for this driver
    rm -f $V/tenbit.so $V/tenbit.src
    r=$(tb_patch $TB_LIB $V/tenbit.tmp) || { rm -f $V/tenbit.tmp; log "tenbit: $r; skipped"; return 1; }
    mv $V/tenbit.tmp $V/tenbit.so; echo $s > $V/tenbit.src; log "tenbit: patched copy made ($r)"
  fi
  chown 0:0 $V/tenbit.so; chmod 644 $V/tenbit.so; chcon u:object_r:vendor_file:s0 $V/tenbit.so
  if tb_restart tb_bind && bound $TB_LIB && tb_front10; then
    log "tenbit: front cameras offer 10-bit HDR (HLG10) video to apps"
  else
    tb_restart tb_unbind
    log "tenbit: with the change the camera driver didn't stay up or the front cameras still lacked 10-bit; stock driver back"
    return 1
  fi
}

# Super steady's horizontal lock (camextras). Samsung Camera asks for it with Super steady = 2, which the
# S23's camera driver treats as plain Super steady: the picture turns with the phone. The S23's EIS v3
# stabilizer (Qualcomm) has horizon levelling, switched on by the EIS tuning (off for Super steady here)
# or by an app's HorizonLevelControl tag, which the S23 build never reads (it looks up the
# EnableInsensorZoom tag ID instead), and Samsung's S23 driver maps nothing to it. Make a copy of the
# phone's own EIS v3 node where that tag check becomes: if CheckSuperSteadyMode() is 2, set the
# levelling enable field, else use the tuning. The algorithm then levels with the accelerometer (its
# default angles), but clamps the correction to the tuning's per-sensor maximum: 8 degrees on the S23,
# so a 30-degree tilt kept 22 (ha_patch lifts it to 30). Found by instructions, so any build with the
# same code works. Bound like tenbit's.
HL_LIB=/vendor/lib64/camera/components/com.qti.node.eisv3.so
# hl_find FILE: "S 0x.." the tag check, "F 0x.." its found branch (mov w8; mov w0,#enable; ...),
# "J 0x.." the use-tuning join (after a bl: mov w21,wzr; mov w19,#1), "C 0x.." in CheckSuperSteadyMode
hl_find() {
  od -An -v -tx4 -w4 "$1" | awk '
    { w[NR] = $1 }
    END {
      for (i = 1; i + 9 <= NR; i++) {
        if (w[i] ~ /^[9bdf]0....[02468ace]3$/ && w[i+1] == "f9405ac4" && w[i+2] ~ /^91...[048c]63$/ && w[i+3] == "aa1f03e0" &&
            w[i+4] == "52800042" && w[i+5] == "2a1f03e5" && w[i+6] == "b8414473" && w[i+7] == "32030261" &&
            w[i+8] ~ /^94/ && w[i+9] ~ /^b4/) printf "S 0x%x\n", (i - 1) * 4
        if (w[i] ~ /^52[89a-f]...[02468ace]8$/ && w[i+1] ~ /^52[89a-f]...[02468ace]0$/ && w[i+2] == "2a1f03f5" &&
            w[i+3] == "52800033" && w[i+4] == "b8286b96" && w[i+6] == "b8206b98") printf "F 0x%x\n", (i - 1) * 4
        if (w[i] ~ /^94/ && w[i+1] == "2a1f03f5" && w[i+2] == "52800033") printf "J 0x%x\n", i * 4
        if (w[i] == "b8410468" && w[i+1] == "f9405804" && w[i+2] == "aa1f03e0" && w[i+3] == "32040901" && w[i+4] ~ /^94/) {
          for (k = i; k > i - 24 && k > 0; k--) if (w[k] == "d503233f") break
          if (w[k] == "d503233f") printf "C 0x%x\n", (k - 1) * 4 }
      }
    }'
}
# hl_patch STOCK OUT: write the patched copy; says why not on failure
hl_patch() {
  F=$1; O=$2; m=$(hl_find $F)
  for k in S F C; do [ "$(echo "$m" | grep -c "^$k ")" = 1 ] || { echo "its EIS code differs (part $k found $(echo "$m" | grep -c "^$k ") times)"; return 1; }; done
  S=$(($(echo "$m" | awk '$1=="S"{print $2}'))); FB=$(($(echo "$m" | awk '$1=="F"{print $2}'))); C=$(($(echo "$m" | awk '$1=="C"{print $2}')))
  J=""; for j in $(echo "$m" | awk '$1=="J"{print $2}'); do [ $((j)) -gt $S ] && [ $((j)) -lt $((S + 0x200)) ] && [ $((j)) != $((FB + 8)) ] && J=$((j)); done
  [ -n "$J" ] && [ $FB -gt $S ] && [ $FB -lt $J ] || { echo "its EIS code is laid out differently"; return 1; }
  EN=$(((0x$(tb_rd $F $((FB + 4)) 4) >> 5) & 0xffff))   # the enable field's offset, from "mov w0, #offset"
  cp $F $O || { echo "no room for a copy"; return 1; }
  tb_wr $O $S 0xaa1603e0                                                   # mov x0, x22 (the node)
  tb_wr $O $((S + 4)) $((0x94000000 | ((C - S - 4) / 4 & 0x3ffffff)))      # bl CheckSuperSteadyMode
  tb_wr $O $((S + 8)) 0x7100081f                                           # cmp w0, #2
  tb_wr $O $((S + 12)) $((0x54000001 | (((J - S - 12) / 4 & 0x7ffff) << 5)))   # b.ne tuning
  tb_wr $O $((S + 16)) $((0x52800008 | (EN << 5)))                        # mov w8, #enable field
  tb_wr $O $((S + 20)) 0x52800029                                          # mov w9, #1
  tb_wr $O $((S + 24)) 0xb8286b89                                          # str w9, [x28, x8]
  tb_wr $O $((S + 28)) $(tb_b $((S + 28)) $J)                              # b tuning join
  printf 'check at 0x%x, enable field 0x%x' $S $EN
}
# The stabilizer itself (com.qti.eisv3.so) reads that maximum once per sensor slot while it starts:
# 16 loads of [xN, #596] in one tight run (the only other such load is in a debug dump, far away),
# each then turned into radians. ha_patch makes a copy where each load is "fmov sN, #30.0".
HA_LIB=/vendor/lib64/camera/components/com.qti.eisv3.so
# ha_patch STOCK OUT: write the copy with the 30-degree cap; says why not on failure
ha_patch() {
  F=$1; O=$2
  offs=$(od -An -v -tx4 -w4 "$F" | awk '
    /^ *bd425[4-7]/ { a = (NR - 1) * 4                       # ldr sN, [xM, #596]
      if (cnt && a - last > 128) { if (cnt == 16) print run; run = ""; cnt = 0 }
      run = run " " a; cnt++; last = a }
    END { if (cnt == 16) print run }')
  [ "$(echo "$offs" | grep -c .)" = 1 ] && [ "$(echo $offs | wc -w)" = 16 ] || { echo "its stabilizer code differs"; return 1; }
  cp $F $O || { echo "no room for a copy"; return 1; }
  for a in $offs; do tb_wr $O $a $((0x1e27d000 | (0x$(tb_rd $F $a 4) & 31))); done   # fmov sN, #30.0
  echo "levelling up to 30 degrees"
}
# The preview runs its own stabilizer pair (EIS v2: node and com.qti.eisv2.so). Its node is newer code:
# a GetHorizonLevelingOverride that copies the tag's enable and maximum into the per-sensor block if the
# tag is found, else only logs "Use tuning". hl2_patch replaces that log with: if CheckSuperSteadyMode()
# is 2, enable = 1 and maximum = 30. Its stabilizer takes ha_patch as is (same 16-load run).
HL2_LIB=/vendor/lib64/camera/components/com.qti.node.eisv2.so
HA2_LIB=/vendor/lib64/camera/components/com.qti.eisv2.so
# hl2_find FILE: "L 0x.." the tag lookup's "ldr x4,[x30,#144]" (then "P 0x.." the ldr x30,[sp,#..] before
# it), "F 0x.." the found path's two stores, "T 0x.." each tuning join, "C 0x.." CheckSuperSteadyMode
hl2_find() {
  od -An -v -tx4 -w4 "$1" | awk '
    { w[NR] = $1 }
    END {
      for (i = 1; i + 9 <= NR; i++) {
        if (w[i] == "f9404bc4" && w[i+1] ~ /^91...063$/ && w[i+2] == "aa1f03e0" && w[i+3] == "52800042" && w[i+4] == "2a1f03e5" &&
            w[i+5] ~ /^b84184/ && w[i+6] ~ /^320301/ && w[i+7] ~ /^94/ && w[i+8] ~ /^b4/) {
          printf "L 0x%x\n", (i - 1) * 4
          for (k = i - 1; k > i - 12; k--) if (w[k] ~ /^f94.....$/ && w[k] ~ /fe$/) { printf "P 0x%x\n", (k - 1) * 4; break } }
        if (w[i] ~ /^529....d$/ && w[i+1] ~ /^529....c$/ && w[i+2] == "f9006bff" && w[i+3] == "52800033" &&
            w[i+4] == "b82d6a99" && w[i+5] == "b82c6a95") printf "F 0x%x\n", (i - 1) * 4
        if (w[i] == "f9006bff" && w[i+1] == "52800033") printf "T 0x%x\n", (i - 1) * 4
        if (w[i] == "b8410468" && w[i+1] == "32040901" && w[i+2] ~ /^94/) {
          for (k = i; k > i - 24 && k > 0; k--) if (w[k] == "d503233f") break
          if (w[k] == "d503233f") printf "C 0x%x\n", (k - 1) * 4 }
      }
    }'
}
# hl2_patch STOCK OUT: write the patched copy; says why not on failure
hl2_patch() {
  F=$1; O=$2; m=$(hl2_find $F)
  for k in L P F C; do [ "$(echo "$m" | grep -c "^$k ")" = 1 ] || { echo "its preview EIS code differs (part $k found $(echo "$m" | grep -c "^$k ") times)"; return 1; }; done
  L=$(($(echo "$m" | awk '$1=="L"{print $2}'))); P=$(($(echo "$m" | awk '$1=="P"{print $2}')))
  FB=$(($(echo "$m" | awk '$1=="F"{print $2}'))); C=$(($(echo "$m" | awk '$1=="C"{print $2}')))
  cb=$((0x$(tb_rd $F $((L + 32)) 4)))                                     # cbz x0, N
  N=$(((cb >> 5) & 0x7ffff)); [ $N -ge 262144 ] && N=$((N - 524288)); N=$((L + 32 + N * 4))
  T=""; for t in $(echo "$m" | awk '$1=="T"{print $2}'); do [ -z "$T" ] && [ $((t)) -gt $N ] && [ $((t)) -lt $((N + 0x200)) ] && T=$((t)); done
  [ -n "$T" ] && [ $((T - N)) -ge 48 ] && [ $FB -gt $L ] && [ $FB -lt $N ] || { echo "its preview EIS code is laid out differently"; return 1; }
  SL=$((((0x$(tb_rd $F $P 4)) >> 10 & 0xfff) * 8))                        # the node's stack slot
  EN=$(((0x$(tb_rd $F $FB 4) >> 5) & 0xffff)); MX=$(((0x$(tb_rd $F $((FB + 4)) 4) >> 5) & 0xffff))
  cp $F $O || { echo "no room for a copy"; return 1; }
  tb_wr $O $N $((0xf94003e0 | (SL / 8) << 10))                            # ldr x0, [sp, #node]
  tb_wr $O $((N + 4)) 0xf9404800                                           # ldr x0, [x0, #144]
  tb_wr $O $((N + 8)) $((0x94000000 | ((C - N - 8) / 4 & 0x3ffffff)))      # bl CheckSuperSteadyMode
  tb_wr $O $((N + 12)) 0x7100081f                                          # cmp w0, #2
  tb_wr $O $((N + 16)) $((0x54000001 | (((T - N - 16) / 4 & 0x7ffff) << 5)))   # b.ne tuning
  tb_wr $O $((N + 20)) $((0x52800008 | (EN << 5)))                        # mov w8, #enable field
  tb_wr $O $((N + 24)) 0x52800029                                          # mov w9, #1
  tb_wr $O $((N + 28)) 0xb8286a89                                          # str w9, [x20, x8]
  tb_wr $O $((N + 32)) $((0x52800008 | (MX << 5)))                        # mov w8, #maximum field
  tb_wr $O $((N + 36)) 0x52a83e09                                          # mov w9, #30.0
  tb_wr $O $((N + 40)) 0xb8286a89                                          # str w9, [x20, x8]
  tb_wr $O $((N + 44)) $(tb_b $((N + 44)) $T)                              # b tuning
  printf 'check at 0x%x, enable field 0x%x' $N $EN
}
# target:copy:patcher. The record-side node copy is the one levelling needs; the others widen it
HL_SET="$HL_LIB:hlock:hl_patch $HA_LIB:hlalgo:ha_patch $HL2_LIB:hl2node:hl2_patch $HA2_LIB:hl2algo:ha_patch"
hl_unbind() {
  for e in $HL_SET; do t=${e%%:*}; while bound $t; do umount $t || return 1; done; done
}
hl_bind() {
  hl_unbind || return 1
  for e in $HL_SET; do t=${e%%:*}; c=${e#*:}; c=$V/${c%%:*}.so
    [ ! -f $c ] || mount -o bind,ro $c $t || return 1; done
}
# hl_ours: every copy we have is bound, and every target without a copy is stock and known not to patch
hl_ours() {
  for e in $HL_SET; do t=${e%%:*}; n=${e#*:}; n=${n%%:*}
    if [ -f $V/$n.so ]; then bound $t && [ "$(md5 $t)" = "$(md5 $V/$n.so)" ] || return 1
    else ! bound $t && [ "$(cat $V/$n.src 2>/dev/null)" = "$(md5 $t)" ] || return 1; fi
  done
}
hlock_apply() {
  [ -f $V/hlock.so ] && hl_ours && { log "camextras: horizontal lock levelling already on"; return 0; }
  for e in $HL_SET; do t=${e%%:*}; n=${e#*:}; n=${n%%:*}
    bound $t || continue
    [ -f $V/$n.so ] && [ "$(md5 $t)" = "$(md5 $V/$n.so)" ] ||
      { log "camextras: something else is bound over $t; horizontal lock won't level"; return 1; }
  done
  # some of our copies are on (an older version, or an earlier failure): take them off, then redo all
  if bound $HL_LIB || bound $HA_LIB || bound $HL2_LIB || bound $HA2_LIB; then
    tb_restart hl_unbind || { log "camextras: couldn't take the old levelling copies off"; return 1; }
  fi
  for e in $HL_SET; do t=${e%%:*}; n=${e#*:}; p=${n#*:}; n=${n%%:*}
    s=$(md5 $t); [ -n "$s" ] || continue
    [ "$(cat $V/$n.src 2>/dev/null)" = "$s" ] && continue   # (re)make a copy only for a new stock file; remember failures too
    rm -f $V/$n.so
    if r=$($p $t $V/$n.tmp); then mv $V/$n.tmp $V/$n.so; log "camextras: patched copy of ${t##*/} made ($r)"
    else rm -f $V/$n.tmp; log "camextras: ${t##*/}: $r"; fi
    echo $s > $V/$n.src
  done
  [ -f $V/hlock.so ] || { log "camextras: horizontal lock shows but won't level"; return 1; }
  for e in $HL_SET; do n=${e#*:}; c=$V/${n%%:*}.so
    [ -f $c ] && { chown 0:0 $c; chmod 644 $c; chcon u:object_r:vendor_file:s0 $c; }; done
  if tb_restart hl_bind && bound $HL_LIB; then
    log "camextras: Super steady's horizontal lock levels the horizon: $(hl_desc)"
  else
    tb_restart hl_unbind
    log "camextras: with the levelling change the camera driver didn't stay up; stock EIS back, horizontal lock won't level"
    return 1
  fi
}
hl_desc() {
  echo "recording up to $(bound $HA_LIB && echo 30 || echo 8) degrees, preview $(bound $HL2_LIB && { bound $HA2_LIB && echo "up to 30" || echo "up to 8"; } || echo "not levelled")"
}

# Audio Eraser (Gallery > video > Edit > Audio eraser). The S23's video editor engine was built with
# its audio scanner compiled out ("AudioScanner is not supported"), and the S23 lacks the S24's
# sound-separation libraries and models. Only Gallery's video editor loads the engine.
AE_LIBS="libsbs.so libtensorflowlite_gpu_delegate.so libmultisourceseparator.so libmultisourceseparator.audio.samsung.so"
AE_ETC="public.libraries-audio.samsung.txt mss_v0.23.0_VMWO_2_fp32.sorione fastScanner.tflite"
VE=libveframework.videoeditor.samsung.so
audioeraser_stage() {
  pl_check audioeraser $AE_LIBS $AE_ETC $VE || return 1
  ff_set AUDIO_CONFIG_MULTISOURCE_SEPARATOR '{FastScanning_6, SourceSeparator_4, Version_1.3.0}'
  for f in $AE_LIBS; do stage lib64 $PL/audioeraser/$f; done
  for f in $AE_ETC; do stage etc $PL/audioeraser/$f; done
  return 0
}
audioeraser_bind() {
  bind_file $PL/audioeraser/$VE /system/lib64/$VE system_lib_file && am force-stop com.sec.android.app.vepreload
  log "audioeraser: S24 video editor engine, sound-separation libraries and models on"
}

# Adaptive Color Tone (Settings > Display). Samsung compiled the S23's Settings to report it as
# unsupported (SecEADPreferenceController.getAvailabilityStatus() returns 3): patch that byte in a RAM
# copy of Settings, and add the S24's colour-tone service (com.samsung.android.sead), which drives the
# display from the S23's own colour light sensor.
EAD=EnvironmentAdaptiveDisplay
EAD_PERM=privapp-permissions-com.samsung.android.sead.xml
colortone_stage() {
  pl_check colortone $EAD.apk $EAD_PERM || return 1
  [ -z "$(ead_row)" ] || [ -f $D/files/SecSettings-ead-$(getprop ro.build.PDA).patch ] || fail "colortone: files/SecSettings-ead-$(getprop ro.build.PDA).patch missing"
  [ -f /system/priv-app/$EAD/$EAD.apk ] || stage priv-app/$EAD $PL/colortone/$EAD.apk
  stage etc/permissions $PL/colortone/$EAD_PERM
  return 0
}
colortone_bind() {
  sm=$(md5sum $SETTINGS | cut -d' ' -f1)
  set -- $(ead_row); eb=$1; SETTINGS_STOCK_MD5=${2:-none}; SETTINGS_EAD_MD5=${3:-none}
  if [ "$sm" = $SETTINGS_EAD_MD5 ]; then :   # already patched (an earlier apply this boot)
  elif [ "$sm" != $SETTINGS_STOCK_MD5 ]; then
    log "colortone: Settings isn't the $(ead_builds) build, so the Adaptive color tone switch stays hidden"; return
  else
    P=$PL/colortone/SecSettings.apk   # the patched copy stays on storage and is reused at the next boot
    if [ "$(md5sum $P 2>/dev/null | cut -d' ' -f1)" != $SETTINGS_EAD_MD5 ]; then
      cp $SETTINGS $P.new
      grep -v '^#' $D/files/SecSettings-ead-$eb.patch | while read off oct; do
        printf "\\$oct" | dd of=$P.new bs=1 seek=$off conv=notrunc 2>/dev/null; done
      [ "$(md5sum $P.new | cut -d' ' -f1)" = $SETTINGS_EAD_MD5 ] || { rm -f $P.new; fail "colortone: Settings patch gave the wrong file"; }
      mv $P.new $P
    fi
    chmod 644 $P; chcon u:object_r:system_file:s0 $P
    mount -o bind,ro $P $SETTINGS || fail "colortone: bind $SETTINGS"
    am force-stop com.android.settings
  fi
  log "colortone: Adaptive color tone on (Settings > Display)"
}
cam24fps_bind() {
  cam24_soft=${1:-}
  set -- $(cam24_row)
  if [ -z "$1" ]; then
    if [ -n "$cam24_soft" ]; then log "profps: this Camera APK has no 10x patch; the XML frame rates still apply and the 10x stays hidden"; return 0; fi
    log "cam24fps: this Camera APK isn't one the patch was made for (Camera 17.0.00.43 of $(cam24_builds)), so 24 fps stays hidden"; return 1
  fi
  CAM_STOCK_MD5=$1; CAM_PATCHED_MD5=$2; cpf=$3
  if [ -n "$cam24_soft" ] && ! grep -q BACK_SECOND_TELE $D/files/$cpf 2>/dev/null; then
    log "profps: this firmware's Camera patch doesn't unhide the 10x; the XML frame rates still apply"; return 0
  fi
  cm=$(md5sum $CAM_APK | cut -d' ' -f1)
  if [ "$cm" = $CAM_PATCHED_MD5 ]; then :   # already patched (an earlier apply this boot)
  else
    mkdir -p $PL/cam24fps
    P=$PL/cam24fps/SamsungCamera.apk   # patched copy stays on storage and is reused at the next boot
    if [ "$(md5sum $P 2>/dev/null | cut -d' ' -f1)" != $CAM_PATCHED_MD5 ]; then
      cp $CAM_APK $P.new
      grep -v '^#' $D/files/$cpf | while read off oct; do
        printf "\\$oct" | dd of=$P.new bs=1 seek=$off conv=notrunc 2>/dev/null; done
      if [ "$(md5sum $P.new | cut -d' ' -f1)" != $CAM_PATCHED_MD5 ]; then
        rm -f $P.new
        [ -n "$cam24_soft" ] && { log "profps: the Camera patch didn't match this APK; the 10x stays hidden"; return 0; }
        fail "cam24fps: Camera patch gave the wrong file"
      fi
      mv $P.new $P
    fi
    chmod 644 $P; chcon u:object_r:system_file:s0 $P
    mount -o bind,ro $P $CAM_APK || fail "cam24fps: bind $CAM_APK"
    am force-stop com.sec.android.app.camera
  fi
  if [ -n "$cam24_soft" ]; then log "profps: 10x super tele unhidden at 25/48/50 fps in Pro video"
  else log "cam24fps: 24 FPS in standard Video on (Camera > Video > FHD / UHD / 8K at 24 fps)"; fi
}

# Now Brief, Creative Studio, Call Assist: the S24 firmware ships newer builds of these three apps.
# Bind each S24 APK over the S23 firmware copy and drop its parse-cache entry (the cache is keyed on
# the folder's time, so the new APK would be ignored), then the framework restart rescans them.
# Samsung's installer refuses these platform-signed builds as normal updates. Side effect: a newer
# firmware copy replaces any Galaxy Store update of Personal Data Intelligence; after a reboot without
# this tweak, Galaxy Store offers its update again.
GAI_APPS="priv-app/SamsungSmartSuggestions app/SketchBook priv-app/CallAssistant"
galaxyai_stage() {
  for p in $GAI_APPS; do n=${p#*/}
    pl_check galaxyai $n.apk || return 1
    [ -f /system/$p/$n.apk ] || { log "galaxyai: this phone has no /system/$p/$n.apk; skipped"; return 1; }
  done
  ff_set FRAMEWORK_SUPPORT_PERSONALIZED_DATA_CORE TRUE; ff_set FRAMEWORK_CONFIG_NOW_NUDGE_VERSION 2
  ff_set COMMON_CONFIG_AI_VERSION 20263
  c2pa_stage
  return 0
}
# AI version 20263 also makes the S23's Visual Cloud Core pick its "V2" C2PA adapter (>= 20261), whose
# four natives the S23's V1 libC2paDps.camera.samsung.so lacks: it crashed with UnsatisfiedLinkError
# C2paLib.getVersion() (issue #19). floating_feature.xml is parsed in zygote, so the key can't be hidden
# from that one app. files/libC2paDps-shim.so (src/c2pashim) goes over the library instead: it maps the
# four V2 calls onto the V1 ones and forwards the rest to the original, added beside it as
# libC2paDps_s23.camera.samsung.so. Skipped when the phone's library already has the V2 calls.
C2PA=/system/lib64/libC2paDps.camera.samsung.so; C2PA_ORIG=$V/libC2paDps_s23.camera.samsung.so; C2PA_SHIM=$V/libC2paDps-shim.so
c2pa_stage() {
  c2pa=0
  [ -f $C2PA ] && [ -f $D/files/libC2paDps-shim.so ] || return 1
  if ! same_size $C2PA $D/files/libC2paDps-shim.so; then   # the firmware's library (not the shim of an earlier apply)
    grep -q C2paLib_getVersion $C2PA && { log "galaxyai: this firmware's C2PA library already has the V2 calls; left as is"; return 1; }
    cp $C2PA $C2PA_ORIG || return 1
  fi
  [ -s $C2PA_ORIG ] || return 1
  cp $D/files/libC2paDps-shim.so $C2PA_SHIM || return 1
  stage lib64 $C2PA_ORIG
  c2pa=1
}
galaxyai_bind() {
  for p in $GAI_APPS; do n=${p#*/}
    bind_file $PL/galaxyai/$n.apk /system/$p/$n.apk system_file && rm -f /data/system/package_cache/*/$n-16-*
  done
  [ "${c2pa:-0}" = 1 ] && [ -f /system/lib64/${C2PA_ORIG##*/} ] && bind_file $C2PA_SHIM $C2PA system_lib_file
  log "galaxyai: S24 Now Brief (Personal Data Intelligence), Creative Studio and Call Assist on"
}
# Settings search: the S24's Settings search app (com.android.settings.intelligence, same signature).
# Its new search bar shows; the semantic ("natural language") answers stay off, because they need
# Samsung's Semantic Search Core 4.x and both phones ship only a 1.0 stub.
SSI=priv-app/SecSettingsIntelligence
settingssearch_stage() {
  pl_check settingssearch SecSettingsIntelligence.apk || return 1
  [ -f /system/$SSI/SecSettingsIntelligence.apk ] || { log "settingssearch: this phone has no /system/$SSI; skipped"; return 1; }
  return 0
}
settingssearch_bind() {
  bind_file $PL/settingssearch/SecSettingsIntelligence.apk /system/$SSI/SecSettingsIntelligence.apk system_file &&
    rm -f /data/system/package_cache/*/SecSettingsIntelligence-16-*
  log "settingssearch: S24 Settings search on"
}

# Call screening (Phone app). Needs Samsung Language Core (com.samsung.android.offline.languagemodel);
# the S23 firmware has none and Galaxy Store refuses the S23 (9908). Install the real one (Samsung-signed)
# as an ordinary app. Persistent (survives reboot); undo with pm uninstall $LC_PKG (not
# uninstall-system-updates: it isn't an update of a system app here). Its 3.1 GB download comes in two parts (GitHub caps a file at 2 GB)
# and is deleted once installed. What works: screening, the greeting, the voice message and the AI
# summary (with this exact build, the one on APKMirror; another build's summary failed). AI replies
# untested. See docs/findings.md.
LC_PKG=com.samsung.android.offline.languagemodel
LC_APK=languagecore-4.0.01.24.apk
LC_MD5=994620f3071706391d17ff132ea16c42
lc_ok() { [ "$(lc_installed)" -ge 400000000 ] 2>/dev/null; }
lc_installed() { dumpsys package $LC_PKG 2>/dev/null | grep -m1 -oE 'versionCode=[0-9]+' | cut -d= -f2; }
callscreen_apply() {
  lc_ok && { log "callscreen: Language Core $(lc_installed) already installed"; return 0; }
  A=$PL/callscreen/$LC_APK
  [ -f $A ] || { log "callscreen: its download isn't there; skipped"; return 1; }
  [ "$(md5 $A)" = $LC_MD5 ] || { rm -rf $PL/callscreen; log "callscreen: the download is damaged; deleted, apply again to fetch it"; return 1; }
  log "callscreen: installing Samsung Language Core 4.0.01.24 (a minute or two)"
  # The installer can't read files under /data/adb, and streaming it through stdin fails: pm's -S size
  # is a 32-bit int and the APK is 3.1 GB ("Failed transaction"). Install a copy in /data/local/tmp
  T=/data/local/tmp/s23t-languagecore.apk
  [ "$(df -k /data | awk 'NR == 2 {print $4}')" -gt 3500000 ] || { log "callscreen: needs 3.5 GB free to install Language Core; skipped"; return 1; }
  cp $A $T && chmod 644 $T && chcon u:object_r:shell_data_file:s0 $T && r=$(pm install -r $T 2>&1) || r="couldn't copy it to /data/local/tmp: $r"
  rm -f $T
  case "$r" in
    *Success*) rm -rf $PL/callscreen; mkdir -p $V/undo; touch $V/undo/languagecore; log "callscreen: Language Core installed; turn on Phone > Settings > Call screening" ;;
    *) log "callscreen: install failed: $r" ;;
  esac
}

# weather: the lock screen Weather effect (rain, snow, fog or sun over the wallpaper, following Samsung
# Weather). The effect is SpriteWallpaper's WeatherWallpaperService and runs on the S23 as is, but the
# wallpaper editor (DressRoom) hides its Weather button unless LOCKSCREEN_CONFIG_WALLPAPER_STYLE has
# GENWEATHER and Samsung AI Core reports FEATURE_WALLPAPER/FEATURE_DOWNLOAD and its "visionlvm" model
# as downloaded. The S23 has no AI Core, so files/aicore-stub.apk (src/aicorestub; WX_VER = its
# versionCode) answers just those checks and runs nothing; the model only feeds the S25's AI-generated
# weather images, which the S23 can't make. A real AI Core, if installed, is left alone. The effect
# also needs the live wallpaper app enabled: debloat lists often disable it, and then Android drops the
# wallpaper ("WeatherWallpaperService is unavailable") and the lock screen goes black.
WX_PKG=com.samsung.android.aicore; WX_LIVE=com.samsung.android.wallpaper.live; WX_VER=2
WX_KEY=LOCKSCREEN_CONFIG_WALLPAPER_STYLE
wx_style() {   # the stock value plus GENWEATHER (the file may be our own copy, which has it already)
  v=$(grep -m1 -o "<SEC_FLOATING_FEATURE_$WX_KEY>[^<]*" $FF | cut -d'>' -f2 | tr ',' '\n' | grep -vx GENWEATHER | grep . | tr '\n' ',')
  echo "${v}GENWEATHER"
}
wx_code() { dumpsys package $WX_PKG 2>/dev/null | grep -m1 -oE 'versionCode=[0-9]+' | cut -d= -f2; }
wx_stub() { dumpsys package $WX_PKG 2>/dev/null | grep -q 'versionName=[^ ]*-s23tweaks'; }
wx_real() { pm path $WX_PKG >/dev/null 2>&1 && ! wx_stub; }
wx_live_off() { pm list packages -d --user 0 2>/dev/null | grep -qx "package:$WX_LIVE"; }
weather_apply() {   # after the framework restart, so the package manager is settled
  if wx_live_off; then pm enable --user 0 $WX_LIVE >/dev/null 2>&1 && log "weather: Samsung's live wallpaper app was disabled; turned it back on"; fi
  if wx_real; then log "weather: Samsung AI Core is installed; it answers the editor itself"
  elif [ "$(wx_code)" = $WX_VER ] && wx_stub; then :
  else
    T=/data/local/tmp/s23t-aicore-stub.apk   # the installer can't read files under /data/adb
    cp $D/files/aicore-stub.apk $T && chmod 644 $T && chcon u:object_r:shell_data_file:s0 $T && r=$(pm install -r $T 2>&1)
    case "$r" in *UPDATE_INCOMPATIBLE*) pm uninstall $WX_PKG >/dev/null 2>&1; r=$(pm install $T 2>&1) ;; esac   # signed by another build
    rm -f $T
    case "$r" in *Success*) ;; *) log "weather: couldn't install the AI Core stub: $r"; return 1 ;; esac
  fi
  log "weather: on; pick it in the lock screen editor (Wallpaper and style > Lock screen > Weather)"
}

# payload_fetch: download and unpack the files of each picked tweak that has them, unless the
# unpacked copy already matches the pinned checksum. A failed download skips that tweak, not the rest.
dl() {   # dl <url> <file>: curl if the phone has it, else KernelSU's busybox wget
  if command -v curl >/dev/null; then curl -fsSL --retry 2 -o "$2" "$1"
  else for b in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox; do [ -x $b ] && { $b wget -q -O "$2" "$1"; return; }; done; return 1; fi
}
payload_fetch() {
  for k in $(echo "$PAYLOADS" | awk '{print $1}' | uniq); do
    t=${k%%:*}; has $t || continue
    case $k in *:*) [ $t = hideksu ] && [ "${k#*:}" = "$(hks_row | cut -d' ' -f1)" ] || continue ;; esac
    [ $t = callscreen ] && lc_ok && continue      # installed already; its 3.1 GB isn't kept
    sums=$(echo "$PAYLOADS" | awk -v k=$k '$1 == k {print $3}' | tr '\n' ' ' | sed 's/ $//')
    [ "$(cat $PL/$t/.sha256 2>/dev/null)" = "$sums" ] && continue
    mkdir -p $V/dl
    [ $t = callscreen ] && [ "$(df -k /data | awk 'NR == 2 {print $4}')" -lt 7340032 ] &&
      { log "$t: needs 7 GB free on the phone for its download; skipped"; continue; }
    parts=""; ok=1
    for f in $(echo "$PAYLOADS" | awk -v k=$k '$1 == k {print $2}'); do
      sum=$(echo "$PAYLOADS" | awk -v f=$f '$2 == f {print $3}'); z=$V/dl/$f
      if [ "$(sha256sum $z 2>/dev/null | cut -d' ' -f1)" != "$sum" ]; then
        log "$t: downloading $f"
        rm -f $z; dl "$PAYLOAD_URL/$f" $z.part && mv $z.part $z || { rm -f $z.part; log "$t: download failed (no internet?); skipped"; ok=0; break; }
        [ "$(sha256sum $z | cut -d' ' -f1)" = "$sum" ] || { rm -f $z; log "$t: $f doesn't match its checksum; skipped"; ok=0; break; }
      fi
      parts="$parts $z"
    done
    [ $ok = 1 ] || continue
    rm -rf $PL/$t $PL/$t.new; mkdir -p $PL/$t.new
    case "$parts" in
      *.tar.gz) tar -xzf $parts -C $PL/$t.new ;;
      *) cat $parts | tar -xf - -C $PL/$t.new ;;
    esac || { rm -rf $PL/$t.new; log "$t: couldn't unpack its download; skipped"; continue; }
    echo "$sums" > $PL/$t.new/.sha256; mv $PL/$t.new $PL/$t; rm -f $parts
    if [ $t = airdrop ]; then
      chmod 755 $AIR/moseyrun $AIR/sqlite3 $AIR/pbflag
      chcon u:object_r:system_file:s0 $AIR/moseyrun   # its exec into mosey_server's domain needs this label
    fi
    log "$t: files ready"
  done
}

# stage everything, mount the layers, then the single-file binds; returns 0 if any payload tweak ran
payload_apply() {
  ran=1
  has camerahdr && camerahdr_stage && ran=0
  has hdr2023 && hdr2023_check && { ran=0; h23=1; }
  has audioeraser && audioeraser_stage && { ran=0; ae=1; }
  has colortone && colortone_stage && { ran=0; ct=1; }
  has galaxyai && galaxyai_stage && { ran=0; gai=1; }
  has settingssearch && settingssearch_stage && { ran=0; ssi=1; }
  layers_mount
  [ "${h23:-0}" = 1 ] && hdr2023_bind
  [ "${ae:-0}" = 1 ] && audioeraser_bind
  return $ran   # the APKs are bound later, by apk_binds
}
# An app whose APK is swapped crashes if it starts before the framework restart: Android still has the
# stock APK's parsed manifest, and its resource IDs point at the wrong entries in the new APK
# (SmartSuggestions: "Failed to parse XML configuration from Canadian_dollar"). So bind the APKs
# right before the restart, not ahead of the ~30 s of camera driver restarts.
apk_binds() {
  [ "${ct:-0}" = 1 ] && colortone_bind
  [ "${gai:-0}" = 1 ] && galaxyai_bind
  [ "${ssi:-0}" = 1 ] && settingssearch_bind
  return 0
}

# Settings > Battery > Battery information shows health only when an authenticated battery IC
# (sec_auth) exists. Present one whose values mirror /efs/FactoryApp, so syncs are no-ops.
# batt_full_status_usage is optional: Android uses it only when the kernel reports BFSU, and some
# phones (e.g. an S918B) don't have it. Without it the auth IC simply has no such node.
BATT_EFS="HwParamBattQR batt_beginning_date asoc batt_discharge_level"
battery_auth() {
  PS=/sys/class/power_supply; T=/dev/s23tweaks_ps; E=/efs/FactoryApp
  mounted $PS tmpfs && { log "battery: auth IC already present"; return 0; }
  for f in $BATT_EFS; do
    [ -f $E/$f ] || { log "battery: $E/$f missing; skipping the battery health page"; return 1; }
  done
  [ -e $PS/sec_auth ] && { log "battery: this phone already has a battery auth IC"; return 0; }
  mkdir -p $T
  mount -t tmpfs -o mode=755,context=u:object_r:sysfs:s0 s23tweaks_ps $T
  for e in $(ls $PS); do ln -s "$(readlink $PS/$e)" $T/$e; done
  mkdir $T/sec_auth
  mount -t tmpfs -o mode=755,uid=1000,gid=1000,context=u:object_r:sysfs_battery:s0 s23tweaks_auth $T/sec_auth
  w() { printf '%s' "$1" > $T/sec_auth/$2; }
  w "$(cat $E/HwParamBattQR)" qr_code; w 1 presence; w 1 batt_auth
  w "$(cat $E/batt_beginning_date)" first_use_date; w 0 fai_expired; w "$(cat $E/asoc)" asoc
  w "$(cat $E/batt_discharge_level)" batt_discharge_level
  [ -f $E/batt_full_status_usage ] && w "$(cat $E/batt_full_status_usage)" batt_full_status_usage
  chown 1000:1000 $T/sec_auth/*; chmod 664 $T/sec_auth/*
  mount --rbind $T $PS || fail "power_supply overlay"
  log "battery: auth IC presented"
}

# ---------- CSC (callrec, india): any sales code; the paths come from csc_paths ----------
# csc_unbind: drop the module's binds so the stock files show again (an apply always starts from stock)
csc_unbind() {
  for f in $CSCF $CCF $CUST $PRISM; do [ -n "$f" ] && bound $f && umount $f; done
  return 0
}
csc_bind() { cp "$1" $R/$3; chmod 644 $R/$3; chcon u:object_r:vendor_configs_file:s0 $R/$3; mount --bind $R/$3 "$2" || fail "bind $2"; }
# callrec_make <out>: the phone's own stock cscfeature.xml, decoded, with call recording allowed in every
# FeatureSet (multi-country files have one per country). Refuses a layout it can't edit line by line.
REC_KEYS="<CscFeature_VoiceCall_ConfigRecording>RecordingAllowed</CscFeature_VoiceCall_ConfigRecording>
<CscFeature_VoiceCall_SupportVoiceRecordingDuringHoldCall>TRUE</CscFeature_VoiceCall_SupportVoiceRecordingDuringHoldCall>"
callrec_make() {
  chmod 755 $OMCDEC 2>/dev/null; $OMCDEC $CSCF > $1.dec 2>>$L || { log "callrec: couldn't decode $CSCF"; rm -f $1.dec; return 1; }
  sets=$(grep -c '</FeatureSet>' $1.dec); lines=$(grep -cE '^[[:space:]]*</FeatureSet>[[:space:]]*$' $1.dec)
  if ! grep -q '</SamsungMobileFeature>' $1.dec || [ "$sets" = 0 ] || [ "$sets" != "$lines" ] || grep -q '<CscFeature_.*<CscFeature_' $1.dec; then
    log "callrec: $CSCF isn't laid out one feature per line; skipped"; rm -f $1.dec; return 1
  fi
  echo "$REC_KEYS" | awk 'NR == FNR { k[++n] = $0; next }
    /<CscFeature_VoiceCall_ConfigRecording>|<CscFeature_VoiceCall_SupportVoiceRecordingDuringHoldCall>/ { next }
    /^[ \t]*<\/FeatureSet>/ { i = $0; sub(/<.*/, "", i); for (j = 1; j <= n; j++) print i "  " k[j] }
    { print }' - $1.dec > $1 && rm -f $1.dec
  [ "$(grep -c 'ConfigRecording>RecordingAllowed<' $1)" = "$sets" ] || { log "callrec: editing $CSCF failed"; rm -f $1; return 1; }
}
callrec_apply() {
  csc_unbind; mkdir -p $R
  callrec_make $R/csc_callrec.xml || return 1
  chmod 644 $R/csc_callrec.xml; chcon u:object_r:vendor_configs_file:s0 $R/csc_callrec.xml
  mount --bind $R/csc_callrec.xml $CSCF || fail "bind $CSCF"
  log "callrec: call recording on in $SC's carrier config (Phone app > Settings > Record calls)"
}
# india: the INS (India) files of S918BXXUAGZIF over the phone's own sales code's. Only the config files
# are swapped; the sales code (sales_code.dat, omc.info, mps_code.dat) is never touched.
# Present the phone as the Indian S23 Ultra so Samsung Wallet's India features and the 6 GHz hotspot
# work. Runtime only (see the IN_MODEL comment); the marker lets csc_paths/why_not tell our spoofed INS
# from a phone that is genuinely INS.
india_identity() {
  RP=/data/adb/ksu/bin/resetprop
  [ -x $RP ] || { log "india: KernelSU resetprop not found; device identity unchanged (Samsung Wallet may show 'not supported')"; return 1; }
  for p in $IN_MODEL_PROPS; do [ -n "$(getprop $p)" ] && $RP $p $IN_MODEL; done
  for p in $IN_SALES_PROPS; do [ -n "$(getprop $p)" ] && $RP $p INS; done
  $RP ro.csc.countryiso_code IN
  touch $V/india_identity
  for a in com.samsung.android.spay com.samsung.android.spayfw; do am force-stop $a 2>/dev/null; done
  log "india: device reported as $IN_MODEL / INS, country IN (Samsung Wallet India + 6 GHz hotspot)"
  log "india: if Samsung Wallet still says 'not supported', clear its storage (Settings > Apps > Samsung Wallet > Storage > Clear data) and reopen it"
}
# Samsung's CID Manager (com.samsung.android.cidmanager) pops "Switch to <carrier>?" when the SIM's
# carrier wants a different sales code than the phone reports. With india forcing INS on, that nags on
# every boot and the dialog won't dismiss. The dialog is drawn by the com.android.phone process (shared
# uid 1001) under this package's SYSTEM_ALERT_WINDOW appop, so disabling the package alone isn't enough -
# denying that appop is the lever that actually blocks it. We do both. pm/appops persist across reboots,
# so india_simprompt_on undoes it when india isn't picked. Marker: $V/india_simprompt (so we only
# restore what we disabled).
CIDMGR=com.samsung.android.cidmanager
india_simprompt_off() {
  pm disable-user --user 0 $CIDMGR 2>/dev/null
  appops set $CIDMGR SYSTEM_ALERT_WINDOW ignore 2>/dev/null
  for p in $(pidof $CIDMGR 2>/dev/null); do kill $p 2>/dev/null; done
  touch $V/india_simprompt
  log "india: carrier-switch prompt (CID Manager) suppressed"
}
india_simprompt_on() {
  [ -e $V/india_simprompt ] || return 0
  pm enable $CIDMGR 2>/dev/null
  appops set $CIDMGR SYSTEM_ALERT_WINDOW allow 2>/dev/null
  rm -f $V/india_simprompt
  log "india: carrier-switch prompt restored (india not picked)"
}
india_apply() {
  csc_unbind; mkdir -p $R; I=$D/files/ins
  csc_bind $I/cscfeature.xml $CSCF csc_ins.xml
  [ -f $CCF ] && csc_bind $I/customer_carrier_feature.json $CCF ccf_ins.json
  [ -f $CUST ] && csc_bind $I/customer.xml $CUST customer_ins.xml
  # prism: full copy of the phone's folder (its sales_code.dat etc. unchanged) plus INS keystrings/images
  if [ -n "$PRISM" ] && [ -d $PRISM ]; then
    rm -rf $R/prism; mkdir $R/prism; cp -p $PRISM/* $R/prism/
    for f in $I/prism/*; do n=${f##*/}; case $n in INS_keystrings.dat) n=${SC}_keystrings.dat ;; esac; cp $f $R/prism/$n; done
    chmod 755 $R/prism; chmod 644 $R/prism/*; chcon -R u:object_r:vendor_configs_file:s0 $R/prism
    mount --bind $R/prism $PRISM || fail "bind $PRISM"
  fi
  log "india: INS carrier config on (sales code stays $SC on disk)"
  india_identity
  india_simprompt_off
}

# Samsung's Mobile Hotspot offers 6 GHz only when SemWifiApServiceImpl.supportWifiAp6GBasedOnCountry() says
# so, and that wants the CSC country (ro.csc.countryiso_code) on a hard-coded list (isRegionFor6GCountry).
# Most S23 CSCs aren't on it, though the hardware and the stock hostapd run a 6 GHz hotspot fine.
# Setting the country to IN passes, but Samsung's servers then see a non-Indian model in India and refuse
# it: Samsung Wallet won't open (v1.3.3 and earlier did that). Instead this uses the method's own debug
# override, vendor.wifiap.6gbandcountry=1. system_server honours it only when SemWifiManager.MHSDBG is true,
# which is SemWifiApCust.DBG, read once from ro.product_ship=false. So: ro.product_ship false and the
# override (resetprop), restart the framework, wait for system_server to report 6g_Country:true (that
# call latches the flag), then put ro.product_ship back. The country is never changed. Until a reboot,
# Samsung's debug logging stays on in the processes that started during the restart (logcat only).
# With india the country is IN anyway, so nothing is needed.
H6_PROP=vendor.wifiap.6gbandcountry
h6_offered() { dumpsys sem_wifi 2>/dev/null | grep -q '6g_Country:true'; }
# before the framework restart: returns 0 when the restart is needed for it
hotspot6g_pre() {
  RP=/data/adb/ksu/bin/resetprop; [ -x $RP ] || { log "hotspot6g: KernelSU resetprop not found; skipped"; return 1; }
  [ "$(getprop ro.csc.countryiso_code)" = IN ] && { log "hotspot6g: CSC country is IN, which already offers 6 GHz"; return 1; }
  $RP $H6_PROP 1
  h6_offered && { log "hotspot6g: already on"; return 1; }
  H6_SHIP=$(getprop ro.product_ship); [ "$H6_SHIP" = false ] && H6_SHIP=""
  [ -n "$H6_SHIP" ] && $RP ro.product_ship false
  H6_WAIT=1
  log "hotspot6g: Samsung's 6 GHz hotspot override set; it loads with the framework restart (country stays $(getprop ro.csc.countryiso_code))"
}
# after the restart
hotspot6g_post() {
  [ "${H6_WAIT:-0}" = 1 ] || return 0
  RP=/data/adb/ksu/bin/resetprop; n=30; until h6_offered; do n=$((n-1)); [ $n = 0 ] && break; sleep 2; done
  [ -n "$H6_SHIP" ] && $RP ro.product_ship "$H6_SHIP"
  if h6_offered; then log "hotspot6g: Mobile hotspot > Band now offers 6 GHz (needs WPA3); country unchanged, Samsung Wallet unaffected"
  else log "hotspot6g: this firmware didn't take Samsung's 6 GHz override; 6 GHz not offered"; fi
}

# display: Always On Display auto brightness. The AOD app (BrightnessManager) builds its brightness curve
# from two framework tables, config_autoBrightnessLevels_doze (lux) and config_autoBrightnessDisplayValuesNits_doze
# (nits). The S23 ships both empty, so every light reading logs "getBrightnessValues not matched!" and the
# AOD gets 0 nits: the wallpaper on AOD shows bright, then drops to the minimum, whatever the room light.
# files/aodbright.apk (built from src/aodbright) is a static overlay with the S24 Ultra's two tables and
# nothing else. The AOD app reads them through Resources.getSystem(), which only has the overlays zygote
# found in the partitions' overlay folders when it started: so it goes on /product/overlay (an overlay
# layer, nothing written) and the framework restarts.
AODB=/product/overlay/s23tweaks-aodbright.apk
aodb_apply() {
  [ -f $AODB ] && { log "display: AOD brightness curve already in"; return 1; }
  [ -f $D/files/aodbright.apk ] || { log "display: files/aodbright.apk missing; AOD brightness curve skipped"; return 1; }
  T=/dev/s23tweaks_aodb; mkdir -p $T; mounted $T tmpfs || mount -t tmpfs -o mode=755 s23tweaks_aodb $T
  cp $D/files/aodbright.apk $T/${AODB##*/} && chmod 644 $T/${AODB##*/} && chcon -R u:object_r:system_file:s0 $T || fail "aodbright copy"
  mount -t overlay s23tweaks_product_overlay -o ro,lowerdir=$T:/product/overlay /product/overlay || fail "overlay on /product/overlay"
  log "display: AOD brightness curve added (/product/overlay)"
}
# Samsung's package manager skips it ("Package is not in allowed list"), so cmd overlay never lists it; zygote
# still loads it into every process's system resources, which is all the AOD app reads. On = system_server has it.
aodb_on() { grep -q s23tweaks-aodbright /proc/$(pidof system_server)/maps 2>/dev/null; }

# HideKSU: hide the KernelSU manager (me.weishu.kernelsu) from third-party apps, so their root/tamper
# checks (CRED, banking apps) can't enumerate it and stop crashing. The patched services.jar carries a
# helper (s23tweaks/H) called at the top of AppsFilterBase.shouldFilterApplicationInternal: it filters
# the manager out for any caller with appId >= 10000 except df.root (DFRoot loads root at boot) and the
# launcher (so its icon still shows). Nothing is injected into the apps themselves, so an app's own
# /proc/self/maps scan stays clean. Takes effect on a framework restart (system_server reloads the jar).
KSUJAR=/system/framework/services.jar
# The patched jar replaces the whole file, so it only goes on a phone whose stock services.jar is the exact
# one it was made from, whatever the firmware name. One row per stock jar: md5 stock, md5 patched, where
# it came from. tools/hideksupatch.sh makes the payload for another jar and prints its row; each payload
# is a PAYLOADS line "hideksu:<stock md5>".
HIDEKSU_JARS="30d17f5d60b0d42585b97a94412f6e12 f4c5966939637df194bb465478234fc3 SM-S918W S918WVLU8GZIF (XAC)
7dc62286f9f0675f84459943cdc397b6 a5449f73103be635f03fb6fdaf9f7d98 SM-S918B (INS)
c438dd27a76486855d01e74379e13b5d f4918c7454965788ecc0c9003cbea941 SM-S918U1"
# the row for the services.jar in place now (stock, or our patched copy bound over it)
hks_row() { m=$(md5 $KSUJAR); echo "$HIDEKSU_JARS" | awk -v m="$m" '$1 == m || $2 == m'; }
hideksu_apply() {
  [ -f $PL/hideksu/services.jar ] || { log "hideksu: payload missing; skipped"; return 1; }
  hideksu_on && { log "hideksu: patched services.jar already loaded"; return 1; }
  T=/dev/s23tweaks_svc; mkdir -p $T; mounted $T tmpfs || mount -t tmpfs -o mode=755 s23tweaks_svc $T
  bound $KSUJAR && umount $KSUJAR 2>/dev/null   # drop any earlier bind so one clean layer remains
  set -- $(hks_row)
  [ "$(md5 $KSUJAR)" = "$1" ] || { log "hideksu: this phone's services.jar isn't one a patch was made from; skipped"; return 1; }
  [ "$(md5 $PL/hideksu/services.jar)" = $2 ] || { log "hideksu: the downloaded services.jar isn't the one for this phone's; skipped"; return 1; }
  cp $PL/hideksu/services.jar $T/services.jar && chmod 644 $T/services.jar && chcon u:object_r:system_file:s0 $T $T/services.jar || fail "hideksu stage"
  mount -o bind $T/services.jar $KSUJAR || fail "bind services.jar"
  pidof system_server > $T/ss_at_bind   # hideksu_on: a system_server started after this loaded the jar
  log "hideksu: patched services.jar bound; the KernelSU manager is hidden from apps after the restart"
}
# On = the system_server that's running mapped OUR bound jar (its inode), not the stock one. Before a
# restart the bind is in place but the stock jar is still loaded, so the inode won't match yet.
hideksu_on() {
  # system_server runs the jar's dex from memory (the stock odex no longer matches), so the jar never shows
  # in its maps; instead: our jar is bound and system_server has restarted since it was bound
  bound $KSUJAR && [ -f /dev/s23tweaks_svc/ss_at_bind ] || return 1
  ss=$(pidof system_server) && [ "$ss" != "$(cat /dev/s23tweaks_svc/ss_at_bind)" ]
}

# hideksu part 2: hide the module's mounts from apps that shouldn't see them. The module binds every
# tweak into init's mount namespace, so every app inherits them and a detector flags them as
# suspicious/inconsistent mounts. KernelSU's own umount is all-or-nothing (every non-root app at spawn),
# which would also strip the mounts from the Samsung apps the tweaks modify (Camera, Gallery, Settings,
# the galaxyai apps, ...) and break them. files/hidemnt (src/hidemnt) instead watches process spawns via
# the kernel's process-event connector and, by install origin, hides the mounts only from apps that
# never consume them: every user-installed app (banking, root detectors) is hidden from by default,
# while every preinstalled system/Samsung app keeps the mounts (a system app updated via the store keeps
# FLAG_SYSTEM, so updated consumers are safe too). It enters only that app's mount namespace and detaches
# the module's mounts there (one native setns+umount pass, fast enough to finish before the app's own code
# runs). init and every other process keep the mounts. $HIDEAPPS is an optional override list: a plain
# package force-hides a system app, a leading '-' force-keeps a user-installed one; re-apply or reboot
# (or just edit it - the watcher reloads it on change) to apply.
HIDEMNT=$D/files/hidemnt
HIDEAPPS=$V/hide-apps.txt; HIDESYS=$V/hidemnt-system.txt
seed_hideapps() {
  [ -f $HIDEAPPS ] && return
  cat > $HIDEAPPS <<'EOF'
# hideksu overrides (optional). By default the module's mounts are hidden from every user-installed app
# (banking, root detectors) and kept for every preinstalled system/Samsung app, so you usually need
# nothing here. One package per line, '#' starts a comment. The watcher reloads this file when it changes.
#   <package>     force-hide this app even if it is a system app
#   -<package>    force-keep this app (don't hide) even if it is user-installed
# Examples:
#   com.google.android.gms
#   -com.example.myrootedapp
EOF
  chmod 644 $HIDEAPPS
}
hidemnt_count() { grep -cvE '^[[:space:]]*(#|$)' $HIDEAPPS 2>/dev/null || echo 0; }
hidemnt_running() { ps -A -o ARGS 2>/dev/null | grep -q "[h]idemnt daemon"; }
hidemnt_stop() {
  for p in $(ps -A -o PID,ARGS 2>/dev/null | grep "[h]idemnt daemon" | awk '{print $1}'); do kill "$p" 2>/dev/null; done
  rm -f $V/hidemnt.pid
}
hidemnt_start() {
  [ -x $HIDEMNT ] || { chmod 755 $HIDEMNT 2>/dev/null; [ -x $HIDEMNT ] || { log "hideksu: files/hidemnt missing; app mount-hiding skipped"; return 1; }; }
  seed_hideapps
  hidemnt_stop                          # restart so an edited override list takes effect
  # The system packages, from the package manager: One UI 7+ stores packages.xml as binary XML (ABX),
  # which hidemnt can't read. Apps installed later aren't system apps, so the list needn't be refreshed
  # until an update adds system apps, and every boot rewrites it. -u: also those removed for this user.
  pm list packages -s -u 2>/dev/null | sed -n 's/^package://p' > $HIDESYS.tmp && mv $HIDESYS.tmp $HIDESYS
  ns=$(grep -c . $HIDESYS 2>/dev/null); ns=${ns:-0}
  setsid $HIDEMNT daemon $HIDEAPPS $HIDESYS </dev/null >/dev/null 2>&1 &
  echo $! > $V/hidemnt.pid
  n=$(hidemnt_count)
  [ "$n" -gt 0 ] 2>/dev/null && ov=" ($n override(s) in ${HIDEAPPS##*/})" || ov=""
  if [ "$ns" -lt 32 ] 2>/dev/null; then
    log "hideksu: warning: the package manager listed only $ns system apps; hiding mounts only from the apps in ${HIDEAPPS##*/}"
  else
    log "hideksu: hiding the module's mounts from user-installed apps ($ns system apps keep them)$ov"
  fi
}

# After a framework restart SystemUI can come up while Wi-Fi is still reconnecting and then drop the
# Wi-Fi *signal* icon from the status bar (Wi-Fi Calling stays), even though Wi-Fi is connected. Cycling
# the Wi-Fi slot through SystemUI's icon blocklist makes it rebuild the slot from the live state; it's a
# display-only nudge and never touches the radio. The user's existing blocklist is preserved exactly, and
# if they've deliberately hidden the Wi-Fi icon (wifi already in the list) it's left alone.
statusbar_wifi_refresh() {
  cur=$(settings get secure icon_blacklist 2>/dev/null); [ "$cur" = null ] && cur=""
  case ",$cur," in *,wifi,*) return 0 ;; esac
  [ -n "$cur" ] && new="$cur,wifi" || new="wifi"
  settings put secure icon_blacklist "$new" 2>/dev/null || return 0
  sleep 1
  if [ -n "$cur" ]; then settings put secure icon_blacklist "$cur"; else settings delete secure icon_blacklist; fi
  log "status bar: nudged SystemUI to redraw the Wi-Fi icon after the framework restart"
}

# dual5g: 5G standalone on both SIMs at once (5G+5G DSDS). The modem's Qualcomm policyman decides it:
# device_config.xml has <msim_config mode="5G_PLUS_5G" list="msim_plmns"/>, and global_defines.xml limits
# msim_plmns to 460-* 712-* (China, Costa Rica). Anywhere else the modem runs 5G_PLUS_4G, and
# disable_sa_ndds.xml takes the SA bands away from the SIM that isn't the data SIM. This adds the MCCs of
# the SIMs in the phone to msim_plmns. It is a file in the modem's own storage (EFS), so unlike the other
# tweaks it stays after a reboot: dual5g_restore puts the original back. files/efstool (src/efstool) reads
# and writes EFS through the stock /vendor/bin/diag_socket_log; policyman reads the file when the modem
# boots, so a write is followed by a modem-only restart (remoteproc, ~15 s without signal).
D5G=$V/dual5g; D5G_F=/policyman/global_defines.xml; D5G_SD=/sdcard/Download/s23tweaks-modem-backup
EFST=$D/files/efstool   # module files ship 0644; cleanup runs from /dev after the module folder is gone
if [ -f $EFST ]; then [ -x $EFST ] || chmod 755 $EFST 2>/dev/null; else EFST=/dev/s23tweaks_efstool; fi
d5g_mccs() {   # MCCs of the SIMs and of the networks they're on; countries with several MCCs get all of them
  for n in $(getprop gsm.sim.operator.numeric | tr ',' ' ') $(getprop gsm.operator.numeric | tr ',' ' '); do
    m=$(echo "$n" | cut -c1-3)
    case $m in
      404|405|406) echo 404 405 406 ;;                       # India (a carrier's SIM and towers can differ)
      310|311|312|313|314|315|316) echo 310 311 312 313 314 315 316 ;;   # United States
      440|441) echo 440 441 ;;                               # Japan
      234|235) echo 234 235 ;;                               # United Kingdom
      [0-9][0-9][0-9]) echo $m ;;
    esac
  done | tr ' ' '\n' | grep -E '^[0-9]{3}$' | sort -u | tr '\n' ' '
}
d5g_line() { grep -v '<!--' "$1" | grep '<plmn_list name="msim_plmns"'; }   # skips the commented-out stock line
d5g_list() { d5g_line "$1" | sed -E 's/.*<plmn_list name="msim_plmns"[^>]*>([^<]*)<\/plmn_list>.*/\1/'; }
d5g_added() { grep -m1 -o 's23tweaks dual5g added:[ 0-9]*' "$1" 2>/dev/null | cut -d: -f2; }
d5g_strip() {   # $1 -> $2 without what dual5g added (used only when there is no stock backup)
  rm_list=$(d5g_added "$1")
  awk -v rm="$rm_list" 'BEGIN { n = split(rm, a, " ") }
    /s23tweaks dual5g added:/ { next }
    /<plmn_list name="msim_plmns"/ && !/<!--/ { for (i = 1; i <= n; i++) gsub(" " a[i] "-\\*", "") }
    { print }' "$1" > "$2"
}
d5g_modem_restart() {
  r=""; for x in /sys/class/remoteproc/remoteproc*; do grep -q 'remoteproc-mss' $x/name 2>/dev/null && r=$x; done
  [ -n "$r" ] || { log "dual5g: can't find the modem's remoteproc; reboot the phone to use the new setting"; return 1; }
  log "dual5g: restarting the modem so it reads the new setting (no signal for ~15 s)"
  echo stop > $r/state 2>/dev/null; sleep 2
  for i in 1 2 3; do echo start > $r/state 2>/dev/null; wait_for 20 [ "$(cat $r/state)" = running ] && break; done
  [ "$(cat $r/state)" = running ] || { log "dual5g: the modem didn't come back; reboot the phone"; return 1; }
  wait_for 60 sh -c 'getprop gsm.sim.state | grep -q LOADED'; log "dual5g: modem back up"
}
d5g_put() {   # $1 new file, $2 the file it replaces (rollback). Write, read back, compare; roll back on mismatch
  $EFST put "$1" $D5G_F 2>>$L && $EFST get $D5G_F $R/d5g_check.xml 2>>$L && cmp -s "$1" $R/d5g_check.xml && return 0
  log "dual5g: the write didn't verify; putting the previous file back"
  $EFST put "$2" $D5G_F 2>>$L && $EFST get $D5G_F $R/d5g_check.xml 2>>$L && cmp -s "$2" $R/d5g_check.xml &&
    { log "dual5g: previous file restored"; return 1; }
  log "dual5g: COULD NOT RESTORE the modem file. The original is in $D5G/stock and $D5G_SD; run 'tweaks.sh dual5g-restore', or use *#27663368378# > ETC > MCFG > MCFG HW & SW RELOAD"
  return 1
}
d5g_backup_stock() {   # once, before the first write ever; never overwritten
  [ -f $D5G/stock/global_defines.xml ] && return 0
  mkdir -p $D5G/stock
  if [ -n "$(d5g_added $1)" ]; then d5g_strip $1 $D5G/stock/global_defines.xml   # ours already: rebuild the original
  else cp $1 $D5G/stock/global_defines.xml; fi
  for f in device_config.xml disable_sa_ndds.xml; do $EFST get /policyman/$f $D5G/stock/$f 2>/dev/null; done
  mkdir -p $D5G_SD && cp $D5G/stock/* $D5G_SD/ && cat > $D5G_SD/README.txt <<EOF
Original modem files from before s23-ultra-tweaks' "dual5g" tweak changed /policyman/global_defines.xml
(model $(getprop ro.product.model), firmware $(getprop ro.build.PDA), saved $(date '+%Y-%m-%d %H:%M')).
To put the original back: un-pick dual5g and apply, or run as root: sh <module folder>/tweaks.sh dual5g-restore
Without the module: dial *#27663368378# > ETC > MCFG > MCFG HW & SW RELOAD (rewrites the modem's stock config).
EOF
  log "dual5g: original modem file backed up to $D5G/stock and $D5G_SD"
}
dual5g_apply() {
  mkdir -p $R $D5G
  wait_for 90 sh -c 'getprop gsm.sim.state | grep -q LOADED' || { log "dual5g: skipped: no SIM is ready"; return 1; }
  sleep 3; mccs=$(d5g_mccs)
  [ -n "$mccs" ] || { log "dual5g: skipped: the SIMs report no network code yet (try again later)"; return 1; }
  $EFST get $D5G_F $R/d5g_live.xml 2>>$L || { log "dual5g: can't read $D5G_F from the modem"; return 1; }
  [ "$(d5g_line $R/d5g_live.xml | wc -l)" = 1 ] || { log "dual5g: skipped: this modem has no single msim_plmns list in $D5G_F"; return 1; }
  d5g_backup_stock $R/d5g_live.xml || { log "dual5g: couldn't back up the original; not changing anything"; return 1; }
  cur=" $(d5g_list $R/d5g_live.xml) "; add=""
  for m in $mccs; do case "$cur" in *" $m-* "*) ;; *) add="$add $m" ;; esac; done
  if [ -z "$add" ]; then
    log "dual5g: on; the modem already allows 5G on both SIMs for $(echo $mccs | sed 's/[0-9][0-9]*/&-*/g')"
    echo "$cur" > $D5G/applied; return 0
  fi
  cp $R/d5g_live.xml $D5G/before-$(date +%Y%m%d-%H%M%S).xml   # every write gets its own backup
  ours=$(echo $(d5g_added $R/d5g_live.xml) $add | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')
  plmns=$(echo $add | sed 's/[0-9][0-9]*/&-*/g')
  awk -v plmns="$plmns" -v ours="$ours" '
    /s23tweaks dual5g added:/ { next }
    /<plmn_list name="msim_plmns"/ && !/<!--/ { sub(/ *<\/plmn_list>/, " " plmns " </plmn_list>"); print
      print "    <!-- s23tweaks dual5g added: " ours " -->"; next }
    { print }' $R/d5g_live.xml > $R/d5g_new.xml
  [ "$(d5g_line $R/d5g_new.xml | wc -l)" = 1 ] && grep -q '</policy>' $R/d5g_new.xml || { log "dual5g: building the new file failed; nothing changed"; return 1; }
  d5g_put $R/d5g_new.xml $R/d5g_live.xml || return 1
  log "dual5g: msim_plmns is now$(d5g_list $R/d5g_new.xml)"
  echo " $(d5g_list $R/d5g_new.xml) " > $D5G/applied
  d5g_modem_restart
}
dual5g_restore() {   # put the original modem file back
  mkdir -p $R
  $EFST get $D5G_F $R/d5g_live.xml 2>>$L || { log "dual5g: can't read $D5G_F from the modem"; return 1; }
  if [ -f $D5G/stock/global_defines.xml ]; then src=$D5G/stock/global_defines.xml
  elif [ -f $D5G_SD/global_defines.xml ]; then src=$D5G_SD/global_defines.xml
  elif [ -n "$(d5g_added $R/d5g_live.xml)" ]; then d5g_strip $R/d5g_live.xml $R/d5g_orig.xml; src=$R/d5g_orig.xml
  else log "dual5g: no backup and no change of ours in the modem file; nothing to restore"; rm -f $D5G/applied; return 0; fi
  if cmp -s $src $R/d5g_live.xml; then log "dual5g: the modem file is already the original"; rm -f $D5G/applied; return 0; fi
  d5g_put $src $R/d5g_live.xml || return 1
  rm -f $D5G/applied; log "dual5g: original modem file restored (msim_plmns:$(d5g_list $src))"
  d5g_modem_restart
}

restart_framework() {
  old=$(pidof system_server); log "restarting the Android framework (screen goes black for ~30 s)"
  setprop ctl.restart zygote
  n=150; until p=$(pidof system_server) && [ -n "$p" ] && [ "$p" != "$old" ] && pm path android >/dev/null 2>&1; do
    n=$((n-1)); [ $n = 0 ] && fail "framework did not come back"; sleep 1; done
  sleep 10; log "framework back"
  # The restart parsed the bound APKs and cached the result in package_cache, under the stock app's name
  # and newer than the stock file. After a reboot (binds gone) Android would keep using that parse for
  # the stock app, and the app crashes looking for the other build's resources. Drop those entries so
  # the next boot parses the stock app again.
  for a in $(awk '$2 ~ /\.apk$/ {print $2}' /proc/mounts | sort -u); do
    n=${a%/*}; n=${n##*/}; rm -f /data/system/package_cache/*/$n-[0-9]*
  done
}

# ---------- Why a tweak can't run on this phone, and whether it's on (probe, apply log) ----------
mod_ver() { if [ $MODULE = 1 ]; then grep -m1 '^version=' $D/module.prop | cut -d= -f2; else echo "script (install.sh)"; fi; }
phone_facts() {
  model=$(getprop ro.product.model); build=$(getprop ro.build.PDA); csc=$(getprop ro.csc.sales_code)
  gms=$(dumpsys package com.google.android.gms 2>/dev/null | grep -m1 -oE 'versionCode=[0-9]+' | cut -d= -f2)
  lcv=$(lc_installed)
}
# why_not TWEAK: print why it can't run on this phone (nothing if it can). Needs phone_facts.
why_not() {
  case "$model" in SM-S918*) ;; *) echo "this is for the Galaxy S23 Ultra (SM-S918*), not $model"; return ;; esac
  case $1 in
    airdrop|wifi7)
      kernel_supported || { echo "needs firmware $(echo $AIRDROP_FW | sed 's/ /, /g') (this phone runs $build)"; return; }
      if [ $1 = airdrop ] && ! kernel_stock && ! cfg80211_stock; then
        echo "this kernel ships its own Wi-Fi stack (cfg80211.ko built for $(cfg80211_vermagic | grep . || echo "an unknown kernel"), not $AIRDROP_KBASE*), which the S24 Wi-Fi driver can't register with; Wi-Fi 7 and the 6 GHz hotspot still work"; return
      fi
      [ "${gms:-0}" -ge $GMS_MIN ] || echo "needs Google Play services 26.11 or newer" ;;
    callrec|india)
      [ -f "$CSCF" ] || { echo "can't find this phone's carrier config (mdc.system.path is '$CSYS')"; return; }
      if [ $1 = india ]; then
        [ "$SC" = INS ] && [ ! -e $V/india_identity ] && { echo "this phone's sales code is INS already"; return; }
        [ "$(getprop ro.build.version.oneui | cut -c1)" = 9 ] || echo "needs One UI 9 (the INS files come from One UI 9 firmware)"
      else
        [ -f $OMCDEC ] || echo "files/omcdec is missing"
      fi ;;
    battery)
      for f in $BATT_EFS; do [ -f /efs/FactoryApp/$f ] || { echo "this phone has no $f in /efs/FactoryApp"; return; }; done ;;
    colortone)
      [ -n "$(ead_row)" ] || echo "needs firmware $(ead_builds) (it patches that build's Settings app; this phone runs $build)" ;;
    hotspot6g) [ -x /data/adb/ksu/bin/resetprop ] || echo "needs KernelSU's resetprop" ;;
    weather)
      pm path $WX_LIVE >/dev/null 2>&1 || { echo "this phone has no Samsung live wallpaper app ($WX_LIVE)"; return; }
      pm path com.samsung.android.app.dressroom >/dev/null 2>&1 || echo "this phone has no Wallpaper and style app (DressRoom)" ;;
    camerahdr) grep -q "<SEC_FLOATING_FEATURE_$CH_KEY>[^<]" $FF 2>/dev/null || echo "this firmware has no $CH_KEY camera setting to add the HDR steps to" ;;
    videosoftening|afcontrol|aelimit) grep -q '</SecFloatingFeatureSet>' $FF 2>/dev/null || echo "this firmware's $FF can't be edited" ;;
    tenbit) [ -f $TB_LIB ] || echo "this phone has no $TB_LIB" ;;
    hideksu)
      set -- $(hks_row); m=$(md5 $KSUJAR)
      [ -n "$1" ] && { [ "$m" = $1 ] || bound $KSUJAR; } ||
        { echo "this phone's /system/framework/services.jar (md5 $m) isn't one a patch was made from ($(echo "$HIDEKSU_JARS" | cut -d' ' -f3- | tr '\n' ',' | sed 's/,$//; s/,/, /g')); tools/hideksupatch.sh can make one"; return; }
      pm path me.weishu.kernelsu >/dev/null 2>&1 || echo "the KernelSU manager (me.weishu.kernelsu) isn't installed, so there's nothing to hide" ;;
    hdr2023) for f in $H23_LIBS; do [ -f /system/lib64/$f ] || { echo "this phone has no /system/lib64/$f to replace"; return; }; done ;;
    logvideo|camextras|wideflash|prowbtint|zoomrocker|slowmoaf|extstorage|anamorphic|profps|dofadapter|mirror8k|longrec) grep -q '</resources>' $CF 2>/dev/null || echo "this firmware's $CF can't be edited" ;;
    slowmo4k120)
      grep -q '</resources>' $CF 2>/dev/null || { echo "this firmware's $CF can't be edited"; return; }
      grep -q 'BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_120FPS' $CF 2>/dev/null || echo "this firmware has no 4K120 entry to enable in Slow motion" ;;
    cam24fps)
      [ -f $CAM_APK ] || { echo "this phone has no $CAM_APK"; return; }
      pm path com.sec.android.app.camera 2>/dev/null | grep -q "^package:$CAM_APK$" || { echo "uninstall Samsung Camera updates first so stock $CAM_APK is active"; return; }
      set -- $(cam24_row)
      [ -n "$1" ] || { echo "this phone's Samsung Camera isn't one the 24 fps patch was made for (Camera 17.0.00.43 of $(cam24_builds)); tools/cam24patch.py can make one"; return; }
      [ -f $D/files/$3 ] || { echo "patch file $3 missing"; return; }
      grep -q '</resources>' $CF 2>/dev/null || echo "this firmware's $CF can't be edited" ;;
    galaxyai)
      for p in $GAI_APPS; do [ -f /system/$p/${p#*/}.apk ] || { echo "this phone has no /system/$p/${p#*/}.apk to replace"; return; }; done ;;
    settingssearch) [ -f /system/$SSI/SecSettingsIntelligence.apk ] || echo "this phone has no /system/$SSI to replace" ;;
    dual5g)
      [ -x $EFST ] || { echo "files/efstool is missing"; return; }
      [ -x /vendor/bin/diag_socket_log ] || { echo "this firmware has no /vendor/bin/diag_socket_log to reach the modem with"; return; }
      [ "$(getprop persist.radio.multisim.config)" = dsds ] || echo "needs a dual-SIM phone in dual standby (DSDS) mode" ;;
    callscreen)
      [ "${lcv:-0}" -ge 400000000 ] 2>/dev/null || [ "$(df -k /data | awk 'NR == 2 {print $4}')" -ge 7340032 ] ||
        echo "needs about 7 GB free on the phone for its 3.1 GB download" ;;
  esac
}
# is_on TWEAK: is it in effect right now?
is_on() {
  case $1 in
    airdrop) [ -d /sys/module/wonder ] && bound /system_ext/bin ;;
    battery) mounted /sys/class/power_supply tmpfs ;;
    features) bound $FF && grep -q SETTINGS_SUPPORT_AUTO_POWER_ON_OFF $FF 2>/dev/null ;;
    india) bound $CSCF && grep -q '<SalesCode>INS<' $CSCF 2>/dev/null ;;
    callrec) bound $CSCF && grep -q 'ConfigRecording>RecordingAllowed<' $CSCF 2>/dev/null ;;
    hotspot6g) h6_offered ;;
    wifi7) bound $WPAS && bound $INI ;;
    display) bound $FF && grep -q "<SEC_FLOATING_FEATURE_LCD_CONFIG_AOD_FULLSCREEN>1<" $FF 2>/dev/null ;;
    logvideo) bound $CF && grep -q 'name="SUPPORT_LOG_VIDEO" value="true"' $CF 2>/dev/null ;;
    camextras) bound $CF && grep -q 'name="SUPPORT_SUPER_STEADY_HORIZONTAL_LOCK" value="true"' $CF 2>/dev/null ;;
    wideflash) bound $CF && grep -q 'name="SUPPORT_FLASH_IN_WIDE_LENS" value="true"' $CF 2>/dev/null ;;
    prowbtint) bound $CF && grep -q 'name="SUPPORT_PRO_WHITE_BALANCE_TINT" value="true"' $CF 2>/dev/null ;;
    zoomrocker) bound $CF && grep -q 'name="SUPPORT_VIDEO_MODE_ZOOM_ROCKER" value="true"' $CF 2>/dev/null ;;
    videosoftening) grep -q '<SEC_FLOATING_FEATURE_CAMERA_SUPPORT_VIDEO_SOFTENING>TRUE<' $FF 2>/dev/null ;;
    afcontrol) grep -q '<SEC_FLOATING_FEATURE_CAMERA_SUPPORT_AFSPEED>TRUE<' $FF 2>/dev/null && grep -q '<SEC_FLOATING_FEATURE_CAMERA_SUPPORT_AFSENSITIVITY>TRUE<' $FF 2>/dev/null ;;
    aelimit) grep -q '<SEC_FLOATING_FEATURE_CAMERA_SUPPORT_AUTO_EXPOSURE_LIMIT>TRUE<' $FF 2>/dev/null ;;
    slowmoaf) bound $CF && grep -q 'name="SUPPORT_SLOW_MOTION_AF_DURING_RECORDING" value="true"' $CF 2>/dev/null && grep -q '<SEC_FLOATING_FEATURE_CAMERA_SUPPORT_AF_DURING_SLOWMOTION_RECORDING>TRUE<' $FF 2>/dev/null ;;
    extstorage) bound $CF && grep -q 'BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_60FPS.*external-storage-support="true"' $CF 2>/dev/null ;;
    anamorphic) bound $CF && grep -q 'name="SUPPORT_CAMERA_ASSISTANT_ANAMORPHIC_LENS" value="true"' $CF 2>/dev/null ;;
    profps) bound $CF && grep -q 'name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_25FPS" value="true"' $CF 2>/dev/null ;;
    slowmo4k120) bound $CF && grep -q 'name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_120FPS".*slow_motion' $CF 2>/dev/null ;;
    dofadapter) bound $CF && grep -q 'name="SUPPORT_CAMERA_ASSISTANT_DOF_ADAPTER" value="true"' $CF 2>/dev/null ;;
    mirror8k) bound $CF && grep -q 'name="SUPPORT_CAMERA_ASSISTANT_RECORDING_8K_WHEN_MIRRORING" value="true"' $CF 2>/dev/null ;;
    longrec) bound $CF && grep -q 'name="MAX_SEAMLESS_ZOOM_RECORDING_TIME_LIMIT_IN_OVERHEAT_CONDITION" value="3600"' $CF 2>/dev/null &&
      grep -q 'name="MIN_RECORDING_TIME_TO_ENABLE_LOW_POWER_MODE" value="3600"' $CF 2>/dev/null ;;
    autoframe) grep -q "<SEC_FLOATING_FEATURE_CAMERA_CONFIG_AUTOFRAMING>uhd<" $FF 2>/dev/null ;;
    bargein) grep -q "<SEC_FLOATING_FEATURE_BIXBY_CONFIG_BARGEIN_PARAM_MODE>2<" $FF 2>/dev/null ;;
    weather) grep -q "<SEC_FLOATING_FEATURE_$WX_KEY>[^<]*GENWEATHER" $FF 2>/dev/null && pm path $WX_PKG >/dev/null 2>&1 && ! wx_live_off ;;
    settingssearch) bound /system/$SSI/SecSettingsIntelligence.apk ;;
    callscreen) [ "$(lc_installed)" -ge 400000000 ] 2>/dev/null ;;
    vulkan) [ "$(getprop debug.hwui.renderer)" = skiavk ] ;;
    camerahdr) grep -q 'mfhdr.arcsoft.v4' $FF 2>/dev/null && [ -f /system/lib64/liblow_light_hdr.arcsoft.so ] ;;
    audioeraser) [ -f /system/etc/fastScanner.tflite ] ;;
    hdr2023) bound /system/lib64/libae_bracket_hdr.arcsoft.so && bound /system/lib64/libhybrid_high_dynamic_range.arcsoft.so ;;
    colortone) bound $SETTINGS ;;
    tenbit) bound $TB_LIB && [ "$(md5 $TB_LIB)" = "$(md5 $V/tenbit.so)" ] ;;
    cam24fps) bound $CAM_APK && bound $CF && grep -q 'name="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_24FPS".*supported-mode="[^"]*video' $CF 2>/dev/null ;;
    galaxyai) bound /system/priv-app/SamsungSmartSuggestions/SamsungSmartSuggestions.apk ;;
    hideksu) hideksu_on ;;
    dual5g) [ -f $D5G/applied ] ;;
    *) return 1 ;;
  esac
}

case "$1" in
apply)
  [ "$(id -u)" = 0 ] || { echo "needs root" >&2; exit 1; }
  to_root_cgroup
  if [ "${S23T_LOCKED:-0}" = 1 ] && [ -d $APPLY_LOCK ]; then echo $$ > $APPLY_LOCK/pid   # handed over by start
  else take_lock || { echo "another apply is already running (see $L)" >&2; exit 3; }; fi
  trap 'rm -rf $APPLY_LOCK' EXIT
  TWEAKS=" $2 "; : > $L
  log "applying:$TWEAKS"
  for x in $2; do case " $TWEAK_IDS " in *" $x "*) ;; *) fail "unknown tweak: $x" ;; esac; done
  echo "$2" > $V/choices
  has wifi7 && ! has airdrop && fail "wifi7 needs airdrop (the S24 Wi-Fi driver)"
  phone_facts; keep=""
  log "module $(mod_ver) on $model $build ($csc), Android $(getprop ro.build.version.release), kernel $(uname -r)"
  for x in $2; do
    w=$(why_not $x); if [ -n "$w" ]; then log "$x: skipped: $w"; else keep="$keep $x"; fi
  done
  TWEAKS=" $keep "
  # what an apply doesn't undo (binds, kernel modules, properties) stays until a reboot: say so
  for x in $STAYS_TILL_REBOOT; do
    has $x && continue
    { is_on $x || { [ $x = colortone ] && [ -f /system/priv-app/$EAD/$EAD.apk ]; }; } &&
      log "$x: not picked, but still on from an earlier apply in this boot; a reboot turns it off"
  done
  payload_fetch   # before the AirDrop driver swap takes Wi-Fi down
  if has airdrop; then
    has wifi7 && wifi7_bind   # before the driver loads, so it reads the MLO settings
    airdrop_kernel
    if has wifi7 && [ "${W7_OFF:-0}" = 0 ]; then [ "${AK_LOADED:-0}" = 1 ] && [ "${W7_INI_NEW:-0}" = 1 ] && wifi7_reload; wifi7_check; fi
  fi
  restart=0
  has airdrop && airdrop_overlays && restart=1
  payload_apply && restart=1   # camerahdr hdr2023 audioeraser colortone galaxyai: before the flag file
  has battery && { ff_tags="$ff_tags BATTERY_SUPPORT_BSOH_SETTINGS SETTINGS_ENABLE_EU_BATTERY_REGULATORY"; battery_auth; }
  has features && ff_tags="$ff_tags SETTINGS_SUPPORT_AUTO_POWER_ON_OFF AUDIO_SUPPORT_VOIP_SOUND_LOUDER"
  if has display; then  # the lock screen wallpaper on Always On Display
    # Not LCD_CONFIG_VIVIDNESS / VIVIDPLUS (the S24's Vividness slider): the S23 panel has no vividness
    # control (the slider writes to a missing /sys/class/mdnie/mdnie/vividness), and VIVIDPLUS 1 makes
    # Vivid screen mode put SurfaceFlinger in sRGB instead of the panel's wide gamut: washed-out colours.
    ff_set LCD_CONFIG_AOD_FULLSCREEN 1; ff_set LCD_CONFIG_AOD_BRIGHTNESS_ANIMATION 1
    # Keep AOD_BRIGHTNESS_ANIMATION: without it the wallpaper on AOD can't be seen on the S23. With it
    # the wallpaper starts bright and dims sharply after a few seconds, to the S23's AOD brightness: the
    # AOD app's light-sensor curve is empty on the S23 (0 nits). aodb_apply adds the S24 Ultra's curve.
    aodb_apply && restart=1
  elif [ -f $AODB ]; then log "display: not picked, but the AOD brightness curve stays until a reboot"
  fi
  if has logvideo; then
    ff_set CAMERA_CONFIG_LOG_VIDEO V1.0; ff_set GALLERY_SUPPORT_LOG_CORRECT_COLOR TRUE
    cf_add="$cf_add
$CF_LOG"
    loglut_bind
  fi
  has camextras && cf_add="$cf_add
$CF_HLOCK"
  has wideflash && cf_add="$cf_add
$CF_WIDEFLASH
$CF_WIDEFLASH_CA"
  has prowbtint && cf_add="$cf_add
$CF_PROWBTINT"
  has zoomrocker && cf_add="$cf_add
$CF_ZOOMROCKER"
  has slowmoaf && cf_add="$cf_add
$CF_SLOWMOAF"
  has anamorphic && cf_add="$cf_add
$CF_ANAMORPHIC
$CF_ANAMORPHIC_SCALER"
  has profps && cf_add="$cf_add
$CF_PROFPS"
  has slowmo4k120 && cf_slowmo_modes="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_120FPS BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_120FPS"
  has dofadapter && cf_add="$cf_add
$CF_DOFADAPTER"
  has mirror8k && cf_add="$cf_add
$CF_MIRROR8K"
  has longrec && cf_add="$cf_add
$CF_LONGREC"
  has cam24fps && cf_video_modes="BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_24FPS BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_24FPS BACK_CAMCORDER_RESOLUTION_FEATURE_MAP_7680X4320_24FPS FRONT_CAMCORDER_RESOLUTION_FEATURE_MAP_3840X2160_24FPS FRONT_CAMCORDER_RESOLUTION_FEATURE_MAP_1920X1080_24FPS"
  camfeat_apply && restart=1
  if has cam24fps; then cam24fps_bind
  elif has profps; then cam24fps_bind soft   # only where the APK patch is compatible; one bind either way
  fi
  # 4K auto framing (untested): the S24's UHD setting for auto framing in video
  has autoframe && ff_set CAMERA_CONFIG_AUTOFRAMING uhd
  # Camera Assistant: video softening (Off / Medium / High) and the AF speed/sensitivity controls
  has videosoftening && ff_set CAMERA_SUPPORT_VIDEO_SOFTENING TRUE
  has afcontrol && { ff_set CAMERA_SUPPORT_AFSPEED TRUE; ff_set CAMERA_SUPPORT_AFSENSITIVITY TRUE; }
  has aelimit && ff_set CAMERA_SUPPORT_AUTO_EXPOSURE_LIMIT TRUE
  has slowmoaf && ff_set CAMERA_SUPPORT_AF_DURING_SLOWMOTION_RECORDING TRUE
  has tenbit && tenbit_apply   # restarts only the camera driver
  if has camextras; then hlock_apply   # restarts only the camera driver
  elif bound $HL_LIB || bound $HA_LIB || bound $HL2_LIB || bound $HA2_LIB; then tb_restart hl_unbind && log "camextras: not picked; stock EIS back"; fi
  # Bixby barge-in (untested): talk over Bixby while it answers, as on the S24
  has bargein && ff_set BIXBY_CONFIG_BARGEIN_PARAM_MODE 2
  # Lock screen Weather effect: the editor's Weather button (weather_apply adds the AI Core stub)
  has weather && ff_set $WX_KEY "$(wx_style)"
  # Draw apps with Vulkan instead of OpenGL (Samsung's libhwui ignores ro.hwui.use_vulkan)
  has vulkan && { setprop debug.hwui.renderer skiavk; log "vulkan: apps render with Skia on Vulkan"; restart=1; }
  has hideksu && hideksu_apply && restart=1   # patched services.jar: needs a framework restart to load
  ff_apply && restart=1
  if has india; then india_apply && { setprop ctl.restart ril-daemon; log "india: mobile network restarting"; restart=1; }
  elif has callrec; then callrec_apply && restart=1; fi
  has india || india_simprompt_on   # restore the carrier-switch prompt we suppressed for india
  if has hotspot6g; then hotspot6g_pre && restart=1   # after india, which may set the country to IN
  elif [ "$(getprop $H6_PROP)" = 1 ]; then /data/adb/ksu/bin/resetprop $H6_PROP 0 && log "hotspot6g: not picked; 6 GHz override off"; fi
  apk_binds
  [ $restart = 1 ] && restart_framework
  if has hideksu; then hidemnt_start                                   # after the restart, so it catches the respawned apps
  elif hidemnt_running; then hidemnt_stop; log "hideksu: app mount-hiding stopped (not picked)"; fi
  has hotspot6g && hotspot6g_post
  has camextras && directorsview_pref
  if has wideflash; then wideflash_pref
  elif [ -f $WF_UNDO ]; then wideflash_unpref && log "wideflash: not picked; the camera's wide-lens flash setting is back as it was"; fi
  has callscreen && callscreen_apply
  if has weather; then weather_apply
  elif wx_stub; then pm uninstall $WX_PKG >/dev/null 2>&1 && log "weather: not picked; AI Core stub uninstalled"; fi
  if has dual5g; then dual5g_apply
  elif [ -f $D5G/applied ]; then log "dual5g: not picked; putting the original modem file back"; dual5g_restore; fi
  has airdrop && airdrop_post
  [ $restart = 1 ] && statusbar_wifi_refresh   # the framework restart can drop the Wi-Fi status-bar icon
  on=""; off=""; for x in $2; do if is_on $x; then on="$on $x"; else off="$off $x"; fi; done
  log "on:${on:- none}"
  [ -n "$off" ] && log "not on:$off (the reason is in the lines above)"
  touch /dev/s23tweaks_applied   # lets the boot apply know this boot already has them
  log "DONE"
  ;;
start)
  [ "$(id -u)" = 0 ] || { echo "needs root" >&2; exit 1; }
  [ -n "$2" ] || { echo "usage: tweaks.sh start \"<tweaks>\"" >&2; exit 2; }
  to_root_cgroup
  # take the lock here and hand it to apply, so two quick starts can't both go ahead
  take_lock || { echo "another apply is already running (see $L)" >&2; exit 3; }
  : > $L
  S23T_LOCKED=1 nsenter -t 1 -m -- setsid sh $D/tweaks.sh apply "$2" </dev/null >/dev/null 2>&1 &
  n=30; while [ $n -gt 0 ] && [ "$(cat $APPLY_LOCK/pid 2>/dev/null)" = $$ ]; do n=$((n-1)); sleep 0.1; done
  echo "started; progress in $L"
  ;;
probe)
  # One line of JSON for the WebUI and install.sh. Values never contain quotes or backslashes.
  phone_facts; kern=$(uname -r); android=$(getprop ro.build.version.release)
  ver=$( [ $MODULE = 1 ] && grep -m1 '^version=' $D/module.prop | cut -d= -f2 || echo script)
  j() { w=$(why_not $1); printf '{"id":"%s","available":%s,"why":"%s","active":%s}' "$1" \
          "$( [ -z "$w" ] && echo true || echo false)" "$w" "$(is_on $1 && echo true || echo false)"; }
  sim=$(getprop gsm.sim.operator.numeric | cut -d, -f1)   # MCC+MNC of the first SIM; 404/405 = India
  printf '{"version":"%s","module":%s,"phone":{"model":"%s","firmware":"%s","csc":"%s","android":"%s","kernel":"%s","gms":%s,"sim":"%s"},' \
    "$ver" "$( [ $MODULE = 1 ] && echo true || echo false)" "$model" "$build" "$csc" "$android" "$kern" "${gms:-0}" "$sim"
  printf '"picked":"%s","autostart":%s,"applying":%s,"tweaks":[' "$(cat $V/choices 2>/dev/null)" \
    "$( [ -f $V/autostart ] && echo true || echo false)" "$( lock_alive && echo true || echo false)"
  sep=""; for x in $TWEAK_IDS; do printf '%s%s' "$sep" "$(j $x)"; sep=","; done
  printf ']}\n'
  ;;
loop)
  # init can't start mosey_server (its .rc isn't loaded on this boot). moseyrun starts it the way
  # mosey.rc does: uid system, groups system+inet, ambient NET_ADMIN/NET_RAW, u:r:mosey_server:s0
  # (as root it fails to open /dev/tun). It's a lazy service that exits when idle: restart it.
  while true; do $AIR/moseyrun; sleep 1; done
  ;;
guard)
  # If the Wi-Fi firmware ever crashes, the S24 driver's recovery leaks the AirDrop interface and
  # ~50 s later the phone hard-resets. Stop the daemon, keep the log, and reboot cleanly instead.
  # dmesg -W blocks until the kernel logs something new and prints only new lines, so this waits without
  # using CPU. (Reading the whole kernel log every second instead cost about a third of an idle phone's CPU.)
  until dmesg -W | grep -q -m1 "Received firmware hang event"; do sleep 5; done   # retry only if dmesg ends
  log "Wi-Fi firmware crashed: saving the kernel log and rebooting"
  echo "the Wi-Fi firmware crashed before the last reboot (log saved in $V)" > $V/boot.skip
  ps -A -o PID,ARGS | grep "[t]weaks.sh loop" | while read pid rest; do kill $pid; done
  pkill mosey_server; sleep 3; dmesg > $V/fwcrash_$(cut -d. -f1 /proc/uptime).txt; sync
  reboot
  ;;
status)
  echo "saved choices: $(cat $V/choices 2>/dev/null); $(sh $D/tweaks.sh autostart)"
  echo "airdrop:  modules [$(grep -oE '^(wonder|bwfix) ' /proc/modules | tr -d '\n')]," \
       "Mosey $(bound /system_ext/bin && echo on || echo off), daemon $(running loop && echo running || echo stopped)," \
       "Mosey service $(service check com.google.android.moseyservice.IMoseyService/default | grep -q ': found' && echo registered || echo "not registered")"
  echo "features: $(bound $FF && grep -oE '<SEC_FLOATING_FEATURE_(SETTINGS_SUPPORT_AUTO_POWER_ON_OFF|AUDIO_SUPPORT_VOIP_SOUND_LOUDER)>' $FF | sed 's/<SEC_FLOATING_FEATURE_//; s/>//' | tr '\n' ' ' || echo off)"
  echo "battery:  auth IC $(mounted /sys/class/power_supply tmpfs && echo presented || { [ -e /sys/class/power_supply/sec_auth ] && echo "real (presence $(cat /sys/class/power_supply/sec_auth/presence 2>/dev/null), auth $(cat /sys/class/power_supply/sec_auth/batt_auth 2>/dev/null))" || echo off; }),"\
       "flags [$(grep -oE '<SEC_FLOATING_FEATURE_(BATTERY_SUPPORT_BSOH_SETTINGS|SETTINGS_ENABLE_EU_BATTERY_REGULATORY)>[A-Z]*' $FF | sed 's/<SEC_FLOATING_FEATURE_//; s/>/=/' | tr '\n' ' ')]"
  echo "display:  $(bound $FF && grep -q '<SEC_FLOATING_FEATURE_LCD_CONFIG_AOD_FULLSCREEN>1<' $FF && echo on || echo off), AOD brightness curve $(aodb_on && echo on || { [ -f $AODB ] && echo "added, waiting for a framework restart" || echo off; })"
  echo "logvideo: $(is_on logvideo && echo on || echo off), Gallery LUTs $(bound $LV && echo on || echo off)"
  echo "camextras: horizon lock $(is_on camextras && echo on || echo off), levelling $(bound $HL_LIB && echo "on ($(hl_desc))" || echo off), Director's view $(grep -q '<string name="directors_view_mode">1</string>' $CAM_PREFS 2>/dev/null && echo shown || echo hidden)"
  echo "autoframe: $(grep -o '<SEC_FLOATING_FEATURE_CAMERA_CONFIG_AUTOFRAMING>[^<]*' $FF | cut -d'>' -f2 | grep . || echo stock)"
  echo "bargein:  $(grep -q '<SEC_FLOATING_FEATURE_BIXBY_CONFIG_BARGEIN_PARAM_MODE>2<' $FF && echo on || echo off)"
  echo "weather:  flag $(grep -q "<SEC_FLOATING_FEATURE_$WX_KEY>[^<]*GENWEATHER" $FF && echo on || echo off), AI Core $(wx_stub && echo "stub $(wx_code)" || { wx_real && echo Samsung || echo none; }), live wallpaper app $(wx_live_off && echo disabled || echo enabled)"
  echo "settingssearch: $(bound /system/$SSI/SecSettingsIntelligence.apk && echo S24 || echo stock)"
  echo "callscreen: Language Core $(dumpsys package $LC_PKG 2>/dev/null | grep -m1 -oE 'versionName=[^ ]+' | cut -d= -f2)"
  echo "camerahdr: libraries $([ -f /system/lib64/liblow_light_hdr.arcsoft.so ] && echo on || echo off), list entries $(grep -q 'mfhdr.arcsoft.v4' $FF && echo on || echo off)"
  echo "hdr2023:  $(same_size /system/lib64/libae_bracket_hdr.arcsoft.so $PL/hdr2023/libae_bracket_hdr.arcsoft.so && same_size /system/lib64/libhybrid_high_dynamic_range.arcsoft.so $PL/hdr2023/libhybrid_high_dynamic_range.arcsoft.so && echo "2023 engines" || echo stock)"
  echo "tenbit:   front-camera 10-bit $(is_on tenbit && echo on || echo off)"
  echo "cam24fps: Camera $(bound $CAM_APK && echo patched || echo stock), 24fps video modes $(is_on cam24fps && echo on || echo off)"
  echo "wideflash: $(is_on wideflash && echo on || echo off)"
  echo "prowbtint: $(is_on prowbtint && echo on || echo off)"
  echo "zoomrocker: $(is_on zoomrocker && echo on || echo off)"
  echo "videosoftening: $(is_on videosoftening && echo on || echo off)"
  echo "afcontrol: $(is_on afcontrol && echo on || echo off)"
  echo "aelimit: $(is_on aelimit && echo on || echo off)"
  echo "slowmoaf: $(is_on slowmoaf && echo on || echo off)"
  echo "extstorage: $(is_on extstorage && echo on || echo off)"
  echo "anamorphic: $(is_on anamorphic && echo on || echo off)"
  echo "profps: $(is_on profps && echo on || echo off), 10x Camera $(cam24_profps_on && echo "APK patched" || echo "XML only")"
  echo "slowmo4k120: $(is_on slowmo4k120 && echo on || echo off)"
  echo "dofadapter: $(is_on dofadapter && echo on || echo off)"
  echo "mirror8k: $(is_on mirror8k && echo on || echo off)"
  echo "longrec:  $(is_on longrec && echo on || echo off)"
  echo "audioeraser: $([ -f /system/etc/fastScanner.tflite ] && echo on || echo off), engine $(same_size /system/lib64/$VE $PL/audioeraser/$VE && echo S24 || echo stock)"
  echo "colortone: Settings $(bound $SETTINGS && echo patched || echo stock), service $([ -f /system/priv-app/$EAD/$EAD.apk ] && echo on || echo off)"
  echo "galaxyai: $(for p in $GAI_APPS; do n=${p#*/}; printf '%s=%s ' $n "$(same_size /system/$p/$n.apk $PL/galaxyai/$n.apk && echo S24 || echo stock)"; done)C2PA=$(same_size $C2PA $D/files/libC2paDps-shim.so && echo shim || echo stock)"
  echo "vulkan:   renderer $(getprop debug.hwui.renderer | grep . || echo default)"
  echo "hideksu:  $(hideksu_on && echo "on (KernelSU manager hidden from apps)" || { bound $KSUJAR && echo "bound, waiting for a framework restart" || echo off; }); mounts $(hidemnt_running && { n=$(hidemnt_count); [ "$n" -gt 0 ] 2>/dev/null && echo "hidden from user-installed apps ($n override(s))" || echo "hidden from user-installed apps"; } || echo "visible to apps")"
  echo "wifi7:    wpa_supplicant $(bound $WPAS && echo S24 || echo stock), driver MLO settings $(bound $INI && echo on || echo off)"
  echo "6ghz ap:  $(h6_offered && echo offered || echo "not offered") (CSC country $(getprop ro.csc.countryiso_code), override $(getprop $H6_PROP | grep . || echo unset))"
  echo "csc:      $SC $(bound $CSCF && { grep -q '<SalesCode>INS<' $CSCF && echo "with the INS config" || echo "with call recording"; } || echo stock) ($CSYS)"
  echo "reported: model $(getprop ro.product.model), csc $(getprop ro.csc.sales_code), country $(getprop ro.csc.countryiso_code)$([ -e $V/india_identity ] && [ "$(getprop ro.product.model)" = $IN_MODEL ] && echo " (india identity on)")"
  echo "dual5g:   $([ -f $D5G/applied ] && echo "on (modem msim_plmns:$(cat $D5G/applied))" || echo off)$([ -f $D5G/stock/global_defines.xml ] && echo "; original backed up in $D5G/stock")"
  ;;
cleanup)
  # Undo everything that outlives a reboot, then delete the state folder. module/uninstall.sh runs this
  # from a copy in /dev when the module is removed. It waits for Android and the first unlock, since
  # the Play services database and the Camera settings sit in app storage that's locked until then.
  n=0; until [ "$(getprop sys.boot_completed)" = 1 ] && [ "$(getprop sys.user.0.ce_available)" = true ] &&
    pm path android >/dev/null 2>&1; do n=$((n+1)); [ $n -gt 4320 ] && exit 1; sleep 5; done
  say() { /system/bin/log -t s23tweaks "cleanup: $*" 2>/dev/null; echo "$*"; }   # Android's log: log() here is ours
  [ -x $AIR/sqlite3 ] && sh "$0" unflag >/dev/null 2>&1 && say "Play services flag overrides removed"
  if [ -f $V/undo/languagecore ] && pm path $LC_PKG >/dev/null 2>&1; then
    pm uninstall $LC_PKG >/dev/null 2>&1 && say "Language Core uninstalled"
    for k in call_screening call_screening_auto_screening_onoff call_screening_voice call_screening_voice_speech_rate; do
      settings delete system $k >/dev/null 2>&1; done
  fi
  wx_stub && pm uninstall $WX_PKG >/dev/null 2>&1 && say "AI Core stub uninstalled"
  if [ -f $V/undo/directors_view ] && [ -f $CAM_PREFS ]; then
    v=$(cat $V/undo/directors_view); am force-stop com.sec.android.app.camera; mkdir -p $R
    if [ "$v" = absent ]; then grep -v 'name="directors_view_mode"' $CAM_PREFS > $R/camprefs.new
    else sed "s|<string name=\"directors_view_mode\">[^<]*</string>|<string name=\"directors_view_mode\">$v</string>|" $CAM_PREFS > $R/camprefs.new; fi
    grep -q '</map>' $R/camprefs.new && cat $R/camprefs.new > $CAM_PREFS && say "Camera setting restored"
  fi
  wideflash_unpref && say "Camera's wide-lens flash setting restored"
  # parsed manifests of the apps the tweaks swap, in case a restart cached one; Android re-parses them
  for n in SamsungSmartSuggestions SketchBook CallAssistant SecSettingsIntelligence SecSettings EnvironmentAdaptiveDisplay MoseyApp SamsungCamera; do
    rm -f /data/system/package_cache/*/$n-[0-9]*; done
  if [ -e $V/india_simprompt ]; then
    pm enable $CIDMGR >/dev/null 2>&1; appops set $CIDMGR SYSTEM_ALERT_WINDOW allow >/dev/null 2>&1
    say "carrier-switch prompt (CID Manager) restored"
  fi
  if [ -f $D5G/applied ] || [ -f $D5G/stock/global_defines.xml ]; then
    mkdir -p $R; : > $L
    if dual5g_restore; then say "dual5g: original modem file restored"
    else say "dual5g: COULD NOT restore the modem file; the original stays in $D5G_SD"; cp -r $D5G $D5G_SD/state 2>/dev/null; fi
  fi
  rm -f /dev/s23tweaks_efstool
  rm -f /data/adb/service.d/s23tweaks.sh
  cd /; rm -rf $V
  say "done; the next reboot removes what's still mounted"
  case "$0" in /dev/*) rm -f "$0" ;; esac
  exit 0
  ;;
report)
  # One text file for bug reports: phone and firmware, what each tweak found, the stock values and files
  # it depends on, the last logs and recent crash summaries. Leaves out the serial number, email
  # addresses, MAC addresses and long numbers (IMEI). Saved in Download; the last line is its path.
  phone_facts; mkdir -p /sdcard/Download
  out=/sdcard/Download/s23-ultra-tweaks-report-$(date +%Y%m%d-%H%M%S).txt
  ver() { dumpsys package $1 2>/dev/null | grep -m1 -oE 'versionName=[^ ]+' | cut -d= -f2; }
  sec() { printf '\n===== %s =====\n' "$1"; }
  sn=$(getprop ro.serialno)
  {
    echo "s23-ultra-tweaks report, $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "module $(mod_ver)"
    sec phone
    echo "model $model, firmware $build, CSC $csc, Android $(getprop ro.build.version.release) (One UI $(o=$(getprop ro.build.version.oneui); echo $((o / 10000)).$((o / 100 % 100)))), patch $(getprop ro.build.version.security_patch)"
    echo "kernel $(uname -r)"
    echo "root: $(/data/adb/ksud -V 2>/dev/null || echo "no KernelSU ksud"), SELinux $(getenforce)"
    echo "apps: Play services $(ver com.google.android.gms) ($gms), Camera $(ver com.sec.android.app.camera), Settings $(ver com.android.settings), Quick Share $(ver com.samsung.android.app.sharelive)"
    echo "SIM operator $(getprop gsm.sim.operator.numeric | cut -d, -f1), free on /data $(df -h /data | awk 'NR == 2 {print $4}')"
    sec "tweaks (available, why not, active)"
    sh $D/tweaks.sh probe | tr '{' '\n' | grep '"id"'
    sec status
    sh $D/tweaks.sh status
    sec "what the tweaks depend on"
    echo "airdrop/wifi7 kernel match: $(kernel_stock && echo yes || { kernel_override && echo "no, allowed by allow-any-kernel" || echo "no (supported: $AIRDROP_FW)"; })"
    echo "camera-feature.xml ($(bound $CF && echo "module's copy" || echo stock)):"
    grep -E 'LOG_VIDEO|PREVIEW_LUT|HORIZONTAL_LOCK|AUTO_FRAMING|MULTI_RECORDING' $CF | sed 's/^ */  /'
    echo "floating_feature.xml ($(bound $FF && echo "module's copy" || echo stock)):"
    grep -oE '<SEC_FLOATING_FEATURE_(CAMERA_CONFIG_(LOG_VIDEO|AUTOFRAMING|VENDOR_LIB_INFO)|GALLERY_SUPPORT_LOG_CORRECT_COLOR|LCD_CONFIG_(VIVIDNESS|VIVIDPLUS|AOD_FULLSCREEN)|BIXBY_CONFIG_BARGEIN_PARAM_MODE|BATTERY_SUPPORT_BSOH_SETTINGS|SETTINGS_SUPPORT_AUTO_POWER_ON_OFF)>[^<]*' $FF |
      sed 's/<SEC_FLOATING_FEATURE_/  /; s/>/=/' | cut -c1-200
    echo "camera driver: $(md5 $TB_LIB) $(bound $TB_LIB && echo "(module's copy, made from $(cat $V/tenbit.src 2>/dev/null))")"
    echo "mounts from the module:"
    awk '$4 ~ /s23tweaks/ || $10 ~ /s23tweaks/ {print "  " $5 " <- " $4 " (" $9 ")"}' /proc/self/mountinfo | sort -u | head -80
    sec display
    echo "screen mode $(settings get system screen_mode_setting) (4 = Vivid, 1 = Natural), vividness $(settings get system vividness_intensity), Adaptive color tone $(settings get system ead_enabled)"
    echo "SurfaceFlinger: $(dumpsys SurfaceFlinger 2>/dev/null | grep -m1 'Current color mode' | sed 's/^ *//'), persist.sys.sf.native_mode $(getprop persist.sys.sf.native_mode)"
    echo "panel white point (sensorRGB) $(cat /sys/class/mdnie/mdnie/sensorRGB 2>/dev/null), night mode $(cat /sys/class/mdnie/mdnie/night_mode 2>/dev/null)"
    sec "AirDrop and Wi-Fi"
    echo "Wi-Fi: $(cmd wifi status 2>/dev/null | grep -m1 -oE 'Wifi is (enabled|disabled)'), $(cmd wifi status 2>/dev/null | grep -m1 -oE 'Wi-Fi standard: [^,]*'), driver $(cat /sys/module/wlan/version 2>/dev/null || grep -m1 -oE '^kiwi_v2 [0-9]+' /proc/modules)"
    echo "kernel log (Wi-Fi driver, AirDrop modules, PCIe), last 25:"
    dmesg 2>/dev/null | grep -iE 'wonder|bwfix|mhifix|s23tweaks|kiwi_v2.*(error|fail|assert|crash)|cnss.*(fail|error|crash|assert|ssr|recover)|wlan.*firmware' |
      grep -vE 'Runtime (suspend|resume)|PCI link|MHI state' | tail -n 25 | sed 's/^/  /' | cut -c1-200
    echo "Mosey / Quick Share warnings and errors, last 30 (names in quotes masked):"
    logcat -d -v brief 2>/dev/null | grep -E '^[EW]/[^(]*(Mosey|mosey|AirDrop|Awdl|NearbySharing|ShareLive|Wonder)' | grep -v '	at ' |
      sed -E "s/\"[^\"]*\"/<name>/g; s/'[^']*'/<name>/g" | tail -n 30 | sed 's/^/  /' | cut -c1-220
    sec "Galaxy AI secure storage"
    # Samsung's Pass Storage (Now Brief's Personal Data Intelligence, aasaservice) is refused with "Root
    # detected" when system_server sees su at one of StorageManagerService.isRootedDevice's paths. Listed
    # by reading the folders, since KernelSU's su compatibility answers file checks from root itself.
    s=$(nsenter -t $(pidof system_server) -m -- sh -c 'for f in /sbin/su /system/su /system/bin/su /system/xbin/su \
      /system/bin/.ext/.su /data/local/xbin/su /data/local/bin/su /system/sd/xbin/su /system/bin/failsafe/su /data/local/su \
      /system/app/Superuser.apk /system/usr/we-need-root/su-backup /system/xbin/mu; do
      ls -a "${f%/*}" 2>/dev/null | grep -qxF "${f##*/}" && echo "$f"; done' 2>/dev/null | tr '\n' ' ')
    echo "su files the system sees: ${s:-none}"
    echo "Pass Storage log, last 15:"
    logcat -d 2>/dev/null | grep -E 'StorageManagerService: (isDetectedRoot|rooting:)|VoldNativeService: (create|get|unlock)PassStorage|SecureStorage(Adapter|Impl)' |
      tail -n 15 | sed 's/^/  /' | cut -c1-200
    sec "every apply since this boot (seconds since boot)"
    tail -n 150 $HIST 2>/dev/null | cut -c1-220
    sec "tweaks.log (last apply)"
    cat $L 2>/dev/null
    sec "boot.log (last 60 lines)"
    tail -n 60 $V/boot.log 2>/dev/null
    sec "native crashes in the last 2 days (count, newest, process, signal, abort message)"
    for t in $(find /data/tombstones -name 'tombstone_[0-9]*' ! -name '*.pb' -mtime -2 2>/dev/null); do
      printf '%s|%s | %s | %s\n' "$(grep -m1 '^Timestamp' $t | cut -c12-30)" "$(grep -m1 '^Cmdline' $t | cut -c10- | cut -d' ' -f1)" \
        "$(grep -m1 '^signal' $t | cut -d, -f1)" "$(grep -m1 '^Abort message' $t | cut -c16-200)"
    done | sort -r | awk -F'|' '{ k = substr($0, index($0, "|") + 1); n[k]++; if (!(k in t)) { t[k] = $1; o[++m] = k } }
      END { for (i = 1; i <= m; i++) printf "%dx  %s |%s\n", n[o[i]], t[o[i]], o[i] }'
    sec "app crashes (count, newest, app, error)"
    logcat -d -b crash 2>/dev/null | awk '
      / Process: / { p = $0; sub(/.* Process: /, "", p); sub(/,.*/, "", p); t = $1 " " $2; want = 1; next }
      want && /AndroidRuntime: [A-Za-z0-9_.$]+(Exception|Error)/ { e = $0; sub(/.*AndroidRuntime: /, "", e); k = p " | " substr(e, 1, 160)
        n[k]++; last[k] = t; if (!(k in seen)) { seen[k] = 1; o[++m] = k }; want = 0 }
      END { for (i = m; i >= 1; i--) printf "%dx  %s | %s\n", n[o[i]], last[o[i]], o[i] }' | head -n 20
  } 2>&1 | sed -E -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g' \
      -e 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g' -e 's/(^|[^0-9])[0-9]{14,17}([^0-9]|$)/\1<number>\2/g' |
    if [ -n "$sn" ]; then sed "s/$sn/<serial>/g"; else cat; fi > $out
  echo "$out"
  ;;
dual5g-restore)
  # put the modem's original /policyman/global_defines.xml back (also what un-picking dual5g does)
  [ "$(id -u)" = 0 ] || { echo "needs root" >&2; exit 1; }
  mkdir -p $R; L=$R/dual5g-restore.log; : > $L
  dual5g_restore; rc=$?
  cat $L; cat $L >> $V/tweaks.log; exit $rc
  ;;
unflag)
  G=/data/data/com.google.android.gms; DB=$G/databases/phenotype.db; SQ=$AIR/sqlite3; W=$R/gms
  [ -x $SQ ] || { echo "the AirDrop download (with its sqlite3) isn't on the phone; pick AirDrop once to fetch it" >&2; exit 1; }
  rm -rf $W; mkdir -p $W; am force-stop com.google.android.gms
  cp $DB $W/p.db; [ -f $DB-wal ] && cp $DB-wal $W/p.db-wal
  in_list=""
  for f in $NEARBY_FLAGS; do in_list="${in_list:+$in_list, }'$f'"; done
  $SQ $W/p.db "DELETE FROM experiment_states_to_overrides WHERE override_id IN (SELECT override_id FROM flag_overrides WHERE name IN ($in_list) AND account_id=0);
    DELETE FROM flag_overrides WHERE name IN ($in_list) AND account_id=0; PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null
  am force-stop com.google.android.gms; cat $W/p.db > $DB && rm -f $DB-wal $DB-shm; rm -rf $W
  echo "Play services flag overrides removed"
  ;;
autostart)
  S=/data/adb/service.d/s23tweaks.sh
  case "$2" in
  on)
    # the module's own service.sh does the boot call; install.sh needs a service.d script
    rm -f $V/boot.skip $V/boot.pending
    if [ $MODULE = 1 ]; then rm -f $S; touch $V/autostart; echo "autostart on: the saved tweaks ($(cat $V/choices 2>/dev/null)) re-apply at every boot"; exit 0; fi
    mkdir -p /data/adb/service.d
    cat > $S <<EOF
#!/system/bin/sh
# s23-ultra-tweaks: re-apply the saved tweaks at boot. KernelSU runs this once DFRoot has rooted the
# phone. Remove with: sh $D/tweaks.sh autostart off
unset ASH_STANDALONE
[ -f $V/autostart ] && /system/bin/nsenter -t 1 -m -- /system/bin/setsid /system/bin/sh $D/tweaks.sh boot </dev/null >/dev/null 2>&1 &
EOF
    chmod 700 $S; touch $V/autostart; echo "autostart on: the saved tweaks ($(cat $V/choices 2>/dev/null)) re-apply at every boot" ;;
  off) rm -f $S $V/autostart $V/boot.pending $V/boot.skip; echo "autostart off" ;;
  *) [ -f $V/autostart ] && { [ $MODULE = 1 ] || [ -f $S ]; } && echo "autostart on" || echo "autostart off" ;;
  esac
  ;;
boot)
  B=$V/boot.log
  blog() { echo "$(date '+%F %T') $*" >> $B; }
  note() { cmd notification post -S bigtext -t "S23 tweaks" s23tweaks "$1" >/dev/null 2>&1; }
  [ -f $V/autostart ] || exit 0
  t=$(cat $V/choices 2>/dev/null); [ -n "$t" ] || exit 0
  # KernelSU can run boot scripts more than once per boot (seen with DFRoot's late load): only the
  # first call goes on
  mkdir /dev/s23tweaks_boot.lock 2>/dev/null || exit 0
  to_root_cgroup
  # The module replaces an earlier computer install: drop that copy's code (not its state). Safe
  # only now, at boot, when nothing can still be running from it.
  if [ $MODULE = 1 ] && [ "$D" != "$V" ] && [ -f $V/tweaks.sh ]; then
    rm -rf $V/tweaks.sh $V/files $V/airdrop; rm -f /data/adb/service.d/s23tweaks.sh
  fi
  n=600; until [ "$(getprop sys.boot_completed)" = 1 ]; do n=$((n-1)); [ $n = 0 ] && break; sleep 1; done
  sleep 30   # let Wi-Fi, Play services and the launcher settle before swapping the driver
  # Fail-safe against a boot loop: if the last boot's apply never finished (the phone rebooted in the
  # middle) or the Wi-Fi firmware crashed, skip this boot once and say so.
  why=""
  [ -f $V/boot.pending ] && why="the last automatic apply didn't finish"
  [ -f $V/boot.skip ] && why=$(cat $V/boot.skip)
  if [ -n "$why" ]; then
    rm -f $V/boot.pending $V/boot.skip; blog "skipped: $why"
    note "Tweaks not applied at this boot: $why. Apply them from KernelSU > Modules > S23 Ultra Tweaks (or the installer), or reboot to try again."
    exit 0
  fi
  [ -f /dev/s23tweaks_applied ] && { blog "skipped: already applied in this boot"; exit 0; }
  touch $V/boot.pending; sync; blog "applying: $t"
  S23T_BOOT=1 sh $D/tweaks.sh apply "$t"; rc=$?
  rm -f $V/boot.pending
  [ $rc = 3 ] && { blog "skipped: an apply was already running"; exit 0; }
  if grep -q DONE $L; then blog "done"; note "Applied: $t"
  else f=$(grep FAILED $L | tail -1 | cut -d' ' -f2-); blog "failed: $f"; note "Applying the tweaks failed: $f. Details: $L"; fi
  ;;
wifi7page)
  # Samsung ships this page on the S23, but its entry in Wi-Fi Labs is hard-coded as unsupported
  # (WifiLabs7ModeSettingsController.getAvailabilityStatus() returns 3). The page itself has no
  # check. SubSettings isn't exported, so it can only be opened as root/system.
  am start -n com.android.settings/.SubSettings \
    --es :settings:show_fragment com.samsung.android.settings.wifi.develop.WifiLabs7ModeSettingsFragment
  ;;
*) echo "usage: tweaks.sh start|apply \"<tweaks>\" | probe | status | unflag | dual5g-restore | autostart on|off | wifi7page"; exit 2 ;;
esac
