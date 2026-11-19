local wezterm = require("wezterm")
local config = {}

if wezterm.config_builder then
    config = wezterm.config_builder()
end

config = {
    default_cursor_style = "BlinkingBlock",
    -- the cursor fades in and out instead of switching on and off
    cursor_blink_rate = 700,
    cursor_blink_ease_in = "EaseOut",
    cursor_blink_ease_out = "EaseOut",
    animation_fps = 60,
    -- splits you're not typing in fade back; the active one stays bright
    inactive_pane_hsb = { saturation = 0.8, brightness = 0.55 },
    automatically_reload_config = true,
    window_close_confirmation = "NeverPrompt",
    adjust_window_size_when_changing_font_size = false,
    window_decorations = "RESIZE",
    tab_bar_at_bottom = true,
    tab_and_split_indices_are_zero_based = true,
    hide_tab_bar_if_only_one_tab = false,
    check_for_updates = false,
    -- the "fancy" tab bar: the only one where tabs get a clickable × close button.
    -- With persistent sessions, × always asks "Really kill this tab?" (hard-coded
    -- in WezTerm for session-server tabs); Cmd+W / Ctrl+Shift+W close at once.
    use_fancy_tab_bar = true,
    show_close_tab_button_in_tabs = true,
    window_frame = {
        font = wezterm.font("JetBrains Mono", { weight = "Bold" }),
        font_size = 11.5,
        active_titlebar_bg = "#1f2330",
        inactive_titlebar_bg = "#1f2330",
    },
    font_size = 12.5,
    -- Medium for normal text, so bold actually stands out; italics in a
    -- cursive face (comments in nvim, *emphasis* in Markdown). Victor Mono is
    -- installed by install.sh / the Brewfile; without it italics stay JetBrains.
    font = wezterm.font_with_fallback({
        { family = "JetBrains Mono", weight = "Medium" },
        { family = "JetBrainsMono Nerd Font", weight = "Medium" },
    }),
    font_rules = {
        { intensity = "Bold", italic = false, font = wezterm.font("JetBrains Mono", { weight = "ExtraBold" }) },
        { intensity = "Half", italic = false, font = wezterm.font("JetBrains Mono", { weight = "Light" }) },
        {
            intensity = "Bold", italic = true,
            font = wezterm.font_with_fallback({
                { family = "VictorMono Nerd Font", weight = "Bold", style = "Italic" },
                { family = "Victor Mono", weight = "Bold", style = "Italic" },
                { family = "JetBrains Mono", weight = "ExtraBold", style = "Italic" },
            }),
        },
        {
            intensity = "Normal", italic = true,
            font = wezterm.font_with_fallback({
                { family = "VictorMono Nerd Font", weight = "DemiBold", style = "Italic" },
                { family = "Victor Mono", weight = "DemiBold", style = "Italic" },
                { family = "JetBrains Mono", weight = "Medium", style = "Italic" },
            }),
        },
        {
            intensity = "Half", italic = true,
            font = wezterm.font_with_fallback({
                { family = "VictorMono Nerd Font", weight = "Regular", style = "Italic" },
                { family = "Victor Mono", weight = "Regular", style = "Italic" },
                { family = "JetBrains Mono", weight = "Light", style = "Italic" },
            }),
        },
    },
    -- ligatures (=> != === ->) and a slashed zero
    harfbuzz_features = { "calt=1", "clig=1", "liga=1", "zero" },
    enable_tab_bar = true,
    tab_max_width = 28,
    window_padding = {
        left = 8,
        right = 8,
        top = 8,
        bottom = 8,
    },
    background = {
        {
            source = {
                -- Portable: resolves to ~/.config/wezterm on Linux and macOS
                File = wezterm.config_dir .. "/bg-monterey.jpg",
            },
            hsb = {
                hue = 1.0,
                saturation = 1.02,
                brightness = 0.25,
            },
            -- attachment = { Parallax = 0.3 },
            -- width = "100%",
            -- height = "100%",
        },
        {
            source = {
                Color = "#282c35",
            },
            width = "100%",
            height = "100%",
            opacity = 0.55,
        },
    },
    -- from: https://akos.ma/blog/adopting-wezterm/
    hyperlink_rules = {
        -- Matches: a URL in parens: (URL)
        {
            regex = "\\((\\w+://\\S+)\\)",
            format = "$1",
            highlight = 1,
        },
        -- Matches: a URL in brackets: [URL]
        {
            regex = "\\[(\\w+://\\S+)\\]",
            format = "$1",
            highlight = 1,
        },
        -- Matches: a URL in curly braces: {URL}
        {
            regex = "\\{(\\w+://\\S+)\\}",
            format = "$1",
            highlight = 1,
        },
        -- Matches: a URL in angle brackets: <URL>
        {
            regex = "<(\\w+://\\S+)>",
            format = "$1",
            highlight = 1,
        },
        -- Then handle URLs not wrapped in brackets
        {
            -- Before
            --regex = '\\b\\w+://\\S+[)/a-zA-Z0-9-]+',
            --format = '$0',
            -- After
            regex = "[^(]\\b(\\w+://\\S+[)/a-zA-Z0-9-]+)",
            format = "$1",
            highlight = 1,
        },
        -- implicit mailto link
        {
            regex = "\\b\\w+@[\\w-]+(\\.[\\w-]+)+\\b",
            format = "mailto:$0",
        },
    },
    colors = {
        tab_bar = {
            background = "#1f2330",
            inactive_tab_edge = "#1f2330",
            active_tab = {
                bg_color = "#b7bdf8",
                fg_color = "#1e2030",
                intensity = "Bold",
            },
            inactive_tab = {
                bg_color = "#363a4f",
                fg_color = "#cad3f5",
            },
            inactive_tab_hover = {
                bg_color = "#494d64",
                fg_color = "#cad3f5",
            },
            new_tab = {
                bg_color = "#1f2330",
                fg_color = "#cad3f5",
            },
            new_tab_hover = {
                bg_color = "#494d64",
                fg_color = "#cad3f5",
                intensity = "Bold",
            },
        },
    },
}

