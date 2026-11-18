#!/bin/bash
# Check for Node.js ecosystem updates (cached daily).
# Never blocks shell startup: print cache immediately, refresh in background.
# macOS: uses Homebrew. Linux: compares node (same major line) and pnpm
# against the latest published versions.

CACHE_FILE="$HOME/.cache/node-update-check"
CACHE_MAX_AGE=86400  # 24 hours in seconds

YELLOW='\033[0;33m'
NC='\033[0m'

print_cached() {
    if [[ -f "$CACHE_FILE" ]]; then
        cached=$(cat "$CACHE_FILE")
        [[ -n "$cached" ]] && echo -e "$cached"
    fi
}

refresh_cache() {
    mkdir -p "$(dirname "$CACHE_FILE")"
    local msg=""
    if command -v brew >/dev/null 2>&1; then
        local outdated
        outdated=$(HOMEBREW_NO_AUTO_UPDATE=1 brew outdated --quiet node pnpm 2>/dev/null | tr '\n' ' ' | xargs)
        [[ -n "$outdated" ]] && msg="${YELLOW} Updates available: ${outdated}${NC} (brew upgrade ${outdated})"
    else
        local parts=() cur latest
        if command -v node >/dev/null 2>&1; then
            cur=$(node -v 2>/dev/null | sed 's/^v//')
            latest=$(curl -fsSL --max-time 10 https://nodejs.org/dist/index.json 2>/dev/null \
                | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const m=process.argv[1].split(".")[0];const r=JSON.parse(d).find(x=>x.version.startsWith("v"+m+"."));if(r)process.stdout.write(r.version.slice(1))}catch{}})' "$cur")
            [[ -n "$latest" && "$latest" != "$cur" ]] && parts+=("node $cur → $latest")
        fi
        if command -v pnpm >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
            cur=$(pnpm -v 2>/dev/null)
            latest=$(npm view pnpm version 2>/dev/null)
            [[ -n "$latest" && "$latest" != "$cur" ]] && parts+=("pnpm $cur → $latest")
        fi
        if (( ${#parts[@]} )); then
            local joined; joined=$(printf '%s, ' "${parts[@]}"); joined=${joined%, }
            msg="${YELLOW} Updates available: ${joined}${NC}"
        fi
    fi
    # Write only — never print from background (would stomp the prompt).
    echo -e "$msg" > "$CACHE_FILE"
}

print_cached

needs_refresh=1
if [[ -f "$CACHE_FILE" ]]; then
    mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE")
    (( $(date +%s) - mtime < CACHE_MAX_AGE )) && needs_refresh=0
fi

if [[ $needs_refresh -eq 1 ]]; then
    (refresh_cache) &>/dev/null &
    disown 2>/dev/null || true
fi
