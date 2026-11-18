-- Extras borrowed from Warp / kitty / Ghostty (`dot keys` lists the keys):
--   Shift+↑/↓      jump to the previous / next command (Warp "blocks")
--   Leader y       copy the last command's output
--   triple-click   select a whole command output
--   Leader Space   Quick Select: label URLs, paths, hashes, IPs, issue keys… → copy
--   Leader u       Quick Select a URL → open it
--   Leader p       projects in ~/Github → open/switch a workspace (shell, nvim, lazygit)
--   Ctrl+Shift+P   command palette (with the entries below added)
--   Ctrl+Shift+U   emoji / symbol picker
--   Leader a       agent radar: every Claude Code session, what it's doing, jump to it
--   Leader ?       side pane with Claude, already given what you're looking at
-- Plus: ● on a tab when Claude Code is waiting for you (hooks call
-- ~/.config/scripts/agent-notify), the screen text for `ai fix`, a colour per
-- git project (tab stripe, badge, tinted tab bar) and sessions that survive
-- closing the window. Needs the shell marks from ~/.config/shell/marks.sh.
--
-- Per-machine settings (not committed): ~/.config/wezterm/machine.lua, e.g.
--   return {
--     persistent_sessions = false,                 -- default true
--     wayland = true,                              -- Linux; default: XWayland
--     project_colors = { ["kaine-forge"] = "#f5a97f" },
--   }

local wezterm = require("wezterm")
local act = wezterm.action
local mux = wezterm.mux

local M = {}

local home = wezterm.home_dir
local is_flatpak = os.getenv("FLATPAK_ID") ~= nil

local ok_machine, machine = pcall(require, "machine")
if not ok_machine or type(machine) ~= "table" then machine = {} end
M.machine = machine

local function host_cmd(args)
    if not is_flatpak then return args end
    local wrapped = { "flatpak-spawn", "--host" }
    for _, a in ipairs(args) do table.insert(wrapped, a) end
    return wrapped
end

local function basename(path)
    return (path:gsub("/+$", ""):match("([^/]+)$")) or path
end

local function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function toast(window, title, body, ms)
    window:toast_notification(title, body or "", nil, ms or 4000)
end

-- ------------------------------------------------------------ blocks -----

-- Text of the most recent command output that isn't empty
local function last_output(pane)
    local ok, zones = pcall(function() return pane:get_semantic_zones("Output") end)
    if not ok or not zones then return nil end
    for i = #zones, 1, -1 do
        local text = pane:get_text_from_semantic_zone(zones[i])
        if text and text:match("%S") then
            return (text:gsub("%s+$", ""))
        end
    end
    return nil
end

local copy_last_output = wezterm.action_callback(function(window, pane)
    local text = last_output(pane)
    if not text then
        toast(window, "Nothing to copy", "No command output found (shell marks not loaded?)")
        return
    end
    window:copy_to_clipboard(text, "Clipboard")
    local _, lines = text:gsub("\n", "")
    toast(window, "Copied output", (lines + 1) .. " line(s)", 2000)
end)

-- Shift+↑/↓ jump between prompts; full-screen apps (nvim, lazygit…) get the key
local function prompt_jump(key, dir)
    return {
        key = key,
        mods = "SHIFT",
        action = wezterm.action_callback(function(window, pane)
            if pane:is_alt_screen_active() then
                window:perform_action(act.SendKey { key = key, mods = "SHIFT" }, pane)
            else
                window:perform_action(act.ScrollToPrompt(dir), pane)
            end
        end),
    }
end

-- --------------------------------------------------------- projects -----

local function is_dir(path)
    return (pcall(wezterm.read_dir, path))
end

local function is_repo(path)
    return #wezterm.glob(path .. "/.git") > 0
end

