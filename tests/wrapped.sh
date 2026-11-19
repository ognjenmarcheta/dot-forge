#!/usr/bin/env bash
# Tests for dot wrapped / dot credits / dot-calendar with a stand-in `atuin`,
# throwaway repos and canned agent / night-shift logs (nothing leaves the machine,
# except dot-calendar's first run downloading its two Python packages via uv).
# shellcheck disable=SC2034  # vars are read by the eval in check()
set -uo pipefail
DOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
S="$DOT/config/scripts"
T="$(cd "$(mktemp -d)" && pwd -P)"   # physical path (macOS: /var → /private/var)
FB="$T/fakebin"
mkdir -p "$FB" "$T/Github"
cd "$T" || exit 1
REAL_UV_CACHE="${UV_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/uv}"   # reuse downloaded packages
export HOME="$T" XDG_CONFIG_HOME="$T/.config" XDG_DATA_HOME="$T/.local/share" XDG_CACHE_HOME="$T/.cache" XDG_STATE_HOME="$T/.local/state"
export GIT_CONFIG_GLOBAL="$T/gitconfig" PATH="$FB:$PATH" DOT_PROJECTS="$T/Github" NO_COLOR=1
unset DOT_CALENDAR_ICS
fails=0
pass() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
w() { python3 "$S/dot-wrapped" "$@"; }

git config --global user.email me@example.com
git config --global user.name "Test Person"
git config --global init.defaultBranch main

Y="$(python3 -c 'import datetime as d; print((d.date.today() - d.timedelta(days=1)).isoformat())')"
OLD="$(python3 -c 'import datetime as d; print((d.date.today() - d.timedelta(days=10)).isoformat())')"
ep() { python3 -c 'import datetime as d,sys; print(int(d.datetime.fromisoformat(sys.argv[1]).timestamp()))' "$1"; }

# two repos: commits yesterday (mine and someone else's) and an old one
commit() { # repo date author-email message
    echo "$4" >> "$T/Github/$1/log.txt"
    git -C "$T/Github/$1" add log.txt
    GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$T/Github/$1" -c user.email="$3" commit -qm "$4"
}
for r in app api; do git init -q "$T/Github/$r"; done
commit app "${OLD}T09:00:00" me@example.com "old work"
commit app "${Y}T10:05:00" me@example.com "feat: one"
commit app "${Y}T11:05:00" me@example.com "feat: two"
commit app "${Y}T11:06:00" other@example.com "someone else"
commit api "${Y}T10:15:00" me@example.com "fix: api"

# shell history (atuin rows): a typo and its fix, a long dev server, an old row
R="$T/rows"
row() { printf '%s\t%s\t%s\t%s\t%s\0' "$1" "$2" "$3" "$4" "$5"; }
{
    row "$Y 10:00:00" 1s 0 "$T/Github/app" "git status"
    row "$Y 10:02:00" 30ms 127 "$T/Github/app" "gti status"
    row "$Y 10:02:20" 40ms 0 "$T/Github/app" "git status"
    row "$Y 10:10:00" "1h 5m" 0 "$T/Github/api/web" "pnpm dev"
    row "$Y 10:20:00" 20ms 0 "$T/Github/app" "ll"
    row "$Y 11:00:00" 20ms 0 "$T/Github/app/src" "clear; ll"
    row "$OLD 09:00:00" 1s 0 "$T/Github/app" "old command"
} > "$R"
cat > "$FB/atuin" <<'EOF'
#!/usr/bin/env bash
echo "atuin $*" >> "$FAKE_ATUIN_LOG"
[ "$1" = search ] && cat "$FAKE_ROWS"
EOF
chmod +x "$FB/atuin"
export FAKE_ROWS="$R" FAKE_ATUIN_LOG="$T/atuin.log"

# Claude Code hook log and night-shift queue
mkdir -p "$XDG_DATA_HOME/dotfiles/night"
{
    printf '%s\tworking\tapp\ts1\n' "$(ep "${Y}T10:00:00")"
    printf '%s\tdone\tapp\ts1\n'    "$(ep "${Y}T10:30:00")"
    printf '%s\tworking\tapp\ts1\n' "$(ep "${Y}T11:00:00")"
    printf '%s\twaiting\tapp\ts1\n' "$(ep "${Y}T11:10:00")"
    printf '%s\tworking\tapi\ts2\n' "$(ep "${Y}T13:00:00")"
    printf '%s\tdone\tapi\ts2\n'    "$(ep "${Y}T16:00:00")"
} > "$XDG_DATA_HOME/dotfiles/agents.log"
cat > "$XDG_DATA_HOME/dotfiles/night/queue.json" <<EOF
[{"id": "a1", "repo": "$T/Github/app", "task": "x", "state": "pr", "finished": "${Y}T02:10:00"},
 {"id": "a2", "repo": "$T/Github/app", "task": "y", "state": "queued"},
 {"id": "a3", "repo": "$T/Github/app", "task": "z", "state": "ready", "finished": "${OLD}T02:10:00"}]
