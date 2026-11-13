#!/usr/bin/env bash
# Screen recording: a second call while one runs stops it.
#   record.sh [--region "X,Y WxH" | --fullscreen [--output NAME]] [--sound | --mic]
#   record.sh --stop       stops one if it runs, and clears a state left saying it does
# --region takes slurp's form (logical, global); without it or --fullscreen, slurp asks. --sound records what the
# computer plays, --mic the microphone. The notch reads the state (states.json .record: enable, file, started, thumb)
# and says it all, so this script only speaks when something fails.
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
CUSTOM_PATH=$(jq -r '.screenRecord.savePath // empty' "$CONFIG_FILE" 2>/dev/null)
# with no path set, the account's Videos folder by its own name (xdg-user-dirs names it in the account's language:
# ~/Vidéos), the one the recorder's folder button opens; a made-up ~/Videos beside it hid every recording
VIDEOS=$(xdg-user-dir VIDEOS 2>/dev/null); [[ -z "$VIDEOS" || "$VIDEOS" == "$HOME" ]] && VIDEOS=$HOME/Videos
RECORDING_DIR="${CUSTOM_PATH:-$VIDEOS}"
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/states.json"
THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/recordings"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/tacit-record.lock"

say() {
    notify-send "Screen recording" "$1" -a 'Recorder' & disown
}

# set_state <jq filter> [jq args...]
set_state() {
    local filter=$1 tmp
    shift
    # beside the state file, so the mv is a rename: the notch never reads a half-copied file
    tmp=$(mktemp "$STATE_FILE.XXXXXX" 2>/dev/null)
    # Without the file the jq pipeline writes nothing, the `&& mv` never runs, and the shell's
    # recording indicator keeps whatever it had - so it says "recording" when nothing is.
    if [[ ! -f "$STATE_FILE" ]] || ! jq "$@" "$filter" "$STATE_FILE" > "$tmp"; then
        rm -f "$tmp"
        say "The notch may show the wrong thing for this recording: its note could not be updated."
        return 1
    fi
    mv "$tmp" "$STATE_FILE"
}

getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

# The second call: wf-recorder finishes the file on SIGINT, and the call that started it writes the state once it has.
if [[ "$1" == --stop ]] && ! pgrep -x wf-recorder > /dev/null; then
    # The call that started the recording holds this lock until it has finished the file and written the state: a Stop
    # pressed again meanwhile has nothing to do, and clearing the state now would raise the card with no length or still.
    exec 9>"$LOCK_FILE"
    flock -n 9 || exit 0
    # --stale (shell start after a crash): no file either, a cut-off recording is no "saved" card. A plain --stop keeps it.
    if [[ "$(jq -r '.record.enable' "$STATE_FILE" 2>/dev/null)" == "true" ]]; then
        if [[ "$2" == --stale ]]; then set_state '.record.enable = false | .record.file = ""'; else set_state '.record.enable = false'; fi
    fi
    exit 0
fi
if pgrep -x wf-recorder > /dev/null; then
    pkill -INT -x wf-recorder
    # wf-recorder writes the mp4's index when it ends, which takes a while after a long recording: killed
    # before that the file does not play
    for _ in $(seq 600); do
        pgrep -x wf-recorder > /dev/null || break
        sleep 0.1
    done
    pkill -KILL -x wf-recorder 2>/dev/null
    # the starting call was killed with it (a shell restart, a logout): nobody else will say it stopped
    for _ in $(seq 30); do
        [[ "$(jq -r '.record.enable' "$STATE_FILE" 2>/dev/null)" == "true" ]] || exit 0
        sleep 0.1
    done
    set_state '.record.enable = false'
    exit 0
fi

REGION=""
FULLSCREEN=0
OUTPUT=""
AUDIO=""
while (( $# > 0 )); do
    case "$1" in
        --region) REGION="$2"; shift ;;
        --fullscreen) FULLSCREEN=1 ;;
        --output) OUTPUT="$2"; shift ;;
        --sound) AUDIO=system ;;
        --mic) AUDIO=mic ;;
    esac
    shift
done

mkdir -p "$RECORDING_DIR" || { say "The folder $RECORDING_DIR could not be made, so nothing was recorded."; exit 1; }

WHERE=()
if (( FULLSCREEN )); then
    WHERE=(-o "${OUTPUT:-$(getactivemonitor)}")
else
    if [[ -z "$REGION" ]] && ! REGION="$(slurp 2>/dev/null)"; then
        exit 1
    fi
    WHERE=(--geometry "$REGION")
fi

# pactl, not wpctl: wf-recorder takes a PulseAudio source name, and only pactl gives them (pipewire-pulse)
SOUND=()
if [[ -n "$AUDIO" ]]; then
    if ! command -v pactl > /dev/null 2>&1; then
        say "This recording has no sound: the sound system could not be reached."
    elif [[ "$AUDIO" == system ]]; then
        SOUND=(--audio="$(pactl get-default-sink).monitor")
    else
        SOUND=(--audio="$(pactl get-default-source)")
    fi
fi

# "Screen recording 21 Oct at 07.15.mp4", as the notch names it; a second one in the same minute gets "(2)"
base="Screen recording $(LC_ALL=C date '+%-d %b at %H.%M')"
FILE="$RECORDING_DIR/$base.mp4"
n=2
while [[ -e "$FILE" ]]; do
    FILE="$RECORDING_DIR/$base ($n).mp4"
    n=$((n + 1))
done

# held until this call exits (the recorder itself is started without it), so --stop can tell a recording that is still
# being finished from a state left behind
exec 9>"$LOCK_FILE"
flock -n 9
set_state '.record.enable = true | .record.file = $f | .record.started = ($t | tonumber) | .record.stopped = 0 | .record.thumb = ""' \
    --arg f "$FILE" --arg t "$(date +%s%3N)" || exit 1
# The encoder is the heaviest thing running for as long as the recording lasts. At normal priority with a thread per
# core, a software encode of a large or fast screen starves the compositor and the shell: the pointer (drawn by the
# hardware) still moves while the dock, the bar and the windows stall. It runs behind them, on at most half the cores.
THREADS=$(( $(nproc 2>/dev/null || echo 4) / 2 ))
(( THREADS < 2 )) && THREADS=2
nice -n 10 wf-recorder "${WHERE[@]}" "${SOUND[@]}" --pixel-format yuv420p -p "threads=$THREADS" -f "$FILE" > /dev/null 2>&1 9>&-
code=$?
STOPPED=$(date +%s%3N)

if [[ ! -s "$FILE" ]]; then
    rm -f "$FILE"
    set_state '.record.enable = false | .record.file = ""'
    echo "wf-recorder exited with $code" >&2
    say "The recording could not start. Try again, or pick another screen."
    exit 1
fi
# the notch's card shows a still from the start; the old stills go
THUMB=""
if mkdir -p "$THUMB_DIR"; then
    find "$THUMB_DIR" -name '*.jpg' -delete
    THUMB="$THUMB_DIR/$(date +%s%3N).jpg"
    ffmpeg -loglevel error -y -i "$FILE" -frames:v 1 -vf 'scale=-2:240' "$THUMB" < /dev/null || THUMB=""
fi
set_state '.record.enable = false | .record.thumb = $th | .record.stopped = ($s | tonumber)' --arg th "$THUMB" --arg s "$STOPPED"
