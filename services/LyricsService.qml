pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    // Rebinding to another player fires no trackTitle change: the player that took over usually
    // has its title set already, so the previous song's words kept scrolling. Watch the pair,
    // which also catches two consecutive tracks that share a title.
    readonly property string trackKey: `${root.activePlayer?.trackTitle ?? ""}§${root.activePlayer?.trackArtist ?? ""}`
    onTrackKeyChanged: if (root.watched) refetchTimer.restart()

    // Lyrics widgets on screen (Lyrics.qml counts itself in and out). With none, no lookup runs:
    // lyrics.py asks lrclib.net for every track that is not cached.
    property int viewers: 0
    readonly property bool watched: root.viewers > 0
    onWatchedChanged: {
        if (root.watched) {
            root.restartLyrics()
        } else {
            refetchTimer.stop()
            lyricsProc.running = false
        }
    }

    Timer {
        // One track change arrives as two property changes, title and artist. A fetch per change
        // killed the first run halfway; wait for the pair to settle and fetch once.
        id: refetchTimer
        interval: 150
        onTriggered: root.restartLyrics()
    }

    property var lyricsLines: []
    property int activeIndex: -1
    property string status: "loading"
    property var slots: ["", "", "", "", "", "", ""]

    readonly property int before: 3
    readonly property int after:  3
    readonly property int total:  7

    function buildSlots(idx) {
        let result = []
        for (let i = 0; i < root.total; i++) {
            let lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < root.lyricsLines.length)
                result.push(root.lyricsLines[lineIdx].text || "♪")
            else
                result.push("")
        }
        return result
    }

    Timer {
        id: syncTimer
        interval: 300
        repeat: true
        running: root.status === "ok" && root.lyricsLines.length > 0
        onTriggered: {
            // MprisPlayer.position only refreshes when asked: read as it was, the line lagged by whatever else ticked
            // it (3 s for the media card) and never moved on a desktop widget alone
            if (root.activePlayer?.isPlaying)
                root.activePlayer.positionChanged()
            const pos = root.activePlayer?.position ?? 0
            let idx = -1
            for (let i = 0; i < root.lyricsLines.length; i++) {
                if (root.lyricsLines[i].time <= pos) idx = i
                else break
            }
            if (idx !== root.activeIndex) {
                root.activeIndex = idx
                root.slots = root.buildSlots(idx)
            }
        }
    }

    Process {
        id: lyricsProc
        running: false
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                if (trimmed === "not_found") { root.status = "not_found"; return }
                if (trimmed === "no_info")   { root.status = "no_info";   return }

                const parts = trimmed.split("§")
                if (parts.length < 3) return
                if (parts[parts.length - 1].trim() !== "ok") return

                let lines = []
                for (let i = 0; i < parts.length - 1; i += 2) {
                    const t = parseFloat(parts[i])
                    const txt = parts[i + 1] || ""
                    if (!isNaN(t)) lines.push({ time: t, text: txt })
                }

                if (lines.length === 0) { root.status = "not_found"; return }

                root.lyricsLines = lines
                root.activeIndex = -1
                root.slots = root.buildSlots(-1)
                root.status = "ok"
            }
        }
    }

    function restartLyrics() {
        if (!root.watched) return
        lyricsProc.running = false
        root.lyricsLines = []
        root.activeIndex = -1
        root.slots = ["", "", "", "", "", "", ""]
        root.status = "loading"

        const title    = root.activePlayer?.trackTitle  ?? ""
        const artist   = root.activePlayer?.trackArtist ?? ""
        const duration = root.activePlayer?.length       ?? 0

        if (!title || !artist) { root.status = "no_info"; return }

        lyricsProc.command = [
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            title, artist, String(Math.floor(duration))
        ]
        lyricsProc.running = true
    }
}