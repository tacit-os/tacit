import QtQuick
import Tacit.Kit as K

Item {
    id: body
    property bool animateExpansion: true
    property bool expanded: true
    default property alias contents: content.data
    width: parent.width
    height: content.height
    visible: height > 0
    clip: true
    states: State {
        name: "collapsed"
        when: !body.expanded
        PropertyChanges { body.height: 0 }
    }
    // Animate toggles; the HTML presentation already animates its own height.
    transitions: Transition {
        enabled: body.animateExpansion
        NumberAnimation {
            target: body
            property: "height"
            duration: K.Kit.ms(body.expanded ? K.Kit.motion("arriveSmall").ms : K.Kit.motion("leave").ms)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: body.expanded ? K.Kit.motion("arriveSmall").curve : K.Kit.motion("leave").curve
        }
    }
    Column {
        id: content
        width: parent.width
        spacing: 0
    }
}
