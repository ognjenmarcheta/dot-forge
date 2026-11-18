# ai — turn a plain-English request into a shell command using Claude Code
# (your Claude subscription via the `claude` CLI). Works in bash and zsh.
#
#   ai create 10 folders named project-1 … project-10
#   ai find android devices via adb
#   ai show what is using port 3000
#   ai explain tar -xzvf x.tgz -C /opt   explain a command (nothing runs)
#   ai fix                               fix the command that just failed
#   ai -h                                help
#
# Claude only *suggests* the command (all of Claude Code's tools are disabled),
# you see it first and choose: Enter = run, e = edit, c = copy, n = cancel.
# The command runs in your current shell (so `cd` etc. work) and is added to
# your shell history.
#
# Settings (env vars):
#   AI_MODEL   model alias passed to claude --model (default: sonnet;
#              use "haiku" for faster answers, "opus" for hard ones)

_ai_claude_bin() {
    local c
    for c in "$(command -v claude 2>/dev/null)" "$HOME/.local/bin/claude" "$HOME/.claude/local/claude"; do
        [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
    done
    return 1
}

_ai_context() {
    local os="" shell_name
    [ -r /etc/os-release ] && os=$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-$NAME}")
    [ -z "$os" ] && os=$(uname -sr)
    if [ -n "$ZSH_VERSION" ]; then shell_name="zsh $ZSH_VERSION"; else shell_name="bash $BASH_VERSION"; fi
    printf 'OS: %s (%s)\n' "$os" "$(uname -m)"
    printf 'Shell: %s\n' "$shell_name"
    printf 'User: %s\n' "$USER"
    printf 'Home: %s\n' "$HOME"
    printf 'Current directory: %s\n' "$PWD"
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf 'Git repo: yes (branch: %s)\n' "$(git branch --show-current 2>/dev/null)"
    fi
    printf 'Entries in current directory (first 40):\n'
    command ls -A1 2>/dev/null | head -n 40 | sed 's/^/  /'
}

_ai_system_prompt='You are a shell command generator running inside the user'"'"'s terminal.
Turn the request into commands for the given OS and shell.

Reply format, nothing else:
- Optionally 1-3 lines starting with "# " explaining briefly what the command does.
- If the command deletes or overwrites data, needs sudo, or changes system settings,
  include a line starting with "# WARNING: " saying why.
- Then the command itself. Prefer one line; chain steps with && or put them on separate lines.
- No markdown, no code fences, no prose outside "# " lines.
If the request cannot be done with a command, reply with only "# " lines explaining why.
Use tools that are normally installed on this OS; if a tool may be missing, add a "# " line
with the install command instead of guessing. Never invent file names: use the directory
listing provided.'

_ai_explain_prompt='You explain shell commands inside the user'"'"'s terminal.
Explain the given command for the given OS and shell: what it does overall, then each
part (flags, pipes, redirections) in short plain lines. Point out anything risky
(deleting data, sudo, overwriting files, network access) on a line starting with
"WARNING: ". Plain text, no markdown headings, no code fences, at most ~15 lines.'

_ai_help() {
    cat <<'EOF'
ai — describe what you want, get a shell command (via Claude Code)

  ai <what you want to do>

Examples:
  ai create 10 folders named client-01 to client-10
  ai find android devices via adb
  ai list the 10 biggest files in this folder
  ai kill whatever is listening on port 5173
  ai convert all .mov files here to mp4
  ai explain find . -name '*.log' -mtime +7 -delete
  ai fix                      (right after a command failed)

After the suggestion:  Enter = run   e = edit   c = copy   n = cancel
Model: AI_MODEL=haiku|sonnet|opus (default: sonnet)
EOF
}

