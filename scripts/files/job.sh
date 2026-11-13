#!/bin/bash
# Files' job runner: one operation, detached from the shell, reporting to a JSON file that the
# window and the notch read. Outlives the window, a shell reload and a crash.
#
#   job.sh <id> copy    <policy> <dest-dir> <src>...     policy: replace | keep | skip
#   job.sh <id> move    <policy> <dest-dir> <src>...
#   job.sh <id> trash   <src>...
#   job.sh <id> restore <trash-item>...                 (names under trash:///)
#   job.sh <id> rename  <src> <new-name>
#   job.sh <id> mkdir   <dir> <name>
#   job.sh <id> delete  <src>...                        (permanent; the UI has asked)
#   job.sh <id> moveback <from> <to> ...                (undo of a move or rename)
#   job.sh <id> restore-paths <orig-path>...            (undo of a trash)
#   job.sh <id> touch   <dir> <name>                    (a new, empty file)
#   job.sh <id> compress <dir> <zip-name> <src>...      (one .zip of them, in <dir>)
#   job.sh <id> renames <src> <new-name> ...            (many at once; every name checked before any moves)
#   job.sh <id> unreplace <path> <old-file> <old-record> ...  (undo of a copy that replaced: see set_aside)
#
# Report: $XDG_STATE_HOME/quickshell/user/files/jobs/<id>.json
#   { id, op, dest, state: running|done|failed|cancelled, total, done, bytes, bytesDone, pid,
#     current, error, said, started, ended, results: [...], undo: {...} }
#   said: a done job's own sentence, when the usual one would leave something out; else empty
# Cancel: touch <id>.cancel next to the report.
set -u
id=$1; op=$2; shift 2
dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/files/jobs"
mkdir -p "$dir"
report="$dir/$id.json"; cancel="$dir/$id.cancel"
state=running; total=0; done_=0; bytes=0; bytesDone=0; current=""; error=""; said=""; dest=""
started=$(date +%s%3N); ended=null
results=(); undo='null'

