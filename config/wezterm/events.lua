local wezterm = require("wezterm")
local mux = wezterm.mux
local is_macos = wezterm.target_triple:find("darwin") ~= nil
-- Flatpak WezTerm runs sandboxed: run file-manager commands on the host.
local is_flatpak = os.getenv("FLATPAK_ID") ~= nil

local function host_cmd(args)
    if is_flatpak then
        local wrapped = { "flatpak-spawn", "--host" }
        for _, a in ipairs(args) do table.insert(wrapped, a) end
        return wrapped
    end
    return args
end

local function truncate_title(title, max_width)
    if max_width <= 0 then
        return ""
    end

    if #title <= max_width then
        return title
    end

    if max_width <= 1 then
        return title:sub(1, max_width)
    end

    return title:sub(1, max_width - 1) .. "…"
end

-- wezterm.on("gui-startup", function()
--     local _, _, window = mux.spawn_window({})
--     window:gui_window():maximize()
-- end)

-- wezterm.on("window-resized", function(window, pane)
-- 	readjust_font_size(window, pane)
-- end)

-- Readjust font size on window resize to get rid of the padding at the bottom
function readjust_font_size(window, pane)
    local window_dims = window:get_dimensions()
    local pane_dims = pane:get_dimensions()

    local config_overrides = {}
    local initial_font_size = 16 -- Set to your desired font size
    config_overrides.font_size = initial_font_size

    local max_iterations = 5
    local iteration_count = 0
    local tolerance = 3

    -- Calculate the initial difference between window and pane heights
    local current_diff = window_dims.pixel_height - pane_dims.pixel_height
    local min_diff = math.abs(current_diff)
    local best_font_size = initial_font_size

    -- Loop to adjust font size until the difference is within tolerance or max iterations reached
    while current_diff > tolerance and iteration_count < max_iterations do
        -- wezterm.log_info(window_dims, pane_dims, config_overrides.font_size)
        wezterm.log_info(
            string.format(
                "Win Height: %d, Pane Height: %d, Height Diff: %d, Curr Font Size: %.2f, Cells: %d, Cell Height: %.2f",
                window_dims.pixel_height,
                pane_dims.pixel_height,
                window_dims.pixel_height - pane_dims.pixel_height,
                config_overrides.font_size,
                pane_dims.viewport_rows,
                pane_dims.pixel_height / pane_dims.viewport_rows
            )
        )

        -- Increment the font size slightly
        config_overrides.font_size = config_overrides.font_size + 0.5
        window:set_config_overrides(config_overrides)

        -- Update dimensions after changing font size
        window_dims = window:get_dimensions()
        pane_dims = pane:get_dimensions()
        current_diff = window_dims.pixel_height - pane_dims.pixel_height

        -- Check if the current difference is the smallest seen so far
        local abs_diff = math.abs(current_diff)
        if abs_diff < min_diff then
            min_diff = abs_diff
            best_font_size = config_overrides.font_size
        end

        iteration_count = iteration_count + 1
    end

    -- If no acceptable difference was found, set the font size to the best one encountered
    if current_diff > tolerance then
        config_overrides.font_size = best_font_size
        window:set_config_overrides(config_overrides)
    end
end

