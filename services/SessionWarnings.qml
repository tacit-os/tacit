pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import "../modules/claude/Titles.js" as Titles

Singleton {
    id: root

    property bool packageManagerRunning: false
    property bool downloadRunning: false
    // An agent-host session mid-turn (working, or waiting on a permission): a restart or shut down stops the host and
    // its agents with the session, so the turn is cut off half done.
    property bool agentWorking: false
    // the conversations those turns are in, named as Praxis's rail names them (Titles.js), so the warning says which
    property var agentTitles: []
    // a title cut as the notch cuts one (Claude.shorten): at a word, near 40 characters
    function cut(t) {
        if (t.length <= 40) return t;
        const at = t.lastIndexOf(" ", 40);
        return t.substring(0, at > 20 ? at : 40) + "…";
    }

    // said when the three looks below have come back (a caller that acts on the answer waits for it)
    signal checked()
    property int pending: 0
    function settle() {
        root.pending = Math.max(0, root.pending - 1);
        if (root.pending === 0)
            root.checked();
    }

    function refresh() {
        pending = 3;
        packageManagerRunning = false;
        downloadRunning = false;
        agentWorking = false;
        agentTitles = [];
        detectPackageManagerProc.running = false;
        detectPackageManagerProc.running = true;
        detectDownloadProc.running = false;
        detectDownloadProc.running = true;
        detectAgentProc.running = false;
        detectAgentProc.running = true;
    }

    Process {
        id: detectPackageManagerProc
        command: ["bash", "-c", "pidof yay paru dnf zypper apt apx xbps snap apk yum epsi pikman || ls /var/lib/pacman/db.lck"]
        onExited: (exitCode, exitStatus) => {
            root.packageManagerRunning = (exitCode === 0);
            root.settle();
        }
    }

    Process {
        id: detectDownloadProc
        // Not `pidof curl wget`: any health check, script or agent satisfied that, and a
        // warning row that cries wolf teaches the user to ignore the one beside it. A partial
        // file in the downloads folder, or one of the two tools that only ever download.
        command: ["bash", "-c", "pidof aria2c yt-dlp || find \"$1\" -maxdepth 1 -type f \\( -name '*.part' -o -name '*.crdownload' \\) -print -quit | grep -q .",
                  "_", FileUtils.trimFileProtocol(Directories.downloads)]
        onExited: (exitCode, exitStatus) => {
            root.downloadRunning = (exitCode === 0);
            root.settle();
        }
    }

    Process {
        id: detectAgentProc
        // agent-host's own word: the hello it sends every client on connect lists its sessions with their state. No
        // host, or no answer within 3 s, is no turn running. A turn's conversation is named from the host's history
        // (its title, its first question): the hello's prompt is only the first message since the host last attached
        // it. A history slower than the 3 s leaves the hello's.
        command: ["python3", "-I", "-c", [
                  "import json, socket, sys, time",
                  "end = time.monotonic() + 3",
                  "s = socket.socket(socket.AF_UNIX); s.settimeout(3); s.connect(sys.argv[1]); f = s.makefile('rw', encoding='utf-8')",
                  "busy = {x['id']: x for x in json.loads(f.readline()).get('sessions', []) if x.get('state') in ('working', 'waiting')}",
                  "if not busy: sys.exit(1)",
                  "try:",
                  "    f.write(json.dumps({'op': 'history'}) + '\\n'); f.flush()",
                  "    while time.monotonic() < end:",
                  "        s.settimeout(max(0.1, end - time.monotonic())); m = json.loads(f.readline())",
                  "        if m.get('ev') == 'history':",
                  "            for e in m.get('sessions', []):",
                  "                if e.get('id') in busy: busy[e['id']].update({k: e[k] for k in ('title', 'prompt', 'lastPrompt') if e.get(k)})",
                  "            break",
                  "except Exception: pass",
                  "print(json.dumps([{k: x.get(k, '') for k in ('title', 'prompt', 'lastPrompt')} for x in busy.values()]))"].join("\n"),
                  `${Quickshell.env("XDG_RUNTIME_DIR")}/agent-host.sock`]
        stdout: StdioCollector { id: agentOut }
        onExited: (exitCode, exitStatus) => {
            root.agentWorking = (exitCode === 0);
            let named = [];
            try { named = JSON.parse(agentOut.text); } catch (e) {}
            root.agentTitles = root.agentWorking ? named.map(x => root.cut(Titles.of(x))) : [];
            root.settle();
        }
    }
}
