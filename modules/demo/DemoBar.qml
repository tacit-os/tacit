pragma ComponentBehavior: Bound

// Local demo only: a top-centre sheet that stands in for the notch and shows three bar styles
// at once, so they can be compared on a real desktop. Kept in its own folder and loaded by one
// line in panelFamilies/IllogicalImpulseFamily.qml - remove that line to get the notch back.
//
// Every colour comes from the wallpaper palette or Tacit's inks; the only surface is the frost,
// drawn as one top-docked silhouette with coves (DockedRect), as the notch itself does.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.demo

Scope {
    id: demoBar

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: barLoader
            active: true
            required property ShellScreen modelData

            component: PanelWindow {
                id: root
                screen: barLoader.modelData

                WlrLayershell.namespace: "quickshell:demo-bar"
                WlrLayershell.layer: WlrLayer.Top
                // A passive sheet: no keys, and no reserve that would shuffle the desktop while it is up.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"

                // Top-anchored only; the compositor centres a fixed-width top layer, and the
                // window never resizes - only its contents do (AGENTS.md, shell behaviour).
                anchors.top: true
                implicitWidth: 920
                implicitHeight: 232
                mask: Region { item: body }

                Item {
                    id: body
                    x: 6
                    width: 908
                    height: 232

                    DockedRect {
                        anchors.fill: parent
                        edge: "top"
                        cornerRadius: Appearance.rounding.normal
                        fillet: 6
                        color: Appearance.colors.colPanelFrost
                        borderWidth: 0
                    }

                    Column {
                        anchors {
                            fill: parent
                            leftMargin: 18
                            rightMargin: 18
                            topMargin: 8
                            bottomMargin: 8
                        }
                        spacing: 4

                        RibbonStyle { width: parent.width; height: 68 }
                        SegmentStyle { width: parent.width; height: 68 }
                        EditorialStyle { width: parent.width; height: 68 }
                    }
                }
            }
        }
    }
}
