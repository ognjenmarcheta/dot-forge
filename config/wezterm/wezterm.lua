local wezterm = require("wezterm")
local config = require("config")
require("events")
require("features").apply(config) -- blocks, quick select, projects, palette, agent alerts

-- Apply color scheme based on the WEZTERM_THEME environment variable
local themes = {
    nord = "Nord (Gogh)",
    onedark = "One Dark (Gogh)",
}

local function detect_theme()
    -- On Linux, GUI apps usually inherit the session env (~/.profile,
    -- ~/.config/environment.d), so check our own environment first.
    local value = os.getenv("WEZTERM_THEME")
    if value and value ~= "" then
        return value
    end

    -- Fallback (needed on macOS, where GUI apps don't inherit shell env):
    -- ask the login shell for the variable.
    local shell = os.getenv("SHELL") or "/bin/bash"
    local cmd = { shell, "-l", "-c", "printenv WEZTERM_THEME" }
    if os.getenv("FLATPAK_ID") then
        -- Flatpak sandbox: the user's shell lives on the host
        table.insert(cmd, 1, "--host")
        table.insert(cmd, 1, "flatpak-spawn")
    end
    local ok, stdout = wezterm.run_child_process(cmd)
    if ok and stdout then
        return stdout
    end
    return ""
end

local selected_theme = detect_theme():gsub("%s+", "") -- strip whitespace/newlines
config.color_scheme = themes[selected_theme]

return config
