# s23-ultra-tweaks

Turns on Galaxy S24-and-newer features on a rooted Galaxy S23 Ultra running One UI 9 / Android 17, with no flashing.

The tweaks come in six categories. The module page lets you pick a whole category or single tweaks.
Each one works on any S23 Ultra on One UI 9 unless it says otherwise.

**What's new** (details in the [changelog](CHANGELOG.md)):
- **v1.8.0**: three new camera tweaks: Camera Assistant's DOF adapter (`dofadapter`), 8K recording while mirroring (`mirror8k`) and 1-hour recording limits in overheat and low-power conditions (`longrec`). Also fixes 24 fps Video showing only the 1x lens in UHD and FHD (the 0.6×, 3× and 10× are back).
- **v1.7.2**: fixes Chromium browsers such as Vivaldi crashing on launch with `hideksu` on ("GPU process isn't usable").
- **v1.7.1**: fixes `wideflash` (the 0.6× flash and torch) on a camera that had been used before, where it stayed greyed out.
- **v1.7.0**: the camera update: flash and torch on the 0.6× ultrawide (`wideflash`), 24 fps now on the rear and front cameras (`cam24fps`), white-balance tint in Pro video (`prowbtint`), the Video zoom rocker (`zoomrocker`), Camera Assistant's Video softening, autofocus speed/sensitivity and auto exposure limit (`videosoftening`, `afcontrol`, `aelimit`), touch focus in Slow motion (`slowmoaf`), recording to USB-C storage (`extstorage`), anamorphic desqueeze (`anamorphic`), extra Pro video frame rates, including 4K120 on the Wide/Ultrawide, 21:9 Cinema and the 10× super tele at 25/48/50 on the patched Camera APK (`profps`), and 4K120 in Slow motion (`slowmo4k120`). Flash, tint, the zoom rocker and 24 fps are grouped as one **Camera Tweaks** switch in the module page. AirDrop works again on Play services 26.46+, says "not available" instead of freezing on kernels with their own Wi-Fi stack, and an apply no longer stops at "keep /system/etc/floating_feature.xml".
- **v1.6.0**: Dual SIM 5G (`dual5g`): 5G standalone on both SIMs at once, instead of only the data SIM. The original modem file is backed up first.
- **v1.3.5**: HideKSU can now also hide the module's own mounts from apps you list, so mount-scanning root detectors and banking apps no longer see the tweaks (verified against Native Detector).
- **v1.3.4**: the 6 GHz hotspot no longer changes the phone's country, so Samsung Wallet keeps working with it on.
- **v1.3.3**: the India config now also makes Samsung Wallet India (UPI) and the 6 GHz hotspot work, by reporting the phone as the Indian model (reverts on reboot).
- **v1.3.2**: call recording and the India carrier config work on any sales code, not just XAC/EUX. HideKSU also supports SM-S918B INS and SM-S918U1 (both untested on a phone).
- **v1.3.1**: horizontal lock levels the viewfinder too and corrects up to about 20° instead of 8°, with its [limits](#horizontal-lock) spelled out. AirDrop and Wi-Fi 7 can try a custom kernel (opt-in, untested; see [Known limitations](#known-limitations)).
- **v1.3.0**: 24 fps in standard Video (`cam24fps`). AirDrop finds Apple devices again after Mosey updates itself from Google Play. No more SmartSuggestions crashes during an apply. HideKSU checks the framework file's MD5 instead of the firmware name.
- **v1.2.9**: HideKSU, so root-aware apps like CRED stop crashing with the KernelSU manager installed.
- **v1.2.8**: Always On Display brightness follows the room light, and AirDrop's crash guard uses far less CPU.

### 🌐 Connectivity

- 📲 **1 · AirDrop** with iPhones, iPads and Macs: Quick Share → *Share with Apple devices*. **Tested end to end** · `airdrop`
  - Works on: One UI 9 build **GZIF** on SM-S918W, S918B, S918U1, S918U or S918N (tested on the S918W and S918B)
- 📶 **2 · Wi-Fi 7 multi-link (MLO)** with Wi-Fi 7 routers. Includes AirDrop · `wifi7`
  - Works on: same as AirDrop
- 📡 **3 · 6 GHz Mobile Hotspot** (Wi-Fi 6E, 160 MHz): Mobile Hotspot → Band → 6 GHz · `hotspot6g`

### 📷 Camera

- 🎞️ **4 · Log video**: Camera → Pro video gets the LOG button (10-bit HEVC). No LUT preview: on the S24 the camera HAL draws it, and the S23's can't · `logvideo`
- 🎬 **5 · Director's view** (front and back camera at once, hidden by One UI 9) and Super steady's **horizontal lock**, which keeps the horizon level for small tilts (up to about 20°) in the viewfinder and the recording. Not the S26's 360° lock; see [its limits](#horizontal-lock) · `camextras`
- 🌗 **6 · Camera HDR processing**: puts back the multi-frame and low-light HDR steps One UI 9 removed from the S23 ([details](docs/findings.md)). **Untested** · `camerahdr`
  - 21 MB download
- 🕰️ **7 · 2023 ArcSoft HDR**: One UI 6's hybrid and bracketed HDR engines instead of today's. Bracketed HDR tested, hybrid HDR (ordinary daylight) **untested**. Not included when you pick the whole Camera category · `hdr2023`
  - Works on: any S23 Ultra on One UI 9; tested on S918WVLU8GZIF (28 MB download)
- 🎯 **8 · 4K auto framing** in video, as on the S24. Works on the SM-S918W (front camera, UHD with auto framing on); **reported to make the camera fail** on an S918B, so it's not included when you pick the whole Camera category · `autoframe`
- 🌈 **9 · 10-bit HDR video from the front cameras in any app** (Camera2 HLG10), as the rear cameras already allow. Samsung Camera keeps its own HDR10+. Patches a copy of the phone's own camera driver and keeps it only if a front camera then really offers 10-bit; the first apply takes about 15 s longer · `tenbit`
  - Works on: any S23 Ultra whose camera driver has the expected code (found in One UI 6 and 9 builds; tested on S918WVLU8GZIF)
- 🎥 **10 · 24 FPS in standard Video**: unlocks 24 fps for FHD (1080p), UHD (4K) and 8K in Samsung Camera's standard Video mode (not just Pro video), on the rear and front cameras. Adds `video` to the 24 fps entries (back and front) in `camera-feature.xml` and adds `RESOLUTION_3840X2160_24FPS` + `RESOLUTION_1920X1080_24FPS` to `te.f0.i` (8K 24 is already allowlisted) in a copy of `SamsungCamera.apk` (`device/files/SamsungCamera-24fps-<firmware>.patch`, made by `tools/cam24patch.py`) · `cam24fps`
  - Works on: a stock Samsung Camera 17.0.00.43 the patch knows, checked by MD5 whatever the firmware name (so far S918BXXUAGZIF and S918WVLU8GZIF; no download needed). `tools/cam24patch.py` adds another
- 🔦 **11 · Flash on the 0.6× ultrawide**: Photo's flash and Video's torch work on the 0.6× ultrawide lens, and Camera Assistant gets the matching wide-flash option. Two switches in `camera-feature.xml` (`SUPPORT_FLASH_IN_WIDE_LENS`, `SUPPORT_CAMERA_ASSISTANT_WIDE_FLASH_MENU`); no APK or HAL patch · `wideflash`
  - Works on: any S23 Ultra whose `camera-feature.xml` can be edited (validated on-device on an S23 Ultra)
- 🎚️ **12 · White-balance tint in Pro**: the **Tint** slider next to the colour temperature in Pro and Pro video's white balance (`SUPPORT_PRO_WHITE_BALANCE_TINT`); no APK or HAL patch · `prowbtint`
  - Works on: any S23 Ultra whose `camera-feature.xml` can be edited
- 🎥 **13 · Video zoom rocker**: the smooth zoom rocker/slider in the standard Video mode, as on newer models (`SUPPORT_VIDEO_MODE_ZOOM_ROCKER`); no APK or HAL patch · `zoomrocker`
  - Works on: any S23 Ultra whose `camera-feature.xml` can be edited
- 🎞️ **14 · Video softening**: Camera Assistant's **Video softening** (Off / Medium / High), which reduces over-sharpening in video (`CAMERA_SUPPORT_VIDEO_SOFTENING`); no APK or HAL patch · `videosoftening`
  - Works on: any S23 Ultra on One UI 9; the switch is in Camera → Settings → Camera Assistant
- 🎯 **15 · Autofocus speed and sensitivity**: Camera Assistant's **AF speed** and **AF sensitivity** controls (`CAMERA_SUPPORT_AFSPEED`, `CAMERA_SUPPORT_AFSENSITIVITY`); no APK or HAL patch · `afcontrol`
  - Works on: any S23 Ultra on One UI 9; the switches are in Camera → Settings → Camera Assistant
- 📏 **16 · Auto exposure limit**: Camera Assistant's **Auto exposure limit**, which caps how far the camera raises ISO or slows the shutter (`CAMERA_SUPPORT_AUTO_EXPOSURE_LIMIT`); no APK or HAL patch · `aelimit`
  - Works on: any S23 Ultra on One UI 9; the switch is in Camera → Settings → Camera Assistant
- 👆 **17 · Touch focus in Slow motion**: tap the viewfinder to focus while recording a slow-motion video (`SUPPORT_SLOW_MOTION_AF_DURING_RECORDING` and `CAMERA_SUPPORT_AF_DURING_SLOWMOTION_RECORDING`); no APK or HAL patch · `slowmoaf`
  - Works on: any S23 Ultra whose `camera-feature.xml` can be edited
- 💾 **18 · Record to USB-C storage**: records straight to a USB-C SSD or drive in every video mode (4K60, 4K60 21:9, 8K, FHD120), by flipping `external-storage-support` to `true` on the resolution map lines; no APK or HAL patch · `extstorage`
  - Works on: any S23 Ultra whose `camera-feature.xml` can be edited
- 🎥 **19 · Anamorphic desqueeze**: Camera Assistant's **anamorphic lens desqueeze** (1.33× / 1.55× / 2.0×) for anamorphic lenses (`SUPPORT_CAMERA_ASSISTANT_ANAMORPHIC_LENS`, `SUPPORT_CAMERA_ASSISTANT_ANAMORPHIC_LENS_HW_SCALER`); no APK or HAL patch · `anamorphic`
  - Works on: any S23 Ultra whose `camera-feature.xml` can be edited
- ⏱️ **20 · Extra Pro video frame rates**: 4K 25/48/50/100/120 (120 on the Wide and Ultrawide), FHD 25/48/50/100, 8K 25, and 21:9 Cinema 25/48/50/100/120 in Pro video. On a phone whose `SamsungCamera.apk` the patch knows, it also unhides the **10× super tele at 25/48/50 fps**; the 0.6×, 1× and 3× work everywhere, and 8K stays 10×-free (HAL limitation) · `profps`
  - Works on: any S23 Ultra whose `camera-feature.xml` can be edited; the 10× needs the patched Camera APK (S918BXXUAGZIF today, `device/files/SamsungCamera-24fps-S918BXXUAGZIF.patch`)
- 🐢 **21 · 4K120 in Slow motion**: adds 4K120 and FHD120 to the Slow motion mode, and rebuilds the FHD240 menu entry so the Slow motion resolution list is complete (`supported-mode="slow_motion"`); the Log profile works with `logvideo` on · `slowmo4k120`
  - Works on: any S23 Ultra whose `camera-feature.xml` has the 4K120 entry
- 🎛️ **22 · DOF adapter in Camera Assistant**: Camera Assistant's DOF (depth-of-field) adapter option for manual-focus adapters (`SUPPORT_CAMERA_ASSISTANT_DOF_ADAPTER`); no APK or HAL patch · `dofadapter`
  - Works on: any S23 Ultra whose `camera-feature.xml` can be edited
- 🖥️ **23 · 8K recording while mirroring**: records in 8K while the phone is mirrored to a display over HDMI or Smart View, with the matching Camera Assistant option (`SUPPORT_CAMERA_ASSISTANT_RECORDING_8K_WHEN_MIRRORING`); no APK or HAL patch · `mirror8k`
  - Works on: any S23 Ultra whose `camera-feature.xml` can be edited
- ⏳ **24 · Longer recording limits**: raises the recording time limit in overheat conditions and the delay before low-power mode from 300 s (5 min) to 3600 s (1 h) (`MAX_SEAMLESS_ZOOM_RECORDING_TIME_LIMIT_IN_OVERHEAT_CONDITION`, `MIN_RECORDING_TIME_TO_ENABLE_LOW_POWER_MODE`), inserting the entries when the stock file lacks them; no APK or HAL patch · `longrec`
  - Works on: any S23 Ultra whose `camera-feature.xml` can be edited

All fifteen camera tweaks added in this fork — 24 fps (rear and front), flash on the 0.6× ultrawide, white-balance tint, the Video zoom rocker, 4K120 in Slow motion, video softening, AF speed/sensitivity, auto exposure limit, touch focus in Slow motion, USB-C storage, anamorphic desqueeze, the extra Pro video frame rates, the DOF adapter, 8K while mirroring and 1-hour recording limits — are grouped as one **Camera Tweaks** switch in the module page. They stay independent in `tweaks.sh`; the twelve from v1.7.0 were tested individually and validated on an S23 Ultra.

### 🎨 Display and graphics

- 🖌️ **25 · Always On Display: lock screen wallpaper, and AOD brightness that follows the room light** · `display`
- 🌤️ **26 · Adaptive color tone**: Settings → Display, the screen's colour follows the room light · `colortone`
  - Works on: firmware S918WVLU8GZIF or S918BXXUAGZIF (1 MB download)
- ⚡ **27 · Vulkan rendering**: apps draw with Vulkan instead of OpenGL, as on the S24. It can make some lock screen animations stutter more, such as Samsung's stretchable clocks between AOD and the lock screen (issue #27); unpick it if you see that · `vulkan`
- 🌧️ **28 · Lock screen weather effect**: rain, snow, fog or sun animated over your own lock screen wallpaper, following Samsung Weather. Brings back the **Weather** button in the lock screen editor (Wallpaper and style → Lock screen → Weather → Done). It animates only when the weather calls for it: cloudy weather and clear nights show nothing. The editor asks Samsung AI Core before it offers Weather, and the S23 has none, so the module installs a 12 KB stub app (`com.samsung.android.aicore`, source in `src/aicorestub`) that answers just those checks; a real AI Core is left alone. It also turns Samsung's live wallpaper app back on if a debloat disabled it · `weather`

### ✨ Galaxy AI and Samsung apps

- 🧠 **29 · Now Brief, Creative Studio and Call Assist** from the S24 · `galaxyai`
  - Works on: firmware S918WVLU8GZIF (219 MB download)
- 🔇 **30 · Audio Eraser**: Gallery → video → Edit → remove wind, noise, music or voices · `audioeraser`
  - Works on: firmware S918WVLU8GZIF (34 MB download)
- 🔎 **31 · Settings search** bar from the S24. Natural-language answers stay off (they need Samsung's Semantic Search Core 4.x) · `settingssearch`
  - Works on: firmware S918WVLU8GZIF (10 MB download)
- 📞 **32 · Call screening** in the Phone app: screening, greeting, voice messages and the AI summary work. **Stays after a reboot** · `callscreen`
  - Works on: firmware S918WVLU8GZIF (3.1 GB download, about 7 GB free while it installs)
- 🗣️ **33 · Bixby barge-in**: talk over Bixby while it answers. **Untested** · `bargein`

### 🔋 Battery and settings

- 🩺 **34 · Battery health**: Settings → Battery → Battery information shows health and cycle count · `battery`
- ⏰ **35 · Auto power on/off** schedule and **louder VoIP calls** · `features`
- 🫥 **36 · HideKSU**: hides the KernelSU root manager (`me.weishu.kernelsu`) from apps, so root-aware apps like CRED stop detecting root and crashing. Nothing is injected into the apps, so their in-process tamper scans stay clean. The manager stays installed — its launcher icon, DFRoot's boot-time root and the system still see it; only third-party apps don't. Needs the KernelSU manager installed. It replaces `services.jar` with a patched copy of the phone's own, so it only runs on a phone whose stock `services.jar` is one a patch was made from (checked by MD5, whatever the firmware name): so far the SM-S918W's (S918WVLU8GZIF), an SM-S918B INS one and an SM-S918U1 one. Applies on a framework restart. It also **hides the module's own mounts** from every user-installed app automatically (keeping them for the preinstalled Samsung apps that consume them; see [Hiding the module's mounts](#hiding-the-modules-mounts)), so mount-scanning detectors and banking apps don't see the tweaks' bind/overlay mounts · `hideksu`

### 📱 Carrier

- ⏺️ **37 · Call recording** in the Samsung Phone app, on any sales code: the module decodes the phone's own carrier config and allows recording in it · `callrec`
- 🇮🇳 **38 · India carrier config** for Airtel / Jio SIMs: the **Use 5G standalone networks** switch (Settings → Connections → Mobile networks), call recording, Smart IVR, message cards and more. It also makes the phone report itself as the Indian S23 Ultra (SM-S918B / INS / country IN) so **Samsung Wallet India** (UPI, DigiLocker, transit) and the **6 GHz hotspot** work; this is a runtime change that reverts on reboot and never writes the sales code to disk (no factory-reset risk). If Samsung Wallet still shows "not supported" after applying (it can cache the earlier state), clear its storage — Settings → Apps → Samsung Wallet → Storage → **Clear data** — and reopen it. It also **stops Samsung's "Switch to \<carrier\>?" prompt** (the CID Manager dialog that keeps asking to restart and re-flash the carrier customization when the SIM's carrier doesn't match the reported sales code), which is reverted when you unpick `india` or remove the module. Works on any sales code on One UI 9. With an Indian SIM, picking the Carrier category takes this instead of call recording · `india`
- 📶 **39 · Dual SIM 5G**: 5G standalone on **both SIMs at the same time**, instead of only the SIM set for mobile data. The S23's modem can do it; Samsung's modem config allows it only on Chinese and Costa Rican networks. The module adds your SIMs' country to that list. Unlike the other tweaks this one **stays after a reboot** (it's a file in the modem's own storage); the original is backed up first and goes back when you un-pick it or remove the module · `dual5g` ([details](#dual-sim-5g))

Not included, because they don't work on the S23: the AI-generated weather wallpaper, which redraws the
photo for each kind of weather (its model is built only for newer NPUs; the weather effect above is a
different feature), Dual rec (can't open the S23's cameras), and two-lens or seamless-zoom
Portrait video (they crash the camera).

**Apart from `dual5g`, nothing is written to any partition.** Every change is a kernel module load, an overlay, a bind mount or a runtime setting. The files behind them stay on storage in `/data/adb/s23tweaks`, so they use no RAM. A reboot puts the phone back to stock, and then the tweaks re-apply by themselves (see [After a reboot](#after-a-reboot)). The exceptions: the Google Play services flag overrides that `airdrop` adds, the camera setting that shows Director's view (`camextras`), Samsung Language Core, which `callscreen` installs as an app update, and the AI Core stub app that `weather` installs (see [Undo](#undo)). `dual5g` edits one policy file inside the modem, which the modem keeps on its own storage; see [Dual SIM 5G](#dual-sim-5g) for its backup and undo.

**Different firmware?** Point your AI coding agent at [AGENTS.md](AGENTS.md) and it can build the kernel modules for your phone (see [Other firmware](#other-firmware-let-your-ai-agent-build-it)).

<a id="before-you-start"></a>

## ✅ Before you start

You need:

1. **A Galaxy S23 Ultra** on One UI 9.
2. **Root, from two apps:**
   - **DFRoot** (by diabl0w): [github.com/diabl0w/DFRoot](https://github.com/diabl0w/DFRoot). It roots the stock, locked-bootloader firmware at runtime by loading KernelSU, and does it again by itself at every boot.
   - **KernelSU manager, Samsung build `samsung-v2.2`**: [its samsung-v2.2 release](https://github.com/diabl0w/KernelSU/releases/tag/samsung-v2.2). DFRoot needs it installed to load root.

   Install both APKs, open DFRoot and tap **LAUNCH ROOT** once.
3. **Optional, only for the `adb` commands in this README:** a computer (macOS or Linux) with [Android platform-tools](https://developer.android.com/tools/releases/platform-tools) (`adb`), a USB cable, and **USB debugging** on (Settings → About phone → Software information → tap *Build number* 7 times, then Settings → Developer options → *USB debugging*). Run `adb devices` once and accept the prompt on the phone, then in KernelSU → **Superuser** allow **Shell**.

> Root has side effects. Some apps with anti-tamper checks refuse to run while the KernelSU manager app is installed (for example CRED in India). You do this at your own risk.

<a id="install"></a>

## 📦 Install

1. On the phone, download the `s23-ultra-tweaks-v….zip` file from the [latest release](https://github.com/dtechterminal/s23-ultra-tweaks/releases/latest).
2. Open **KernelSU** → **Modules** → **Install** and pick the zip. It checks that this is an S23 Ultra and whether the AirDrop files match your firmware.
3. **Reboot.** DFRoot roots the phone by itself during boot and KernelSU activates the module.
4. Open **KernelSU** → **Modules** → **S23 Ultra Tweaks** → the page icon. Tick the tweaks you want, switch on **Apply at every boot** if you like, and tap **Apply**.

The page greys out tweaks your phone can't take and says why. During the apply, Wi-Fi drops for ~30 s (AirDrop and Wi-Fi 7), and the screen goes black for ~30 s while Android restarts. The page closes during that; reopen it to see the result. The module's action button (▶) re-applies your saved picks.

To remove it: KernelSU → Modules → S23 Ultra Tweaks → Remove, then reboot.

### After a reboot

With **Apply at every boot** on, there's nothing to do:

1. DFRoot roots the phone by itself during boot (its boot receiver runs the same exploit as **LAUNCH ROOT**).
2. KernelSU then starts the module, which re-applies your saved picks.
3. About a minute after boot, the tweaks re-apply: Wi-Fi drops for ~30 s and the screen goes black for ~30 s once. A notification says when they're on.

A fail-safe prevents boot loops. If a boot's apply never finished (the phone rebooted in the middle), or the Wi-Fi firmware crashed, the next boot skips the tweaks once and a notification says why. Reboot again or tap **Apply** on the module page to bring them back.

If DFRoot didn't root the phone at boot (no notification after a few minutes), open DFRoot and tap **LAUNCH ROOT**. The tweaks then apply by themselves.

**Don't want root at every boot?** In DFRoot's settings, turn off **Start at Boot**. The phone then boots stock, with no KernelSU loaded, until you tap **LAUNCH ROOT**. With **Apply at every boot** on, the tweaks apply by themselves a minute after you tap it. So you get root, and the tweaks, only when you ask for them.

Without **Apply at every boot**, tap the module's action button (▶) after each reboot to re-apply your saved picks.

To turn it off later, switch off **Apply at every boot** on the module page, or:

```sh
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh autostart off"
```

### Using AirDrop

1. On the iPhone/Mac: Control Center → AirDrop → **Everyone for 10 minutes**, and keep it unlocked and close by.
2. On the S23: share a photo → **Quick Share** → **Share with Apple devices**. Apple devices show up in the list.

The S23's Wi-Fi briefly disconnects while Quick Share is looking for Apple devices. The S24 does the same.

If no Apple device shows up after the first apply, Play services may not have picked up its two flags yet. On an S918B it started offering Apple devices only after being restarted some minutes later: `adb shell su -c 'am force-stop com.google.android.gms'`, then open Quick Share again.

<a id="how-airdrop-works-on-an-s23"></a>

## 🍏 How AirDrop works on an S23

Samsung's S24-and-newer phones do AirDrop through Google's **Mosey** stack. The phone runs Apple's peer-to-peer Wi-Fi protocol (AWDL) itself, using a Qualcomm firmware feature called *Wondertap*. The S23 Ultra has the same Wi-Fi chip as the S24 Ultra (Qualcomm WCN7850), but its firmware, driver and system image leave all of this out. The `airdrop` tweak adds the S24 pieces at runtime:

1. **S24 Wi-Fi driver** (`kiwi_v2.ko`): Samsung's GPL source for the S24 Ultra's qcacld-3.0 driver with Wondertap, built against the S23 kernel. The patches are in `src/qcacld-patch`; they cover the S23's older cnss2 platform driver and a CFI function-type mismatch.
2. **S24 Wi-Fi firmware** (`amss20.bin`, `phy_ucode20.elf`, `regdb.bin`) in an overlay. The S23's own board file stays.
3. **`mhifix.ko`**: cnss2 sizes its firmware-download buffers for the boot-time firmware, and loading the bigger S24 image would crash the kernel. mhifix frees those buffers first.
4. **`bwfix.ko`**: when AirDrop starts, the S24 firmware asks for a PCIe Gen3 link. The S23's PCIe root port tops out at Gen2, so the request is refused, and the firmware crashes on the refusal. bwfix sets Gen2 and acknowledges.
5. **`wonder.ko`**: Google's virtual Wi-Fi driver that Mosey drives, with small S23 patches (`src/wonder-patch`).
6. **Mosey**: `MoseyApp.apk`, `mosey_server` and `libmosey_daemon_ffi.so` from the S24 Ultra system image, added to `/system_ext` in an overlay. `moseyrun` starts the daemon as uid `system` with only `NET_ADMIN`/`NET_RAW`, the same way the S24's init script does.
7. **Play services**: three Nearby flags (`45704091`, `45723015`, and `sharing_package_whitelist_check_bypass` for Play services 26.46+) that make Play services hand AirDrop to Mosey, set as local overrides.

A watchdog script also runs. If the Wi-Fi firmware ever crashes, it saves the kernel log and reboots cleanly. Without it, the S24 driver's recovery leaves the phone to hard-reset about a minute later.

<a id="reporting-a-problem"></a>

## 🐞 Reporting a problem

Module page → Status → **Make a bug report**. It saves one text file in Download and offers to copy it.
Attach the file (or paste the text) in a [new issue](https://github.com/dtechterminal/s23-ultra-tweaks/issues),
with what you expected and what happened. Without the module page:

```sh
# prints the report file's path
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh report"
```

The report has the phone model, firmware, kernel and app versions, which tweaks are on and why any
aren't offered, the camera and feature settings the tweaks change (and what the phone had before),
the files the module mounts, the last apply and boot logs, and summaries of recent crashes. It leaves
out the serial number, email addresses, MAC addresses and long numbers such as the IMEI.

<a id="status-and-logs"></a>

## 📋 Status and logs

The module page shows all of this. From a computer:

```sh
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh status"
adb shell su -c "cat /data/adb/s23tweaks/tweaks.log"
# automatic applies at boot
adb shell su -c "cat /data/adb/s23tweaks/boot.log"
```

<a id="wi-fi-7-multi-link-mlo"></a>

## 📶 Wi-Fi 7 multi-link (MLO)

The S23 Ultra's chip (WCN7850) does Wi-Fi 7, including multi-link operation (MLO): one connection to a Wi-Fi 7 router over two bands at once. The S23's software only does part of it. Its `wpa_supplicant` has no 802.11be/MLO code, and its driver config leaves MLO off. `wifi7` builds on the `airdrop` driver, whose S24 source has MLO built in:

- **S24 `wpa_supplicant`** bind-mounted over the S23's. It speaks the same Samsung HAL extensions and needs one library the S23 vendor image lacks (`android.hardware.wifi.supplicant-V2-ndk.so`), which is added to `/vendor/lib64` with a read-only RAM overlay.
- **Driver config:** the S23's own `WCNSS_qcom_cfg.ini` plus the S24's four MLO lines (`mlo_support_link_num=2`, `mlo_5gl_5gh_mlsr=1`, `oem_eht_mlo_crypto_bitmap=0`, `epcs_support_enable=1`).

If Wi-Fi doesn't come up with the S24 supplicant, the tweak switches back to the S23's and carries on without MLO. If the S24 driver itself doesn't bring Wi-Fi up with these settings (seen on a custom kernel, issue #21), `airdrop` drops all of `wifi7` for that boot, reloads the driver and carries on, so AirDrop still works.

Tested so far: Wi-Fi runs and connects normally with the S24 supplicant, and the driver's MLO code checks each network it joins. A multi-link connection itself hasn't been tested yet; that needs a Wi-Fi 7 router with MLO on. With one, Settings → Wi-Fi → (network) should show Wi-Fi 7, and `adb shell cmd wifi status` shows `MLO Link Id`s.

### Wi-Fi 7 mode page

One UI has a **Wi-Fi 7 mode** page (an on/off switch and *Maximum multi link count*). On the S23 its menu entry is hard-coded as unsupported, so it never shows up. The page itself works. To open it:

```sh
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh wifi7page"
```

The switch stores `Settings.Secure sec_wifi_7_mode_enabled` (default 1 = on). Samsung's Wi-Fi service applies a change at the next Wi-Fi disconnect. It switches Wi-Fi 7 off anyway in countries on Samsung's blocklist.

<a id="6-ghz-hotspot"></a>

## 📡 6 GHz hotspot

The S23 Ultra's Wi-Fi chip and its stock `hostapd` run a 6 GHz hotspot fine (tested: channel 1, 5975 MHz, 160 MHz wide, with an iPhone connected). Samsung's Settings only offers the 6 GHz band when the firmware's CSC country is on a hard-coded list (`SemWifiApServiceImpl.isRegionFor6GCountry`). For most S23 firmware it isn't: Canada, for example, needs a phone that launched with Android 15. `hotspot6g` turns on Samsung's own debug override for that check (`vendor.wifiap.6gbandcountry=1`) instead of changing the country. `system_server` only honours it when `ro.product_ship` is `false` at the moment it starts, so the module sets that briefly, restarts the framework (the screen goes black for about 30 s), checks that 6 GHz is offered, and puts `ro.product_ship` back. Runtime properties only, reverting on reboot; the sales code and the country aren't touched, so **Samsung Wallet keeps working**.

- The hotspot's security must be **WPA3** on 6 GHz (Settings switches it for you).
- Transmit power and channels still follow the regulatory country the Wi-Fi driver detects.
- Until the next reboot, Samsung's extra debug logging is on in the apps that started during the restart (logcat only).
- v1.3.3 and earlier set the CSC country to `IN` instead. On a non-Indian model that made Samsung's servers refuse the phone, and Samsung Wallet showed "there's a problem with Google Play services". After updating and rebooting, clear Samsung Wallet's storage (Settings → Apps → Samsung Wallet → Storage → **Clear data**) if it still won't open.

The hotspot can't do Wi-Fi 7 (802.11be): neither the S23's nor the S24's `hostapd` is built with it.

<a id="display-log-video-and-vulkan"></a>

<a id="horizontal-lock"></a>

## 🎬 Horizontal lock

Camera → Video → Super steady (the running-person icon) → **Super steady with horizontal lock**.

The S23's Qualcomm stabilizer has horizon levelling built in, but the S23 never shipped the feature: Samsung's driver never switches it on, and the camera tuning caps the correction at 8°. `camextras` patches copies of the four EIS libraries (node and stabilizer, for the recording and for the viewfinder) to switch levelling on in this mode and raise the cap to 30°. The copies are bound from storage, and each patch is found by its instructions, so other builds with the same code get it too.

What it does and doesn't do, measured on the phone (gyroscope against the recorded video):

- **Levels small tilts.** Up to about 20° the horizon stays level, in the viewfinder and the recording. Before, the picture turned with the phone.
- **About 20° at most.** Super steady keeps about 20% of the image as spare crop margin, and rotating the picture uses it up. Past about 20° the rest of the tilt shows. There are no black corners: the stabilizer stops at the edge of its margin.
- **Not 360°.** The Galaxy S26's horizontal lock levels through a full turn because it crops the picture much tighter. The S23 would need its crop margin raised to about 100%, which this tweak doesn't do. Qualcomm's levelling also snaps to the nearest 90° orientation, so if you turn the phone further, the picture turns with it.
- **Trails quick moves.** The correction is smoothed, so fast twists show briefly before the picture settles.
- **Ultrawide only.** Super steady normally records with the ultrawide (0.6×). If it switches to the main 1× camera, the margin is too small for levelling to show.

## 🎨 Display, Log video and Vulkan

- **Always On Display**: *Lock screen and AOD → Always On Display* gets *Show Lock screen wallpaper*. *Erase background* only works with a photo wallpaper whose subject was cut out by the wallpaper editor (a "layered" wallpaper), not with the AI weather wallpaper.
  - **AOD brightness**: the S23 ships the AOD's light-sensor brightness table empty, so the AOD sits at its minimum in any light (the AOD app logs `getBrightnessValues not matched!`). The tweak adds the S24 Ultra's table (2 nits in the dark up to 490 nits above 3000 lux) with a small framework overlay (`files/aodbright.apk`, source in `src/aodbright`), layered onto `/product/overlay` in memory; the framework restarts once. Nothing is written to the phone, and it's gone after a reboot without the tweak.
- **Log video**: in *Pro video*, tap **LOG** at the top. The S23's camera already records 10-bit; the tweak only turns on Samsung's switches for it.
- **Vulkan**: Samsung's renderer ignores the S24's `ro.hwui.use_vulkan`; the tweak sets `debug.hwui.renderer=skiavk`. Check with `adb shell dumpsys gfxinfo com.android.systemui | grep Pipeline` (should say `Skia (Vulkan)`).

<a id="downloaded-tweaks-camerahdr-hdr2023-audioeraser-colortone-galaxyai-settingssearch"></a>

## ⬇️ Downloaded tweaks: camerahdr, hdr2023, audioeraser, colortone, galaxyai, settingssearch

These need files from Samsung firmware (from the S24's for the last three, and from the S23's own One UI 6
firmware for `camerahdr` and `hdr2023`). Each one is a separate file in the GitHub release `payloads-S918WVLU8GZIF`,
downloaded by the phone only when you pick that tweak. Its SHA-256 is pinned in `device/tweaks.sh`, and
it's kept in `/data/adb/s23tweaks/payload/` so it isn't downloaded again.

- **camerahdr** (untested): One UI 9 dropped the S23's ArcSoft multi-frame HDR and low-light HDR steps.
  The camera app still has them and, without them, runs a pass-through step that leaves the photo
  unprocessed. The tweak adds back the One UI 6 libraries and their entries in the camera's processing
  list. Details and how to check it: [docs/findings.md](docs/findings.md).
- **hdr2023**: binds the One UI 6 (2023) builds of the ArcSoft hybrid HDR and bracketed HDR engines and
  their Samsung wrappers over today's four libraries in `/system/lib64` (each checked by MD5 before use).
  For anyone who prefers the older HDR look; pick it by number.
- **audioeraser**: the S23's video editor engine was built without the audio scanner. The tweak swaps in
  the S24 engine and adds its sound-separation libraries and two models.
- **colortone**: Samsung compiled the S23's Settings to hide the switch. The tweak patches one byte in
  a patched copy of Settings, kept on storage (`device/files/SecSettings-ead-<firmware>.patch`, checked by MD5; `tools/eadpatch.py` makes one for another firmware's Settings app) and adds the S24's
  colour-tone service.
- **galaxyai**: binds the S24 builds of the three apps over the S23's. While it's on, it replaces any
  Galaxy Store update of Personal Data Intelligence; after a reboot without it, Galaxy Store offers the
  update again.
- **settingssearch**: binds the S24's Settings search app (same Samsung signature) over the S23's. The
  new search bar shows; the natural-language answers stay off, because they need Samsung's Semantic
  Search Core 4.x and both phones ship only a 1.0 placeholder.

<a id="call-screening"></a>

## 📞 Call screening

The Phone app's Call screening needs Samsung Language Core. The S23 firmware doesn't have it, and
Galaxy Store refuses the S23 ("not compatible", 9908). `callscreen` installs it (version 4.0.01.24,
signed by Samsung) as an ordinary app.

- **What works:** the Call screening switch, *Screen call* on incoming calls, the greeting read to the
  caller, recording the caller's voice message, and the AI summary of the call. The summary needs this
  exact build, 4.0.01.24 (the one on APKMirror, MD5 `994620f3071706391d17ff132ea16c42`), which is the
  one `callscreen` installs. An earlier test with another Language Core build failed with "Something
  went wrong while summarizing this call".
- **Not tested yet:** the AI replies to the caller.
- **Installing it yourself:** if `callscreen` can't install it, download Samsung Language Core
  4.0.01.24 from APKMirror and install it like any APK.
- **A 3.1 GB download.** GitHub caps a release file at 2 GB, so the phone downloads Language Core in
  two parts, checks each against its SHA-256, joins them, checks the APK's MD5, installs it and
  deletes the download. It needs about 7 GB free while it does this; use Wi-Fi.
- **It stays after a reboot**, unlike the other tweaks. Remove it with
  `adb shell pm uninstall com.samsung.android.offline.languagemodel`.

<a id="hiding-the-modules-mounts"></a>

## 🫥 Hiding the module's mounts

Every tweak is applied by bind- and overlay-mounting files into init's mount namespace, so the changes
are visible to the whole system. A side effect is that **every app inherits those mounts**, and an app
that scans `/proc/self/mountinfo` (root detectors, some banking apps) sees the module's bind/overlay
mounts and flags the device as modified — even though the files themselves are stock Samsung files.

`hideksu` hides those mounts automatically. It ships `files/hidemnt`, a small native daemon that watches
app spawns (through the kernel's process-event connector) and, the moment an app starts, enters **only
that app's** mount namespace and detaches the module's mounts there. The system and every other app keep
seeing the mounts, so nothing breaks. It is namespace-local and leaves no trace in the app: no code is
injected, and the files it would have seen are simply the stock ones.

- **Which apps, by default:** it hides the mounts from **every user-installed app** (the banking apps and
  root detectors that have no business seeing them) and **keeps them for every preinstalled system/Samsung
  app** (Camera, Gallery, Settings, the Galaxy AI apps …) — the only apps that actually consume the
  tweaks. The split is by install origin (the app's `FLAG_SYSTEM`), which stays set even on a system app
  updated through the Galaxy Store, so updated consumers are kept too. Samsung's own apps installed from
  the Galaxy Store (`com.samsung.*`, `com.sec.*`: Voice Recorder, Samsung Health, …) are kept as well. The
  list of system apps comes from the package manager at each apply. You don't have to list anything.
- **Overrides:** `/data/adb/s23tweaks/hide-apps.txt` (created on first apply) fine-tunes the default, one
  package per line (`#` starts a comment): a plain `com.example.app` **force-hides** a system app, and a
  leading-dash `-com.example.app` **force-keeps** a user-installed one. The daemon reloads the file when
  it changes — no re-apply needed.
- **Why not just use KernelSU's umount:** KernelSU's built-in "umount modules" strips the mounts from
  *every* non-root app at launch, which also hides them from the Samsung apps that need them and silently
  turns those tweaks off. Hiding by install origin protects every bank/detector automatically while never
  touching a consumer, because no consumer is ever user-installed.
- **Scope:** this hides the module's mounts only. The KernelSU manager app is hidden separately by the
  patched `services.jar` (above). Together they clear mount- and package-based detection; verified against
  Native Detector 7.7.0, which went from flagging suspicious/inconsistent mounts to "The Environment is
  normal".
- It never detaches anything in init's own mount namespace. Some app processes share it (Chrome's app
  zygote does), and a detach there would remove the tweaks for the whole phone.
- It runs only while `hideksu` is on.

<a id="dual-sim-5g"></a>

## 📶 Dual SIM 5G

With two SIMs, the S23 Ultra normally gives 5G standalone (SA) only to the SIM picked for mobile data;
the other one drops to LTE, and they swap within a second when you change the data SIM. That isn't the
hardware: the modem (Snapdragon X70) supports 5G on both SIMs in dual standby ("5G+5G DSDS"), and
Android already asks it for 5G on both. The modem's own policy files decide:

- `/policyman/device_config.xml`: `<msim_config mode="5G_PLUS_5G" list="msim_plmns"/>`, so 5G+5G applies only on the networks in `msim_plmns`;
- `/policyman/global_defines.xml`: Samsung's `msim_plmns` is `460-* 712-*`, China and Costa Rica only;
- everywhere else the modem runs 5G+4G, and `/policyman/disable_sa_ndds.xml` removes the SA bands from the SIM that isn't the data SIM.

`dual5g` adds your SIMs' mobile country codes to `msim_plmns`: it reads them from the SIMs (and the
networks they're on) at each apply, adding all of a country's codes where it has several (India 404, 405,
406; the US 310–316; Japan 440, 441; the UK 234, 235). It only adds; what's already listed stays. The
file lives in the modem's storage (EFS), which the module reaches with its own small tool
(`files/efstool`, source in `src/efstool`) through the phone's stock `diag_socket_log` — no computer,
nothing flashed. The modem only reads the file when it starts, so after a change the module restarts
just the modem (about 15 seconds without signal, no phone reboot). At later boots, when the list already
has your country, nothing is written and the modem isn't restarted.

**Backups, before anything is changed:**

- the original file (and the two related policy files, for reference) goes to `/data/adb/s23tweaks/dual5g/stock/` once, before the first write, and is never overwritten;
- a copy of it, with a README, goes to **Download/s23tweaks-modem-backup/** on the phone, where you can see it and copy it off;
- every write also saves the file it replaces as `/data/adb/s23tweaks/dual5g/before-<date>.xml`;
- each write is read back from the modem and compared; if it doesn't match, the previous file is written back.

**Undo:** un-pick `dual5g` and apply, or remove the module: the original file goes back and the modem
restarts. By hand:

```sh
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh dual5g-restore"
```

Without the module at all, the service menu rewrites the modem's stock config: dial `*#27663368378#` →
ETC → MCFG → **MCFG HW & SW RELOAD**. A firmware update can also reset the list; the next apply adds
your country again.

Whether a SIM shows 5G still depends on its coverage where you are. Tested on an SM-S918W with Airtel
(data) and Jio: before, the standby SIM was never on SA; after, it stayed on SA while Airtel had data,
and both were on SA (and VoNR) at once.

<a id="undo"></a>

## ↩️ Undo

**Remove the module** (KernelSU → Modules → S23 Ultra Tweaks → Uninstall) and reboot. During that
boot the module cleans up after itself once the phone is unlocked:

- removes AirDrop's Play services flag overrides;
- uninstalls Samsung Language Core and its Call screening settings, if `callscreen` installed it;
- uninstalls the AI Core stub, if `weather` installed it (unpicking `weather` also removes it);
- puts the Camera app's Director's view setting back the way it was (`camextras`);
- puts the modem's original 5G+5G list back, if `dual5g` changed it (unpicking `dual5g` also does);
- drops Android's cached manifests of the apps the tweaks swap, so the stock apps are re-read;
- deletes `/data/adb/s23tweaks` (downloads, logs, backups) and the boot script.

The mounts themselves were already undone by the reboot. To clean up by hand:

```sh
adb shell su -c "sh /data/adb/modules/s23_ultra_tweaks/tweaks.sh cleanup"
```

Without removing anything, a plain reboot puts the phone back to stock except for those persistent
items (the flags do nothing on their own; `tweaks.sh unflag` removes just them).

<a id="known-limitations"></a>

## ⚠️ Known limitations

- **AirDrop needs One UI 9 build GZIF** (S918WVLU8GZIF, S918BXXUAGZIF, S918U1UEU8GZIF, S918USQU8GZIF or S918NKSU8GZIF). The modules are built on the S918W kernel. The other four have the same Wi-Fi drivers and the same kernel symbol CRCs, checked with `tools/kocompat.py` and `tools/modcmp.py` against their firmware files, but only the S918W and S918B have been tested on a phone. A different build needs the modules rebuilt (below).
  - **Custom kernels** (untested, opt-in): on one of those builds with a non-Samsung 5.15 android13 kernel, `su -c touch /data/adb/s23tweaks/allow-any-kernel` lets AirDrop and Wi-Fi 7 try anyway. The kernel needs `CONFIG_MODVERSIONS` and must not force module signatures. It still refuses the modules if any kernel symbol they use has a different CRC, and the module then puts the stock Wi-Fi driver back. Delete the file to go back to the check. AirDrop also needs the kernel's stock Wi-Fi stack: a kernel that ships its own `cfg80211.ko` (its `vermagic` isn't `5.15.197-android13-8-34343818-ab…`) makes the S24 driver fail to register, so AirDrop is shown as not available there; Wi-Fi 7 and the 6 GHz hotspot still work (issue #21).
- **Horizontal lock levels only up to about 20°** and isn't the S26's 360° lock (see [Horizontal lock](#horizontal-lock)).
- The Wi-Fi link to the PCIe bus stays at Gen2, so very large transfers may be slower than on an S24.
- `callrec` and `india` work on the carrier config of whatever sales code the phone runs (the folder in `mdc.system.path`). `callrec` decodes the stock `cscfeature.xml` on the phone (`files/omcdec`, from `src/omcdec`) and adds the two recording keys to every `FeatureSet`, so it needs no per-firmware files. `india` binds the INS files of S918BXXUAGZIF (One UI 9) over the phone's `cscfeature.xml`, `customer_carrier_feature.json` and `customer.xml`, and adds the INS keystrings and regulatory images to a copy of its prism folder. `india` also runs `resetprop` so the phone reports itself as the Indian S23 Ultra (model `SM-S918B`, sales code `INS`, country `IN`): Samsung's server then accepts it as an Indian device, so Samsung Wallet's India features (UPI, DigiLocker, transit) and the 6 GHz hotspot work. That is a runtime property override only — it reverts on reboot and writes none of the CSC files, so there is no factory-reset risk — but while it is on the reported model changes for every app, and adding bank payment cards may still fail because that path checks the real model through hardware attestation. So far `callrec` is tested on XAC and EUX, and `india` on XAC (carrier config and Samsung Wallet verified). Neither tweak ever writes the sales code (`mps_code.dat`, `sales_code.dat`, `omc.info`); changing those on disk can factory-reset the phone.
- Tested on an SM-S918W (S918WVLU8GZIF, XAC, Android 17, Play services 26.45). On an SM-S918B (S918BXXUAGZIF, EUX) `airdrop`, `wifi7` (without a multi-link connection), `colortone`, `callrec` and `battery` have also been tested. A contributor tested `cam24fps` on an S918B (S918BXXUAGZIF). On an SM-S918U1 (S918U1UEU8GZIF, XAA) `logvideo` records Log in HEVC, and `tenbit` found its three changes in that build's own camera driver. Reports from other models are welcome.

<a id="other-firmware-let-your-ai-agent-build-it"></a>

## 🤖 Other firmware: let your AI agent build it

The kernel modules only load on the exact kernel they were built for. If your S23 Ultra runs different firmware, the module page marks `airdrop` and `wifi7` as unavailable. You can build your own modules by handing the job to an AI coding agent (Claude Code, Codex, Cursor and similar):

1. Clone this repo and open the agent in it, on a computer with Docker and your phone connected over USB (rooted, USB debugging on).
2. Tell it something like:

   > Read AGENTS.md and build the kernel modules and payload for my phone's firmware. Show me every script before you run it on the phone.

[AGENTS.md](AGENTS.md) tells the agent:

- **Rules for working on your phone:** show every script before running it, never write to a partition, and never touch the sales code.
- **What to download:** the Samsung kernel source for your firmware, the matching compiler, and the S24 firmware the payload files come from.
- **How to rebuild:** regenerate the symbol-version data from your phone's own modules, re-derive the values that change per firmware, and rebuild the payload.
- **How to test** safely on the phone, step by step.

It takes a few hours of mostly downloading and compiling. The Samsung source and the S24 firmware together are about 25 GB. The rest of the tweaks (`battery`, `features`, `hotspot6g`) don't need any of this.

<a id="building-the-kernel-modules"></a>

## 🛠️ Building the kernel modules

You only need this to change the modules or to support other firmware. To port everything to another firmware, see [AGENTS.md](AGENTS.md). You need Docker (an x86-64 image; it runs under emulation on Apple Silicon), AOSP clang `clang-r450784e`, and Samsung's kernel sources from <https://opensource.samsung.com>:

- `SM-S918B_17_Opensource.zip` (S23 Ultra): extract `Kernel.tar.gz` to `/work/s23` in a Docker volume.
- `SM-S928B_17_Opensource.zip` (S24 Ultra): extract `Kernel.tar.gz` to `/work/s24`. The driver, Wondertap and `wonder` sources are under `vendor/qcom/opensource/wlan`.

```sh
docker build -t s23kbuild build -f build/Dockerfile
docker build -t s23kbuild16 build -f build/Dockerfile.cc16
run() { docker run --rm --platform linux/amd64 -v s23kvol:/work -v /path/to/clang-r450784e:/clang:ro \
          -v "$PWD":/repo:ro -v "$PWD/out":/out "$@"; }
run s23kbuild   bash /repo/build/prep-vendor-tree.sh   # Samsung's vendor-module config for GZIF
run s23kbuild   bash /repo/build/build-kiwi.sh         # out/kiwi_v2.ko
run s23kbuild   bash /repo/build/build-wonder.sh       # out/wonder.ko
run s23kbuild16 bash /repo/build/build-mhifix.sh       # out/mhifix.ko
run s23kbuild16 bash /repo/build/build-bwfix.sh        # out/bwfix.ko
```

`build/Module.symvers.base` and `build/extra.symvers` hold the export CRCs of the GZIF kernel and its vendor modules, so the modules load without `modprobe --force`. The phone-side helpers (`moseyrun`, `pbflag`, plus a static `sqlite3`) build with the Android NDK: `aarch64-linux-android34-clang -O2 -static`.

<a id="legal"></a>

## ⚖️ Legal

The scripts and the source in `src/` are GPL-2.0 (see `LICENSE`); the kernel modules have to be. The driver and `wonder` binaries are built from Samsung's and Google's GPL sources listed above. The release payload also contains files from the Galaxy S24 Ultra firmware (Qualcomm Wi-Fi firmware, Google's Mosey app and daemon). Those belong to their owners and are only provided so the S23 can use a feature its hardware supports. This project is not affiliated with Samsung, Google, Qualcomm or Apple. AirDrop is a trademark of Apple Inc.