-- Same window on macOS and Linux: borderless, tab bar at the bottom.
-- On GNOME, move the window with Super+drag, maximize with Super+Up.
if not wezterm.target_triple:find("darwin") then
    -- Start the shell with ~/.config/shell setup (starship clickable prompt,
    -- clickable ls/ll, zoxide `z`). Your own ~/.bashrc / ~/.zshrc still load first.
    local home = wezterm.home_dir
    local login_shell = os.getenv("SHELL") or ""
    local function exists(path)
        local f = io.open(path, "r")
        if f then f:close() return true end
        return false
    end
    -- zsh whenever it's installed (autosuggestions, highlighting, fzf-tab),
    -- even before a re-login picks up `chsh`; bash otherwise
    local zsh = (login_shell:find("zsh") and login_shell)
        or (exists("/usr/bin/zsh") and "/usr/bin/zsh")
        or (exists("/bin/zsh") and "/bin/zsh")
    if zsh then
        config.default_prog = { zsh, "-l" }
        config.set_environment_variables = { ZDOTDIR = home .. "/.config/shell/zsh" }
    else
        config.default_prog = { "bash", "--rcfile", home .. "/.config/shell/bashrc", "-i" }
    end
end

-- tmux
-- Alt+q, then a key (features.apply_leader turns these into a key table
-- that shows the keys in the tab bar and waits 4 s)
config.leader = { key = "q", mods = "ALT" }
config.keys = {
    {
        mods = "LEADER",
        key = "c",
        action = wezterm.action.SpawnTab "CurrentPaneDomain",
    },
    {
        mods = "LEADER",
        key = "x",
        action = wezterm.action.CloseCurrentPane { confirm = false }
    },
    -- close a tab without "Really kill this tab?" (with persistent sessions
    -- WezTerm can't see what runs in a tab, so its own binding always asked)
    { mods = "SUPER", key = "w", action = wezterm.action.CloseCurrentTab { confirm = false } },
    { mods = "CTRL|SHIFT", key = "w", action = wezterm.action.CloseCurrentTab { confirm = false } },
    { mods = "CTRL|SHIFT", key = "W", action = wezterm.action.CloseCurrentTab { confirm = false } },
    { mods = "CTRL", key = "W", action = wezterm.action.CloseCurrentTab { confirm = false } },
    {
        mods = "LEADER",
        key = "b",
        action = wezterm.action.ActivateTabRelative(-1)
    },
    {
        mods = "LEADER",
        key = "n",
        action = wezterm.action.ActivateTabRelative(1)
    },
    {
        mods = "LEADER",
        key = "|",
        action = wezterm.action.SplitHorizontal { domain = "CurrentPaneDomain" }
    },
    {
        mods = "LEADER",
        key = "-",
        action = wezterm.action.SplitVertical { domain = "CurrentPaneDomain" }
    },
    {
        mods = "LEADER",
        key = "h",
        action = wezterm.action.ActivatePaneDirection "Left"
    },
    {
        mods = "LEADER",
        key = "j",
        action = wezterm.action.ActivatePaneDirection "Down"
    },
    {
        mods = "LEADER",
        key = "k",
        action = wezterm.action.ActivatePaneDirection "Up"
    },
    {
        mods = "LEADER",
        key = "l",
        action = wezterm.action.ActivatePaneDirection "Right"
    },
    {
        mods = "LEADER",
        key = "LeftArrow",
        action = wezterm.action.AdjustPaneSize { "Left", 5 }
    },
    {
        mods = "LEADER",
        key = "RightArrow",
        action = wezterm.action.AdjustPaneSize { "Right", 5 }
    },
    {
        mods = "LEADER",
        key = "DownArrow",
        action = wezterm.action.AdjustPaneSize { "Down", 5 }
    },
    {
        mods = "LEADER",
        key = "UpArrow",
        action = wezterm.action.AdjustPaneSize { "Up", 5 }
    },
}

-- Workspaces: named sets of tabs (one per project/client)
table.insert(config.keys, { -- Leader w: fuzzy-pick or switch workspace
    mods = "LEADER", key = "w",
    action = wezterm.action.ShowLauncherArgs { flags = "FUZZY|WORKSPACES" },
})
table.insert(config.keys, { -- Leader W: new named workspace
    mods = "LEADER", key = "W",
    action = wezterm.action.PromptInputLine {
        description = "Name for the new workspace",
        action = wezterm.action_callback(function(window, pane, line)
            if line and line ~= "" then
                window:perform_action(wezterm.action.SwitchToWorkspace { name = line }, pane)
            end
        end),
    },
})

-- Seamless Ctrl+h/j/k/l between Neovim splits and WezTerm panes
-- (smart-splits.nvim sets the IS_NVIM user var). Alt+h/j/k/l resizes.
-- With no pane in that direction the key goes to the program as usual, so
-- Ctrl+L still clears the screen and Ctrl+K still kills to end of line.
local direction_keys = { h = "Left", j = "Down", k = "Up", l = "Right" }
local function is_nvim(pane)
    return pane:get_user_vars().IS_NVIM == "true"
end
local function split_nav(kind, key)
    local mods = kind == "resize" and "META" or "CTRL"
    return {
        key = key,
        mods = mods,
        action = wezterm.action_callback(function(win, pane)
            local dir = direction_keys[key]
            if is_nvim(pane) then
                win:perform_action({ SendKey = { key = key, mods = mods } }, pane)
                return
            end
            local tab = pane:tab()
            local has_neighbor = tab and tab:get_pane_direction(dir) ~= nil
            if not has_neighbor then
                win:perform_action({ SendKey = { key = key, mods = mods } }, pane)
            elseif kind == "resize" then
                win:perform_action({ AdjustPaneSize = { dir, 3 } }, pane)
            else
                win:perform_action({ ActivatePaneDirection = dir }, pane)
            end
        end),
    }
end
for _, k in ipairs({ "h", "j", "k", "l" }) do
    table.insert(config.keys, split_nav("move", k))
    table.insert(config.keys, split_nav("resize", k))
end

for i = 0, 9 do
    -- leader + number to activate that tab
    table.insert(config.keys, {
        key = tostring(i),
        mods = "LEADER",
        action = wezterm.action.ActivateTab(i),
    })
end

-- Hyperlinks still open on click; selection is not auto-copied on mouse-up.
-- Copy with Cmd+C (macOS) / Ctrl+Shift+C or Super+C (Linux) after a deliberate
-- drag-select instead. On Linux this also means the PRIMARY selection is not
-- filled on drag, so middle-click paste won't pick up terminal selections.
-- (WezTerm has no copy_on_select option; auto-copy comes from CompleteSelection
-- mouse bindings, which we deliberately do not use here.)
config.mouse_bindings = {
    {
        event = { Up = { streak = 1, button = "Left" } },
        mods = "NONE",
        action = wezterm.action.OpenLinkAtMouseCursor,
    },
    -- Inside apps that use the mouse (nvim, lazygit, btop, herdr…) plain
    -- clicks go to the app untouched. Stealing only the button *release*
    -- left the app thinking the button was still held, so every click turned
    -- into a drag-selection. Use Ctrl+click to open a link there instead; the
    -- Ctrl+press is swallowed too so the app never sees a half click.
    {
        event = { Down = { streak = 1, button = "Left" } },
        mods = "CTRL",
        action = wezterm.action.Nop,
        mouse_reporting = true,
    },
    {
        event = { Up = { streak = 1, button = "Left" } },
        mods = "CTRL",
        action = wezterm.action.OpenLinkAtMouseCursor,
        mouse_reporting = true,
    },
}

return config
