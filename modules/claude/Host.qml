import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * The app's line to agent-host (~/dev/agent-host): the sessions it runs, as they change, and
 * requests with their replies. Sessions running in a terminal come from Claude Code's own
 * roster (`claude agents --json`), polled while the window is open.
 */
Item {
    id: host

    readonly property bool connected: host.link?.connected ?? false
    property var live: ({})        // id -> the host's summary of a session it runs
    property var terminals: ({})   // id -> { status, cwd, name } for sessions in a terminal
    // id -> { status, pid } for a turn the previous agent-host's process is still finishing: a host restart closes its
    // stdin, and Claude Code ends the turn before it exits. In an agent scope, so not a terminal (it read as one).
    property var leftovers: ({})
    // The roster has answered since the socket last connected, or has not in 5 s: until then a turn the previous host's
    // process is still finishing is not known, and its session looks idle (a message sent then waits: Conversation).
    property bool rosterAnswered: false
    Timer { id: rosterWait; interval: 5000; onTriggered: host.rosterAnswered = true }
    property int pollInterval: 10000
    property bool roster: true         // the notch has its own session list: it turns this off
    property var callbacks: ({})
    property int nextTag: 1
    // agent-host's line protocol as this file was written. The daemon outlives many shell and app
    // reloads, so new-shell/old-daemon is the normal state after a pull rather than an edge case:
    // the daemon says which protocol and build is answering in its hello, and it is compared here.
    readonly property int proto: 6
    property string hostVersion: ""
    property bool protoMismatch: false
    // the hello's agents: { claude|codex|pi|opencode: { installed, version, signedIn, reason, caps } };
    // empty with a host older than protocol 5
    property var agents: ({})
    property bool helloSent: false     // this connection has said which protocol it speaks
    property bool greeted: false       // the host has answered it: agents and features are known
    // what this host can do beyond its protocol number ("accounts", "catalog", "effort"); empty
    // while disconnected and with an older host
    property var features: []
    signal event(string id, int seq, var data)
    signal items(string id, var list)
    signal exited(string id, string reason, var stderr, string ended)   // stderr: the process's last lines; ended: "oom", else ""
    signal historyChanged()
    // untagged events this file does not handle (accounts, signin, install, catalog), for whoever
    // reads them (AccountsModel)
    signal pushed(var m)

    // Protocol 5 history (pi and opencode rows, files, resume) is per connection: said before any
    // request, so a request made in another handler of the same connect still comes after it.
    function sayHello() {
        if (host.helloSent || !host.connected) return;
        host.helloSent = true;
        host.link.write(JSON.stringify({ op: "hello", proto: host.proto }) + "\n");
        host.link.flush();
    }

    function request(obj, cb) {
        host.sayHello();
        const tag = host.nextTag++;
        obj.tag = tag;
        // answered here, not kept: a callback left in the table was failed a second time by the next drop
        if (!host.connected) { if (cb) cb({ ev: "error", message: "Lost the connection to the background service. Praxis keeps trying to reconnect.", disconnected: true }); return; }
        if (cb)
            host.callbacks[tag] = cb;
        host.link.write(JSON.stringify(obj) + "\n");
        host.link.flush();
    }

    // A dropped socket answers nothing, so every request in flight is failed here: without this
    // their callers wait for a reply that cannot come (a follow that never asks again, a message
    // that is never sent) until the app is restarted. `disconnected` tells a caller that this is
    // the connection going, not the host refusing.
    function failPending() {
        const pending = host.callbacks;
        host.callbacks = ({});
        for (const tag in pending)
            pending[tag]({ ev: "error", message: "Lost the connection to the background service. Praxis keeps trying to reconnect.", disconnected: true });
    }

    readonly property bool testRun: Quickshell.env("PRAXIS_TEST") === "1"
    function receive(line) {
        let m;
        const t0 = Date.now();
        try { m = JSON.parse(line); } catch (e) { return; }
        const t1 = Date.now();
        if (m.tag !== undefined && host.callbacks[m.tag]) {
            const cb = host.callbacks[m.tag];
            delete host.callbacks[m.tag];
            cb(m);
            if (host.testRun && Date.now() - t0 > 8)
                console.warn(`TESTSWITCH reply ${m.ev} ${Math.round(line.length / 1024)} KB: parse ${t1 - t0} ms, handled ${Date.now() - t1} ms`);
            return;
        }
        Appearance.agentMoved();
        switch (m.ev) {
        case "hello":
            host.hostVersion = m.version ?? "";
            host.agents = m.agents ?? ({});
            host.features = m.features ?? [];
            host.protoMismatch = m.proto !== host.proto;
            host.greeted = true;
            if (host.protoMismatch)
                console.warn("agent-host speaks protocol", m.proto ?? "(none)", "and this shell", host.proto,
                             "- version", host.hostVersion || "(none)", ": restart agent-host.service");
            // falls through: a hello carries the session list
        case "sessions": {
            const l = {};
            for (const s of m.sessions) l[s.id] = s;
            host.live = l;
            break;
        }
        case "state": {
            const l = Object.assign({}, host.live);
            l[m.session.id] = m.session;
            host.live = l;
            break;
        }
        case "event":
            host.event(m.id, m.seq, m.data);
            break;
        case "items":
            host.items(m.id, m.items);
            break;
        case "exit":
            host.exited(m.id, m.reason, m.stderr ?? [], m.ended ?? "");
            host.historyChanged();
            break;
        default:
            if (m.tag === undefined)
                host.pushed(m);
        }
    }

    // Quickshell 0.3.1's Socket does not try again after a refused first connect (setting
    // `connected` false and back to true does nothing), so a socket that is not connected is rebuilt
    // on each knock until the host answers (the pattern of services/BluetoothAgent.qml).
    property int gen: 0
    property var link: null
    Instantiator {
        model: [host.gen]
        delegate: Socket {
            id: sock
            path: `${Quickshell.env("XDG_RUNTIME_DIR")}/agent-host.sock`
            connected: true
            parser: SplitParser { onRead: line => host.receive(line) }
            onConnectedChanged: {
                host.rosterAnswered = false;
                if (connected) {
                    rosterWait.restart();
                    retry.stop();
                    retry.tries = 0;
                    host.sayHello();
                    // a host that restarted holds none of the old one's sessions: a turn the old process is finishing
                    // is known from the roster alone, read now rather than up to a poll later, when it may have ended
                    if (host.roster) { roster.running = false; roster.running = true; }
                    return;
                }
                rosterWait.stop();
                host.helloSent = false;
                host.greeted = false;
                host.features = [];
                host.failPending();
                // The sessions in here died with the daemon, and every surface reads this list: left
                // standing it keeps offering conversations that are gone and reports the host as owning
                // them. What is on disk comes back through a transcript read when the socket answers.
                host.live = ({});
                retry.start();
            }
        }
        onObjectAdded: (index, object) => host.link = object
        onObjectRemoved: (index, object) => { if (host.link === object) host.link = null; }
    }
    // Not there: start the service, then keep knocking until the socket answers. The app outlives
    // many hosts (closing the window keeps the process), so the start is offered again every fifth
    // knock rather than once for the app's life: a host that has crashed is otherwise never
    // restarted, and `systemctl --user start` on a running unit does nothing.
    Timer {
        id: retry
        property int tries: 0
        // a host that is not coming back is knocked on quietly; a minute at 5 s between first: straight to 30 s,
        // a restart that took over 6 s left the app on "unreachable" for up to half a minute after it was back
        interval: retry.tries < 5 ? 1200 : retry.tries < 17 ? 5000 : 30000
        repeat: true
        onTriggered: {
            if (host.connected) {
                stop();
                return;
            }
            if (retry.tries % 5 === 0)
                Quickshell.execDetached(["systemctl", "--user", "start", "agent-host.service"]);
            retry.tries++;
            host.gen++;
        }
    }
    Component.onCompleted: retry.start()

    // Polls that did not answer since the last one that did. The roster is the only evidence a
    // session is in a terminal, and that evidence locks the composer: a poll that fails says
    // nothing, so the last roster stands, but not past three failures.
    property int rosterFails: 0
    // The roster lists agent-host's own Claude Code processes too (stream-json, its children), as "interactive":
    // a session Praxis runs read as one in a terminal, and when it really was open in a terminal as well, the
    // two rows for it decided its state by their order. The host's children are named after the roster and left
    // out; `checked` says that worked (no agent-host found: nothing can be told apart, as before).
    Process {
        id: roster
        command: ["bash", "-c", "claude agents --json; echo; echo @@scoped@@; for p in $(pgrep -x claude); do grep -qs '/app.slice/agent-' /proc/$p/cgroup && printf '%s ' $p; done; echo; echo @@host@@; h=${PRAXIS_HOST_PID:-$(pgrep -xo agent-host)} && pgrep -P \"$h\" | tr '\\n' ' '"]
        stdout: StdioCollector {
            onStreamFinished: {
                const at = this.text.indexOf("@@host@@");
                const sc = this.text.indexOf("@@scoped@@");
                let rows = null;
                try { rows = JSON.parse(this.text.substring(0, sc >= 0 ? sc : at >= 0 ? at : this.text.length)); } catch (e) {}
                // a CLI that answers in another shape is a failure; a run that got to its end has said all it can
                // (one stopped part way, as the restart on connect stops a poll, has not)
                if (!Array.isArray(rows)) { if (at >= 0) host.rosterAnswered = true; return; }
                host.rosterFails = 0;
                const own = at >= 0 ? this.text.substring(at + 8).trim().split(/\s+/).filter(x => x.length) : [];
                const checked = own.length > 0;
                const scoped = sc >= 0 ? this.text.substring(sc + 10, at >= 0 ? at : this.text.length).trim().split(/\s+/).filter(x => x.length) : [];
                const t = {}, left = {};
                for (const r of rows) {
                    if (r.kind !== "interactive" || !r.sessionId || own.includes(String(r.pid))) continue;
                    if (scoped.includes(String(r.pid))) left[r.sessionId] = { status: r.status, pid: r.pid };
                    else t[r.sessionId] = { status: r.status, cwd: r.cwd ?? "", name: r.name ?? "", checked: checked };
                }
                if (JSON.stringify(left) !== JSON.stringify(host.leftovers)) host.leftovers = left;
                // an unchanged roster keeps its object: a new one resets every list bound to it
                if (JSON.stringify(t) !== JSON.stringify(host.terminals)) host.terminals = t;
                if (at >= 0) host.rosterAnswered = true;
                // A session open in a terminal that the host also holds, idle: the host's process no longer knows
                // what the terminal does there, and a message sent to it would carry on from before and split the
                // conversation. Closed, the next message from here resumes from the transcript as it then is.
                for (const id in t) {
                    const l = host.live[id];
                    if (checked && l && l.alive && l.state === "idle") host.request({ op: "close", id: id });
                }
            }
        }
    }
    // The host does not own a leftover turn's process, so it cannot interrupt it: Stop ends the process itself, as
    // the roster named it. The pid is checked again here (still a Claude Code in an agent scope), since the roster
    // is up to a poll old and pids are reused. True when there was a process to end.
    function stopLeftover(id) {
        const pid = host.leftovers[id]?.pid;
        if (!pid) return false;
        Quickshell.execDetached(["bash", "-c", "p=$1; grep -qs /app.slice/agent- /proc/$p/cgroup && [ \"$(cat /proc/$p/comm)\" = claude ] && kill $p", "stop", String(pid)]);
        afterStop.restart();
        return true;
    }
    // the roster again soon after, so the turn is seen to have ended without waiting out the poll
    Timer {
        id: afterStop
        interval: 1500
        onTriggered: { roster.running = false; roster.running = true; }
    }
    Timer {
        running: host.roster
        interval: host.pollInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // counted here rather than on the process: a `claude` that cannot be run at all finishes
            // no stream and would never be counted
            if (++host.rosterFails >= 3 && Object.keys(host.terminals).length) host.terminals = ({});
            if (host.rosterFails >= 3 && Object.keys(host.leftovers).length) host.leftovers = ({});
            roster.running = false;
            roster.running = true;
        }
    }
}
