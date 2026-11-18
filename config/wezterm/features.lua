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

-- ------------------------------------------------- share mode -----
-- `dot mode share [CLIENT]` sends dot_mode; while sharing: bigger font, no
-- toasts, only CLIENT's projects named in tabs and badges, red SHARING badge.

function M.sharing()
    local m = wezterm.GLOBAL.mode
    return (m and m.mode == "share") and m or nil
end

-- may this folder be shown by name while sharing?
function M.share_allows(path)
    local m = M.sharing()
    if not m then return true end
    if not path then return false end
    for _, p in ipairs(m.paths or {}) do
        if path == p or path:sub(1, #p + 1) == p .. "/" then return true end
    end
    return false
end

local function toast(window, title, body, ms)
    if M.sharing() then return end -- nothing pops up during a call
    window:toast_notification(title, body or "", nil, ms or 4000)
end

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

local function host_output(args)
    local ok, out = wezterm.run_child_process(host_cmd(args))
    return ok and out or ""
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

M.cwd_path = cwd_of

local function git_root(dir)
    if not dir or dir == "" then return nil end
    dir = dir:gsub("/+$", "")
    if root_cache[dir] ~= nil then return root_cache[dir] or nil end
    local d = dir
    while d and d ~= "" and d ~= home do
        -- plain io.open, not wezterm.glob: glob is async and errors inside
        -- synchronous events like format-tab-title ("attempt to yield from
        -- outside a coroutine"). Opening works for a .git dir and a worktree's .git file.
        local f = io.open(d .. "/.git", "r")
        if f then
            f:close()
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

-- ------------------------------------------------- mood lighting -----
-- One place sets the window's colour overrides, so the pieces don't fight:
--   * tab bar tinted in the active project's colour
--   * a short red wash after a failed command (shell sends dot_fail)
--   * after 22:00 and before 07:00: dimmer text and a warmer background
--     (machine.lua: night = false turns it off, night_hours = {22, 7})

local base_background -- config.background as written in config.lua (set in apply)
local base_font_size

local function is_night()
    if machine.night == false then return false end
    local from, to = table.unpack(machine.night_hours or { 22, 7 })
    local h = tonumber(os.date("%H"))
    if from > to then return h >= from or h < to end
    return h >= from and h < to
end

local function compose(window, pane)
    local _, color = M.project(pane:get_current_working_dir())
    local wid = tostring(window:window_id())
    wezterm.GLOBAL.flash = wezterm.GLOBAL.flash or {}
    wezterm.GLOBAL.applied = wezterm.GLOBAL.applied or {}
    local flash = (wezterm.GLOBAL.flash[wid] or 0) > os.time()
    local night = is_night()
    local share = M.sharing()
    if share and not M.share_allows(cwd_of(pane:get_current_working_dir())) then color = nil end
    local sig = (color or "-") .. (flash and "|flash" or "") .. (night and "|night" or "") .. (share and "|share" or "")
    if wezterm.GLOBAL.applied[wid] == sig then return end
    wezterm.GLOBAL.applied[wid] = sig

    local overrides = window:get_config_overrides() or {}
    local base_bg = (base_colors and base_colors.tab_bar and base_colors.tab_bar.background) or "#1f2330"
    local colors = copy(base_colors) or {}
    colors.tab_bar = colors.tab_bar or {}
    colors.tab_bar.background = color and blend(color, base_bg, 0.22) or base_bg
    overrides.colors = colors

    if base_background then
        local bg = copy(base_background)
        if night then
            for _, layer in ipairs(bg) do
                if layer.hsb then layer.hsb.brightness = (layer.hsb.brightness or 1) * 0.75 end
            end
            table.insert(bg, { source = { Color = "#3a2414" }, width = "100%", height = "100%", opacity = 0.20 })
        end
        if flash then
            table.insert(bg, { source = { Color = "#ed8796" }, width = "100%", height = "100%", opacity = 0.14 })
        end
        overrides.background = bg
    end
    overrides.foreground_text_hsb = night and { hue = 1.0, saturation = 0.9, brightness = 0.85 } or nil
    overrides.font_size = share and ((base_font_size or 12.5) + 3) or nil
    window:set_config_overrides(overrides)
end

-- Called from update-status: project badge (+ applies the overrides above)
function M.project_status(window, pane)
    pcall(compose, window, pane)
    local share = M.sharing()
    if share then
        return {
            { Background = { Color = "#ed8796" } },
            { Foreground = { Color = "#1e2030" } },
            { Attribute = { Intensity = "Bold" } },
            { Text = " ● SHARING · " .. (share.label or "") .. " " },
            "ResetAttributes",
        }
    end
    local name, color = M.project(pane:get_current_working_dir())
    if not name then return {} end
    return {
        { Background = { Color = color } },
        { Foreground = { Color = "#1e2030" } },
        { Attribute = { Intensity = "Bold" } },
        { Text = " " .. name .. " " },
        "ResetAttributes",
    }
end

local function flash_failure(window)
    local wid = tostring(window:window_id())
    wezterm.GLOBAL.flash = wezterm.GLOBAL.flash or {}
    wezterm.GLOBAL.flash[wid] = os.time() + 2
    local p = window:active_pane()
    if p then pcall(compose, window, p) end
    wezterm.time.call_after(2.5, function()
        local ap = window:active_pane()
        if ap then pcall(compose, window, ap) end
    end)
end

-- ------------------------------------------------------- status bar -----
-- Right side: agents (● needs you / ⟳ working), CPU and GPU temperature, RAM,
-- running containers, CI runner. Files under /sys and /proc are read
-- directly; anything slow (docker, nvidia-smi, gh) runs in the background
-- (scripts/dot-status) and is read from ~/.cache/dotfiles/status.json.

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local t = f:read("*a")
    f:close()
    return t
end

local hwmon -- name -> directory
local function temp_of(names)
    if not hwmon then
        hwmon = {}
        for _, n in ipairs(wezterm.glob("/sys/class/hwmon/hwmon*/name")) do
            local name = (read_file(n) or ""):gsub("%s+", "")
            if name ~= "" and not hwmon[name] then hwmon[name] = n:gsub("/name$", "") end
        end
    end
    for _, name in ipairs(names) do
        local dir = hwmon[name]
        local v = dir and tonumber(read_file(dir .. "/temp1_input") or "")
        if v then return math.floor(v / 1000 + 0.5) end
    end
end

local function ram_linux()
    local m = read_file("/proc/meminfo")
    if not m then return nil end
    local total = tonumber(m:match("MemTotal:%s+(%d+)"))
    local avail = tonumber(m:match("MemAvailable:%s+(%d+)"))
    if not total or not avail then return nil end
    return (total - avail) / 1048576, total / 1048576
end

local status_file = home .. "/.cache/dotfiles/status.json"
local status_started = 0
local function background_status()
    local now = os.time()
    if now - status_started >= 20 then -- refresh every 20 s, in the background
        status_started = now
        wezterm.background_child_process {
            home .. "/.config/scripts/dot-status", machine.ci_repo or "ognjenmarcheta/kaine-forge",
        }
    end
    local parse = (wezterm.serde and wezterm.serde.json_decode) or wezterm.json_parse
    local ok, data = pcall(parse, read_file(status_file) or "{}")
    return ok and type(data) == "table" and data or {}
end

local function temp_color(t)
    if t >= 85 then return "#ed8796" elseif t >= 70 then return "#eed49f" end
    return "#a5adcb"
end

local right_cache = { t = 0, items = {} }
function M.right_status()
    if M.sharing() then return {} end -- nothing about other work on screen
    if os.time() - right_cache.t < 2 then return right_cache.items end
    local items = {}
    local function add(color, text)
        table.insert(items, { Foreground = { Color = color } })
        table.insert(items, { Text = text .. "  " })
    end
    local waiting, working = 0, 0
    for _, a in ipairs(M.agent_list()) do
        if a.state == "waiting" then waiting = waiting + 1 elseif a.state == "working" then working = working + 1 end
    end
    if waiting > 0 then add("#f5a97f", "● " .. waiting .. " waiting") end
    if working > 0 then add("#8aadf4", "⟳ " .. working) end

    local st = background_status()
    local cpu = temp_of { "k10temp", "zenpower", "coretemp", "cpu_thermal" }
    local gpu = temp_of { "amdgpu" } or tonumber(st.gpu_temp or "")
    if cpu then add(temp_color(cpu), "CPU " .. cpu .. "°") end
    if gpu then add(temp_color(gpu), "GPU " .. gpu .. "°") end
    local used, total = ram_linux()
    if not used and st.ram_used then used, total = tonumber(st.ram_used), tonumber(st.ram_total) end
    if used and total then
        add(used / total > 0.9 and "#ed8796" or "#a5adcb", string.format("RAM %.0f/%.0fG", used, total))
    end
    if tonumber(st.docker or "") and tonumber(st.docker) > 0 then add("#8aadf4", "🐳 " .. st.docker) end
    if st.ci == "up" then add("#a6da95", "CI ●")
    elseif st.ci == "down" then add("#ed8796", "CI ●") end
    right_cache = { t = os.time(), items = items }
    return items
end

-- ------------------------------------------------------- save points -----
-- `dot save-game NAME` / `dot load-game NAME` (the shell asks WezTerm through a
-- user var): tabs, splits, folders, what was running and git branches of the
-- current workspace, kept in ~/.local/share/dotfiles/saves/NAME.json.
-- Restoring: editors, lazygit, dev servers… start again; Claude resumes its
-- last conversation (claude --continue); anything else is typed but not run.

local saves_dir = home .. "/.local/share/dotfiles/saves"
local json_encode = (wezterm.serde and wezterm.serde.json_encode) or wezterm.json_encode
local json_parse = (wezterm.serde and wezterm.serde.json_decode) or wezterm.json_parse

local function pane_dir(p)
    local cwd = p:get_current_working_dir()
    local ok, path = pcall(function() return cwd and cwd.file_path end)
    return ok and path or nil
end

local function git_branch(dir)
    if not dir then return "" end
    local ok, out = wezterm.run_child_process(host_cmd { "git", "-C", dir, "branch", "--show-current" })
    return ok and (out:gsub("%s+$", "")) or ""
end

local function save_game(window, name)
    local ws = window:active_workspace()
    if name == "" or name == "__workspace__" then name = ws end
    name = name:gsub("[^%w._-]", "_")
    local data = { name = name, workspace = ws, saved_at = os.time(), windows = {} }
    local npanes, ntabs = 0, 0
    for _, mw in ipairs(mux.all_windows()) do
        if mw:get_workspace() == ws then
            local w = { tabs = {} }
            for _, tab in ipairs(mw:tabs()) do
                ntabs = ntabs + 1
                local t = { title = tab:get_title(), panes = {} }
                for _, info in ipairs(tab:panes_with_info()) do
                    npanes = npanes + 1
                    local dir = pane_dir(info.pane)
                    local vars = info.pane:get_user_vars()
                    table.insert(t.panes, {
                        left = info.left, top = info.top, width = info.width, height = info.height,
                        active = info.is_active, cwd = dir, prog = vars.dot_prog or "", branch = git_branch(dir),
                    })
                end
                table.insert(w.tabs, t)
            end
            table.insert(data.windows, w)
        end
    end
    host_output { "mkdir", "-p", saves_dir }
    write_private_file(saves_dir .. "/" .. name .. ".json", json_encode(data))
    toast(window, "💾 Saved \"" .. name .. "\"", ntabs .. " tab(s), " .. npanes .. " pane(s) — dot load-game " .. name)
end

-- ---------------------------------------------------- terminal recall -----
-- The shell sends dot_done after each (non-interactive) command; we keep its
-- output in ~/.local/share/dotfiles/recall/YYYY-MM-DD.jsonl (private, secrets
-- masked, 30 days) so `dot recall` can search what was ever on screen.

local recall_dir = home .. "/.local/share/dotfiles/recall"
local recall_max = 20000
local recall_masks = {
    "(%f[%w][%w_]*[Tt][Oo][Kk][Ee][Nn][%w_]*%s*[=:]%s*)%S+",
    "(%f[%w][%w_]*[Ss][Ee][Cc][Rr][Ee][Tt][%w_]*%s*[=:]%s*)%S+",
    "(%f[%w][%w_]*[Pp][Aa][Ss][Ss][Ww]?[Oo]?[Rr]?[Dd][%w_]*%s*[=:]%s*)%S+",
    "(%f[%w][%w_]*[Aa][Pp][Ii]_?[Kk][Ee][Yy][%w_]*%s*[=:]%s*)%S+",
    "([Aa]uthorization:%s*%a+%s+)%S+",
    "(://[^/%s:@]+:)[^@%s]+(@)",
}
local recall_raw = { "ghp_%w+", "gho_%w+", "github_pat_[%w_]+", "sk%-ant%-[%w%-_]+", "sk%-[%w]+", "AKIA%u%u%u%u%u%u%u%u%u%u%u%u%u%u%u%u", "xox[bpas]%-[%w%-]+",
    "%-%-%-%-%-BEGIN [%u ]*PRIVATE KEY%-%-%-%-%-.-%-%-%-%-%-END [%u ]*PRIVATE KEY%-%-%-%-%-" }

function M.mask_secrets(text)
    for _, pat in ipairs(recall_masks) do
        text = text:gsub(pat, function(a, b) return a .. "•••" .. (b or "") end)
    end
    for _, pat in ipairs(recall_raw) do text = text:gsub(pat, "•••") end
    return text
end

local function append_private_file(path, text)
    if is_flatpak then
        wezterm.run_child_process(host_cmd {
            "sh", "-c", 'umask 077 && printf "%s" "$2" >> "$1"', "sh", path, text,
        })
    else
        local f = io.open(path, "a")
        if f then f:write(text); f:close() end
    end
end

local function recall_capture(pane, value)
    if os.getenv("DOT_RECALL") == "0" then return end
    local status, cmd = value:match("^(%-?%d+)\t(.*)$")
    if not cmd or cmd == "" then return end
    local ok, zones = pcall(function() return pane:get_semantic_zones("Output") end)
    if not ok or not zones or #zones == 0 then return end
    local z = zones[#zones]
    local key = z.start_y .. ":" .. z.end_y
    wezterm.GLOBAL.recall_seen = wezterm.GLOBAL.recall_seen or {}
    local id = tostring(pane:pane_id())
    if wezterm.GLOBAL.recall_seen[id] == key then return end -- nothing new (e.g. empty output)
    wezterm.GLOBAL.recall_seen[id] = key
    local text = pane:get_text_from_semantic_zone(z) or ""
    text = text:gsub("%s+$", "")
    if text == "" then return end
    if #text > recall_max then text = "…" .. text:sub(-recall_max) end
    local cwd = cwd_of(pane:get_current_working_dir()) or ""
    if not M.share_allows(cwd) then return end -- not while sharing someone else's screen
    local entry = json_encode {
        t = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        cwd = cwd,
        cmd = M.mask_secrets(cmd),
        status = tonumber(status),
        out = M.mask_secrets(text),
    }
    if not wezterm.GLOBAL.recall_dir_ok then
        host_output { "sh", "-c", 'mkdir -p "$1" && chmod 700 "$1"', "sh", recall_dir }
        wezterm.GLOBAL.recall_dir_ok = true
    end
    append_private_file(recall_dir .. "/" .. os.date("%Y-%m-%d") .. ".jsonl", entry .. "\n")
end

local restart_patterns = {
    "^n?vim", "^lazygit", "^yazi", "^y$", "^btop", "^htop", "^k9s", "^lazydocker", "^tig",
    "^npm run", "^npm start", "^pnpm ", "^yarn ", "^bun run", "^bun dev", "^deno task",
    "^docker compose up", "^docker%-compose up", "^just", "^mise run", "^make ", "^cargo watch", "^cargo run",
    "^npx ", "^uv run", "^python3? manage%.py runserver", "^go run", "^tail %-f",
}

local function restore_command(prog)
    if not prog or prog == "" then return nil end
    if prog:match("^claude") then return "claude --continue", true end
    for _, pat in ipairs(restart_patterns) do
        if prog:match(pat) then return prog, true end
    end
    return prog, false -- typed, not run: you decide
end

local function start_in(p, cwd, prog)
    local cmd = cwd and (" cd -- " .. shell_quote(cwd) .. " && clear") or " clear"
    p:send_text(cmd .. "\n")
    local again, run = restore_command(prog)
    if again then p:send_text(again .. (run and "\n" or "")) end
end

local function load_game(window, pane, name)
    name = name:gsub("[^%w._-]", "_")
    local text = read_file(saves_dir .. "/" .. name .. ".json")
    if not text then
        toast(window, "No save called \"" .. name .. "\"", "dot games lists them")
        return
    end
    local ok, data = pcall(json_parse, text)
    if not ok or type(data) ~= "table" then
        toast(window, "Save \"" .. name .. "\" is unreadable")
        return
    end
    local target = data.name or name
    for _, ws in ipairs(mux.get_workspace_names()) do
        if ws == target then target = target .. "-restored" end
    end
    local domain = { DomainName = pane:get_domain_name() }
    local moved = {}
    for _, w in ipairs(data.windows or {}) do
        local mwin
        for ti, t in ipairs(w.tabs or {}) do
            local ps = t.panes or {}
            table.sort(ps, function(a, b)
                if a.left ~= b.left then return a.left < b.left end
                return a.top < b.top
            end)
            local first = ps[1] or {}
            local tab, p
            if ti == 1 then
                tab, p, mwin = mux.spawn_window { workspace = target, cwd = first.cwd, domain = domain }
            else
                tab, p = mwin:spawn_tab { cwd = first.cwd, domain = domain }
            end
            if t.title and t.title ~= "" then tab:set_title(t.title) end
            local made = { { pane = p, info = first } }
            start_in(p, first.cwd, first.prog)
            for i = 2, #ps do
                local info = ps[i]
                -- split the closest pane above / to the left of this one
                local from
                for _, m in ipairs(made) do
                    if m.info.left <= info.left and m.info.top <= info.top then
                        if not from or (m.info.left + m.info.top) > (from.info.left + from.info.top) then from = m end
                    end
                end
                from = from or made[1]
                local right = math.abs(info.top - from.info.top) <= 1 and info.left > from.info.left
                local size
                if right then
                    size = info.width / math.max(1, info.left + info.width - from.info.left)
                else
                    size = info.height / math.max(1, info.top + info.height - from.info.top)
                end
                local np = from.pane:split {
                    direction = right and "Right" or "Bottom",
                    size = math.min(0.9, math.max(0.1, size)),
                    cwd = info.cwd,
                    domain = domain,
                }
                table.insert(made, { pane = np, info = info })
                start_in(np, info.cwd, info.prog)
            end
            for _, m in ipairs(made) do
                local now_branch = git_branch(m.info.cwd)
                if m.info.branch ~= "" and now_branch ~= "" and now_branch ~= m.info.branch then
                    table.insert(moved, basename(m.info.cwd) .. ": " .. m.info.branch .. " → now " .. now_branch)
                end
            end
        end
    end
    window:perform_action(act.SwitchToWorkspace { name = target }, pane)
    toast(window, "▶ Loaded \"" .. name .. "\"",
        #moved > 0 and ("Branch changed since the save: " .. table.concat(moved, ", ")) or "Everything is where you left it", 8000)
end

-- ---------------------------------------------------- user vars -----


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
    elseif name == "dot_mode" then
        local parse = (wezterm.serde and wezterm.serde.json_decode) or wezterm.json_parse
        local ok, data = pcall(parse, value)
        wezterm.GLOBAL.mode = (ok and type(data) == "table" and data.mode == "share") and data or nil
        wezterm.GLOBAL.applied = {} -- re-apply font / colours everywhere
        for _, gw in ipairs(wezterm.gui.gui_windows()) do
            local ap = gw:active_pane()
            if ap then pcall(compose, gw, ap) end
        end
    elseif name == "dot_fail" then
        flash_failure(window)
    elseif name == "dot_open" then
        if value ~= "" then open_project(window, pane, value) end
    elseif name == "dot_done" then
        pcall(recall_capture, pane, value)
    elseif name == "dot_save" then
        save_game(window, value)
    elseif name == "dot_load" then
        load_game(window, pane, value)
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
            brief = "Save game: keep this workspace (tabs, splits, programs)",
            icon = "md_content_save",
            action = act.PromptInputLine {
                description = "Name for this save (empty = workspace name)",
                action = wezterm.action_callback(function(win, _, line)
                    if line then save_game(win, line) end
                end),
            },
        },
        {
            brief = "Load game…",
            icon = "md_folder_play",
            action = wezterm.action_callback(function(win, p)
                local choices = {}
                for _, f in ipairs(wezterm.glob(saves_dir .. "/*.json")) do
                    local n = f:match("([^/]+)%.json$")
                    table.insert(choices, { id = n, label = n })
                end
                if #choices == 0 then toast(win, "No saves yet", "Palette → Save game, or dot save-game NAME") return end
                win:perform_action(act.InputSelector {
                    title = "Load a save", fuzzy = true, choices = choices,
                    action = wezterm.action_callback(function(w2, p2, id) if id then load_game(w2, p2, id) end end),
                }, p)
            end),
        },
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
    base_background = copy(config.background)
    base_font_size = config.font_size

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
