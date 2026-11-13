#!/usr/bin/env python3
import json, re, subprocess, sys, time, os

# Per session, not per boot: /tmp survives a logout on any distro that does not put it on tmpfs,
# and there the guard made autostart a one-time event forever.
# --now (Settings' run button) starts them whatever ran before: the lock is there so a shell reload does not.
lockfile = os.path.join(os.environ.get('XDG_RUNTIME_DIR', '/tmp'), 'qs-autostart.lock')
if os.path.exists(lockfile) and '--now' not in sys.argv[1:]:
    exit(0)

# The lock is taken once the config has been read: on a new account the file is not there yet at the
# first start, and a lock made before that stopped autostart for the rest of the session.
try:
    with open(f"{os.environ['HOME']}/.config/illogical-impulse/config.json") as f:
        data = json.load(f)
except (OSError, ValueError):
    exit(0)
open(lockfile, 'w').close()

autostart = data.get('hyprland', {}).get('autostartApps', {})
if not autostart.get('enable', False):
    exit(0)

for app in autostart.get('apps', []):
    cmd = app.get('cmd', '').strip()
    workspace = app.get('workspace', 1)
    delay = app.get('delay', 0)
    if not cmd:
        continue

    # The workspace goes with the command as an exec rule ([workspace N] cmd): the window lands there when it
    # maps, however long that takes. Focusing the workspace first and sleeping `delay` left every app of a
    # run with no delay on the last app's workspace, because the next focus came before the first window.
    # A number is a workspace id, anything else a name; a name that would end the rule is left out.
    ws = str(workspace).strip()
    if re.fullmatch(r'-?\d+', ws):
        rule = f'[workspace {ws}] '
    elif ws and not re.search(r'[;\[\]\n]', ws):
        rule = f'[workspace {ws if ws.startswith(("name:", "special:")) else "name:" + ws}] '
    else:
        rule = ''

    expanded_cmd = os.path.expanduser(cmd)
    # The command lands inside a Lua string literal, so a quote in it ended the string and the
    # whole dispatch was rejected - silently, since nothing reads this output.
    lua_cmd = (rule + expanded_cmd).replace('\\', '\\\\').replace('"', '\\"')
    subprocess.Popen(
        ['hyprctl', 'dispatch', f'hl.dsp.exec_cmd("{lua_cmd}")'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        close_fds=True
    )

    time.sleep(delay)