import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Fills its box the way PreserveAspectCrop does, but with the part of the picture the person chose
 * (Wallpapers.focusFor) in view instead of always the middle. Set `target`, not `source`: a tiny copy
 * tells the picture's shape first, then the real one is decoded at the size that covers the box and
 * cut to it. The item stays exactly the box, so the transition shaders and blurs that sample it
 * need no change.
 *
 * Qt never scales a decode up: a picture smaller than that covering size came back at its own size
 * inside a box-sized cut, padded with black (small in the top-left corner), or squashed or not at all
 * for a JPEG (Discord #bugs, 2026-11-13). Such a picture is decoded at its own size (Wallpapers.sizeFor)
 * and the same part is cut from its own pixels, which Stretch scales up to the box.
 */
StyledImage {
    id: root
    property string target: ""
    // device pixels the picture has to cover
    property size view: Qt.size(width, height)
    property real aspect: 0
    // the picture's own size, taken with `aspect` when its decode starts; (0, 0) when it could not be read
    property size natural: Qt.size(0, 0)
    // the picture in `source` is the one asked for in `target` (until the probe is back, `status` still speaks of the last one)
    property string shown: ""
    // the probe has told this target's shape
    property string probed: ""
    property real probedAspect: 0
    readonly property bool loaded: root.status === Image.Ready && root.shown === root.target
    readonly property string targetUrl: FileUtils.fileUrl(root.target)
    // the shown picture's, so the last one is not cut again at the next one's while that loads
    readonly property point focusAt: Wallpapers.focusFor(root.shown)
    readonly property size targetSize: Wallpapers.sizeFor(root.target)

    fillMode: Image.Stretch
    readonly property real viewAspect: root.view.width / root.view.height
    readonly property real coverW: root.aspect > root.viewAspect ? root.view.height * root.aspect : root.view.width
    readonly property real coverH: root.aspect > root.viewAspect ? root.view.height : root.view.width / root.aspect
    // Qt decodes it at its own size (no side larger than the covering size asked for)
    readonly property bool small: root.natural.width > 0
        && root.natural.width <= Math.ceil(root.coverW) && root.natural.height <= Math.ceil(root.coverH)
    // the part with the box's shape, in the picture's own pixels
    readonly property real cutW: Math.min(root.natural.width, root.natural.height * root.viewAspect)
    readonly property real cutH: root.cutW / root.viewAspect
    sourceSize: root.aspect <= 0 || root.small ? Qt.size(0, 0) : Qt.size(Math.ceil(root.coverW), Math.ceil(root.coverH))
    sourceClipRect: root.aspect <= 0 ? Qt.rect(0, 0, 0, 0)
        : root.small ? Qt.rect(
            Math.floor(root.focusAt.x * (root.natural.width - root.cutW)),
            Math.floor(root.focusAt.y * (root.natural.height - root.cutH)),
            Math.floor(root.cutW), Math.floor(root.cutH))
        // Qt rounds the covering size it decodes at: the cut stays inside the rounded-down one
        : Qt.rect(
            Math.floor(root.focusAt.x * (Math.floor(root.coverW) - root.view.width)),
            Math.floor(root.focusAt.y * (Math.floor(root.coverH) - root.view.height)),
            root.view.width, root.view.height)

    onTargetChanged: {
        if (root.target === "") {
            root.source = "";
            root.shown = "";
            root.probed = "";
            root.aspect = 0;
            root.natural = Qt.size(0, 0);
        }
    }
    // The decode waits for both the shape and the size, so its first cut is the right one. Qt reloads on each of these
    // at once, so the size goes last: neither the last picture nor this one is ever asked for whole unless it is small.
    function show() {
        if (root.probed !== root.target || root.targetSize.width < 0 || root.shown === root.target)
            return;
        root.natural = Qt.size(0, 0);
        // the header's size gives the exact shape; the probe's, rounded to 64 pixels, cut a tall picture past its end
        root.aspect = root.targetSize.width > 0 && root.targetSize.height > 0
            ? root.targetSize.width / root.targetSize.height : root.probedAspect;
        root.shown = root.target;
        root.source = root.targetUrl;
        root.natural = root.targetSize;
    }
    onTargetSizeChanged: root.show()

    Image {
        id: probe
        visible: false
        asynchronous: true
        cache: true
        source: root.targetUrl
        sourceSize: Qt.size(64, 64)
        onStatusChanged: {
            if (status === Image.Ready && implicitHeight > 0) {
                root.probedAspect = implicitWidth / implicitHeight;
                root.probed = root.target;
                root.show();
            } else if (status === Image.Error) {
                // let the real load fail too, so the caller's own error path (Status Error) runs; the source first, or
                // the last picture was asked for whole
                root.probed = root.target;
                root.shown = root.target;
                root.source = root.targetUrl;
                root.aspect = 0;
                root.natural = Qt.size(0, 0);
            }
        }
    }
}