# What the terminal shows right now (the failed command and its output), asked
# from WezTerm: the shell sets a user var, WezTerm writes the visible text to
# a private file in ~/.cache/dotfiles that we read and delete. Empty elsewhere.
_ai_screen_context() {
    [ "${TERM_PROGRAM:-}" = WezTerm ] || return 0
    local dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles" f i=0
    mkdir -p "$dir" && chmod 700 "$dir" 2>/dev/null
    f="$dir/ai-ctx-$$-${RANDOM}"
    printf '\033]1337;SetUserVar=%s=%s\007' dot_ai_ctx "$(printf '%s' "$f" | base64 | tr -d '\n')"
    while [ ! -s "$f" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
    [ -s "$f" ] || return 0
    # drop the trailing `ai fix` prompt line(s) and keep it short
    sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' "$f" | tail -n 80 | cut -c1-300
    rm -f -- "$f"
}

ai() {
    local last_status=$?            # first: exit status of the previous command
    if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then _ai_help; return 0; fi

    local mode=command system_prompt="$_ai_system_prompt"
    case "$1" in
        explain)
            shift
            [ $# -gt 0 ] || { echo "usage: ai explain <command>"; return 1; }
            mode=explain
            system_prompt="$_ai_explain_prompt"
            set -- "Explain this command: $*"
            ;;
        fix)
            shift
            local prev
            # history: -1 is this `ai fix`, -2 is the command before it
            prev=$(fc -ln -2 -2 2>/dev/null | sed 's/^[[:space:]]*//')
            if [ -z "$prev" ]; then echo "ai fix: no previous command in history"; return 1; fi
            printf '\033[2mfixing: %s (exit %s)\033[0m\n' "$prev" "$last_status"
            local screen
            screen=$(_ai_screen_context)
            set -- "This command just failed with exit status $last_status: $prev
${screen:+
This is what the terminal showed (its output, possibly cut off at the top):
---
$screen
---
}
Give a corrected command that does what it was meant to do. ${*:+Extra info from the user: $*}"
            ;;
    esac

    local claude_bin
    if ! claude_bin=$(_ai_claude_bin); then
        printf '\033[31mai: Claude Code (claude) is not installed.\033[0m\n'
        printf 'Install it, then run `claude` once and log in with your Claude account:\n'
        printf '  curl -fsSL https://claude.ai/install.sh | bash\n'
        return 1
    fi

    local request="$*" reply rc
    printf '\033[2m… asking Claude\033[0m\r'
    # dot-ai: always your Claude subscription login, never an API key
    reply=$(
        printf 'Context:\n%s\n\nRequest: %s\n' "$(_ai_context)" "$request" |
        "$HOME/.config/scripts/dot-ai" --system "$system_prompt" 2>&1
    )
    rc=$?
    printf '\033[2K'
    if [ $rc -ne 0 ] || [ -z "$reply" ]; then
        printf '\033[31mai: Claude Code failed (exit %s)\033[0m\n%s\n' "$rc" "$reply"
        case "$reply" in *[Ll]ogin*|*[Aa]uth*|*credential*)
            printf 'Run `claude` once and log in with your Claude account.\n' ;;
        esac
        return 1
    fi

    # strip code fences if the model added them anyway
    reply=$(printf '%s\n' "$reply" | sed -e '/^```/d')

    if [ "$mode" = explain ]; then
        printf '%s\n' "$reply" | while IFS= read -r line; do
            case "$line" in
                WARNING*|"# WARNING"*) printf '\033[1;31m%s\033[0m\n' "$line" ;;
                *) printf '%s\n' "$line" ;;
            esac
        done
        return 0
    fi

    local notes cmd
    notes=$(printf '%s\n' "$reply" | grep '^#' || true)
    cmd=$(printf '%s\n' "$reply" | grep -v '^#' | sed -e '/^[[:space:]]*$/d')

    if [ -n "$notes" ]; then
        printf '%s\n' "$notes" | while IFS= read -r line; do
            case "$line" in
                "# WARNING"*) printf '\033[1;31m%s\033[0m\n' "$line" ;;
                *)            printf '\033[2m%s\033[0m\n' "$line" ;;
            esac
        done
    fi
    if [ -z "$cmd" ]; then return 0; fi

    # local safety net on top of the model's own warning
    if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(sudo|rm[[:space:]]+-[a-zA-Z]*[rf]|dd[[:space:]]|mkfs|shred|chmod[[:space:]]+-R|chown[[:space:]]+-R)|>[[:space:]]*/dev/sd'; then
        printf '\033[1;31m⚠  This command can change or delete data — read it before running.\033[0m\n'
    fi
    printf '\033[1;36m%s\033[0m\n' "$cmd"

    local key
    while :; do
        printf '\033[2m[Enter] run  [e] edit  [c] copy  [n] cancel \033[0m'
        # A failed read (no terminal, end of input) must never count as Enter.
        if [ -n "$ZSH_VERSION" ]; then
            read -rs -k1 key || { printf '\ncancelled\n'; return 1; }
        else
            IFS= read -rsn1 key || { printf '\ncancelled\n'; return 1; }
        fi
        printf '\n'
        case "$key" in
            ""|$'\n'|$'\r'|y|Y)
                break ;;
            e|E)
                if [ -n "$ZSH_VERSION" ]; then vared -p '> ' cmd; else IFS= read -r -e -i "$cmd" -p '> ' cmd; fi
                [ -z "$cmd" ] && return 0
                break ;;
            c|C)
                if command -v pbcopy >/dev/null 2>&1; then printf '%s' "$cmd" | pbcopy
                elif command -v wl-copy >/dev/null 2>&1; then printf '%s' "$cmd" | wl-copy
                elif command -v xclip >/dev/null 2>&1; then printf '%s' "$cmd" | xclip -selection clipboard
                else printf 'ai: no clipboard tool found (Linux: install wl-clipboard)\n'; continue; fi
                printf '\033[2mcopied\033[0m\n'; return 0 ;;
            n|N|q|Q|$'\e')
                return 0 ;;
        esac
    done

    # remember it like a command you typed, then run it in this shell
    if [ -n "$ZSH_VERSION" ]; then print -s -- "$cmd"; else history -s -- "$cmd"; fi
    eval "$cmd"
}
