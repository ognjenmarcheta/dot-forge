#!/usr/bin/env zsh

emulate -L zsh
setopt pipe_fail

HERDR_CONFIG_DIR="${HERDR_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr}"
HERDR_PROJECT_REGISTRY="${HERDR_PROJECT_REGISTRY:-$HERDR_CONFIG_DIR/project-sessions.tsv}"

herdr_project_root() {
  local target="${1:-$PWD}"
  local root

  if root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
    cd "$root" && pwd -P
    return
  fi

  cd "$target" && pwd -P
}

herdr_slug() {
  local value="$1"
  value="$(print -rn -- "$value" | tr -cs '[:alnum:]_.-' '-')"
  value="${value#-}"
  value="${value%-}"
  [[ -n "$value" ]] || value="root"
  print -r -- "$value"
}

herdr_path_hash() {
  print -rn -- "$1" | shasum -a 1 | awk '{ print substr($1, 1, 8) }'
}

herdr_session_for_root() {
  local root="$1"
  local base session existing in_use

  mkdir -p "$HERDR_CONFIG_DIR"
  touch "$HERDR_PROJECT_REGISTRY"

  existing="$(awk -F '\t' -v root="$root" '$1 == root { print $2; exit }' "$HERDR_PROJECT_REGISTRY")"
  if [[ -n "$existing" ]]; then
    print -r -- "$existing"
    return
  fi

  base="$(herdr_slug "${root:t}")"
  in_use="$(awk -F '\t' -v session="$base" -v root="$root" '$2 == session && $1 != root { print $1; exit }' "$HERDR_PROJECT_REGISTRY")"

  if [[ -n "$in_use" ]]; then
    session="${base}-$(herdr_path_hash "$root")"
  else
    session="$base"
  fi

  printf '%s\t%s\t%s\n' "$root" "$session" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$HERDR_PROJECT_REGISTRY"
  print -r -- "$session"
}

herdr_resolve_project() {
  local target="${1:-$PWD}"

  HP_ROOT="$(herdr_project_root "$target")" || return
  HP_SESSION="$(herdr_session_for_root "$HP_ROOT")" || return
  HP_SESSION_DIR="$HERDR_CONFIG_DIR/sessions/$HP_SESSION"
  HP_SOCKET_PATH="$HP_SESSION_DIR/herdr.sock"
}

herdr_forget_project_root() {
  local root="$1"
  local tmp

  [[ -f "$HERDR_PROJECT_REGISTRY" ]] || return 0
  tmp="$(mktemp)"
  awk -F '\t' -v root="$root" '$1 != root { print }' "$HERDR_PROJECT_REGISTRY" > "$tmp" \
    && mv "$tmp" "$HERDR_PROJECT_REGISTRY"
}

herdr_session_running() {
  local session="$1"

  command herdr session list --json 2>/dev/null \
    | jq -e --arg session "$session" '.sessions[]? | select(.name == $session and .running == true)' >/dev/null
}

herdr_notify() {
  local title="$1"
  local message="$2"
  local subtitle="${3:-}"

  if command -v terminal-notifier >/dev/null 2>&1; then
    if [[ -n "$subtitle" ]]; then
      terminal-notifier -title "$title" -subtitle "$subtitle" -message "$message" >/dev/null 2>&1
    else
      terminal-notifier -title "$title" -message "$message" >/dev/null 2>&1
    fi
  elif command -v notify-send >/dev/null 2>&1; then
    # Linux (GNOME): desktop notification
    if [[ -n "$subtitle" ]]; then
      notify-send --app-name=herdr "$title" "$subtitle: $message" >/dev/null 2>&1
    else
      notify-send --app-name=herdr "$title" "$message" >/dev/null 2>&1
    fi
  else
    osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\"" >/dev/null 2>&1
  fi
}
