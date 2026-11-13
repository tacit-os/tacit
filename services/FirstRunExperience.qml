pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    // Without the trim this is a file:// URL, which only the FileView understands: the two
    // helpers below ran rm and echo on the literal string "file:///home/..." and did nothing.
    property string firstRunFilePath: FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property string firstRunNotifSummary: "Welcome!"
    property string firstRunNotifBody: "Hit Super+/ for a list of keybinds"

    function load() {
        firstRunFileView.reload()
    }

    // The camera, answered once for the apps Tacit installs, as on the owner's Book4 (its permission store says yes):
    // without an answer the first page that looks for cameras (YouTube does) brought up the GTK portal's own "Allow
    // Apps to Use the Camera?" box over the desktop (the VM install test, 2026-10-17). Thyris still asks each site
    // itself. Only where nothing is stored yet, so a "no" stays a no; every start, so an update brings it to accounts
    // made before.
    Process {
        running: true
        command: ["bash", "-c", 'd="--session --dest org.freedesktop.impl.portal.PermissionStore --object-path /org/freedesktop/impl/portal/PermissionStore --method org.freedesktop.impl.portal.PermissionStore"; case "$(gdbus call $d.Lookup devices camera 2>/dev/null)" in *"\'\': "*) ;; *) gdbus call $d.SetPermission devices true camera "" "[\'yes\']" >/dev/null ;; esac']
    }

    // Tacit's wallpapers, the Horizons (made with code, like dusk), into the folder Settings' Wallpaper and the switcher
    // show: a new account has no ~/Pictures/Wallpapers, so they offered only the picture in use (Discord 2026-10-21).
    // Once per account, and only where that folder does not exist yet: one that does is the person's own. Every start
    // until it is done, so an update brings them to accounts made before.
    Process {
        running: true
        command: ["bash", "-c", '[ -e "$3" ] && exit 0; if [ ! -e "$2" ]; then mkdir -p "$2" && cp -n "$1"/*.jpg "$2"/ || exit 0; fi; mkdir -p "${3%/*}" && touch "$3"',
            "bash", Quickshell.shellPath("assets/wallpapers/horizons"),
            `${FileUtils.trimFileProtocol(Directories.pictures)}/Wallpapers`,
            FileUtils.trimFileProtocol(`${Directories.state}/user/horizons-given`)]
    }

    // The glass scale for the wallpaper in use where it was never measured (scripts/colors/measure-glass.sh): it is
    // written when a wallpaper is picked, so accounts from before 1.1.3 kept the unscaled glass on light wallpapers.
    // Every start; the script does nothing once the scale is there.
    Process {
        running: true
        command: ["bash", Quickshell.shellPath("scripts/colors/measure-glass.sh")]
        onExited: Appearance.seeThroughMeasured()
    }

    function enableNextTime() {
        Quickshell.execDetached(["rm", "-f", root.firstRunFilePath])
    }
    function disableNextTime() {
        Quickshell.execDetached(["bash", "-c", `echo '${root.firstRunFileContent}' > '${root.firstRunFilePath}'`])
    }

    // A new account's first start (2026-10-16, the VM install test: no wallpaper, no palette, a blank lock ground):
    // Tacit's own wallpaper, dusk.jpg, through the ordinary switcher, which makes the palette Tacit's look was made with
    // (scheme-content from dusk), the Qt and Kvantum colours, the cursor and the lock's ground; and Kvantum told to use
    // the theme the switcher writes. A wallpaper already set is left alone.
    property bool firstRun: false
    function start() {
        if (!root.firstRun || !Config.ready)
            return;
        root.firstRun = false;
        Quickshell.execDetached(["bash", "-c", 'k="$HOME/.config/Kvantum/kvantum.kvconfig"; [ -e "$k" ] || { mkdir -p "${k%/*}" && printf "[General]\\ntheme=MaterialAdw\\n" > "$k"; }']);
        // the notch's Claude Code hooks (needs you, done, what a terminal session is doing), merged into the person's
        // ~/.claude/settings.json once, where they can remove them for good
        Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/praxis/claude_hooks.py"), `${Directories.tacitBin}/notch-session`]);
        // the names first, saved at once, and the look after: the wallpaper switcher rewrites the settings file several
        // times while it works, and names set meanwhile were lost (the VM install test, 2026-10-17: no name anywhere)
        nameProc.running = true;
    }
    function look() {
        if ((Config.options.background.wallpaperPath ?? "") === "") {
            // into the shell's own settings first: switchwall's write was lost under the shell's, which then kept ""
            const dusk = Quickshell.shellPath("assets/wallpapers/dusk.jpg");
            Config.options.background.wallpaperPath = dusk;
            Config.writeNow();
            Wallpapers.apply(dusk, true);
        }
        // the marker last: a shell that restarts before the name and the look are done meets a first run again
        // (every step above only fills in what is still empty)
        firstRunFileView.setText(root.firstRunFileContent);
    }
    // the notch greets the person by the first name Setup made the account with (as it greets the owner); Settings'
    // Your name and the lock show the whole name (they showed the login name, "sam" for "Sam Tester")
    Process {
        id: nameProc
        command: ["bash", "-c", 'getent passwd "$USER" | cut -d: -f5 | cut -d, -f1']
        stdout: StdioCollector {
            onStreamFinished: {
                const full = text.trim();
                const first = full.split(/\s+/)[0] ?? "";
                if (first !== "" && (Config.options.island.greeting.name ?? "") === "")
                    Config.options.island.greeting.name = first;
                if (full !== "" && (Config.options.profile.displayName ?? "") === "")
                    Config.options.profile.displayName = full;
                Config.writeNow();
                root.look();
            }
        }
    }
    Connections {
        target: Config
        function onReadyChanged() { root.start() }
    }

    FileView {
        id: firstRunFileView
        path: Qt.resolvedUrl(firstRunFilePath)
        // A first run records that it happened and starts Tacit's look (start above). It used to run the wallpaper
        // switcher on the inherited default_wallpaper.png, which replaced the look the machine was shipped with, and
        // then open upstream's welcome tour, which walks the user through panels this fork does not have.
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                root.firstRun = true
                root.start()
            }
        }
    }
}
