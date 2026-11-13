import qs.modules.common
import qs.modules.common.functions
import qs.services
import "layouts.js" as Layouts
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
    id: root    
    property var layouts: Layouts.byName
    // The keys send scancodes, so what they type is the compositor's layout: label them with it when layouts.js has
    // it (the config value is only written on a layout change, not for the one active at start), else the config's
    property var activeLayoutName: layouts.hasOwnProperty(HyprlandXkb.currentLayoutName) ? HyprlandXkb.currentLayoutName
        : (layouts.hasOwnProperty(Config.options?.osk.layout)) 
        ? Config.options?.osk.layout 
        : Layouts.defaultLayout
    // A layout layouts.js has no labels for (French, UK, Dvorak ...): the US keys, each labelled with what the keymap
    // types on it (xkb_labels.py); where the keymap cannot be read, the US labels, and the header says they are
    readonly property string compositorLayout: HyprlandXkb.currentLayoutName
    readonly property bool unlabelled: compositorLayout !== "" && !layouts.hasOwnProperty(compositorLayout)
    property var keymap: ({ name: "", labels: null })   // xkb_labels.py's last answer, and the layout it is for
    readonly property bool keymapRead: unlabelled && keymap.name === compositorLayout
    readonly property bool fromKeymap: keymapRead && keymap.labels !== null
    property var currentLayout: fromKeymap ? relabelled(layouts[Layouts.defaultLayout], keymap.labels)
        : unlabelled ? layouts[Layouts.defaultLayout] : layouts[activeLayoutName]
    readonly property string heading: keymapRead && !fromKeymap ? Translation.tr("US labels, typing %1").arg(compositorLayout)
        : unlabelled ? compositorLayout
        : `${currentLayout.name_short}, ${currentLayout.description.split(" - ")[0]}`

    // the layout's keys, the printable ones labelled from labels ({keycode: [label, with Shift]}), the right Alt as AltGr
    // where the keymap makes it one
    function relabelled(base, labels) {
        return Object.assign({}, base, { keys: base.keys.map(row => row.map(key => {
            const l = labels[key.keycode];
            if (l && key.keytype === "normal" && key.labelShift !== undefined)
                return Object.assign({}, key, { label: l[0], labelShift: l[1] });
            if (l && key.keytype === "modkey" && l[0] === "AltGr")
                return Object.assign({}, key, { label: l[0] });
            return key;
        })) });
    }
    onCompositorLayoutChanged: readKeymap()
    Connections { target: HyprlandXkb; function onLayoutCodesChanged() { root.readKeymap(); } }
    Component.onCompleted: readKeymap()
    function readKeymap() {
        if (!root.unlabelled) return;
        if (keymapProc.running) { keymapProc.again = true; return; }    // the layouts changed while they were read
        keymapProc.forName = root.compositorLayout;
        keymapProc.command = ["python3", FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/xkb_labels.py`),
                              HyprlandXkb.layoutCodes.join(","), HyprlandXkb.variantCodes.join(","), root.compositorLayout];
        keymapProc.running = true;
    }
    Process {
        id: keymapProc
        property string forName: ""
        property bool again: false
        stdout: StdioCollector {
            id: keymapOut
            // nothing printed (the name is not one of the layouts, no keymap could be made): null, the US labels
            onStreamFinished: {
                let labels = null;
                try { labels = JSON.parse(keymapOut.text); } catch (e) {}
                root.keymap = { name: keymapProc.forName, labels: labels };
            }
        }
        onRunningChanged: if (!running && again) { again = false; root.readKeymap(); }
    }

    implicitWidth: keyRows.implicitWidth
    implicitHeight: keyRows.implicitHeight

    ColumnLayout {
        id: keyRows
        anchors.fill: parent
        spacing: 5

        Repeater {
            model: root.currentLayout.keys

            delegate: RowLayout {
                id: keyRow
                required property var modelData
                spacing: 5
                
                Repeater {
                    model: modelData
                    // A normal key looks like this: {label: "a", labelShift: "A", shape: "normal", keycode: 30, type: "normal"}
                    delegate: OskKey { 
                        required property var modelData
                        keyData: modelData
                    }
                }
            }
        }
    }
}
