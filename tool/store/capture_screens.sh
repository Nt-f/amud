#!/bin/bash
# capture_screens.sh DEVICE DISPLAY OUTDIR [NAMES...]: opens each store screen
# in Amud on a booted simulator (Amud installed) and saves a screenshot of
# DISPLAY ("primary"; on iPhone Duo, "primary" is the outer display and
# "primary-1" the inner). Set the status bar first, as Apple's marketing
# guidelines ask (full signal, Wi-Fi and battery):
#   xcrun simctl status_bar DEVICE override --time 9:41 --dataNetwork wifi --wifiMode active \
#     --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
# Then tool/store/compose_screenshots.swift puts the captions and bezels on.
dev=$1 display=$2 out=$3; shift 3
# the app group the app reads its pending route from (apple/AmudTimeline.swift)
prefs="$(xcrun simctl get_app_container "$dev" page.amud group.page.amud)/Library/Preferences/group.page.amud"
mkdir -p "$out"
screens=(
  "01-home|amud:///"
  "02-pray_shacharit|amud://pray/shacharit"
  "03-torah_gemara_read|amud://torah/read?b=Berakhot&u=2a"
  "04-zmanim|amud://zmanim"
  "05-siddur|amud://siddur"
  "06-learning|amud://learning"
  "07-calendar|amud://calendar"
  "08-torah_tehillim|amud://torah/tehillim"
  "09-pray_birkat|amud://pray/birkat"
)
for s in "${screens[@]}"; do
  name=${s%%|*} url=${s#*|}
  if [ $# -gt 0 ] && [[ ! " $* " == *" $name "* ]]; then continue; fi
  xcrun simctl terminate "$dev" page.amud 2>/dev/null
  sleep 1
  # The route widgets and App Intents leave for the app, read at launch:
  # unlike openurl, it opens without iOS's "Open in Amud?" prompt.
  xcrun simctl spawn "$dev" defaults write "$prefs" amudPendingRoute "$url"
  xcrun simctl launch "$dev" page.amud >/dev/null
  # a debug build starts slowly: the launch animation ends around 30 s
  sleep 45
  xcrun simctl io "$dev" screenshot --display="$display" "$out/$name.png" >/dev/null 2>&1
  echo "$name"
done
