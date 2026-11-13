pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

/**
 * What you are doing now, read once and shared: the focused window's app, its title
 * (cleaned of the browser's suffix), its address, and - on demand - the working directory of
 * the shell inside a focused terminal. Origins asks it at the moment a file arrives (which
 * page a download came from, which window a screenshot shows); Files asks it to choose where
 * to open; hand-to-Claude asks it for the folder.
 */
Singleton {
    id: root

    readonly property var top: ToplevelManager.activeToplevel
    readonly property string app: root.top?.appId ?? ""
    readonly property string rawTitle: root.top?.title ?? ""
    readonly property string title: {
        root.threadsRev;   // again when Opsis's thread names change
        return root.cleanTitle(root.app, root.rawTitle);
    }
    readonly property string address: root.top?.HyprlandToplevel?.address ? `0x${root.top.HyprlandToplevel.address}` : ""
    readonly property var terminalApps: ["foot", "footclient", "kitty", "alacritty", "org.wezfurlong.wezterm", "com.mitchellh.ghostty"]
    readonly property bool terminal: root.terminalApps.includes(root.app)
    // "browser" is Thyris's Qt build, "browser-cef" its CEF build (the one now run and packaged)
    readonly property bool thyris: root.app === "browser" || root.app === "browser-cef"
    readonly property bool browser: root.thyris || ["zen", "zen-browser", "firefox", "chromium", "thorium-browser", "google-chrome"].some(b => root.app.toLowerCase().includes(b))
    // A private window's title is nobody's business: nothing that happens in it is recorded.
    // Opsis titles a private window "Private · <page>" (RailRows.privateTitle). Firefox, Zen and Chrome put the
    // mode in the window title in the interface's language and give the window no other mark, so the words are
    // listed by language (stems, to take in the inflections); a miss records a title, so the list leans to
    // taking in too much: a page with one of these words in its title is simply not recorded.
    readonly property var privateWords: [
        "private browsing", "inprivate", "incognito",                         // en, and the same word in most languages
        "privater modus", "privates fenster", "inkognito",                    // de
        "navigation priv[ée]e", "fen[êe]tre priv[ée]e",                       // fr
        "navegaci[óo]n privada", "ventana privada", "incógnito",              // es
        "navigazione anonima", "finestra anonima",                            // it
        "navega[çc][ãa]o (privada|an[ôo]nima)", "janela (privada|an[ôo]nima)", // pt
        "priv[ée]navigatie", "priv[ée]venster",                               // nl
        "privat fönster", "privat surfning",                                  // sv
        "приватн(ое|ый) (окно|просмотр|режим)", "инкогнито",                  // ru, uk
        "tryb prywatny", "(prywatne|nowe prywatne) okno",                     // pl
        "gizli (pencere|mod|gezinti)",                                        // tr
        "プライベートブラウジング", "プライベートウィンドウ", "シークレット",       // ja
        "无痕", "無痕", "隐私浏览", "隱私瀏覽", "시크릿"                            // zh, ko
    ]
    readonly property var privateTitle: new RegExp(root.privateWords.join("|"), "i")
    readonly property bool privateWindow: root.privateTitle.test(root.rawTitle)
        || (root.thyris && /^Private( · |$)/.test(root.rawTitle))

    // "Tiger wallpapers 4k — Zen Browser" -> "Tiger wallpapers 4k"; Opsis's
    // "<page> · <thread>" (RailRows.windowTitle) -> "<page>", cut only when <thread> is the name
    // of one of its threads (page titles hold " · " too); Opsis with no page ("Browser") -> "".
    function cleanTitle(app, title) {
        let t = (title ?? "").trim();
        t = t.replace(/\s+[—–-]\s+(Zen Browser|Zen|Mozilla Firefox|Firefox|Chromium|Thorium|Google Chrome)$/i, "");
        if (app === "browser" || app === "browser-cef") {
            if (t === "Browser")
                return "";
            if (t.includes(" · ")) {
                const thread = root.threadNames().filter(n => t.length > n.length + 3 && t.endsWith(" · " + n))
                    .reduce((a, n) => n.length > a.length ? n : a, "");
                if (thread.length > 0)
                    t = t.slice(0, t.length - thread.length - 3);
            }
        }
        t = t.replace(/^\(\d+\)\s+/, "");   // "(3) Inbox" badges
        return t;
    }

    // Opsis's thread names (threads.json; RailRows.windowTitle names only threads of 2+ pages):
    // read again when Opsis saves it, parsed only when an Opsis title has a " · " to cut.
    property int threadsRev: 0
    readonly property var threadCache: ({ "names": null })
    function threadNames() {
        if (root.threadCache.names === null) {
            try {
                root.threadCache.names = (JSON.parse(opsisThreads.text()).threads ?? [])
                    .filter(t => (t.pages?.length ?? 0) > 1 && typeof t.title === "string" && t.title.length > 0).map(t => t.title);
            } catch (e) {
                root.threadCache.names = [];
            }
        }
        return root.threadCache.names;
    }
    FileView {
        id: opsisThreads
        path: `${Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"}/browser/threads.json`
        blockLoading: true   // this singleton is made on first use, which reads the names at once
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.threadCache.names = null;
            root.threadsRev++;
        }
    }

    // The folder a terminal window is in: its shell's cwd (the first child of the terminal's
    // pid), read from /proc. Asynchronous: a process, so never on a frame. cb("") when unknown.
    // A terminal process with several shells (kitty's tabs, ghostty's and footclient's windows)
    // does not say which one is in front, so none is guessed, as bin/focus-folder does.
    function cwdFor(address, cb) {
        const client = HyprlandData.windowByAddress[address];
        const pid = client?.pid ?? 0;
        if (!pid) {
            cb("");
            return;
        }
        const p = cwdProc.createObject(root, { "pid": pid, "cb": cb });
        p.running = true;
    }
    function cwdOfFocused(cb) {
        if (!root.terminal) {
            cb("");
            return;
        }
        root.cwdFor(root.address, cb);
    }

    Component {
        id: cwdProc
        Process {
            id: proc
            property int pid: 0
            property var cb
            command: ["bash", "-c", `[ "$(pgrep -c -P ${proc.pid})" -gt 1 ] && exit 0; c=$(pgrep -P ${proc.pid} | head -1); [ -n "$c" ] || c=${proc.pid}; d=$(pgrep -P "$c" | head -1); for p in "$d" "$c"; do [ -n "$p" ] && w=$(readlink /proc/$p/cwd 2>/dev/null) && [ -d "$w" ] && { printf '%s' "$w"; exit 0; }; done`]
            stdout: StdioCollector {
                onStreamFinished: {
                    proc.cb(text.trim());
                    proc.destroy();
                }
            }
        }
    }
}
