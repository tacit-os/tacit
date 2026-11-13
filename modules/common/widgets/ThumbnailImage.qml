import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    property string thumbnailPath: {
        if (sourcePath.length == 0) return;
        const resolvedUrlWithoutFileProtocol = FileUtils.trimFileProtocol(`${Qt.resolvedUrl(sourcePath)}`);
        const encodedUrlWithoutFileProtocol = resolvedUrlWithoutFileProtocol.split("/").map(part => encodeURIComponent(part)).join("/");
        const md5Hash = Qt.md5(`file://${encodedUrlWithoutFileProtocol}`);
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${md5Hash}.png`;
    }
    source: thumbnailPath

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    onSourceSizeChanged: {
        if (!root.generateThumbnail) return;
        root.requestGeneration();
    }
    // a size set once (the gallery's strip) never changes, so ask once at the start too; when the thumbnail is
    // already there this is one quick test
    Component.onCompleted: if (root.generateThumbnail) root.requestGeneration()

    // A slot from Images caps how many magick processes run at once across the shell; a folder
    // of photos spawns one per visible tile otherwise. Held from spawn to exit, and handed back
    // if the tile is destroyed first so a scrolled-away cell cannot hold the cap down.
    property bool holdsThumbnailSlot: false
    // the command the running process was started with; a size or file that changes meanwhile is asked for when it exits
    property string generatingCommand: ""
    function requestGeneration() {
        // a tile with no file (Settings' "add" tile, the Viewer on a file that is not a picture) ran magick on "" six times
        if (root.sourcePath.length === 0) return;
        if (thumbnailGeneration.running) return;
        if (!root.holdsThumbnailSlot) {
            if (!Images.requestThumbnailSlot(root)) return;
            root.holdsThumbnailSlot = true;
        }
        root.generatingCommand = thumbnailGeneration.command.join("\n");
        thumbnailGeneration.running = true;
    }
    function releaseThumbnailSlot() {
        if (!root.holdsThumbnailSlot) return;
        root.holdsThumbnailSlot = false;
        Images.releaseThumbnailSlot();
    }
    Component.onDestruction: root.releaseThumbnailSlot()

    // a new thumbnail (another size, or this tile reused for another file) starts with its tries again
    property int tries: 0
    onThumbnailPathChanged: {
        root.tries = 0;
        if (root.generateThumbnail && root.thumbnailPath.length > 0) root.requestGeneration();
    }
    Timer {
        id: retryTimer
        interval: 1500
        onTriggered: root.requestGeneration()
    }

    Process {
        id: thumbnailGeneration
        // argv, not a shell string: a file name is attacker-controlled input here (this runs
        // for every visible file the moment a picture-heavy folder opens in grid view), and
        // a name containing a quote used to end up as shell words. The exit codes are the
        // caller's contract: 0 = the thumbnail was already there, 1 = it was just made.
        // -nt is the spec's Thumb::MTime in cheaper form: a cached thumbnail older than the
        // picture is remade, so an edited or replaced file stops showing its old self.
        // 2 = it could not be made, 3 = the file was still being written (changed in the last 2 s): both are tried
        // again shortly. A screenshot appears in its folder while it is written, and its failed thumbnail stayed
        // missing until another file came (Discord 2026-10-23). A file dated in the future (a camera's clock ahead, an
        // archive's dates) is not being written: it was taken for one at every try and never got a thumbnail.
        // A video's comes from a frame a second in.
        // A picture's comes from its first frame, turned upright by its EXIF tag: a GIF, PDF or TIFF would otherwise
        // write one file per frame and none at the thumbnail's name.
        command: {
            const maxSize = Images.thumbnailSizes[root.thumbnailSizeName];
            const thumb = FileUtils.trimFileProtocol(root.thumbnailPath);
            const src = FileUtils.trimFileProtocol(root.sourcePath);
            return ["bash", "-c",
                'set -- "$1" "$2" "$3" "$4"; [ -f "$2" ] && [ ! "$1" -nt "$2" ] && exit 0; mkdir -p "$(dirname -- "$2")" || exit 0; '
                + 'age=$(( $(date +%s) - $(stat -c %Y -- "$1" 2>/dev/null || echo 0) )); [ $age -ge 0 ] && [ $age -lt 2 ] && exit 3; '
                + 'case "${1,,}" in *.mp4|*.webm|*.mkv|*.mov|*.avi|*.m4v) '
                + 'for t in 1 0; do ffmpeg -nostdin -v error -y -ss $t -i "$1" -frames:v 1 -vf "scale=$4:$4:force_original_aspect_ratio=decrease" "$2" && [ -s "$2" ] && exit 1; done; rm -f -- "$2"; exit 2 ;; esac; '
                + 'magick "$1[0]" -auto-orient -resize "$3" "$2" && exit 1; rm -f -- "$2"; exit 2',
                "thumbgen", src, thumb, `${maxSize}x${maxSize}`, `${maxSize}`
            ]
        }
        onExited: (exitCode, exitStatus) => {
            root.releaseThumbnailSlot();
            if (root.generateThumbnail && root.generatingCommand !== thumbnailGeneration.command.join("\n")) {
                Qt.callLater(root.requestGeneration);
                return;
            }
            if ((exitCode === 2 || exitCode === 3) && root.tries < 5) {
                root.tries++;
                retryTimer.restart();
                return;
            }
            // reload when it was just made, or when another tile made it after this one had looked and failed
            if (exitCode === 1 || root.status === Image.Error) {
                root.source = "";
                root.source = Qt.binding(() => root.thumbnailPath); // Force reload, and keep following the path
            }
        }
    }
}
