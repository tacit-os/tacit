#!/usr/bin/env python3
# The notch's Claude Code hooks, merged into the person's Claude Code settings at their account's first start
# (FirstRunExperience.qml): bin/notch-session is the only source of a terminal session's "needs you", "done" and what it
# is doing now, and nothing else installs the hooks that run it. Merged, never replacing: the person's own hooks and
# settings stay as they are, an event that already runs a notch-session is left alone, and a file that cannot be read
# as settings is not touched. They are ordinary hooks there, which the person can remove.
#   claude_hooks.py <notch-session>   the hook's path; the settings are $CLAUDE_CONFIG_DIR/settings.json, by default
#                                     ~/.claude/settings.json
# Exits 1 when the settings file is there but is not a JSON object with an object of hooks.
import json
import os
import sys
import tempfile

# event: (matcher, timeout, async), as the hook expects them (bin/notch-session's header)
EVENTS = {
    "SessionStart": (None, 20, False),
    "UserPromptSubmit": (None, 20, False),
    "Stop": (None, 20, False),
    "SessionEnd": (None, 20, False),
    "PreToolUse": (None, 10, True),
    "SubagentStart": (None, 10, True),
    "SubagentStop": (None, 10, True),
    "Notification": ("permission_prompt|agent_needs_input|elicitation_dialog", 20, False),
}


def runs_notch_session(groups):
    return any("notch-session" in str(h.get("command", "")) for g in groups if isinstance(g, dict)
               for h in g.get("hooks", []) if isinstance(h, dict))


def merge(settings, command):
    hooks = settings.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        return None
    added = False
    for event, (matcher, timeout, run_async) in EVENTS.items():
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list) or runs_notch_session(groups):
            continue
        hook = {"type": "command", "command": command, "timeout": timeout}
        if run_async:
            hook["async"] = True
        groups.append({**({"matcher": matcher} if matcher else {}), "hooks": [hook]})
        added = True
    return added


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: claude_hooks.py <notch-session>")
    folder = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    path = os.path.join(folder, "settings.json")
    try:
        with open(path, encoding="utf-8") as f:
            settings = json.load(f)
    except FileNotFoundError:
        settings = {}
    except (OSError, ValueError):
        sys.exit(1)
    if not isinstance(settings, dict):
        sys.exit(1)
    added = merge(settings, sys.argv[1])
    if added is None:
        sys.exit(1)
    if not added:
        sys.exit(0)
    os.makedirs(folder, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".settings.json.")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if os.path.exists(path):
        os.chmod(tmp, os.stat(path).st_mode & 0o777)
    os.replace(tmp, path)
