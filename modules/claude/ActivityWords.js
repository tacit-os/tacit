// The words for an agent's steps: which kind a step is, how a line of them reads ("Ran 4 commands",
// "Read notes.txt"), its glyph, and how long something took ("2m 5s"). Used by ActivityGroup (a
// turn's steps) and AgentRow (an agent's newest step).

function kind(it) {
    if (it.kind === "thinking") return "think";
    switch (it.tool) {
    case "Agent": case "Task": return "agent";
    case "Bash": case "BashOutput": case "KillShell": case "KillBash": case "Monitor": case "TaskOutput": case "TaskStop":
    case "shell": case "shell_command": case "exec_command": return "run";
    case "Edit": case "MultiEdit": case "Write": case "NotebookEdit": case "apply_patch": case "patch": return "edit";
    case "Read": case "view_image": return "read";
    // pi and opencode pass the tools Praxis has no Claude name for through as they call them, in lower case
    case "Grep": case "Glob": case "LS": case "ToolSearch": case "grep": case "find": case "ls": case "list": return "search";
    case "WebSearch": case "websearch": case "codesearch": return "web";
    case "WebFetch": return "fetch";
    case "TaskCreate": case "TaskUpdate": case "TaskList": case "TaskGet": case "TodoWrite": case "update_plan": return "plan";
    }
    return "tool:" + (it.tool ?? "");
}

// A tool Praxis has no wording for, as plain words: an MCP server's "mcp__omnicord__send_message" is
// "omnicord · send message" and "ExitPlanMode" is "exit plan mode", not the identifier.
function plain(t) {
    const words = w => w.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[_-]+/g, " ").toLowerCase();
    const m = /^mcp__(.+?)__(.+)$/.exec(String(t ?? ""));
    return m ? `${words(m[1])} · ${words(m[2])}` : words(String(t ?? ""));
}

// The tools that have words of their own, as [done, done n times, now, name on a step's row]; null for the rest.
function named(t) {
    switch (t) {
    // the host's own tools (agent-host tacit_mcp.rs), which its prompt tells the model to call in every Praxis session
    case "mcp__tacit__choose": return ["Asked you to choose", n => `Asked you to choose ${n} times`, "Asking you to choose", "Choose"];
    case "mcp__tacit__mark": return ["Marked a file", n => `Marked ${n} files`, "Marking a file", "Mark"];
    case "mcp__tacit__claim": return ["Made a claim", n => `Made ${n} claims`, "Making a claim", "Claim"];
    case "mcp__tacit__hand_over": return ["Handed work to a helper", n => `Handed work to ${n} helpers`, "Handing work to a helper", "Hand over"];
    case "mcp__tacit__wait": return ["Waited for helpers", n => `Waited for helpers ${n} times`, "Waiting for helpers", "Wait"];
    case "mcp__tacit__children": return ["Listed the helpers", n => `Listed the helpers ${n} times`, "Listing the helpers", "Helpers"];
    case "Skill": return ["Used a skill", n => `Used ${n} skills`, "Using a skill", "Skill"];
    }
    return null;
}

// a tool's name on its row
function label(t) {
    const w = named(t)?.[3] ?? plain(t);
    return w.charAt(0).toUpperCase() + w.substring(1);
}

function checking(s) { return ["BashOutput", "Monitor", "KillShell", "KillBash", "TaskOutput", "TaskStop"].includes(s.tool); }

// What a turn did to one file, from what each step did to it ("write", "delete", else an edit): a file made
// and then edited was still made; one deleted and then written again was edited.
function kindOver(was, now) { return now === "delete" ? "delete" : was === undefined ? now : was === "delete" ? "edit" : was; }

// What one step did to one of its files. The host marks every file a Write gives "write", new or not; Claude Code's
// result says which ("The file … has been updated successfully." for one that was there): that one was edited.
function fileKind(step, f) {
    return f.kind === "write" && step.tool === "Write" && /^The file .* has been updated/.test(step.result ?? "") ? "edit" : f.kind;
}

// "Created", "Deleted" or "Edited" for a list of {kind} files, "Changed" when they differ
function changed(files) {
    const verbs = new Set(files.map(f => f.kind === "write" ? "Created" : f.kind === "delete" ? "Deleted" : "Edited"));
    return verbs.size === 0 ? "Edited" : verbs.size === 1 ? [...verbs][0] : "Changed";
}

