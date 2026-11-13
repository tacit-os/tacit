#!/usr/bin/env bash
# After the computer wakes (hypridle's after_sleep_cmd): Wi-Fi that does not come back is switched off and on once.
# Some adapters and drivers wake wedged: the adapter is listed but never joins again until the radio is cycled by hand.
# Left alone when Wi-Fi was switched off or disconnected on purpose, when there is no adapter, when no saved network
# would join by itself, and when it is already connected (or joining) after the wait.
export LC_ALL=C LANG=C
command -v nmcli > /dev/null 2>&1 || exit 0
[[ "$(nmcli -t -g WIFI radio 2>/dev/null)" == enabled ]] || exit 0
# an adapter NetworkManager may join with by itself: one the person disconnected (Wi-Fi's Disconnect is `nmcli device
# disconnect`) has its autoconnect off until they join again, through a sleep too, and cycling the radio does not change
# that, so it only flapped Wi-Fi off and on and the notch said "Wi-Fi off."
joins=0
for dev in $(nmcli -t -f DEVICE,TYPE device 2>/dev/null | sed -n 's/:wifi$//p'); do
    [[ "$(nmcli -t -g GENERAL.AUTOCONNECT device show "$dev" 2>/dev/null)" == yes ]] && joins=1
done
(( joins )) || exit 0
nmcli -t -f TYPE,AUTOCONNECT connection show 2>/dev/null | grep -qx '802-11-wireless:yes' || exit 0

# NetworkManager rescans and rejoins on its own within a few seconds of waking, so give it that first
for _ in $(seq "${TACIT_WIFI_WAIT:-25}"); do
    nmcli -t -f TYPE,STATE device 2>/dev/null | grep -Eq '^wifi:(connected|connecting)' && exit 0
    sleep 1
done

nmcli radio wifi off
sleep 2
nmcli radio wifi on
