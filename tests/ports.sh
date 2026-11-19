#!/usr/bin/env bash
# Tests for dot ports / dot name, with stand-ins for lsof / ss / caddy / curl
# (deterministic on both OSes) plus one real listener found with the real tools.
# shellcheck disable=SC2034  # vars are read by the eval in check()
set -uo pipefail
DOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
P="$DOT/config/scripts/dot-ports"
T="$(cd "$(mktemp -d)" && pwd -P)"   # physical path (macOS: /var → /private/var)
FB="$T/fakebin"
mkdir -p "$FB" "$T/Github"
cd "$T" || exit 1
REAL_PATH="$PATH"
export HOME="$T" XDG_CONFIG_HOME="$T/.config" XDG_DATA_HOME="$T/.local/share" XDG_CACHE_HOME="$T/.cache" XDG_STATE_HOME="$T/.local/state"
export GIT_CONFIG_GLOBAL="$T/gitconfig" FAKE_LOG="$T/fake.log" FAKE_PORTS="$T/fake-ports.tsv"
export PATH="$FB:$PATH"
unset TERM_PROGRAM
fails=0
pass() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

git config --global user.email me@example.com
git config --global user.name "Test Person"
git config --global init.defaultBranch main
git init -q "$T/Github/My_App"
git -C "$T/Github/My_App" commit -q --allow-empty -m init
git -C "$T/Github/My_App" worktree add -q -b feat "$T/Github/my-app-feat" 2>/dev/null
mkdir -p "$T/elsewhere"

sleep 300 & SLEEPER=$!; disown "$SLEEPER" 2>/dev/null
# port pid program cwd — what the stand-ins report
cat > "$FAKE_PORTS" <<EOF
5173	$SLEEPER	node	$T/Github/My_App
5174	4242	vite	$T/Github/my-app-feat
8080	4343	python3	$T/elsewhere
EOF

# lsof (macOS path): the LISTEN list (one IPv4 + one IPv6 row per port) and cwd lookups
cat > "$FB/lsof" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" -d cwd "*)
        pid=""; while [ $# -gt 0 ]; do [ "$1" = -p ] && pid="$2"; shift; done
        awk -F'\t' -v p="$pid" '$2 == p { print "p" p; print "fcwd"; print "n" $4 }' "$FAKE_PORTS" ;;
    *) awk -F'\t' '{ print "p" $2; print "c" $3; print "f20"; print "n127.0.0.1:" $1; print "f21"; print "n[::1]:" $1 }' "$FAKE_PORTS" ;;
esac
EOF
# ss (Linux path)
cat > "$FB/ss" <<'EOF'
#!/usr/bin/env bash
awk -F'\t' '{ printf "LISTEN 0 511 0.0.0.0:%s 0.0.0.0:* users:((\"%s\",pid=%s,fd=20))\n", $1, $3, $2
              printf "LISTEN 0 511 [::]:%s [::]:* users:((\"%s\",pid=%s,fd=21))\n", $1, $3, $2 }' "$FAKE_PORTS"