function base(p) { return String(p ?? "").replace(/\/+$/, "").split("/").pop(); }

function says(k, all) {
    const steps = [];
    for (let i = 0; i < all.length; i++) if (k === "think" || all[i].kind !== "thinking") steps.push(all[i]);
    const n = steps.length;
    switch (k) {
    case "think": return "Thought";
    case "run": {
        // checking on a background command is not running one
        const checks = steps.filter(s => checking(s)).length;
        const ran = n - checks;
        if (!ran) return checks === 1 ? "Checked a running command" : `Checked running commands ${checks} times`;
        return ran === 1 ? "Ran a command" : `Ran ${ran} commands`;
    }
    case "agent": return n === 1 ? "Started an agent" : `Started ${n} agents`;
    case "edit": {
        const paths = [], kinds = {};
        for (const st of steps) for (const f of st.files ?? []) {
            if (!paths.includes(f.path)) paths.push(f.path);
            kinds[f.path] = kindOver(kinds[f.path], fileKind(st, f));
        }
        const verb = changed(paths.map(p => ({ kind: kinds[p] })));
        return paths.length === 1 ? `${verb} ${base(paths[0])}` : `${verb} ${paths.length || n} ${(paths.length || n) === 1 ? "file" : "files"}`;
    }
    case "read": {
        const paths = [...new Set(steps.map(s => s.summary ?? ""))];
        return n === 1 || (paths.length === 1 && paths[0].length) ? `Read ${base(paths[0]) || "a file"}` : `Read ${n} files`;
    }
    case "search": return n === 1 ? "Searched" : `Searched ${n} times`;
    case "web": return n === 1 ? "Searched the web" : `Searched the web ${n} times`;
    case "fetch": return n === 1 ? "Read a web page" : `Read ${n} web pages`;
    case "plan": return "Updated the plan";
    }
    const name = k.substring(5), known = named(name), w = plain(name) || "a tool";
    return known ? (n === 1 ? known[0] : known[1](n)) : n === 1 ? `Used ${w}` : `Used ${w} ${n} times`;
}

// The same line while its last step is still going: what it is doing now, not what it did ("Ran a
// command" read as done while the command ran, and while it waited for permission to run at all).
function doing(k, all) {
    const now = all[all.length - 1] ?? {};
    switch (k) {
    case "think": return "Thinking";
    case "run": return checking(now) ? "Checking a running command" : "Running a command";
    case "agent": return "Starting an agent";
    case "edit": {
        const f = (now.files ?? [])[0]?.path ?? now.summary ?? "";
        return base(f) ? `Editing ${base(f)}` : "Editing";
    }
    case "read": return base(now.summary) ? `Reading ${base(now.summary)}` : "Reading";
    case "search": return "Searching";
    case "web": return "Searching the web";
    case "fetch": return "Reading a web page";
    case "plan": return "Updating the plan";
    }
    const name = k.substring(5);
    return named(name)?.[2] ?? `Using ${plain(name) || "a tool"}`;
}

function glyph(k) {
    switch (k) {
    case "think": return "neurology";
    case "run": return "terminal";
    case "edit": return "edit_note";
    case "read": return "description";
    case "search": return "manage_search";
    case "web": case "fetch": return "language";
    case "plan": return "checklist";
    case "tool:Skill": return "bolt";
    case "tool:mcp__tacit__choose": return "checklist";
    case "tool:mcp__tacit__mark": return "bookmark";
    case "tool:mcp__tacit__claim": return "task_alt";
    case "tool:mcp__tacit__hand_over": return "smart_toy";
    case "tool:mcp__tacit__wait": return "hourglass_top";
    case "tool:mcp__tacit__children": return "groups";
    }
    return "widgets";
}

function span(ms) {
    const s = Math.max(0, Math.round(ms / 1000));
    return s < 60 ? `${s}s` : s < 3600 ? `${Math.floor(s / 60)}m ${s % 60}s` : `${Math.floor(s / 3600)}h ${Math.floor(s % 3600 / 60)}m`;
}
