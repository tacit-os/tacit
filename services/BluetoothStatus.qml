pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.devices.values.filter(device => device.connected).length
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    // BlueZ reports a device with no name by falling back to its address with
    // dashes, e.g. "46-95-74-23-1C-E0". Most of those are strangers passing by:
    // modern phones and watches rotate a random address every few minutes, so the
    // entry is unidentifiable and gone again shortly. Hide them from the scan list.
    readonly property var unnamedRegex: /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/
    readonly property bool hideUnnamedDevices: Config.options.bluetooth?.hideUnnamedDevices ?? true

    function hasRealName(device): bool {
        const n = (device?.name ?? "").trim();
        return n.length > 0 && !root.unnamedRegex.test(n);
    }

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = root.unnamedRegex;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    // Connected and paired devices always show. Unpaired ones must have a name,
    // or be mid-pairing, unless the user turns the filter off.
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected
        && (!root.hideUnnamedDevices || root.hasRealName(d) || d.pairing)).sort(sortFunction)
    // What the filter is holding back, so the list can say so: a device whose name has not
    // resolved yet is in here too, and it is the only way to reach one.
    readonly property int hiddenUnnamedCount: root.hideUnnamedDevices
        ? Bluetooth.devices.values.filter(d => !d.paired && !d.connected && !d.pairing && !root.hasRealName(d)).length
        : 0
    readonly property list<var> connectedBatteryDevices: connectedDevices.filter(device => device.batteryAvailable && Number.isFinite(Number(device.battery)))
    readonly property var primaryConnectedDevice: firstActiveDevice ?? connectedDevices[0] ?? null
    readonly property var primaryBatteryDevice: hasBattery(primaryConnectedDevice)
        ? primaryConnectedDevice
        : connectedBatteryDevices[0] ?? null
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]

    function hasBattery(device): bool {
        return !!device && device.batteryAvailable && Number.isFinite(Number(device.battery));
    }

    function togglePower() {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter) return;
        const on = !adapter.enabled;
        adapter.enabled = on;
        Persistent.states.bluetooth.off = !on;
    }

    // BlueZ powers every adapter on when it starts (AutoEnable), so Bluetooth switched off here was on again after a
    // restart. The choice is kept, and an adapter is switched off again the first time it is seen while it says off;
    // one switched on later by anything else is left on.
    property var seenAdapters: []
    function keepChoice(): void {
        const adapter = Bluetooth.defaultAdapter;
        if (!adapter || !Persistent.ready || root.seenAdapters.includes(adapter)) return;
        root.seenAdapters = [...root.seenAdapters, adapter];
        if (Persistent.states.bluetooth.off && adapter.enabled)
            adapter.enabled = false;
    }
    Component.onCompleted: root.keepChoice()
    Connections {
        target: Bluetooth
        function onDefaultAdapterChanged() { root.keepChoice(); }
    }
    Connections {
        target: Persistent
        function onReadyChanged() { root.keepChoice(); }
    }
}
