import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls

/**
 * A button with ripple effect similar to in Material Design.
 */
Button {
    id: root
    property bool toggled
    property string buttonText
    property bool pointingHandCursor: true
    property real buttonRadius: Appearance?.rounding?.small ?? 4
    property real buttonRadiusPressed: buttonRadius
    property real buttonEffectiveRadius: root.down ? root.buttonRadiusPressed : root.buttonRadius
    property int rippleDuration: 1200
    property bool rippleEnabled: true
    property var downAction // When left clicking (down)
    property var releaseAction // When left clicking (release)
    property var altAction // When right clicking
    // A held press (a touch screen's right click) and the Menu key or Shift+F10 run altAction too, for a button
    // whose right click is the only way to its actions; the release that ends the hold clicks nothing
    property bool altOnHold: false
    property var middleClickAction // When middle clicking
    property bool border: false
    property real borderWidth: 1
    property color colBorder: Appearance?.colors.colOutlineVariant ?? "#79747E"

    property color colBackground: ColorUtils.transparentize(Appearance?.colors.colLayer1Hover, 1) || "transparent"
    property color colBackgroundHover: Appearance?.colors.colLayer1Hover ?? "#E5DFED"
    property color colBackgroundToggled: Appearance?.colors.colPrimary ?? "#65558F"
    property color colBackgroundToggledHover: Appearance?.colors.colPrimaryHover ?? "#77699C"
    property color colRipple: Appearance?.colors.colLayer1Active ?? "#D6CEE2"
    property color colRippleToggled: Appearance?.colors.colPrimaryActive ?? "#D6CEE2"
    // Hover, press and disabled were all drawn and keyboard focus was not, so a keyboard user
    // had nothing on screen saying where they were. A 1px ring: nothing moves when it appears.
    property color colFocus: Appearance?.colors.colPrimary ?? "#65558F"
    // Only a keyboard focus draws the ring. activeFocus alone is also set by a click, so every
    // button kept a ring after being pressed and the desktop looked stuck on the last thing
    // touched. Tab, Backtab and a shortcut are the ways focus arrives without a pointer.
    readonly property bool keyboardFocus: root.activeFocus
        && (root.focusReason === Qt.TabFocusReason
            || root.focusReason === Qt.BacktabFocusReason
            || root.focusReason === Qt.ShortcutFocusReason)

    opacity: root.enabled ? 1 : 0.4
    property color buttonColor: ColorUtils.transparentize(root.toggled ? 
        (root.hovered ? colBackgroundToggledHover : 
            colBackgroundToggled) :
        (root.hovered ? colBackgroundHover : 
            colBackground), root.enabled ? 0 : 1)
    property color rippleColor: root.toggled ? colRippleToggled : colRipple

    function startRipple(x, y) {
        const stateY = buttonBackground.y;
        rippleAnim.x = x;
        rippleAnim.y = y - stateY;

        const dist = (ox,oy) => ox*ox + oy*oy
        const stateEndY = stateY + buttonBackground.height
        rippleAnim.radius = Math.sqrt(Math.max(dist(0, stateY), dist(0, stateEndY), dist(width, stateY), dist(width, stateEndY)))

        rippleFadeAnim.complete();
        rippleAnim.restart();
    }

    component RippleAnim: NumberAnimation {
        duration: rippleDuration
        easing.type: Appearance?.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance?.animationCurves.standardDecel
    }

    MouseArea {
        id: gesture
        anchors.fill: parent
        cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        property bool held: false
        onPressed: (event) => { 
            gesture.held = false
            if(event.button === Qt.RightButton) {
                if (root.altAction) root.altAction(event);
                return;
            }
            if(event.button === Qt.MiddleButton) {
                if (root.middleClickAction) root.middleClickAction();
                return;
            }
            root.down = true
            if (root.downAction) root.downAction();
            if (!root.rippleEnabled) return;
            const {x,y} = event
            startRipple(x, y)
        }
        onPressAndHold: (event) => {
            if (!root.altOnHold || !root.altAction || event.button !== Qt.LeftButton) return;
            gesture.held = true
            root.down = false
            if (root.rippleEnabled) rippleFadeAnim.restart();
            root.altAction(event);
        }
        onReleased: (event) => {
            root.down = false
            if (event.button != Qt.LeftButton) return;
            if (gesture.held) return;   // the hold ran altAction
            // Pressing and then dragging off is how a person cancels. QtQuick's own Button
            // works this way; this one did not, so every releaseAction in the desktop fired
            // wherever the pointer happened to be let go. Tested by position rather than by
            // containsMouse, so this MouseArea needs no hoverEnabled and cannot take hover
            // away from the Control whose `hovered` drives the background colour above.
            if (!gesture.contains(Qt.point(event.x, event.y))) {
                if (root.rippleEnabled) rippleFadeAnim.restart();
                return;
            }
            if (root.releaseAction) root.releaseAction();
            root.click() // Because the MouseArea already consumed the event
            if (!root.rippleEnabled) return;
            rippleFadeAnim.restart();
        }
        onCanceled: (event) => {
            root.down = false
            if (!root.rippleEnabled) return;
            rippleFadeAnim.restart();
        }
    }

    Keys.onPressed: (event) => {
        if (!root.altOnHold || !root.altAction) return;
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            root.altAction(event);
            event.accepted = true;
        }
    }

    RippleAnim {
        id: rippleFadeAnim
        duration: rippleDuration * 2
        target: ripple
        property: "opacity"
        to: 0
    }

    SequentialAnimation {
        id: rippleAnim

        property real x
        property real y
        property real radius

        PropertyAction {
            target: ripple
            property: "x"
            value: rippleAnim.x
        }
        PropertyAction {
            target: ripple
            property: "y"
            value: rippleAnim.y
        }
        PropertyAction {
            target: ripple
            property: "opacity"
            value: 1
        }
        ParallelAnimation {
            RippleAnim {
                target: ripple
                properties: "implicitWidth,implicitHeight"
                from: 0
                to: rippleAnim.radius * 2
            }
        }
    }

    background: Rectangle {
        id: buttonBackground
        radius: root.buttonEffectiveRadius
        implicitHeight: 30

        color: root.buttonColor
        border.width: (root.border || root.keyboardFocus) ? root.borderWidth : 0
        border.color: root.keyboardFocus ? root.colFocus : root.colBorder
        Behavior on color {
            animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: buttonBackground.width
                height: buttonBackground.height
                radius: root.buttonEffectiveRadius
            }
        }

        Item {
            id: ripple
            width: ripple.implicitWidth
            height: ripple.implicitHeight
            opacity: 0
            visible: width > 0 && height > 0

            property real implicitWidth: 0
            property real implicitHeight: 0

            Behavior on opacity {
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RadialGradient {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: root.rippleColor }
                    GradientStop { position: 0.3; color: root.rippleColor }
                    GradientStop { position: 0.5; color: Qt.rgba(root.rippleColor.r, root.rippleColor.g, root.rippleColor.b, 0) }
                }
            }

            transform: Translate {
                x: -ripple.width / 2
                y: -ripple.height / 2
            }
        }
    }

    contentItem: StyledText {
        text: root.buttonText
    }
}