-- tmux status
wezterm.on("update-right-status", function(window, _)
    require("features").clear_seen(window) -- you're looking at it: drop its ● marker
    local SOLID_LEFT_ARROW = ""
    local ARROW_FOREGROUND = { Foreground = { Color = "#c6a0f6" } }
    local prefix = ""

    if window:leader_is_active() then
        prefix = " " .. utf8.char(0x1f30a) -- ocean wave
        SOLID_LEFT_ARROW = utf8.char(0xe0b2)
    end

    if window:active_tab():tab_id() ~= 0 then
        ARROW_FOREGROUND = { Foreground = { Color = "#1e2030" } }
    end -- arrow color based on if tab is first pane

    window:set_left_status(wezterm.format {
        { Background = { Color = "#b7bdf8" } },
        { Text = prefix },
        ARROW_FOREGROUND,
        { Text = SOLID_LEFT_ARROW }
    })
end)

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
    local index = tab.tab_index
    -- a name you gave the tab (palette → Rename tab, project tabs) wins
    local title = (tab.tab_title ~= "" and tab.tab_title) or tab.active_pane.title or "shell"
    -- Claude Code waiting (●) / finished (✓) in this tab
    local marker = require("features").tab_marker(tab.tab_id)
    local prefix = string.format(" %d: ", index)
    if marker == "waiting" then
        prefix = string.format(" %d: ● ", index)
    elseif marker == "done" then
        prefix = string.format(" %d: ✓ ", index)
    end
    local suffix = " "
    local available_width = math.max(max_width - #prefix - #suffix, 0)
    local label = truncate_title(title, available_width)

    local bg = "#363a4f"
    local fg = "#cad3f5"

    if tab.is_active then
        bg = "#b7bdf8"
        fg = "#1e2030"
    elseif marker == "waiting" then
        bg = "#f5a97f" -- orange: needs you
        fg = "#1e2030"
    elseif marker == "done" then
        bg = "#a6da95" -- green: finished
        fg = "#1e2030"
    elseif hover then
        bg = "#494d64"
    end

    return {
        { Background = { Color = bg } },
        { Foreground = { Color = fg } },
        { Text = prefix .. label .. suffix },
    }
end)

local function percent_decode(value)
    return value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

local function file_uri_to_path(uri)
    local path = uri:gsub("^file://", "")
    return percent_decode(path)
end

-- Handle custom URI schemes for clickable prompt and listing elements
wezterm.on("open-uri", function(window, pane, uri)
    if uri:find("^x%-cd://parent") then
        pane:send_text("\x15" .. "cd ..\n")
        return false
    end
    if uri:find("^x%-edit://") then
        pane:send_text("\x15" .. "nvim .\n")
        return false
    end
    if uri:find("^file://") then
        local path = file_uri_to_path(uri)
        -- OSC 8 file links may carry a hostname: file://host/path -> /path
        if not path:find("^/") then
            path = path:gsub("^[^/]*", "")
        end
        wezterm.log_info("open-uri: opening path " .. path)

        local is_directory = pcall(wezterm.read_dir, path)

        if is_macos then
            if is_directory then
                wezterm.background_child_process({ "/usr/bin/open", path })
            else
                wezterm.background_child_process({ "/usr/bin/open", "-R", path })
            end
        else
            if is_directory then
                -- Open the folder in the default file manager
                wezterm.background_child_process(host_cmd({ "xdg-open", path }))
            else
                -- Reveal the file in Nautilus (equivalent of `open -R`),
                -- fall back to opening its parent folder.
                -- (spawned in background so a cold-started Nautilus can't block the GUI)
                local has_nautilus = wezterm.run_child_process(host_cmd({ "sh", "-c", "command -v nautilus" }))
                if has_nautilus then
                    wezterm.background_child_process(host_cmd({ "nautilus", "--select", path }))
                else
                    local parent = path:match("^(.*)/[^/]*$")
                    if parent == "" then parent = "/" end
                    wezterm.background_child_process(host_cmd({ "xdg-open", parent or path }))
                end
            end
        end

        return false
    end
    return true
end)

-- Toast when a long command finishes while you're in another window
-- (set by ~/.config/shell/notify.sh through OSC 1337 SetUserVar).
wezterm.on("user-var-changed", function(window, pane, name, value)
    if name ~= "dot_cmd_done" or window:is_focused() then
        return
    end
    local status, secs, cmd = value:match("^(%-?%d+)\t(%d+)\t(.*)$")
    if not status then
        return
    end
    local title = status == "0" and "✓ Finished" or ("✗ Failed (exit " .. status .. ")")
    window:toast_notification(title, cmd .. "  ·  " .. secs .. "s", nil, 6000)
end)