# The freedesktop trash spec, by hand: find the record whose Path is $1 (URL-encoded), move the
# file back, drop the record. The home trash, and the one gio trash makes on the file's own disk (a
# stick's .Trash-UID), whose Paths start at the disk's top: gio's trash:/// needs GVfs, which a
# fresh install does not have, so Undo of a trash on a stick said "Could not put it back".
restore_from_trash() {
    local want=$1 info name path line tdir top
    top=$(stat -c %m -- "$(dirname -- "$want")" 2>/dev/null)
    for info in "${XDG_DATA_HOME:-$HOME/.local/share}/Trash/info/"*.trashinfo "$top/.Trash-$UID/info/"*.trashinfo "$top/.Trash/$UID/info/"*.trashinfo; do
        [ -e "$info" ] || continue
        tdir=${info%/info/*}
        path=""   # the first Path=, URL-decoded in bash: a process per record made a big undo take minutes
        while IFS= read -r line; do
            case $line in Path=*) path=${line#Path=}; path=${path//\\/\\\\}; printf -v path '%b' "${path//%/\\x}"; break ;; esac
        done < "$info"
        case $path in /*) ;; ?*) path=${top%/}/$path ;; esac
        [ "$path" = "$want" ] || continue
        name=$(basename -- "$info" .trashinfo)
        [ -e "$tdir/files/$name" ] || continue   # an orphan record must not fail a valid restore
        [ -e "$want" ] && return 1
        mkdir -p "$(dirname -- "$want")" && mv -- "$tdir/files/$name" "$want" && rm -f -- "$info" && return 0
        return 1
    done
    return 1
}

# Put back by the name a file has in the home trash (Files' Trash lists Trash/files), or in the trash $2 that gio made on
# another drive (<top>/.Trash-UID, listed under the drive's name), whose Paths start at the drive's top: its record says
# where it came from. gio trash --restore does this only where GVfs runs, and a fresh install said "Operation not
# supported", so Put back left everything in the trash (Discord 2026-10-29); gio stays for a name not found here.
restore_by_name() {
    local name=$1 tdir=${2:-${XDG_DATA_HOME:-$HOME/.local/share}/Trash} info path top
    info="$tdir/info/$name.trashinfo"
    [ -e "$info" ] && [ -e "$tdir/files/$name" ] || return 2
    path=$(sed -n 's/^Path=//p' "$info" | head -1 | python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.stdin.read().rstrip("\n")))')
    case $path in
    /*) ;;
    ?*) [ -n "${2:-}" ] && top=$(stat -c %m -- "$tdir" 2>/dev/null) || return 1; path=${top%/}/$path ;;
    *) return 1 ;;
    esac
    # another one of that name is there now: this one comes back beside it, as "notes 2.txt" (taken, restored)
    [ -e "$path" ] && { taken=$path; path=$(keep_name "$(dirname -- "$path")" "$(basename -- "$path")"); }
    restored=$path
    mkdir -p "$(dirname -- "$path")" && mv -- "$tdir/files/$name" "$path" && rm -f -- "$info" && return 0
    return 1
}

# A JSON array from lines on stdin. Lists go to jq as files: one argv string is capped at 128 KiB,
# which a few thousand paths pass, and the report then stopped updating and stayed "running".
write() {
    local ended_json=$ended
    jq -nc --rawfile results <(printf '%s\n' "${results[@]:-}") --rawfile undo <(printf '%s' "$undo") --arg id "$id" --arg op "$op" --arg dest "$dest" --arg state "$state" \
        --argjson total "$total" --argjson done "$done_" --argjson bytes "$bytes" --argjson bytesDone "$bytesDone" \
        --arg current "$current" --arg error "$error" --arg said "$said" --argjson started "$started" --argjson ended "$ended_json" --argjson pid $$ \
        '{id:$id, op:$op, dest:$dest, state:$state, total:$total, done:$done, bytes:$bytes, bytesDone:$bytesDone, pid:$pid, current:$current, error:$error, said:$said, started:$started, ended:$ended, results:($results | split("\n") | map(select(length > 0))), undo:($undo | fromjson)}' \
        > "$report.tmp" && mv -f "$report.tmp" "$report"
}
finish() { state=$1; ended=$(date +%s%3N); current=""; write; rm -f "$cancel"; exit 0; }
cancelled() { [ -e "$cancel" ]; }

# What went wrong, in words: "Could not delete a.txt" + the tool's complaint -> the reason when it is
# one a person can act on. $1 is the sentence, $2 what the tool said, in English: the tools whose words are read here
# run with LC_ALL=C, or gio and coreutils said them in the person's language and nothing matched.
because() {
    local r=""
    case "$2" in
    *"Permission denied"*|*"Operation not permitted"*) r="you are not allowed to change it here" ;;
    *"Read-only file system"*) r="the disk is read-only" ;;
    *"No space left"*) r="the disk is full" ;;
    *"busy"*) r="it is in use" ;;
    *"No such file"*) r="it is not there any more" ;;
    esac
    error="$1${r:+: $r}"
}

# "name", "name 2", "name 3" ... beside a file that is already there
keep_name() {   # dir base -> free path
    local d=$1 b=$2 stem ext n=2
    [ ! -e "$d/$b" ] && { printf '%s' "$d/$b"; return; }
    # a file's extension is its last dot-word, or .tar.<x> whole, as Rename many takes it ("notes 2.markdown",
    # "x 2.tar.gz"; a 1-to-5-letter rule gave "notes.markdown 2"); a folder "Hyprland-0.56.2" has none
    stem=$b; ext=""
    if [ ! -d "$d/$b" ] && { [[ "$b" =~ ^(.+)(\.tar\.[^.[:space:]]+)$ ]] || [[ "$b" =~ ^(.+)(\.[^.[:space:]]+)$ ]]; }; then
        stem=${BASH_REMATCH[1]}; ext=${BASH_REMATCH[2]}
    fi
    while [ -e "$d/$stem $n$ext" ]; do n=$((n+1)); done
    printf '%s' "$d/$stem $n$ext"
}

# Replace moves the old one out of the way before the new one comes (cp and mv would put a folder inside the old one,
# and wrote a file over the old one in place, so Stop or a full disk left it half-written or gone): to the trash, so it
# can come back, or beside itself under a hidden name where the disk has no trash. old_back says how it comes back:
# "<file in the trash><tab><its .trashinfo>", or the hidden name. $1 the target, $2 its name for the error.
trash_records() {   # every .trashinfo in the trashes a file at $1 can go to: home's and its disk's
    local mnt; mnt=$(stat -c %m -- "$1" 2>/dev/null)
    ( shopt -s nullglob; printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/Trash/info/"*.trashinfo \
        "$mnt/.Trash-$UID/info/"*.trashinfo "$mnt/.Trash/$UID/info/"*.trashinfo ) | sort
}
set_aside() {
    local before rec out
    old_back=""
    before=$(trash_records "$1")
    if out=$(LC_ALL=C gio trash -- "$1" 2>&1); then
        rec=$(comm -13 <(printf '%s\n' "$before") <(trash_records "$1") | tail -1)
        [ -n "$rec" ] && old_back="$(dirname -- "$(dirname -- "$rec")")/files/$(basename -- "$rec" .trashinfo)"$'\t'"$rec"
        return 0
    fi
    case "$out" in
    *"not supported"*|*"trash"*"directory"*|*"Unable to find or create"*)
        old_back="$(dirname -- "$1")/.replaced-$id-$(basename -- "$1")"
        mv -- "$1" "$old_back" && return 0 ;;
    esac
    because "Could not replace $2" "$out"; return 1
}
put_back() {   # $1 the target, $2 its old_back: the old one goes back where it was, when nothing is there now
    local file=${2%%$'\t'*} rec=""
    [ -n "$2" ] && [ ! -e "$1" ] && [ -e "$file" ] || return 1
    case "$2" in *$'\t'*) rec=${2#*$'\t'} ;; esac
    mv -- "$file" "$1" && { [ -z "$rec" ] || rm -f -- "$rec"; }
}

case "$op" in
copy|move)
    policy=$1; dest=$2; shift 2
    srcs=("$@"); total=${#srcs[@]}
    write   # at once: the size scan below can take longer than the shell waits for a first report
    for s in "${srcs[@]}"; do b=$(du -sb -- "$s" 2>/dev/null | cut -f1); bytes=$((bytes + ${b:-0})); done
    write
    moved_from=(); made=(); backs=()
    # Undo is of what was made, also when Stop or a failure ends the batch part way
    finish_made() {
        if [ ${#made[@]} -eq 0 ]; then :   # nothing made (all skipped, or the first one failed): nothing to undo
        elif [ "$op" = move ]; then
            undo=$(jq -nc --rawfile to <(printf '%s\n' "${made[@]}") --rawfile from <(printf '%s\n' "${moved_from[@]}") '{op:"move-back", from:($to | split("\n") | map(select(length > 0))), to:($from | split("\n") | map(select(length > 0)))}')
        elif [ ${#backs[@]} -gt 0 ]; then
            # a copy that replaced: Undo puts the old ones back too ("-": a new one that replaced nothing)
            args=(); for t in "${made[@]}"; do
                r=-; for ((i = 0; i < ${#backs[@]}; i += 3)); do [ "${backs[i]}" = "$t" ] && r=$i; done
                if [ "$r" = - ]; then args+=("$t" - -); else args+=("$t" "${backs[r+1]}" "${backs[r+2]}"); fi
            done
            undo=$(jq -nc --rawfile args <(printf '%s\n' "${args[@]}") '{op:"unreplace", args:($args | split("\n") | map(select(length > 0)))}')
        else
            undo=$(jq -nc --rawfile paths <(printf '%s\n' "${made[@]}") '{op:"delete", paths:($paths | split("\n") | map(select(length > 0)))}')
        fi
        finish "$1"
    }
    for s in "${srcs[@]}"; do
        cancelled && finish_made cancelled
        name=$(basename -- "$s"); target="$dest/$name"; current=$name; old_back=""; write
        if [ -e "$target" ]; then
            case "$policy" in
            skip)    done_=$((done_+1)); continue ;;
            keep)    target=$(keep_name "$dest" "$name") ;;
            replace)
                # pasted onto itself: nothing to replace
                if [ "$s" -ef "$target" ]; then done_=$((done_+1)); continue; fi
                if [ -d "$target" ] || [ -d "$s" ]; then
                    case "$target/" in "$s"/*) error="Could not replace $name: it holds the one being put there"; finish_made failed ;; esac
                    case "$s/" in "$target"/*) error="Could not replace $name: it holds the one being put there"; finish_made failed ;; esac
                fi
                # the old one, file or folder, out of the way first, so it can come back
                set_aside "$target" "$name" || finish_made failed ;;
            esac
        fi
        # A move within a disk is a rename, done at once. Across disks mv copies and then deletes the source, so Stop or a
        # full disk left a half copy that looked whole beside the source: such a move is a copy here, and the source goes
        # once the copy is whole. (LC_ALL=C: the reason is read.)
        copying=1; before=$bytesDone
        if [ "$op" = move ]; then
            if LC_ALL=C mv --no-copy -f -- "$s" "$target" 2>"$report.err"; then copying=""
            elif ! grep -q 'cross-device' "$report.err"; then
                because "Could not move $name" "$(cat "$report.err")"; rm -f "$report.err"; put_back "$target" "$old_back"
                finish_made failed
            fi
        fi
        if [ -n "$copying" ]; then
            # progress: the target growing, sampled while the copy runs
            LC_ALL=C cp -a -- "$s" "$target" 2>"$report.err" &
            pid=$!
            while kill -0 "$pid" 2>/dev/null; do
                if cancelled; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -rf -- "$target"; put_back "$target" "$old_back"; finish_made cancelled; fi
                cur=$(du -sb -- "$target" 2>/dev/null | cut -f1); bytesDone=$((before + ${cur:-0})); write; sleep 0.3
            done
            if ! wait "$pid"; then
                because "Could not ${op} $name" "$(cat "$report.err" 2>/dev/null)"; rm -f "$report.err"
                # what was copied goes (the source is whole), and an old one set aside comes back
                rm -rf -- "$target"; put_back "$target" "$old_back"
                finish_made failed
            fi
            # the copy is whole: a move's source goes now. If it cannot, the copy stays, as mv left it.
            if [ "$op" = move ] && ! LC_ALL=C rm -rf -- "$s" 2>"$report.err"; then
                because "Could not move $name" "$(cat "$report.err")"; rm -f "$report.err"; finish_made failed
            fi
        fi
        rm -f "$report.err"
        # the old one set aside on a disk with no trash goes now that the new one is whole; one in the trash stays for Undo
        case "$old_back" in ?*$'\t'*) backs+=("$target" "${old_back%%$'\t'*}" "${old_back#*$'\t'}") ;; ?*) rm -rf -- "$old_back" ;; esac
        cur=$(du -sb -- "$target" 2>/dev/null | cut -f1); bytesDone=$((before + ${cur:-0}))
        results+=("$target"); made+=("$target"); [ "$op" = move ] && moved_from+=("$s")
        done_=$((done_+1)); write
    done
    finish_made done ;;
unreplace)   # triples: <path> <old file in the trash> <its record>, "-" "-" for none: the copy to the trash, the old one back
    total=$(( $# / 3 )); args=("$@"); write
    for ((i = 0; i + 2 < ${#args[@]}; i += 3)); do
        p=${args[i]}; current=$(basename -- "$p"); write
        if [ -e "$p" ] && ! out=$(LC_ALL=C gio trash -- "$p" 2>&1); then because "Could not move $current to the trash" "$out"; finish failed; fi
        if [ "${args[i+1]}" != - ] && ! put_back "$p" "${args[i+1]}"$'\t'"${args[i+2]}"; then error="Could not put $current back"; finish failed; fi
        results+=("$p"); done_=$((done_+1)); write
    done
    finish done ;;
trash)
    total=$#; write
    for s in "$@"; do
        current=$(basename -- "$s"); write
        if ! out=$(LC_ALL=C gio trash -- "$s" 2>&1); then
            # no trash on this filesystem (a stick, /tmp): the UI asks about deleting for good
            case "$out" in *"not supported"*|*"trash"*"directory"*|*"Unable to find or create"*) error="no trash on this disk" ;; *) because "Could not move $(basename -- "$s") to the trash" "$out" ;; esac
            finish failed
        fi
        results+=("$s"); done_=$((done_+1)); write
    done
    undo=$(jq -nc --rawfile paths <(printf '%s\n' "${results[@]}") '{op:"restore-paths", paths:($paths | split("\n") | map(select(length > 0)))}')
    finish done ;;
restore-paths)
    total=$#; write
    for p in "$@"; do
        current=$(basename -- "$p"); write
        item=$(gio list -a trash::orig-path trash:/// 2>/dev/null | awk -F'\t' -v want="$p" '{ n=$1; for (i=2;i<=NF;i++) if (index($i, "trash::orig-path=")==1 && substr($i, 18)==want) print n }' | head -1)
        if [ -z "$item" ] || ! gio trash --restore "trash:///$item" 2>/dev/null; then
            # gio's listing lags a fresh trash by seconds (its monitor has not caught up), and
            # an undo comes right after the trash: read the trashes' own records instead.
            if ! restore_from_trash "$p"; then error="Could not put $(basename -- "$p") back"; finish failed; fi
        fi
        done_=$((done_+1)); write
    done
    finish done ;;
restore)   # names in the home trash, or paths in a drive's (<top>/.Trash-UID/files/<name>)
    total=$#; renamed=(); write
    for item in "$@"; do
        current=${item##*/}; taken=""; write
        case $item in
        /*) restore_by_name "$current" "${item%/files/*}"; r=$? ;;
        *) restore_by_name "$item"; r=$?
           if [ $r = 2 ]; then gio trash --restore "trash:///$item" 2>/dev/null && r=0 || r=1; fi ;;
        esac
        if [ $r != 0 ]; then error="Could not put $current back"; finish failed; fi
        [ -n "$taken" ] && renamed+=("$(basename -- "$taken") as $(basename -- "$restored")")
        done_=$((done_+1)); write
    done
    # said: one that came back under a new name, because another of its name is there now
    case ${#renamed[@]} in
    0) ;;
    1) [ "$total" = 1 ] && said="Put back ${renamed[0]}" || said="Put $total items back · ${renamed[0]}" ;;
    *) said="Put $total items back · ${#renamed[@]} under new names" ;;
    esac
    finish done ;;
rename)
    src=$1; new=$2; total=1; dir_=$(dirname -- "$src"); target="$dir_/$new"; current=$new; write
    if [ -e "$target" ]; then error="$new is already here"; finish failed; fi
    if ! out=$(LC_ALL=C mv -- "$src" "$target" 2>&1); then because "Could not rename" "$out"; finish failed; fi
    results+=("$target"); done_=1
    undo=$(jq -nc --arg from "$target" --arg to "$src" '{op:"move-back", from:[$from], to:[$to]}')
    finish done ;;
mkdir)
    parent=$1; name=$2; total=1; target="$parent/$name"; current=$name; write
    if [ -e "$target" ]; then error="$name is already here"; finish failed; fi
    if ! mkdir -- "$target"; then error="Could not make $name here"; finish failed; fi
    results+=("$target"); done_=1
    undo=$(jq -nc --arg p "$target" '{op:"delete", paths:[$p]}')
    finish done ;;
moveback)   # pairs: from to from to ... (the undo of a move or a rename)
    # Like renames: a "to" that is another pair's "from" waits for that pair; a swap or ring parks one file.
    total=$(( $# / 2 )); args=("$@"); write
    declare -A leaving=() parked=()
    unpark() { for k in "${!parked[@]}"; do mv -n -- "${parked[$k]}" "${args[k]}" 2>/dev/null; done; }
    pend=(); for ((i = 0; i < ${#args[@]} - 1; i += 2)); do leaving[${args[i]}]=1; pend+=("$i"); done
    while [ ${#pend[@]} -gt 0 ]; do
        rest=(); moved=0
        for i in "${pend[@]}"; do
            from=${args[i]}; to=${args[i+1]}; current=$(basename -- "$to")
            if [ -n "${leaving[$to]:-}" ]; then rest+=("$i"); continue; fi
            if [ -e "$to" ]; then unpark; error="$(basename -- "$to") is there again"; finish failed; fi
            mkdir -p -- "$(dirname -- "$to")"
            if ! mv -f -- "${parked[$i]:-$from}" "$to"; then unpark; error="Could not put $(basename -- "$to") back"; finish failed; fi
            unset "parked[$i]"; leaving[$from]=""; moved=1
            results+=("$to"); done_=$((done_+1)); write
        done
        pend=("${rest[@]}")
        if [ $moved = 0 ] && [ ${#pend[@]} -gt 0 ]; then
            i=${pend[0]}; from=${args[i]}; park="$(dirname -- "$from")/.rename-$id-$i"
            if ! mv -n -- "$from" "$park"; then unpark; error="Could not put $(basename -- "${args[i+1]}") back"; finish failed; fi
            parked[$i]=$park; leaving[$from]=""
        fi
    done
    finish done ;;
extract)   # <archive> -> a folder beside it named after it (bsdtar reads every common format)
    src=$1; total=1; d=$(dirname -- "$src"); b=$(basename -- "$src"); stem=${b%.*}; case "$stem" in *.tar) stem=${stem%.tar} ;; esac
    target=$(keep_name "$d" "$stem"); current=$(basename -- "$target"); write
    mkdir -p -- "$target" || { error="Could not make a folder for it"; finish failed; }
    bsdtar -xf "$src" -C "$target" 2>/dev/null &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if cancelled; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -rf -- "$target"; finish cancelled; fi
        cur=$(du -sb -- "$target" 2>/dev/null | cut -f1); bytesDone=${cur:-0}; write; sleep 0.3
    done
    if ! wait "$pid"; then rm -rf -- "$target"; error="Could not unpack $b"; finish failed; fi
    results+=("$target"); done_=1
    undo=$(jq -nc --arg p "$target" '{op:"delete", paths:[$p]}')
    finish done ;;
touch)
    parent=$1; name=$2; total=1; target="$parent/$name"; current=$name; write
    if [ -e "$target" ]; then error="$name is already here"; finish failed; fi
    if ! ( set -o noclobber; : > "$target" ) 2>/dev/null; then error="Could not make $name here"; finish failed; fi
    results+=("$target"); done_=1
    undo=$(jq -nc --arg p "$target" '{op:"delete", paths:[$p]}')
    finish done ;;
compress)   # names go in relative to their folder, so the archive holds them, not the path to them
    dest=$1; name=$2; shift 2; srcs=("$@"); total=${#srcs[@]}
    target=$(keep_name "$dest" "$name"); current=$(basename -- "$target"); write
    names=(); for s in "${srcs[@]}"; do names+=("./$(basename -- "$s")"); done
    bsdtar -a -cf "$target" -C "$(dirname -- "${srcs[0]}")" -- "${names[@]}" 2>/dev/null &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if cancelled; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -f -- "$target"; finish cancelled; fi
        sleep 0.3
    done
    if ! wait "$pid"; then rm -f -- "$target"; error="Could not compress $(basename -- "${srcs[0]}")"; finish failed; fi
    results+=("$target"); done_=$total
    undo=$(jq -nc --arg p "$target" '{op:"delete", paths:[$p]}')
    finish done ;;
renames)   # pairs: <src> <new-name>; nothing moves unless every new name is free (or is left by another of them) and no two are alike
    total=$(( $# / 2 )); args=("$@"); write
    declare -A taken=() leaving=()
    for ((i = 0; i < ${#args[@]}; i += 2)); do
        from=${args[i]}; to="$(dirname -- "$from")/${args[i+1]}"
        [ "$to" != "$from" ] && leaving[$from]=1
    done
    for ((i = 0; i < ${#args[@]}; i += 2)); do
        from=${args[i]}; to="$(dirname -- "$from")/${args[i+1]}"
        [ "$to" = "$from" ] && continue
        if [ -e "$to" ] && [ -z "${leaving[$to]:-}" ]; then error="${args[i+1]} is already here"; finish failed; fi
        if [ -n "${taken[$to]:-}" ]; then error="Two would be called ${args[i+1]}"; finish failed; fi
        taken[$to]=1
    done
    # A chain (img 03 -> img 02, img 04 -> img 03): a file goes once its new name is no longer another's
    # old one. A swap or ring has no such first move: one of them is parked under a hidden name.
    # The order is the one a reverse (undo) needs too.
    unpark() { for k in "${!parked[@]}"; do mv -n -- "${parked[$k]}" "${args[k]}" 2>/dev/null; done; }
    froms=(); tos=(); pend=(); declare -A parked=()
    for ((i = 0; i < ${#args[@]}; i += 2)); do
        from=${args[i]}; to="$(dirname -- "$from")/${args[i+1]}"
        if [ "$to" = "$from" ]; then results+=("$to"); done_=$((done_ + 1)); else pend+=("$i"); fi
    done
    while [ ${#pend[@]} -gt 0 ]; do
        rest=(); moved=0
        for i in "${pend[@]}"; do
            from=${args[i]}; to="$(dirname -- "$from")/${args[i+1]}"
            if [ -n "${leaving[$to]:-}" ]; then rest+=("$i"); continue; fi
            current=${args[i+1]}
            if ! mv -n -- "${parked[$i]:-$from}" "$to"; then unpark; error="Could not rename $(basename -- "$from")"; finish failed; fi
            unset "parked[$i]"; leaving[$from]=""; moved=1
            froms+=("$from"); tos+=("$to"); results+=("$to"); done_=$((done_ + 1)); write
        done
        pend=("${rest[@]}")
        if [ $moved = 0 ]; then
            i=${pend[0]}; from=${args[i]}; park="$(dirname -- "$from")/.rename-$id-$i"
            if ! mv -n -- "$from" "$park"; then unpark; error="Could not rename $(basename -- "$from")"; finish failed; fi
            parked[$i]=$park; leaving[$from]=""
        fi
    done
    rev_froms=(); rev_tos=()
    for ((i = ${#tos[@]} - 1; i >= 0; i--)); do rev_froms+=("${froms[i]}"); rev_tos+=("${tos[i]}"); done
    undo=$(jq -nc --rawfile from <(printf '%s\n' "${rev_tos[@]}") --rawfile to <(printf '%s\n' "${rev_froms[@]}") '{op:"move-back", from:($from | split("\n") | map(select(length > 0))), to:($to | split("\n") | map(select(length > 0)))}')
    finish done ;;
delete)
    total=$#; write
    tdir="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
    for s in "$@"; do
        current=$(basename -- "$s"); write
        if ! out=$(LC_ALL=C rm -rf -- "$s" 2>&1); then because "Could not delete $(basename -- "$s")" "$out"; finish failed; fi
        # "Delete for good" inside the trash: the record goes with the file, or a later "put back"
        # of a same-named file matches a record whose file is gone. Only the trash's own top level
        # has records; a file inside a trashed folder is covered by that folder's one.
        case "$s" in
            "$tdir/files/"*/*) : ;;
            "$tdir/files/"*) rm -f -- "$tdir/info/$(basename -- "$s").trashinfo" ;;
        esac
        results+=("$s"); done_=$((done_+1)); write
    done
    finish done ;;
*)  error="unknown op $op"; finish failed ;;
esac