-- ~/Github/<project>, plus one level deeper for folders that group projects
-- (e.g. ~/Github/clients/<project>)
local function project_dirs()
    local found = {}
    local ok, entries = pcall(wezterm.read_dir, home .. "/Github")
    if not ok then return found end
    for _, dir in ipairs(entries) do
        local name = basename(dir)
        if name:sub(1, 1) ~= "." and is_dir(dir) then
            if is_repo(dir) then
                table.insert(found, dir)
            else
                local nested = {}
                local ok2, children = pcall(wezterm.read_dir, dir)
                if ok2 then
                    for _, child in ipairs(children) do
                        if basename(child):sub(1, 1) ~= "." and is_repo(child) then
                            table.insert(nested, child)
                        end
                    end
                end
                if #nested > 0 then
                    for _, c in ipairs(nested) do table.insert(found, c) end
                else
                    table.insert(found, dir)
                end
            end
        end
    end
    table.sort(found, function(a, b) return a:lower() < b:lower() end)
    return found
end

local function open_project(window, pane, path)
    local name = basename(path)
    for _, ws in ipairs(mux.get_workspace_names()) do
        if ws == name then
            window:perform_action(act.SwitchToWorkspace { name = name }, pane)
            return
        end
    end
    local q = shell_quote(path)
    -- cwd is passed too, but `cd` makes sure even when the shell runs on the
    -- host through the Flatpak sandbox
    -- same domain as where you are (the session server when it's on)
    local domain = { DomainName = pane:get_domain_name() }
    local tab, shell_pane, mwin = mux.spawn_window { workspace = name, cwd = path, domain = domain }
    tab:set_title(name)
    shell_pane:send_text(" cd -- " .. q .. " && clear\n")
    local nvim_tab, nvim_pane = mwin:spawn_tab { cwd = path, domain = domain }
    nvim_tab:set_title("nvim")
    nvim_pane:send_text(" cd -- " .. q .. " && nvim .\n")
    local git_tab, git_pane = mwin:spawn_tab { cwd = path, domain = domain }
    git_tab:set_title("git")
    git_pane:send_text(" cd -- " .. q .. " && lazygit\n")
    tab:activate()
    window:perform_action(act.SwitchToWorkspace { name = name }, pane)
end

local pick_project = wezterm.action_callback(function(window, pane)
    local open = {}
    for _, ws in ipairs(mux.get_workspace_names()) do open[ws] = true end
    local choices = {}
    for _, dir in ipairs(project_dirs()) do
        local name = basename(dir)
        local rel = dir:gsub("^" .. home:gsub("%p", "%%%0"), "~")
        local label = (open[name] and "● " or "  ") .. name .. "   " .. rel
        table.insert(choices, { id = dir, label = label })
    end
    if #choices == 0 then
        toast(window, "No projects", "Nothing found in ~/Github")
        return
    end
    window:perform_action(act.InputSelector {
        title = "Projects  (● = open)",
        fuzzy = true,
        fuzzy_description = "Project: ",
        choices = choices,
        action = wezterm.action_callback(function(win, p, id)
            if id then open_project(win, p, id) end
        end),
    }, pane)
end)

-- ---------------------------------------------------- quick select -----

M.quick_select_patterns = {
    "\\b[A-Z][A-Z0-9]+-\\d+\\b",                        -- issue keys: HELU-7010, ENG-42
    "[\\w./~-]+\\.[a-zA-Z0-9]+:\\d+(?::\\d+)?",         -- file.ts:12:5 (compiler / test output)
    "\\b\\d{1,3}(?:\\.\\d{1,3}){3}(?::\\d+)?\\b",       -- 192.168.1.10:8080
    "\\b[a-z0-9]+(?:-[a-z0-9]+)*-[a-z0-9]{8,10}-[a-z0-9]{5}\\b", -- k8s pod names
    "[\\w.+-]+@[\\w-]+\\.[\\w.-]+",                     -- e-mail
}

local open_url = act.QuickSelectArgs {
    label = "open url",
    patterns = { "https?://[^\\s'\"<>()\\]]+" },
    action = wezterm.action_callback(function(window, pane)
        local url = window:get_selection_text_for_pane(pane)
        window:perform_action(act.ClearSelection, pane)
        if url and url ~= "" then wezterm.open_with(url) end
    end),
}

-- ------------------------------------------------- Claude Code alerts -----

wezterm.GLOBAL.agent = wezterm.GLOBAL.agent or {}

local function looking_at(window, pane)
    local active = window:active_pane()
    return window:is_focused() and active and active:pane_id() == pane:pane_id()
end

-- Marker for a tab: "waiting" beats "done"; nil when nothing is pending
function M.tab_marker(tab_id)
    local tab = mux.get_tab(tab_id)
    if not tab then return nil end
    local marker
    for _, p in ipairs(tab:panes()) do
        local s = wezterm.GLOBAL.agent[tostring(p:pane_id())]
        if s == "waiting" then return "waiting" end
        if s == "done" then marker = "done" end
    end
    return marker
end

-- Called from update-status: forget markers for whatever you're looking at
function M.clear_seen(window)
    if not window:is_focused() then return end
    local pane = window:active_pane()
    if pane then wezterm.GLOBAL.agent[tostring(pane:pane_id())] = nil end
end

-- ------------------------------------------------- project colours -----

local project_palette = {
    "#f5a97f", "#a6da95", "#8aadf4", "#c6a0f6", "#f5bde6",
    "#eed49f", "#8bd5ca", "#ed8796", "#91d7e3", "#f0c6c6",
}
local root_cache = {}

-- folder from OSC 7 (marks.sh): Url object (newer WezTerm) or a file:// string
local function cwd_of(cwd)
    if not cwd then return nil end
    if type(cwd) ~= "string" then
        local ok, p = pcall(function() return cwd.file_path end)
        return ok and p or nil
    end
    local p = cwd:gsub("^file://[^/]*", "")
    return (p:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function git_root(dir)
    if not dir or dir == "" then return nil end
    dir = dir:gsub("/+$", "")
    if root_cache[dir] ~= nil then return root_cache[dir] or nil end
    local d = dir
    while d and d ~= "" and d ~= home do
        if #wezterm.glob(d .. "/.git") > 0 then
            root_cache[dir] = d
            return d
        end
        d = d:match("^(.*)/[^/]*$")
    end
    root_cache[dir] = false
    return nil
end

local function color_for(name)
    local custom = machine.project_colors and machine.project_colors[name]
    if custom then return custom end
    local h = 0
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 2147483647 end
    return project_palette[(h % #project_palette) + 1]
end

-- name, colour of the git project a pane is in (cwd: Url, string or nil)
function M.project(cwd)
    local root = git_root(cwd_of(cwd))
    if not root then return nil, nil end
    local name = basename(root)
    return name, color_for(name)
end

local function blend(hex, base, amount)
    local function rgb(h)
        h = h:gsub("#", "")
        return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
    end
    local r1, g1, b1 = rgb(hex)
    local r2, g2, b2 = rgb(base)
    local function mix(a, b) return math.floor(b + (a - b) * amount + 0.5) end
    return string.format("#%02x%02x%02x", mix(r1, r2), mix(g1, g2), mix(b1, b2))
end

local base_colors -- config.colors as written in config.lua (set in apply)
local function copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copy(v) end
    return c
end

-- Called from update-status: badge with the project + tab bar tinted in its colour
function M.project_status(window, pane)
    local name, color = M.project(pane:get_current_working_dir())
    local base_bg = (base_colors and base_colors.tab_bar and base_colors.tab_bar.background) or "#1f2330"
    local want = color and blend(color, base_bg, 0.22) or base_bg
    local overrides = window:get_config_overrides() or {}
    local current = overrides.colors and overrides.colors.tab_bar and overrides.colors.tab_bar.background
    if current ~= want and not (current == nil and want == base_bg) then
        local colors = copy(base_colors) or {}
        colors.tab_bar = colors.tab_bar or {}
        colors.tab_bar.background = want
        overrides.colors = colors
        window:set_config_overrides(overrides)
    end
    if not name then return {} end
    return {
        { Background = { Color = color } },
        { Foreground = { Color = "#1e2030" } },
        { Attribute = { Intensity = "Bold" } },
        { Text = " " .. name .. " " },
        "ResetAttributes",
    }
end

-- ---------------------------------------------------- user vars -----

local function write_private_file(path, text)
    if is_flatpak then
        -- the sandbox sees $HOME read-only: write it on the host
        wezterm.run_child_process(host_cmd {
            "sh", "-c", 'umask 077 && printf "%s" "$2" > "$1"', "sh", path, text,
        })
    else
        local f = io.open(path, "w")
        if f then f:write(text); f:close() end
    end
end

wezterm.on("user-var-changed", function(window, pane, name, value)
    if name == "dot_agent" then
        local state, project, msg = value:match("^(%a+)\t([^\t]*)\t(.*)$")
        if not state then return end
        local id = tostring(pane:pane_id())
        -- every session, for the agent radar (Leader a)
        wezterm.GLOBAL.agents = wezterm.GLOBAL.agents or {}
        local prev = wezterm.GLOBAL.agents[id]
        wezterm.GLOBAL.agents[id] = {
            state = state,
            project = project,
            -- keep the request while it works; the reply when it's done
            msg = (msg ~= "" and msg) or (prev and prev.msg) or "",
            since = (prev and prev.state == state) and prev.since or os.time(),
        }
        if state == "working" or looking_at(window, pane) then
            wezterm.GLOBAL.agent[id] = nil
            return
        end
        wezterm.GLOBAL.agent[id] = state
        local title = (state == "waiting" and "● Claude needs you" or "✓ Claude finished")
            .. (project ~= "" and (" · " .. project) or "")
        toast(window, title, msg, 6000)
    elseif name == "dot_ai_ctx" then
        -- `ai fix` asks for the visible screen; only ever write our own cache files
        local path = value
        if not path:match("^/[^%z]+/ai%-ctx%-%d+%-%d+$") or path:find("%.%.") then return end
        if not path:find("/dotfiles/ai%-ctx%-") then return end
        local rows = pane:get_dimensions().viewport_rows
        local text = pane:get_lines_as_text(rows)
        write_private_file(path, text ~= "" and text or " ")
    end
end)

-- ------------------------------------------------------ agent radar -----

local function pane_by_id(id)
    local ok, p = pcall(mux.get_pane, tonumber(id))
    return ok and p or nil
end

local function ago(t)
    local s = os.time() - (t or os.time())
    if s < 60 then return s .. "s" end
    if s < 3600 then return math.floor(s / 60) .. "m" end
    return string.format("%dh%02d", math.floor(s / 3600), math.floor(s % 3600 / 60))
end

-- sessions still open, waiting first
function M.agent_list()
    local list = {}
    for id, a in pairs(wezterm.GLOBAL.agents or {}) do
        if pane_by_id(id) then
            table.insert(list, { id = id, state = a.state, project = a.project, msg = a.msg, since = a.since })
        else
            wezterm.GLOBAL.agents[id] = nil -- pane closed
        end
    end
    local rank = { waiting = 1, working = 2, done = 3 }
    table.sort(list, function(a, b)
        if rank[a.state] ~= rank[b.state] then return (rank[a.state] or 9) < (rank[b.state] or 9) end
        return (a.since or 0) < (b.since or 0)
    end)
    return list
end

local function focus_pane(window, pane, id)
    local p = pane_by_id(id)
    if not p then return end
    local tab = p:tab()
    local ws = tab and tab:window() and tab:window():get_workspace()
    if ws then window:perform_action(act.SwitchToWorkspace { name = ws }, pane) end
    if tab then tab:activate() end
    p:activate()
end

local agent_radar = wezterm.action_callback(function(window, pane)
    local icon = { waiting = "● waiting", working = "⟳ working", done = "✓ done   " }
    local choices = {}
    for _, a in ipairs(M.agent_list()) do
        local msg = (a.msg or ""):gsub("%s+", " ")
        if #msg > 70 then msg = msg:sub(1, 69) .. "…" end
        table.insert(choices, {
            id = a.id,
            label = string.format("%s  %-18s %6s  %s", icon[a.state] or a.state, (a.project or ""):sub(1, 18), ago(a.since), msg),
        })
    end
    if #choices == 0 then
        toast(window, "No Claude sessions yet", "Sessions show up here once Claude Code runs (hooks from install.sh)")
        return
    end
    window:perform_action(act.InputSelector {
        title = "Agents  (● needs you · ⟳ working · ✓ done)",
        fuzzy = true,
        choices = choices,
        action = wezterm.action_callback(function(win, p, id)
            if id then focus_pane(win, p, id) end
        end),
    }, pane)
end)

-- ------------------------------------------------------- pair pane -----

local function claude_path()
    for _, c in ipairs({ home .. "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude" }) do
        local f = io.open(c, "r")
        if f then f:close() return c end
    end
    return "claude"
end

local function zone_text(pane, kind)
    local ok, zones = pcall(function() return pane:get_semantic_zones(kind) end)
    if not ok or not zones then return nil end
    for i = #zones, 1, -1 do
        local t = pane:get_text_from_semantic_zone(zones[i])
        if t and t:match("%S") then return (t:gsub("%s+$", "")) end
    end
end

local function host_output(args)
    local ok, out = wezterm.run_child_process(host_cmd(args))
    return ok and out or ""
end

-- Leader ?: Claude in a side pane, told about the folder, git state and the
-- last command + its output. Your subscription only (API keys removed, and
-- dot-ai --check must pass).
local pair_pane = wezterm.action_callback(function(window, pane)
    if not wezterm.run_child_process(host_cmd { home .. "/.config/scripts/dot-ai", "--check" }) then
        toast(window, "Claude isn't on your subscription login", "Run `dot-ai --check` in a terminal to see why")
        return
    end
    local cwd = pane:get_current_working_dir()
    local ok, dir = pcall(function() return cwd and cwd.file_path end)
    dir = ok and dir or home
    local last_cmd = zone_text(pane, "Input") or ""
    local output = zone_text(pane, "Output") or ""
    if #output > 6000 then output = "…" .. output:sub(-6000) end
    local ctx = table.concat({
        "The user opened you in a side pane of their terminal to ask about what they are doing right now.",
        "Answer their questions about it. Don't edit files or run commands unless they ask you to.",
        "",
        "Folder: " .. dir,
        "Git:\n" .. host_output { "git", "-C", dir, "status", "--short", "--branch" },
        "Changes:\n" .. host_output { "git", "-C", dir, "diff", "--stat" },
        "Last command: " .. last_cmd,
        "Its output (may be cut off at the top):\n" .. output,
    }, "\n")
    local file = home .. "/.cache/dotfiles/pair-" .. pane:pane_id() .. ".md"
    host_output { "mkdir", "-p", home .. "/.cache/dotfiles" }
    write_private_file(file, ctx)
    pane:split {
        direction = "Right",
        size = 0.42,
        cwd = dir,
        args = { "/usr/bin/env", "-u", "ANTHROPIC_API_KEY", "-u", "ANTHROPIC_AUTH_TOKEN",
                 claude_path(), "--append-system-prompt-file", file },
    }
end)

-- ------------------------------------------------- standup / updates -----

-- run a command in a fresh tab of the current window, in the current folder
local function run_in_new_tab(window, pane, title, cmd)
    local cwd = pane:get_current_working_dir()
    local ok, path = pcall(function() return cwd and cwd.file_path end)
    local tab, new_pane = window:mux_window():spawn_tab {
        domain = { DomainName = pane:get_domain_name() },
        cwd = ok and path or nil,
    }
    tab:set_title(title)
    new_pane:send_text(" " .. cmd .. "\n")
end

-- client keys from ~/.config/dotfiles/clients.toml (section headers)
local function client_keys()
    local keys = {}
    local f = io.open(home .. "/.config/dotfiles/clients.toml", "r")
    if not f then return keys end
    for line in f:lines() do
        local k = line:match("^%[([%w_%-]+)%]")
        if k and k ~= "settings" then table.insert(keys, { id = k, label = k }) end
    end
    f:close()
    return keys
end

local client_update = wezterm.action_callback(function(window, pane)
    local choices = client_keys()
    if #choices == 0 then
        run_in_new_tab(window, pane, "clients", "dot clients --init")
        return
    end
    window:perform_action(act.InputSelector {
        title = "Client update for…",
        fuzzy = true,
        choices = choices,
        action = wezterm.action_callback(function(win, p, id)
            if id then run_in_new_tab(win, p, "update " .. id, "dot update " .. id) end
        end),
    }, pane)
end)

-- ---------------------------------------------------- palette -----

wezterm.on("augment-command-palette", function(window, pane)
    return {
        { brief = "Projects: open or switch  (Leader p)", icon = "md_folder_search", action = pick_project },
        { brief = "Agents: who needs me?  (Leader a)", icon = "md_robot", action = agent_radar },
        { brief = "Ask Claude about this pane  (Leader ?)", icon = "md_chat_question", action = pair_pane },
        {
            brief = "Standup (yesterday / today / blockers)",
            icon = "md_account_voice",
            action = wezterm.action_callback(function(win, p) run_in_new_tab(win, p, "standup", "dot standup") end),
        },
        { brief = "Client update…", icon = "md_email_fast", action = client_update },
        { brief = "Copy last command output  (Leader y)", icon = "md_content_copy", action = copy_last_output },
        { brief = "Quick select: copy text on screen  (Leader Space)", icon = "md_cursor_text", action = act.QuickSelect },
        { brief = "Open a URL on screen  (Leader u)", icon = "md_web", action = open_url },
        { brief = "Workspaces: switch  (Leader w)", icon = "md_view_dashboard", action = act.ShowLauncherArgs { flags = "FUZZY|WORKSPACES" } },
        {
            brief = "Rename tab",
            icon = "md_rename_box",
            action = act.PromptInputLine {
                description = "New tab name (empty = automatic)",
                action = wezterm.action_callback(function(win, _, line)
                    if line then win:active_tab():set_title(line) end
                end),
            },
        },
        {
            brief = "Rename workspace",
            icon = "md_rename_box",
            action = act.PromptInputLine {
                description = "New workspace name",
                action = wezterm.action_callback(function(_, _, line)
                    if line and line ~= "" then mux.rename_workspace(mux.get_active_workspace(), line) end
                end),
            },
        },
        {
            brief = "Edit dotfiles",
            icon = "md_cog",
            action = wezterm.action_callback(function(win, p)
                local tab, new_pane = win:mux_window():spawn_tab { domain = { DomainName = p:get_domain_name() } }
                tab:set_title("dotfiles")
                new_pane:send_text(' cd -- "$(dot dir)" && nvim .\n')
            end),
        },
        {
            brief = "Show keyboard cheat sheet  (dot keys)",
            icon = "md_keyboard",
            action = wezterm.action_callback(function(win, p)
                local tab, new_pane = win:mux_window():spawn_tab { domain = { DomainName = p:get_domain_name() } }
                tab:set_title("keys")
                new_pane:send_text(" dot keys | less -R; exit\n")
            end),
        },
        { brief = "Emoji / symbol picker  (Ctrl+Shift+U)", icon = "md_emoticon", action = act.CharSelect { copy_on_select = true, copy_to = "ClipboardAndPrimarySelection" } },
    }
end)

-- ---------------------------------------------------- apply -----

function M.apply(config)
    base_colors = copy(config.colors)

    -- Linux: run through XWayland, like the Flatpak build did. WezTerm
    -- 20240203 on native GNOME Wayland can't drag the window by its tab bar
    -- (and has known crashes with fractional scaling). `wayland = true` in
    -- machine.lua switches back.
    if not wezterm.target_triple:find("darwin") then
        config.enable_wayland = machine.wayland == true
    end

    -- Sessions that survive closing the window: tabs run in a background
    -- session server ("unix" domain) and the window just attaches to it.
    -- Not in the Flatpak, whose sandbox stops with the window.
    if machine.persistent_sessions ~= false and not is_flatpak then
        config.unix_domains = { { name = "unix" } }
        config.default_gui_startup_args = { "connect", "unix" }
    end

    config.keys = config.keys or {}
    local keys = {
        prompt_jump("UpArrow", -1),
        prompt_jump("DownArrow", 1),
        { key = "y", mods = "LEADER", action = copy_last_output },
        { key = "Space", mods = "LEADER", action = act.QuickSelect },
        { key = "u", mods = "LEADER", action = open_url },
        { key = "p", mods = "LEADER", action = pick_project },
        { key = "a", mods = "LEADER", action = agent_radar },
        { key = "?", mods = "LEADER", action = pair_pane },
    }
    for _, k in ipairs(keys) do table.insert(config.keys, k) end

    config.quick_select_patterns = M.quick_select_patterns

    config.mouse_bindings = config.mouse_bindings or {}
    table.insert(config.mouse_bindings, {
        event = { Down = { streak = 3, button = "Left" } },
        mods = "NONE",
        action = act.SelectTextAtMouseCursor("SemanticZone"),
    })
end

return M
