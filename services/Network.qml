pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs
import qs.modules.common
import qs.services.network

/**
 * Network service with nmcli.
 */
Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    // One join at a time; each run carries its own target and attempt number, so a result only
    // lands on the row it was launched for.
    property bool wifiConnecting: false
    property WifiAccessPoint wifiConnectTarget
    // Counts the attempts, so a run that has been superseded or given up on can be told from the
    // one the panel is waiting for - two taps on the same network are two different attempts.
    property int wifiJoinSeq: 0
    // What the switch was last asked for, held until nmcli's own state agrees (radioTimeout)
    property bool wifiRadioPending: false
    property bool wifiRadioWanted: false
    // The last thing a command said when it failed, for the panel's one error line
    property string wifiActionError: ""
    // The switch was flipped from the palette or a pill, with no Wi-Fi list open to show an error line: a failure is
    // said in the notch instead of being left in wifiActionError for the next time the list opens
    property bool wifiRadioFromNotch: false
    // The wifi interface, from the device list: what `device disconnect` needs
    property string wifiDevice: ""
    // The device list has been read once, so an empty wifiDevice means no adapter and not "not asked yet"
    property bool devicesKnown: false
    property string connectivity: ""
    // nmcli's own words are parsed here, so every call that reads them is pinned to C
    readonly property var cLocale: ({
        "LANG": "C",
        "LC_ALL": "C"
    })
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    // Stable across scans: saved networks first, then strength in bands of 20, then the name, so
    // a scan that moves a signal by a few points does not reshuffle the rows under the pointer.
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active && !b.active)
            return -1;
        if (!a.active && b.active)
            return 1;
        // A network you already have a profile for is one click away: those come first.
        const known = (root.isKnown(b.ssid ?? "") ? 1 : 0) - (root.isKnown(a.ssid ?? "") ? 1 : 0);
        if (known !== 0)
            return known;
        const band = Math.floor((b.strength ?? 0) / 20) - Math.floor((a.strength ?? 0) / 20);
        if (band !== 0)
            return band;
        return (a.ssid ?? "").localeCompare(b.ssid ?? "");
    })
    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength
    property string networkInterface: ""
    property string ipAddress: ""
    property string publicIpAddress: ""
    property string gateway: ""
    property string macAddress: ""
    // One ladder for the bar glyph and the list rows alike: they read the same signal differently.
    function strengthIcon(strength: int): string {
        return strength > 80 ? "signal_wifi_4_bar"
            : strength > 60 ? "network_wifi_3_bar"
            : strength > 40 ? "network_wifi_2_bar"
            : strength > 20 ? "network_wifi_1_bar"
            : "signal_wifi_0_bar";
    }
    property string materialSymbol: root.ethernet
        ? "lan"
        : (root.wifiEnabled && root.wifiStatus === "connected")
            ? root.strengthIcon(root.active?.strength ?? 0)
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "wifi_find"
                    : (root.wifiStatus === "disabled")
                        ? "signal_wifi_off"
                        : "signal_wifi_bad"

    // Control
    function radioFailed(text: string): void {
        if (root.wifiRadioFromNotch)
            IslandController.request("note", { "icon": "signal_wifi_off", "text": text }, 65);
        else
            root.wifiActionError = text;
    }
    function enableWifi(enabled = true, fromNotch = false): void {
        root.wifiRadioFromNotch = fromNotch;
        root.wifiRadioWanted = enabled;
        root.wifiRadioPending = true;
        root.wifiActionError = "";
        radioTimeout.restart();
        root.run(["nmcli", "radio", "wifi", enabled ? "on" : "off"], r => {
            if (!r.success) {
                root.wifiRadioPending = false;
                radioTimeout.stop();
                root.radioFailed(root.failureText(Translation.tr("Wi-Fi did not change"), r.error));
            }
            root.update();
        }, root.cLocale);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled, true);
    }

    // Without a deadline, a radio change the hardware refused (an rfkill block) would latch the
    // switch on what was asked for and never say anything.
    Timer {
        id: radioTimeout
        interval: 8000
        onTriggered: {
            root.wifiRadioPending = false;
            root.radioFailed(root.wifiRadioWanted ? Translation.tr("Wi-Fi did not turn on") : Translation.tr("Wi-Fi did not turn off"));
        }
    }

    function rescanWifi(): void {
        if (root.wifiScanning)
            return;   // one scan at a time: a second request would end the first one's indicator
        wifiScanning = true;
        scanStart.running = true;
    }

    // The SSIDs of the saved connection profiles: a network with one connects straight away; a
    // secure one without asks for its password FIRST. Before, the connect ran at once, which
    // made NetworkManager drop the current link, fail for want of a password, and only then ask.
    // A profile's name is not always its SSID ("MyWifi 1" for a second one, or what an installer or another tool
    // called it), so the SSID is read from the profile itself and commands that act on a profile use its name.
    property var savedProfiles: []
    // [{name, uuid, ssid, lastUsed}] with lastUsed in ms, 0 = never joined (a profile that never got a
    // password, from the old connect flow, or one made elsewhere)
    property var savedConnections: []
    function isKnown(ssid: string): bool {
        return root.savedProfiles.includes(ssid);
    }
    // the saved profile for an SSID: the one named for it when there is one, else the one joined last
    function profileFor(ssid: string): string {
        const mine = root.savedConnections.filter(c => c.ssid === ssid);
        return (mine.find(c => c.name === ssid) ?? mine.sort((a, b) => b.lastUsed - a.lastUsed)[0])?.name ?? ssid;
    }
    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        if (accessPoint.active)
            return;
        if (accessPoint.isSecure && !root.isKnown(accessPoint.ssid)) {
            accessPoint.askingPassword = true;   // nothing touches the current link yet
            return;
        }
        accessPoint.askingPassword = false;
        // a saved profile under another name is brought up by that name: `dev wifi connect` would make a second one
        const profile = root.profileFor(accessPoint.ssid);
        if (profile !== accessPoint.ssid) {
            root.startJoin(accessPoint, ["nmcli", "--wait", "20", "connection", "up", "id", profile], false, root.cLocale);
            return;
        }
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile
        root.startJoin(accessPoint, ["nmcli", "--wait", "20", "dev", "wifi", "connect", accessPoint.ssid], false, root.cLocale);
    }

    // Every join gets its own process with its target captured for that run: tapping a second
    // network no longer kills the first nmcli and hands its result to the wrong row.
    function startJoin(ap: WifiAccessPoint, cmd: var, freshProfile: bool, env: var): void {
        const ssid = ap.ssid;
        root.wifiJoinSeq = root.wifiJoinSeq + 1;
        const attempt = root.wifiJoinSeq;
        root.wifiConnectTarget = ap;
        root.wifiConnecting = true;
        root.wifiActionError = "";
        ap.lastError = "";
        joinTimeout.restart();
        root.run(cmd, r => {
            // A fresh join that failed leaves a half-made profile behind, which would make the
            // next click skip the password and fail again: take it away. Done even for a run that
            // was superseded, since nobody else will.
            if (!r.success && freshProfile)
                root.run(["nmcli", "connection", "delete", ssid], () => root.update(), root.cLocale);
            if (root.wifiJoinSeq !== attempt)
                return;   // superseded by another tap, or given up on: not the panel's state now
            joinTimeout.stop();
            root.wifiConnecting = false;
            root.wifiConnectTarget = null;
            if (!r.success) {
                // Only a refused secret asks for a password again; every other failure says what
                // it was, because an open network has no password to check.
                const secrets = /secret|802-11-wireless-security|802-1x/i.test(r.error ?? "");
                const enterprise = root.isEnterprise(ap);
                ap.askingPassword = ap.isSecure && (secrets || freshProfile || enterprise);
                ap.lastError = secrets
                    ? (enterprise ? Translation.tr("Could not join · check the name, password or method") : Translation.tr("Could not join · check the password"))
                    : root.failureText(Translation.tr("Could not join"), r.error);
            }
            root.update();
            getNetworks.running = true;
        }, env);
    }

    // nmcli is given --wait, so this is the backstop for a run that never reports at all: a row
    // must never stay locked on "Connecting" with no way out.
    Timer {
        id: joinTimeout
        interval: 30000
        onTriggered: root.cancelJoin(Translation.tr("Could not join · timed out"))
    }

    // Giving up means stop trying: nmcli's wait is only a wait, NetworkManager would carry on
    // associating by itself, so the device goes down too.
    function cancelJoin(message: string): void {
        const ap = root.wifiConnectTarget;
        joinTimeout.stop();
        root.wifiJoinSeq = root.wifiJoinSeq + 1;   // the run still out there stops speaking for the panel
        root.wifiConnecting = false;
        root.wifiConnectTarget = null;
        if (ap)
            ap.lastError = message;
        else
            root.wifiActionError = message;
        root.disconnectDevice(r => root.update());
    }

    // A network row forgets the network: every profile saved for the SSID, whatever it is called, or it would still
    // read as known. A row of the saved list names its own profile and only that one goes.
    function forgetWifiNetwork(ssid: string, profile = ""): void {
        // Deleting the profile you are on drops the link and NetworkManager then auto-activates
        // another saved one, so the device goes down first when it is the network in use.
        const onIt = root.wifiDevice.length > 0 && (profile.length > 0 ? root.networkName === profile : (root.active?.ssid ?? "") === ssid);
        const names = profile.length > 0 ? [profile] : root.savedConnections.filter(c => c.ssid === ssid).map(c => c.name);
        root.run(["bash", "-c", (onIt ? 'nmcli device disconnect "$DEV" >/dev/null 2>&1; ' : "")
            + 'rc=0; while IFS= read -r n; do nmcli connection delete id "$n" || rc=1; done <<< "$NAMES"; exit $rc'], r => {
            if (!r.success)
                root.wifiActionError = root.failureText(Translation.tr("Could not forget %1").arg(ssid), r.error);
            root.update();
            getNetworks.running = true;
        }, { "DEV": root.wifiDevice, "NAMES": (names.length > 0 ? names : [ssid]).join("\n"), "LANG": "C", "LC_ALL": "C" });
    }

    // ---- one-shot commands with a result (caelestia Nmcli.executeCommand, in our Process style)
    component OneShot: Process {
        id: shot
        property var callback: null
        property string out: ""
        property string err: ""
        stdout: StdioCollector {
            onStreamFinished: shot.out = text
        }
        stderr: StdioCollector {
            onStreamFinished: shot.err = text
        }
        onExited: (code, status) => {
            if (callback)
                callback({ success: code === 0, output: out, error: err, exitCode: code });
            destroy();
        }
    }
    Component {
        id: oneShotComponent
        OneShot {}
    }
    function run(cmd: var, callback: var, env: var): void {
        const p = oneShotComponent.createObject(root, { callback: callback });
        if (env)
            p.environment = env;
        p.command = cmd;
        p.running = true;
    }

    // nmcli's terse output escapes a ":" inside a value as "\:" (and a "\" as "\\"), so a plain
    // split corrupts every field after the first one that contains either.
    function splitTerse(line: string): var {
        const fields = [];
        let field = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length)
                field += line[++i];
            else if (c === ":") {
                fields.push(field);
                field = "";
            } else
                field += c;
        }
        fields.push(field);
        return fields;
    }

    // What went wrong, in plain words. nmcli's stderr is logged, never shown; only the failures people
    // actually hit are named, anything else shows the prefix alone.
    function failureText(prefix: string, err: string): string {
        const raw = (err ?? "").trim();
        if (raw.length === 0)
            return prefix;
        console.warn(`Network: ${prefix}: ${raw}`);
        const reasons = [
            [/no network with ssid|out of range/i, Translation.tr("the network is out of range")],
            [/ip configuration|dhcp/i, Translation.tr("the network did not answer")],
            [/timed out|timeout/i, Translation.tr("it took too long")],
            [/not authorized|not authorised|permission|insufficient privileges/i, Translation.tr("this account is not allowed")],
            [/not running|could not create nmclient|unable to connect|org\.freedesktop\.networkmanager/i, Translation.tr("restart the computer and try again")],
            [/busy|unavailable|not ready|device is not/i, Translation.tr("the Wi-Fi adapter is busy")]
        ];
        for (const [re, text] of reasons)
            if (re.test(raw))
                return `${prefix} · ${text}`;
        return prefix;
    }

    // ---- security, as nmcli names it
    function isEnterprise(ap: WifiAccessPoint): bool {
        return /802\.1X|EAP/i.test(ap?.security ?? "");
    }
    function securityLabel(sec: string): string {
        const s = (sec ?? "").trim();
        if (s.length === 0 || s === "--")
            return Translation.tr("Open");
        if (/802\.1X|EAP/i.test(s))
            return "802.1X";
        if (/WPA3/.test(s))
            return "WPA3";
        if (/WPA2/.test(s))
            return "WPA2";
        return s.split(" ")[0];
    }

    // ---- enterprise (802.1X): PEAP + MSCHAPv2 covers eduroam and most offices; TTLS + PAP
    // is the other one seen in the wild. A new profile is created with the password in hand and
    // removed again if the join fails, so a retry starts clean (caelestia AddNetworkPage).
    function joinEnterprise(ap: WifiAccessPoint, identity: string, password: string, method: string): void {
        const ssid = ap.ssid;
        const eap = method === "ttls" ? "ttls" : "peap";
        const phase2 = method === "ttls" ? "pap" : "mschapv2";
        ap.askingPassword = false;
        // An 802.1X profile that already exists may carry certificates, a CA file or a phase-2
        // method set up elsewhere: change only the credentials on it and never replace it.
        const known = root.isKnown(ssid);
        const modify = 'nmcli connection modify id "$PROFILE" 802-1x.identity "$IDENT" 802-1x.password "$PASSWORD" && nmcli --wait 20 connection up id "$PROFILE"';
        const create = 'nmcli connection add type wifi ifname "*" con-name "$SSID" ssid "$SSID" wifi-sec.key-mgmt wpa-eap 802-1x.eap "$EAP" 802-1x.phase2-auth "$P2" 802-1x.identity "$IDENT" 802-1x.password "$PASSWORD" && nmcli --wait 20 connection up "$SSID" || { nmcli connection delete "$SSID" >/dev/null 2>&1; exit 1; }';
        root.startJoin(ap, ["bash", "-c", known ? modify : create], false,
            { "SSID": ssid, "PROFILE": root.profileFor(ssid), "EAP": eap, "P2": phase2, "IDENT": identity, "PASSWORD": password, "LANG": "C", "LC_ALL": "C" });
    }

    // ---- a hidden network: a profile with hidden=yes so NetworkManager probes for it
    // (caelestia Nmcli.addHiddenNetwork)
    property bool hiddenJoinFailed: false
    property bool hiddenJoining: false
    property string hiddenError: ""
    function joinHidden(ssid: string, password: string): void {
        if (!ssid)
            return;
        root.hiddenJoinFailed = false;
        root.hiddenJoining = true;
        root.hiddenError = "";
        const secure = (password ?? "").length > 0;
        // A profile with the name typed here may already exist and be someone's working
        // configuration: set the hidden flag and the key on it rather than replacing it.
        const modify = 'if [ -n "$PASSWORD" ]; then nmcli connection modify id "$PROFILE" 802-11-wireless.hidden yes wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PASSWORD"; else nmcli connection modify id "$PROFILE" 802-11-wireless.hidden yes; fi && nmcli --wait 20 connection up id "$PROFILE"';
        const create = 'if [ -n "$PASSWORD" ]; then nmcli connection add type wifi ifname "*" con-name "$SSID" ssid "$SSID" 802-11-wireless.hidden yes wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PASSWORD"; else nmcli connection add type wifi ifname "*" con-name "$SSID" ssid "$SSID" 802-11-wireless.hidden yes; fi && nmcli --wait 20 connection up "$SSID" || { nmcli connection delete "$SSID" >/dev/null 2>&1; exit 1; }';
        root.run(["bash", "-c", root.isKnown(ssid) ? modify : create],
            r => {
                root.hiddenJoining = false;
                root.hiddenJoinFailed = !r.success;
                root.hiddenError = r.success ? "" : root.failureText(Translation.tr("Could not join"), r.error);
                root.update();
                getNetworks.running = true;
            },
            { "SSID": ssid, "PROFILE": root.profileFor(ssid), "PASSWORD": secure ? password : "", "LANG": "C", "LC_ALL": "C" });
    }

    // ---- hotspot: share this connection. NetworkManager names the profile "Hotspot".
    property bool hotspotActive: false
    property string hotspotError: ""
    function hotspotOn(ssid: string, password: string): void {
        root.hotspotError = "";
        root.run(["bash", "-c", 'dev=$(nmcli -t -f DEVICE,TYPE device status | awk -F: \'$2=="wifi"{print $1; exit}\'); [ -n "$dev" ] || { echo "no wifi device" >&2; exit 1; }; nmcli device wifi hotspot ifname "$dev" ssid "$SSID" password "$PASSWORD"'],
            r => {
                if (!r.success)
                    root.hotspotError = root.failureText(Translation.tr("Hotspot did not start"), r.error);
                root.update();
            },
            { "SSID": ssid, "PASSWORD": password });
    }
    function hotspotOff(): void {
        root.run(["nmcli", "connection", "down", "Hotspot"], r => root.update());
    }
    Process {
        id: hotspotCheck
        command: ["bash", "-c", "nmcli -t -f NAME connection show --active | grep -qx Hotspot && echo on || echo off"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.hotspotActive = text.trim() === "on";
                if (root.hotspotActive)
                    root.hotspotError = "";
            }
        }
    }

    // ---- trust: home and work, marked once; the VPN's auto rule reads it
    function isTrusted(ssid: string): bool {
        return (Persistent.states.network.trusted ?? []).includes(ssid);
    }
    function setTrusted(ssid: string, on: bool): void {
        const list = (Persistent.states.network.trusted ?? []).filter(s => s !== ssid);
        if (on)
            list.push(ssid);
        Persistent.states.network.trusted = list;
        Vpn.applyRule();
    }

    // ---- IPv4 of a saved connection (caelestia Nmcli.getIpv4Config / setIpv4Config)
    function getIpv4Config(name: string, callback: var): void {
        root.run(["nmcli", "-t", "-f", "ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns,connection.autoconnect", "connection", "show", name], r => {
            if (!r.success) {
                callback(null);
                return;
            }
            const cfg = { method: "auto", address: "", gateway: "", dns: "", ignoreAutoDns: false, autoconnect: true };
            for (const line of r.output.trim().split("\n")) {
                const i = line.indexOf(":");
                if (i < 0)
                    continue;
                const key = line.slice(0, i).trim(), value = line.slice(i + 1).trim();
                if (key === "ipv4.ignore-auto-dns")
                    cfg.ignoreAutoDns = value === "yes";
                else if (key === "connection.autoconnect")
                    cfg.autoconnect = value !== "no";
                if (value === "" || value === "--")
                    continue;
                if (key === "ipv4.method")
                    cfg.method = value;
                else if (key === "ipv4.addresses")
                    cfg.address = value.split(",")[0].trim();
                else if (key === "ipv4.gateway")
                    cfg.gateway = value;
                else if (key === "ipv4.dns")
                    cfg.dns = value.replace(/;\s*$/, "").split(/[;,]/).map(d => d.trim()).filter(d => d.length > 0).join(", ");
            }
            if (cfg.method === "auto" && cfg.ignoreAutoDns)
                cfg.method = "auto-dns";
            callback(cfg);
        });
    }
    function setIpv4Config(name: string, cfg: var, callback: var): void {
        const dns = (cfg.dns ?? "").split(",").map(d => d.trim()).filter(d => d.length > 0).join(" ");
        let cmd = ["nmcli", "connection", "modify", name];
        if (cfg.method === "manual")
            cmd = cmd.concat(["ipv4.method", "manual", "ipv4.addresses", cfg.address ?? "", "ipv4.gateway", cfg.gateway ?? "", "ipv4.dns", dns, "ipv4.ignore-auto-dns", "yes"]);
        else if (cfg.method === "auto-dns")
            cmd = cmd.concat(["ipv4.method", "auto", "ipv4.addresses", "", "ipv4.gateway", "", "ipv4.dns", dns, "ipv4.ignore-auto-dns", "yes"]);
        else
            cmd = cmd.concat(["ipv4.method", "auto", "ipv4.addresses", "", "ipv4.gateway", "", "ipv4.dns", "", "ipv4.ignore-auto-dns", "no"]);
        root.run(cmd, r => {
            if (!r.success) {
                callback(r);
                return;
            }
            // reactivate so it takes effect now; a connection that is not up just keeps the change
            root.run(["bash", "-c", 'nmcli -t -f NAME connection show --active | grep -qx -- "$NAME" && nmcli connection up "$NAME" || true'], r2 => callback(r), { "NAME": name });
        });
    }
    // `nmcli connection down` only blocks the profile it took down: NetworkManager then
    // auto-activates the next saved network in range, so the user could never get to an offline
    // state. Taking the device down is what "Disconnect" means.
    function disconnectDevice(callback: var): void {
        if (root.wifiDevice.length === 0) {
            root.wifiActionError = Translation.tr("No Wi-Fi device");
            return;
        }
        root.run(["nmcli", "device", "disconnect", root.wifiDevice], r => {
            if (!r.success)
                root.wifiActionError = root.failureText(Translation.tr("Could not disconnect"), r.error);
            if (callback)
                callback(r);
        }, root.cLocale);
    }
    function disconnectWifiNetwork(): void {
        if (!root.active)
            return;
        root.disconnectDevice(r => {
            root.update();
            getNetworks.running = true;
        });
    }

    // A sign-in page can only stand in for a plain http page: an https one meets the portal's own certificate or a
    // closed port instead. This is the page NetworkManager checks on Arch (networkmanager's 20-connectivity.conf).
    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "http://ping.archlinux.org/nm-check.txt"]);
    }

    function changePassword(network: WifiAccessPoint, password: string): void {
        if (!network.isSecure)
            return;   // an open network has no key to set
        network.askingPassword = false;
        if (root.isKnown(network.ssid)) {
            // a saved profile with a stale key: store the key and bring it up in one command, so
            // one exit code says whether the new key was both stored and used
            root.startJoin(network, ["bash", "-c", 'nmcli connection modify id "$PROFILE" wifi-sec.psk "$PASSWORD" && nmcli --wait 20 connection up id "$PROFILE"'], false,
                { "PASSWORD": password, "PROFILE": root.profileFor(network.ssid), "LANG": "C", "LC_ALL": "C" });
            return;
        }
        // new network: one command creates the profile and connects; the current link is only
        // let go now, with the password in hand
        root.startJoin(network, ["bash", "-c", 'nmcli --wait 20 dev wifi connect "$SSID" password "$PASSWORD"'], true,
            { "PASSWORD": password, "SSID": network.ssid, "LANG": "C", "LC_ALL": "C" });
    }
    // The profile list, then the SSID of each profile it has not read yet (`connection show` lists no SSID column):
    // a profile's SSID does not change, so each is read once.
    property var profileSsids: ({})   // uuid -> ssid
    property var listedProfiles: []
    function publishProfiles(): void {
        const list = root.listedProfiles.map(c => ({ name: c.name, uuid: c.uuid, ssid: root.profileSsids[c.uuid] || c.name, lastUsed: c.lastUsed }));
        root.savedConnections = list;
        root.savedProfiles = list.map(c => c.ssid);
    }
    function readProfileSsids(): void {
        if (ssidProc.running)
            return;   // its end looks again
        const missing = root.listedProfiles.filter(c => !(c.uuid in root.profileSsids)).map(c => c.uuid);
        if (missing.length === 0) {
            root.publishProfiles();
            return;
        }
        ssidProc.uuids = missing;
        ssidProc.command = ["bash", "-c", 'for u in "$@"; do printf "%s\\t%s\\n" "$u" "$(nmcli -e no -g 802-11-wireless.ssid connection show uuid "$u" 2>/dev/null)"; done', "_"].concat(missing);
        ssidProc.running = true;
    }
    Process {
        id: savedProfilesProc
        running: true
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,TIMESTAMP", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = [];
                for (const line of text.split("\n")) {
                    const f = root.splitTerse(line);
                    if (f.length === 4 && f[2] === "802-11-wireless")
                        list.push({ name: f[0], uuid: f[1], lastUsed: Number(f[3]) * 1000 });
                }
                root.listedProfiles = list;
                root.readProfileSsids();
            }
        }
    }
    Process {
        id: ssidProc
        property var uuids: []
        environment: root.cLocale
        stdout: StdioCollector {
            onStreamFinished: {
                const read = Object.assign({}, root.profileSsids);
                for (const u of ssidProc.uuids)
                    read[u] = "";   // one that cannot be read is not asked again; its name stands for it
                for (const line of text.split("\n")) {
                    const t = line.indexOf("\t");
                    if (t > 0)
                        read[line.slice(0, t)] = line.slice(t + 1);
                }
                root.profileSsids = read;
                root.publishProfiles();
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.wifiScanning
        onTriggered: getNetworks.running = true
    }
    // The radio just came on: look for networks at once instead of on the panel's next timer.
    // A short wait first, as the device is still "unavailable" for a moment and refuses a scan.
    Timer {
        id: scanAfterRadio
        interval: 1500
        onTriggered: root.rescanWifi()
    }

    // `nmcli device wifi rescan` asks and returns at once. `list --rescan yes` waited for the scan
    // to finish, and when NetworkManager declined a scan asked for too soon after the last one it
    // sat out its whole 15 s timeout; a real scan on this card takes about 0.2 s.
    Process {
        id: scanStart
        command: ["nmcli", "device", "wifi", "rescan"]
        environment: root.cLocale
        onExited: code => {
            if (code === 0) {
                scanEnd.restart();
            } else {
                // declined (one ran moments ago): the cached list is that scan's
                root.wifiScanning = false;
                getNetworks.running = true;
            }
        }
    }
    Timer {
        id: scanEnd
        interval: 3000
        onTriggered: {
            root.wifiScanning = false;
            getNetworks.running = true;
        }
    }

    // Status update
    // `nmcli monitor` emits a burst of lines for one transition, and a refresh started on top of a
    // refresh still in flight read a half-finished device list: once per burst instead.
    function update(): void {
        updateDebounce.restart();
    }
    // One `nmcli monitor` for the shell: others (Vpn) listen here instead of starting their own.
    signal changed()
    Timer {
        id: updateDebounce
        interval: 150
        onTriggered: {
            root.changed();
            savedProfilesProc.running = true;
            hotspotCheck.running = true;
            updateConnectionType.running = true;
            wifiStatusProcess.running = true;
            getNetworks.running = true;
            updateNetworkName.running = true;
            updateNetworkStrength.running = true;
            updateNetworkDetails.running = true;
        }
    }

    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            // it prints the current state once at start, and everything is read at load anyway
            onRead: if (!settling.running) root.update()
        }
    }
    Timer {
        id: settling
        interval: 1000
        running: true
    }

    Process {
        id: updateConnectionType
        // DEVICE as well: the wifi interface name is what `device disconnect` needs, and it is the
        // only way to tell the radio apart from the wifi-p2p device.
        command: ["sh", "-c", "nmcli -t -f DEVICE,TYPE,STATE d status && nmcli -t -f CONNECTIVITY g"]
        running: true
        // nmcli translates the state values, and they are compared here, so pin the locale.
        environment: root.cLocale
        stdout: StdioCollector {
            // One whole run at a time: a buffer filled by a SplitParser could be emptied under an
            // in-flight child, and the truncated list then read as the real state of the machine.
            onStreamFinished: {
                if (text.trim().length === 0)
                    return;   // the command failed: keep what is known instead of reporting nothing
                const lines = text.trim().split("\n");
                const connectivity = lines.pop() ?? ""; // none, limited, full
                let hasEthernet = false;
                let hasWifi = false;
                let wifiStatus = "disconnected";
                let wifiDevice = "";
                for (const line of lines) {
                    const fields = root.splitTerse(line);
                    if (fields.length < 3)
                        continue;
                    const type = fields[1];
                    // Whole fields, not substrings: "disconnected" contains "connected", and the
                    // state can carry a suffix ("connected (externally)", "connecting (config)").
                    const state = fields[2].split(" ")[0];
                    if (type === "ethernet") {
                        if (state === "connected")
                            hasEthernet = true;
                    } else if (type === "wifi") {
                        wifiDevice = fields[0];
                        if (state === "connected") {
                            hasWifi = connectivity !== "limited";
                            wifiStatus = connectivity === "limited" ? "limited" : "connected";
                        } else if (state === "connecting")
                            wifiStatus = "connecting";
                        else if (state === "unavailable" || state === "unmanaged")
                            wifiStatus = "disabled";
                        else
                            wifiStatus = "disconnected";
                    }
                }
                root.connectivity = connectivity;
                root.wifiDevice = wifiDevice;
                root.devicesKnown = true;
                root.wifiStatus = wifiStatus;
                root.ethernet = hasEthernet;
                root.wifi = hasWifi;
            }
        }
    }

    Process {
        id: updateNetworkName
        // the link's own profile, never a VPN riding on it (a VPN can list first)
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE c show --active | grep -E ':(802-11-wireless|802-3-ethernet)$' | head -1 | cut -d: -f1"]
        running: true
        stdout: StdioCollector {
            // Collected, not per line: with no link the pipeline prints nothing at all, and a
            // parser that only fires on a line kept the last network's name for good.
            onStreamFinished: root.networkName = text.trim()
        }
    }

    Process {
        id: updateNetworkStrength
        running: true
        command: ["sh", "-c", "nmcli -f IN-USE,SIGNAL,SSID device wifi list --rescan no | awk '/^\\*/{if (NR!=1) {print $2}}'"]
        stdout: StdioCollector {
            // As above: with no network in use awk prints nothing, and the last signal stood.
            onStreamFinished: root.networkStrength = parseInt(text.trim()) || 0
        }
    }

    Process {
        id: updateNetworkDetails
        running: true
        command: ["sh", "-c", "device=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$3 == \"connected\" && $2 ~ /^(wifi|ethernet)$/ { print $1; exit }'); if [ -n \"$device\" ]; then nmcli -t -f GENERAL.DEVICE,GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY device show \"$device\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let networkInterface = "";
                let ipAddress = "";
                let gateway = "";
                let macAddress = "";

                for (const line of text.trim().split("\n")) {
                    const separator = line.indexOf(":");
                    if (separator < 0) continue;

                    const key = line.slice(0, separator);
                    const value = line.slice(separator + 1);
                    if (key === "GENERAL.DEVICE")
                        networkInterface = value;
                    else if (key === "GENERAL.HWADDR")
                        macAddress = value;
                    else if (key.startsWith("IP4.ADDRESS") && ipAddress === "")
                        ipAddress = value.split("/")[0];
                    else if (key === "IP4.GATEWAY")
                        gateway = value;
                }

                root.networkInterface = networkInterface;
                root.ipAddress = ipAddress;
                root.gateway = gateway;
                root.macAddress = macAddress;
            }
        }
    }

    // A request to a third party, so it is made only while something that shows the answer is open
    // (the bar's network popup counts itself in here), then again when the link itself changes and
    // the link is actually up - not once per NetworkManager event, and never for a value nothing shows.
    property int publicIpViewers: 0
    readonly property string publicIpKey: root.publicIpViewers > 0 && root.connectivity === "full" ? root.ipAddress : ""
    onPublicIpKeyChanged: {
        if (root.publicIpKey.length === 0)
            root.publicIpAddress = "";
        else
            updatePublicIp.running = true;
    }
    Process {
        id: updatePublicIp
        command: ["curl", "-fsS", "--max-time", "5", "https://api.ipify.org"]
        stdout: StdioCollector {
            onStreamFinished: {
                const candidate = text.trim();
                // an answer that lands after the popup closed is not kept for the next one to show
                root.publicIpAddress = root.publicIpKey !== "" && /^[0-9a-fA-F:.]+$/.test(candidate)
                    ? candidate
                    : "";
            }
        }
    }

    Process {
        id: wifiStatusProcess
        command: ["nmcli", "radio", "wifi"]
        Component.onCompleted: running = true
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const on = text.trim() === "enabled";
                if (on && !root.wifiEnabled) scanAfterRadio.restart();
                root.wifiEnabled = on;
                // nmcli agrees with what the switch was asked for: it can follow the facts again.
                if (root.wifiRadioPending && root.wifiEnabled === root.wifiRadioWanted) {
                    root.wifiRadioPending = false;
                    radioTimeout.stop();
                }
            }
        }
    }

    Process {
        id: getNetworks
        running: true
        // --rescan no: nmcli's default rescans when the last scan is over 30 s old, which with iwd
        // blocks for ~15 s, and a run still in flight swallowed every update started meanwhile
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w", "list", "--rescan", "no"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const allNetworks = text.trim().split("\n").map(n => {
                    const net = root.splitTerse(n);
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: net[3] ?? "",
                        bssid: net[4] ?? "",
                        security: net[5] || ""
                    };
                }).filter(n => n.ssid && n.ssid.length > 0);

                // Group networks by SSID and prioritize connected ones
                const networkMap = new Map();
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid);
                    if (!existing) {
                        networkMap.set(network.ssid, network);
                    } else {
                        // Prioritize active/connected networks
                        if (network.active && !existing.active) {
                            networkMap.set(network.ssid, network);
                        } else if (!network.active && !existing.active) {
                            // If both are inactive, keep the one with better signal
                            if (network.strength > existing.strength) {
                                networkMap.set(network.ssid, network);
                            }
                        }
                        // If existing is active and new is not, keep existing
                    }
                }

                const wifiNetworks = Array.from(networkMap.values());

                const rNetworks = root.wifiNetworks;

                // One object per name, kept across scans: the list shows one row per SSID, and a
                // scan that picks a different BSSID (or band) for that name must not destroy the
                // row - it was losing a password line being typed into. A row a join or a password
                // line is waiting on outlives a scan that misses it, so the result has somewhere
                // to land.
                const destroyed = rNetworks.filter(rn => !wifiNetworks.find(n => n.ssid === rn.ssid)
                    && rn !== root.wifiConnectTarget && !rn.askingPassword);
                for (const network of destroyed)
                    rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

                for (const network of wifiNetworks) {
                    const match = rNetworks.find(n => n.ssid === network.ssid);
                    if (match) {
                        match.lastIpcObject = network;
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: network
                        }));
                    }
                }
            }
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
