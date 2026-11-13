import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The conversation's agents: one or more Agent calls in a row, as one group under the prose
 * that started them. Each line follows its agent as the host reads it from disk (agent-host
 * "agents"); the agents an agent started of its own sit indented under it, theirs under them.
 * A click opens the agent in the side panel's Agents tab.
 */
Column {
    id: group
    property var calls: []            // the Agent/Task tool items, in order
    property var info: null           // agent-host "agents" reply for this session
    property string openAgent: ""     // the agent the side panel shows
    property real now: Date.now()
    // the host may still say how the calls stand: the session runs, or the host is there and has not read its agents yet
    property bool pending: false
    signal opened(string agent)

    function agentOf(call) {
        return (group.info?.agents ?? []).find(a => a.call === call.id) ?? null;
    }
    // parent -> the agents it started, built once per reply
    readonly property var kids: {
        const m = {};
        for (const a of group.info?.agents ?? []) if (a.parent) (m[a.parent] = m[a.parent] ?? []).push(a);
        return m;
    }
    // everything under an agent, each with its depth (1: started by it)
    function below(a) {
        const out = [];
        const walk = (p, d) => { for (const k of group.kids[p] ?? []) { out.push({ a: k, depth: d }); walk(k.agent, d + 1); } };
        if (a) walk(a.agent, 1);
        return out;
    }
    // an agent the host has not read yet (its files appear a moment after the call): the call stands
    // in. A background launch answers at once ("Async agent launched"): still running. Once the host
    // has answered and the session is idle, a call it has no record of (pruned, another machine, the
    // host died) is over as far as anyone can tell: "ended", not running for ever.
    // The 30 s are counted on a clock of their own: the window's (`now`) ticks only while something runs, so a call made
    // after its last tick stayed "running" once the turn was over.
    property real graceNow: Date.now()
    readonly property bool inGrace: group.calls.some(c => c.ts > 0 && group.graceNow - c.ts < 30000)
    Timer { running: group.inGrace; interval: 1000; repeat: true; onTriggered: group.graceNow = Date.now() }
    function statusOf(call, a) {
        if (a) return a.state;
        if (call.error) return "failed";
        const waiting = group.pending || (call.ts > 0 && group.graceNow - call.ts < 30000);
        if (call.result === undefined) return waiting ? "running" : "ended";
        return /^(Async agent launched|Workflow launched)/.test(String(call.result ?? "")) ? (waiting ? "running" : "ended") : "done";
    }
    readonly property int runningCount: group.calls.filter(c => group.statusOf(c, group.agentOf(c)) === "running").length

    spacing: 2

    // at the scale of the turn's step lines (ActivityGroup)
    Item {
        width: parent.width
        height: 32
        MaterialSymbol { anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: "smart_toy"; iconSize: 17; color: Appearance.colors.colInkSecondary }
        StyledText {
            anchors { left: parent.left; leftMargin: 26; verticalCenter: parent.verticalCenter }
            text: (group.calls.length === 1 ? "Agent" : `${group.calls.length} agents`) + (group.runningCount ? ` · ${group.runningCount} running` : "")
            font.pixelSize: 14
            color: group.runningCount ? Appearance.colors.colInkMain : Appearance.colors.colInkMeta
        }
    }
    Repeater {
        model: group.calls
        Column {
            id: entry
            required property var modelData
            readonly property var agent: group.agentOf(entry.modelData)
            readonly property var under: group.below(entry.agent)
            width: group.width
            spacing: 2
            AgentRow {
                width: parent.width
                title: entry.agent?.description || entry.modelData.summary || "Agent"
                kind: entry.agent?.type ?? ""
                status: group.statusOf(entry.modelData, entry.agent)
                started: entry.agent?.started ?? entry.modelData.ts ?? 0
                ended: entry.agent?.ended ?? 0
                steps: entry.agent?.steps ?? -1
                last: entry.agent?.last ?? null
                now: group.now
                open: entry.agent !== null && group.openAgent === entry.agent.agent
                chevron: entry.agent !== null
                onClicked: if (entry.agent) group.opened(entry.agent.agent)
            }
            Repeater {
                model: entry.under
                AgentRow {
                    required property var modelData
                    width: entry.width
                    indent: 28 + 14 * (modelData.depth - 1)
                    title: modelData.a.description || "Agent"
                    kind: modelData.a.type ?? ""
                    status: modelData.a.state
                    started: modelData.a.started ?? 0
                    ended: modelData.a.ended ?? 0
                    steps: modelData.a.steps ?? -1
                    last: modelData.a.last ?? null
                    now: group.now
                    open: group.openAgent === modelData.a.agent
                    onClicked: group.opened(modelData.a.agent)
                }
            }
        }
    }
}
