pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ComboBox {
    id: root

    property string buttonIcon: ""
    property real buttonRadius: height / 2
    property color colBackground: Appearance.colors.colSecondaryContainer
    property color colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    property color colBackgroundActive: Appearance.colors.colSecondaryContainerActive
    property string searchText: ""

    property int visibleCount: {
        if (!root.searchText || root.searchText.length === 0) 
            return root.model?.length ?? 0
        return (root.model ?? []).filter(item => {
            const display = typeof item === "object" ? (item[root.textRole] ?? "") : String(item)
            return display.toLowerCase().includes(root.searchText.toLowerCase())
        }).length
    }

    // Whether row i is shown with the current search (the delegate hides the rest)
    function matchesSearch(i) {
        const item = root.model[i]
        const display = typeof item === "object" ? (item[root.textRole] ?? "") : String(item)
        return display.toLowerCase().includes(root.searchText.toLowerCase())
    }

    // Up and Down step over the rows the search hides
    function stepHighlight(dir) {
        for (let i = listView.currentIndex + dir; i >= 0 && i < (root.model?.length ?? 0); i += dir) {
            if (root.matchesSearch(i)) {
                listView.currentIndex = i
                return
            }
        }
    }

    // Enter picks the row like a click does: the delegate's click sets the index, emits
    // activated for the page to save it, and closes the popup
    function activateHighlighted() {
        const i = listView.currentIndex
        if (i >= 0 && root.matchesSearch(i))
            listView.currentItem?.clicked()
    }

    // The row Up, Down and Enter work from (listView.currentIndex, drawn as hovered): the chosen one when the popup
    // opens, the one under the pointer, and as the person types the first row the search shows
    onHighlightedIndexChanged: listView.currentIndex = root.highlightedIndex
    onSearchTextChanged: {
        if (!root.searchText) {
            listView.currentIndex = root.currentIndex
            return
        }
        listView.currentIndex = -1
        root.stepHighlight(1)
    }

    implicitHeight: 40
    Layout.fillWidth: true

    background: Rectangle {
        radius: root.buttonRadius
        color: (root.down && !root.popup.visible) ? root.colBackgroundActive : root.hovered ? root.colBackgroundHover : root.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
        }
    }

    indicator: MaterialSymbol {
        x: root.width - width - 16
        y: root.height / 2 - height / 2
        text: "keyboard_arrow_down"
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.colors.colOnSecondaryContainer

        rotation: root.popup.visible ? 180 : 0
        Behavior on rotation {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    contentItem: Item {
        implicitWidth: buttonLayout.implicitWidth
        implicitHeight: buttonLayout.implicitHeight

        RowLayout {
            id: buttonLayout
            anchors.fill: parent
            spacing: 8
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: root.buttonIcon.length > 0 || (root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon)
                visible: active
                sourceComponent: MaterialSymbol {
                    text: {
                        if (root.currentIndex >= 0 && typeof root.model[root.currentIndex] === 'object' && root.model[root.currentIndex]?.icon) {
                            return root.model[root.currentIndex].icon;
                        }
                        return root.buttonIcon;
                    }
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: Appearance.colors.colOnSecondaryContainer
                text: root.displayText
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    delegate: ItemDelegate {
        id: itemDelegate
        width: ListView.view ? ListView.view.width : root.width
        // the 2 px between rows is the row's own, under its ground: the list's spacing came after hidden rows too, so a
        // match far down a long list sat 2 px per row above it out of view
        implicitHeight: visible ? 42 : 0
        bottomPadding: padding + 2
        visible: {
            if (!root.searchText || root.searchText.length === 0) return true
            const display = typeof model === "object" ? (model[root.textRole] ?? "") : String(model)
            return display.toLowerCase().includes(root.searchText.toLowerCase())
        }

        required property var model
        required property int index

        // the row the keys work from looks hovered, so the person sees which one Enter takes
        readonly property bool lit: itemDelegate.hovered || itemDelegate.ListView.isCurrentItem
        property color color: {
            if (root.currentIndex === itemDelegate.index) {
                if (itemDelegate.down) return Appearance.colors.colSecondaryContainerActive;
                if (itemDelegate.lit) return Appearance.colors.colSecondaryContainerHover;
                return Appearance.colors.colSecondaryContainer;
            } else {
                if (itemDelegate.down) return Appearance.colors.colLayer3Active;
                if (itemDelegate.lit) return Appearance.colors.colLayer3Hover;
                return ColorUtils.transparentize(Appearance.colors.colLayer3);
            }
        }
        property color colText: (root.currentIndex === itemDelegate.index) ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3

        background: Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: 2
            radius: Appearance.rounding.small
            color: itemDelegate.color
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.PointingHandCursor
            }
        }

        contentItem: RowLayout {
            spacing: 8
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            Loader {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: Appearance.font.pixelSize.larger
                active: typeof itemDelegate.model === 'object' && itemDelegate.model?.icon?.length > 0
                visible: active
                sourceComponent: Item {
                    implicitWidth: icon.implicitWidth
                    implicitHeight: Appearance.font.pixelSize.larger
                    MaterialSymbol {
                        id: icon
                        anchors.centerIn: parent
                        text: itemDelegate.model?.icon ?? ""
                        iconSize: Appearance.font.pixelSize.larger
                        color: itemDelegate.colText
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredHeight: Appearance.font.pixelSize.larger
                color: itemDelegate.colText
                text: itemDelegate.model[root.textRole]
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    popup: Popup {
        y: root.height + 4
        width: root.width
        clip: true
        height: Math.min(
            searchField.implicitHeight + 20 + (visibleCount * 42) + topPadding + bottomPadding,
            320
        )
        padding: 8

        onVisibleChanged: {
            if (visible) {
                searchField.forceActiveFocus()
            } else {
                root.searchText = ""
                searchField.text = ""
            }
        }

        enter: Transition {
            PropertyAnimation {
                properties: "opacity"; to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        exit: Transition {
            PropertyAnimation {
                properties: "opacity"; to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        background: Item {
            StyledRectangularShadow { target: popupBackground }
            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: ColumnLayout {
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: searchField.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 6

                    MaterialSymbol {
                        Layout.leftMargin: 6
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Search..."
                        color: Appearance.colors.colOnLayer1
                        background: null
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.normal
                        onTextChanged: root.searchText = text
                        Keys.onDownPressed: root.stepHighlight(1)
                        Keys.onUpPressed: root.stepHighlight(-1)
                        Keys.onReturnPressed: root.activateHighlighted()
                        Keys.onEnterPressed: root.activateHighlighted()
                    }

                    MaterialSymbol {
                        visible: searchField.text.length > 0
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                        Layout.rightMargin: 6
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchField.text = ""
                                searchField.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            StyledListView {
                id: listView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 320 - searchField.implicitHeight - 8 - 46)
                clip: true
                spacing: 0
                model: root.popup.visible ? root.delegateModel : null
            }
        }
    }
}