EOF

echo "dot wrapped"
j="$(w wrapped --json)"
jq_() { printf '%s' "$j" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
check "--json is valid" 'printf "%s" "$j" | python3 -m json.tool >/dev/null'
check "asks atuin for the period, duplicates kept" 'grep -q -- "search --after" "$FAKE_ATUIN_LOG" && grep -q -- "--include-duplicates" "$FAKE_ATUIN_LOG"'
check "old rows left out (6 commands)" '[ "$(jq_ "d[\"commands\"]")" = 6 ]'
check "active time = 4 five-minute slots" '[ "$(jq_ "d[\"active_seconds\"]")" = 1200 ]'
check "time per project (app 15m, api 5m)" '[ "$(jq_ "d[\"projects\"]")" = "{'"'"'app'"'"': 900, '"'"'api'"'"': 300}" ]'
check "top command counts two words for git" '[ "$(jq_ "d[\"top_commands\"][0]")" = "['"'"'git status'"'"', 2]" ]'
check "\`clear; ll\` counts as ll" '[ "$(jq_ "dict(d[\"top_commands\"]).get(\"ll\")")" = 2 ]'
check "my commits only, in the period (3)" '[ "$(jq_ "d[\"commits_total\"]")" = 3 ] && [ "$(jq_ "d[\"commits\"][\"app\"]")" = 2 ]'
check "agents: 3 prompts, 2 sessions, 2h 40m (long run capped at 2 h)" '[ "$(jq_ "(d[\"agents\"][\"prompts\"], d[\"agents\"][\"sessions\"], d[\"agents\"][\"seconds\"])")" = "(3, 2, 9600)" ]'
check "night-shift tasks finished this week (1)" '[ "$(jq_ "d[\"night_tasks\"]")" = 1 ]'
check "typo fixed (gti → git)" '[ "$(jq_ "d[\"typos_fixed\"]")" = 1 ]'
check "longest command" '[ "$(jq_ "d[\"longest\"][\"cmd\"]")" = "pnpm dev" ]'
out="$(w wrapped)"
check "card renders the numbers" '[[ "$out" == *"20m active"* && "$out" == *"6 commands"* && "$out" == *"3 commits"* && "$out" == *"3 prompts"* && "$out" == *"1 typo fixed"* ]]'
check "card lists projects with commits" 'printf "%s\n" "$out" | grep -E "app .*15m .*2 commits" >/dev/null'
check "card fits in 80 columns" '[ "$(printf "%s\n" "$out" | python3 -c "import sys; print(max(len(l.rstrip(chr(10))) for l in sys.stdin))")" -le 80 ]'
check "no colours when NO_COLOR / not a tty" '! printf "%s" "$out" | grep -q $'"'"'\033'"'"''
check "--since a date" 'w wrapped --since "$OLD" --json | python3 -c "import json,sys; sys.exit(json.load(sys.stdin)[\"commands\"] != 7)"'

echo "dot credits"
check "--line for yesterday" '[ "$(w credits --yesterday --line)" = "🎬 yesterday · 20m · 2 projects · 3 commits · 2 agents · 1 night task · 1 typo fixed" ]'
check "nothing today → no output, exit 0" 'out=$(w credits --line); [ $? -eq 0 ] && [ -z "$out" ]'
check "card for yesterday" 'w credits --yesterday | grep -q "credits · yesterday"'

echo "share mode"
mkdir -p "$XDG_STATE_HOME/dotfiles"
printf 'mode=share\nlabel=Acme\n' > "$XDG_STATE_HOME/dotfiles/mode"
j="$(w wrapped --json)"
check "project names hidden" '[ "$(jq_ "all(k.startswith(\"•••\") for k in list(d[\"projects\"]) + list(d[\"commits\"]))")" = True ]'
check "the current repo stays visible" 'cd "$T/Github/app" && w wrapped --json | grep -q "\"app\": 900"; rc=$?; cd "$T"; [ $rc -eq 0 ]'
out="$(w wrapped)"
check "card says names are hidden, shows none" '[[ "$out" == *"names hidden"* ]] && ! printf "%s" "$out" | grep -qE "(^| )(app|api) "'
rm -f "$XDG_STATE_HOME/dotfiles/mode"

echo "no atuin"
check "works without atuin (commits, agents still count)" 'PATH="$(printf "%s" "$PATH" | sed "s|$FB:||")" w credits --yesterday --line | grep -q "3 commits"'

echo "dot-calendar"
if command -v uv >/dev/null 2>&1; then
    export UV_CACHE_DIR="$REAL_UV_CACHE"
    python3 - "$T/cal.ics" <<'EOF'
import datetime as d, sys
now = d.datetime.now(d.timezone.utc).replace(second=0, microsecond=0)
f = lambda t: t.strftime("%Y%m%dT%H%M%SZ")
weekly = now - d.timedelta(days=7) + d.timedelta(hours=2)
today = d.date.today().strftime("%Y%m%d")
ev = lambda uid, s, e, title, extra="": f"BEGIN:VEVENT\r\nUID:{uid}\r\nDTSTAMP:{f(now)}\r\nDTSTART:{s}\r\nDTEND:{e}\r\nSUMMARY:{title}\r\n{extra}END:VEVENT\r\n"
body = (ev("w", f(weekly), f(weekly + d.timedelta(minutes=30)), "Acme weekly", "RRULE:FREQ=WEEKLY\r\n")
        + ev("c", f(now + d.timedelta(minutes=20)), f(now + d.timedelta(minutes=50)), "Cancelled thing", "STATUS:CANCELLED\r\n")
        + ev("a", today, today, "All day", "")
        + ev("x", f(now + d.timedelta(minutes=40)), f(now + d.timedelta(minutes=70)), "Declined sync",
             "ATTENDEE;PARTSTAT=DECLINED:mailto:me@example.com\r\n")
        + ev("o", f(now + d.timedelta(hours=1)), f(now + d.timedelta(hours=1, minutes=15)), "One-off review"))
body = body.replace(f"DTSTART:{today}\r\nDTEND:{today}", f"DTSTART;VALUE=DATE:{today}\r\nDTEND;VALUE=DATE:{today}")
open(sys.argv[1], "w").write("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:test\r\n" + body + "END:VCALENDAR\r\n")
EOF
    NM="$XDG_CACHE_HOME/dotfiles/hello/next-meeting"
    uv run --quiet --script "$S/dot-calendar"
    check "nothing without DOT_CALENDAR_ICS" '[ ! -e "$NM" ]'
    DOT_CALENDAR_ICS="$T/cal.ics" uv run --quiet --script "$S/dot-calendar"
    check "next meeting: one-off (cancelled, declined, all-day skipped)" '[ "$(cut -f3 "$NM")" = "One-off review" ]'
    check "--print says when" 'uv run --quiet --script "$S/dot-calendar" --print | grep -Eq "^📅 [0-9]{2}:[0-9]{2} One-off review \(in (59|60) min\)$"'
    python3 - "$T/cal.ics" <<'EOF'
import re, sys
s = open(sys.argv[1], newline="").read()
s = re.sub(r"BEGIN:VEVENT\r\n(?:(?!END:VEVENT).)*SUMMARY:One-off review\r\n(?:(?!END:VEVENT).)*END:VEVENT\r\n", "", s, flags=re.S)
open(sys.argv[1], "w", newline="").write(s)
EOF
    DOT_CALENDAR_ICS="$T/cal.ics" uv run --quiet --script "$S/dot-calendar"
    check "recurring meeting expanded (weekly, started a week ago)" '[ "$(cut -f3 "$NM")" = "Acme weekly" ]'
    DOT_CALENDAR_ICS="$T/missing.ics" uv run --quiet --script "$S/dot-calendar"; rc=$?
    check "broken source: exit 0, previous answer kept" '[ $rc -eq 0 ] && [ "$(cut -f3 "$NM")" = "Acme weekly" ]'
    check "--check lists events" 'DOT_CALENDAR_ICS="$T/cal.ics" uv run --quiet --script "$S/dot-calendar" --check | grep -q "Acme weekly"'
else
    echo "  - uv not installed: skipped (dot-calendar needs uv for its packages)"
fi

[ -n "${KEEP:-}" ] || rm -rf "$T"
echo
if [ "$fails" -eq 0 ]; then echo "wrapped: all good"; else echo "wrapped: $fails failed"; exit 1; fi