echo "LISTEN 0 4096 127.0.0.53%lo:53 0.0.0.0:*"   # someone else's: no process info
EOF
cat > "$FB/caddy" <<'EOF'
#!/usr/bin/env bash
echo "caddy $*" >> "$FAKE_LOG"
[ "$1" = start ] && [ -n "${FAKE_BIND_FAIL:-}" ] && { echo "listen tcp :443: bind: permission denied" >&2; exit 1; }
exit 0
EOF
printf '#!/usr/bin/env bash\necho "curl $*" >> "$FAKE_LOG"\n[ -n "${FAKE_CADDY_UP:-}" ]\n' > "$FB/curl"
printf '#!/usr/bin/env bash\nexit "${FAKE_TRUST:-0}"\n' > "$FB/security"
printf '#!/usr/bin/env bash\nexit "${FAKE_TRUST:-0}"\n' > "$FB/openssl"
chmod +x "$FB"/*
# Caddy's local root certificate exists once it has run
mkdir -p "$T/Library/Application Support/Caddy/pki/authorities/local" "$T/.local/share/caddy/pki/authorities/local"
touch "$T/Library/Application Support/Caddy/pki/authorities/local/root.crt" "$T/.local/share/caddy/pki/authorities/local/root.crt"
# Linux process folders
for line in "$SLEEPER:$T/Github/My_App" "4242:$T/Github/my-app-feat" "4343:$T/elsewhere"; do
    mkdir -p "$T/proc/${line%%:*}"; ln -s "${line#*:}" "$T/proc/${line%%:*}/cwd"
done

for os in Darwin Linux; do
    echo "dot ports ($os)"
    export DOT_PORTS_OS=$os DOT_PORTS_PROC="$T/proc"
    out=$(bash "$P")
    check "one row per port (IPv4 + IPv6 deduped)" '[ "$(printf "%s\n" "$out" | grep -c "^5173 ")" -eq 1 ] && [ "$(printf "%s\n" "$out" | wc -l | tr -d " ")" -eq 4 ]'
    check "project and branch" 'printf "%s\n" "$out" | grep "^5173 " | grep -q "My_App (main)"'
    check "worktree marked" 'printf "%s\n" "$out" | grep "^5174 " | grep -q "my-app-feat (feat) ⑂"'
    check "no repo → -, plain URL" 'printf "%s\n" "$out" | grep "^8080 " | grep -q "  -  .*http://localhost:8080"'
    check "not a tty: no escape codes" '! printf "%s" "$out" | grep -q $'"'"'\033'"'"''
    js=$(bash "$P" --json)
    check "--json is valid" 'printf "%s" "$js" | jq -e "length == 3 and .[0].port == 5173 and .[0].project == \"My_App\" and .[2].project == null" >/dev/null'
done
unset DOT_PORTS_OS

echo "dot ports kill / open"
out=$(echo n | bash "$P" kill 5173)
check "kill shows what it is and asks" '[[ "$out" == *"node (pid $SLEEPER)"*"My_App"* && "$out" == *"left running"* ]]'
check "declining leaves it running" 'kill -0 "$SLEEPER" 2>/dev/null'
check "unknown port refused" '! bash "$P" kill 9999 >/dev/null 2>&1'
bash "$P" kill 5173 -y >/dev/null
check "-y stops it" '! kill -0 "$SLEEPER" 2>/dev/null || ps -o stat= -p "$SLEEPER" | grep -q Z'
printf '#!/usr/bin/env bash\necho "open $*" >> "$FAKE_LOG"\n' > "$FB/open"; cp "$FB/open" "$FB/xdg-open"; chmod +x "$FB/open" "$FB/xdg-open"
bash "$P" open 8080 >/dev/null
check "open → localhost URL" 'grep -q "open http://localhost:8080" "$FAKE_LOG"'

echo "dot name"
NT="$XDG_CONFIG_HOME/dotfiles/names.tsv"
CF="$XDG_STATE_HOME/dotfiles/caddy/Caddyfile"
sed -i.bak "s/^5173	$SLEEPER/5173	$$/" "$FAKE_PORTS"   # keep a live pid on 5173 for the rest
mkdir -p "$T/proc/$$"; ln -s "$T/Github/My_App" "$T/proc/$$/cwd"
: > "$FAKE_LOG"
out=$(cd "$T/Github/My_App" && bash "$P" name)
check "lists nothing yet" '[[ "$out" == *"no names yet"* ]]'
out=$(cd "$T/Github/My_App" && bash "$P" name x 2>&1)   # 'x' is a name, port from the repo
check "explicit name, port detected from the repo" 'grep -q "^x	5173$" "$NT"'
bash "$P" name rm x >/dev/null
out=$(cd "$T/Github/My_App/" && bash "$P" name 2>&1)
check "no args in a repo lists (doesn't add)" '[ ! -s "$NT" ]'
out=$(cd "$T/Github/My_App" && bash "$P" name My_App 2>&1)
check "name sanitised, port detected" 'grep -q "^my-app	5173$" "$NT" && [[ "$out" == *"https://my-app.localhost → 127.0.0.1:5173"* ]]'
check "Caddyfile: global block" 'grep -q "admin localhost:2019" "$CF" && grep -q local_certs "$CF" && grep -q skip_install_trust "$CF"'
check "Caddyfile: site" 'grep -q "^my-app.localhost {" "$CF" && grep -q "reverse_proxy 127.0.0.1:5173" "$CF"'
check "Caddy not running, no service → caddy start" 'grep -q "caddy start --config $CF --adapter caddyfile" "$FAKE_LOG"'
: > "$FAKE_LOG"
FAKE_CADDY_UP=1 bash "$P" name api 8080 >/dev/null
check "Caddy running → reload" 'grep -q "caddy reload --config $CF" "$FAKE_LOG" && ! grep -q "caddy start" "$FAKE_LOG"'
check "renaming the same name replaces it" 'bash "$P" name api 8081 >/dev/null && [ "$(grep -c "^api	" "$NT")" -eq 1 ] && grep -q "^api	8081$" "$NT"'
out=$(bash "$P" name)
check "list shows up / down" '[[ "$out" == *"my-app.localhost"*"● up"* && "$out" == *"api.localhost"*"nothing on 8081"* ]]'
out=$(DOT_PORTS_OS=Darwin bash "$P")
check "dot ports shows the name" 'printf "%s\n" "$out" | grep "^5173 " | grep -q "https://my-app.localhost"'
: > "$FAKE_LOG"; bash "$P" open 5173 >/dev/null
check "open uses the name" 'grep -q "open https://my-app.localhost" "$FAKE_LOG"'
out=$(FAKE_TRUST=1 bash "$P" name web 3000 </dev/null 2>&1)
check "untrusted CA: says how to trust it" '[[ "$out" == *"run: caddy trust"* ]]'
check "dot ports trusted (for doctor)" 'bash "$P" trusted && ! FAKE_TRUST=1 bash "$P" trusted'
out=$(DOT_PORTS_OS=Linux FAKE_BIND_FAIL=1 bash "$P" name web2 3001 2>&1)
check "can't bind 443 on Linux → setcap fix" '[[ "$out" == *"setcap cap_net_bind_service=+ep"* ]]'
check "rm" 'bash "$P" name rm api >/dev/null && ! grep -q "^api	" "$NT" && ! grep -q "api.localhost" "$CF"'
check "rm unknown fails" '! bash "$P" name rm nope >/dev/null 2>&1'
out=$(cd "$T/elsewhere" && bash "$P" name 4000 2>&1)
check "outside a repo a name is required" '[[ "$out" == *"give a name"* ]]'
printf '5175\t%s\tnode\t%s\n' "$$" "$T/Github/My_App" >> "$FAKE_PORTS"
out=$(cd "$T/Github/My_App" && bash "$P" name other 2>&1)
check "two ports in the repo → asks which" '[[ "$out" == *"5173 5175"*"pick one"* ]]'

echo "real listener"
if command -v python3 >/dev/null 2>&1; then
    port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
    git init -q "$T/Github/realproj"
    (cd "$T/Github/realproj" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) & srv=$!
    for _ in $(seq 1 50); do python3 -c "import socket,sys; socket.create_connection(('127.0.0.1',$port),0.2)" 2>/dev/null && break; sleep 0.1; done
    out=$(unset DOT_PORTS_OS DOT_PORTS_PROC; PATH="$REAL_PATH" bash "$P")   # the real machine, not the stand-ins
    check "real lsof/ss: python on :$port in realproj" 'printf "%s\n" "$out" | grep "^$port " | grep -q "realproj"'
    kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null
else
    echo "  - python3 not installed: skipped"
fi

kill "$SLEEPER" 2>/dev/null
[ -n "${KEEP:-}" ] || rm -rf "$T"
echo
if [ "$fails" -eq 0 ]; then echo "ports: all good"; else echo "ports: $fails failed"; exit 1; fi
