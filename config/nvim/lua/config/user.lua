--[[
  ╔════════════════════════════════════════════════════════════════╗
  ║                     EcoVim User Configuration                  ║
  ╠════════════════════════════════════════════════════════════════╣
  ║  This is YOUR personal configuration file.                     ║
  ║  It is gitignored and won't be tracked by git.                 ║
  ║                                                                ║
  ║  HOW IT WORKS:                                                 ║
  ║  1. EcoVim.lua loads first (default settings)                  ║
  ║  2. This file loads second (YOUR overrides)                    ║
  ║                                                                ║
  ║  Your settings take priority over EcoVim defaults.             ║
  ║                                                                ║
  ║  TO CUSTOMIZE:                                                 ║
  ║  1. Copy this file: cp user.lua.example user.lua               ║
  ║  2. Edit user.lua with your preferences                        ║
  ║  3. Restart Neovim or run :luafile %                           ║
  ║                                                                ║
  ║  UPDATING ECOVIM:                                              ║
  ║  Since this file is gitignored, you can safely run:            ║
  ║     git pull                                                   ║
  ║  Without worrying about merge conflicts!                       ║
  ╚════════════════════════════════════════════════════════════════╝
--]]

-- ╭──────────────────────────────────────────────────────────────╮
-- │ 1. APPEARANCE                                                │
-- ╰──────────────────────────────────────────────────────────────╯

-- Change the colorscheme (default: "tokyonight-night")
-- Available: "tokyonight-night", "tokyonight-storm", "tokyonight-day"
-- You can install your own!
-- EcoVim.colorscheme = "tokyonight-storm"

-- Change GUI font (for Neovide, etc.)
-- EcoVim.ui.font = { "JetBrainsMono Nerd Font", ":h14" }

-- Change floating window border style
-- Available: "rounded", "single", "double", "shadow", "none"
-- EcoVim.ui.float.border = "rounded"


-- ╭──────────────────────────────────────────────────────────────╮
-- │ 2. LSP (Language Servers)                                    │
-- ╰──────────────────────────────────────────────────────────────╯

-- Add additional LSP servers to auto-install
-- These will be installed via Mason on next startup
-- EcoVim.lsp.ensure_installed = { "rust_analyzer", "gopls", "clangd" }

-- Exclude LSP servers from auto-enabling
-- (Useful if you want to configure them manually)
-- EcoVim.lsp.exclude = { "ts_ls", "copilot", "rust_analyzer" }

-- Enable format on save (default: false)
-- Toggle at runtime with :LspToggleAutoFormat
-- EcoVim.lsp.format_on_save = true

-- Disable inlay hints (default: true)
-- EcoVim.lsp.inlay_hints = false

-- Switch TypeScript server (default: "tsgo")
-- "tsgo" is Microsoft's native Go-based TS server (fast, recommended)
-- "ts_ls" is the classic TypeScript language server
-- The inactive server is automatically excluded from auto-enable
-- EcoVim.lsp.typescript_server = "ts_ls"

-- Add custom LSP server configuration
-- See: https://neovim.io/doc/user/lsp.html
-- EcoVim.lsp.servers.mylsp = {
--   cmd = { "my-lsp", "--stdio" },
--   filetypes = { "javascript", "typescript" },
--   root_markers = { ".git", "package.json" },
-- }


-- ╭──────────────────────────────────────────────────────────────╮
-- │ 3. FORMATTING & LINTING                                      │
-- ╰──────────────────────────────────────────────────────────────╯

-- Override default formatters per filetype
-- The first available formatter will be used
-- EcoVim.formatters = {
--   javascript = { "prettierd", "prettier" },
--   typescript = { "prettierd" },
--   lua = { "stylua" },
-- }

-- Override default linters per filetype
-- EcoVim.linters = {
--   javascript = { "eslint_d", "oxlint" },
--   typescript = { "eslint_d" },
-- }


-- ╭──────────────────────────────────────────────────────────────╮
-- │ 4. AUTOCOMMANDS                                              │
-- ╰──────────────────────────────────────────────────────────────╯

-- Add custom autocmds that run automatically
-- EcoVim.autocmds.auto_save = {
--   event = "FocusLost",                    -- Trigger event
--   pattern = "*",                          -- File pattern
--   command = "silent! wa",                 -- Command to run
-- }

-- EcoVim.autocmds.highlight_yank = {
--   event = "TextYankPost",
--   pattern = "*",
--   callback = function()
--     vim.highlight.on_yank({ higroup = "IncSearch", timeout = 100 })
--   end,
-- }


-- ╭──────────────────────────────────────────────────────────────╮
-- │ 5. PLUGIN OVERRIDES                                          │
-- ╰──────────────────────────────────────────────────────────────╯

-- Override ANY plugin configuration without modifying plugin files
-- This is the most powerful customization option!
-- Use the plugin's repo name (e.g., "snacks.nvim", "blink.cmp", "todo-comments.nvim")

-- Example: Change Snacks picker layout (function receives plugin and opts)
-- EcoVim.plugin_overrides["snacks.nvim"] = function(_, opts)
--   opts.picker.layout = "vertical"
--   opts.picker.preview = false
-- end

-- Example: Customize blink.cmp
-- EcoVim.plugin_overrides["blink.cmp"] = function(_, opts)
--   opts.completion.menu.auto_show = false
-- end

-- Example: Override any plugin with a table (deep-merged with defaults)
-- EcoVim.plugin_overrides["todo-comments.nvim"] = {
--   signs = false,
--   highlight = { keyword = "bg" },
-- }


-- ╭──────────────────────────────────────────────────────────────╮
-- │ 6. PLUGIN TOGGLES                                            │
-- ╰──────────────────────────────────────────────────────────────╯

-- Enable/disable specific AI plugins
-- EcoVim.plugins.ai.avante.enabled = false
-- EcoVim.plugins.ai.copilot.enabled = false
-- EcoVim.plugins.ai.opencode.enabled = true

-- Completion settings
-- EcoVim.plugins.completion.select_first_on_enter = true

-- Disable ghost text in completions (default: true)
-- EcoVim.plugins.completion.ghost_text = false

-- Disable inline git blame on current line (default: true)
-- Toggle at runtime with :Gitsigns toggle_current_line_blame
-- EcoVim.plugins.git.blame_line = false

-- Enable jump by subwords (better word navigation)
-- EcoVim.plugins.jump_by_subwords.enabled = true


-- ╭──────────────────────────────────────────────────────────────╮
-- │ 7. PROJECT & MONOREPO SETTINGS                               │
-- ╰──────────────────────────────────────────────────────────────╯

-- Configure which directories are scanned for projects (<leader>pl)
-- EcoVim.plugins.projects.dev = { "~/Projects", "~/.config" }

-- Configure how project roots are detected
-- Default uses only .git to avoid sub-package false positives in monorepos
-- EcoVim.plugins.projects.patterns = { ".git" }

-- Configure vim-rooter patterns (determines cwd when opening files)
-- Supports monorepo tools: pnpm, Turborepo, Nx, Lerna, Rush
-- Default excludes package.json to prevent cwd from changing to sub-packages
-- If you don't use monorepos, you may want to add "package.json" back
-- EcoVim.plugins.rooter.patterns = {
--   "pnpm-workspace.yaml", "turbo.json", "nx.json", "lerna.json", "rush.json",
--   ".git", "package.json",
-- }


-- ╭──────────────────────────────────────────────────────────────╮
-- │ 8. STATUSLINE                                                │
-- ╰──────────────────────────────────────────────────────────────╯

-- Show full path in statusline
-- EcoVim.statusline.path_enabled = true
-- EcoVim.statusline.path = "absolute"  -- or "relative"


-- ╭──────────────────────────────────────────────────────────────╮
-- │ 9. DIRECT VIM OPTIONS                                        │
-- ╰──────────────────────────────────────────────────────────────╯

-- You can also set raw vim options here
-- vim.o.tabstop = 4
-- vim.o.shiftwidth = 4
-- vim.o.expandtab = false
-- vim.o.number = false
-- vim.o.relativenumber = false


--[[
  ╔════════════════════════════════════════════════════════════════╗
  ║  NEED MORE HELP?                                               ║
  ║  • See README.md for full documentation                        ║
  ║  • Check lua/plugins/ for plugin configurations               ║
  ║  • Visit: https://github.com/ecosse3/nvim                     ║
  ╚════════════════════════════════════════════════════════════════╝
--]]
--

EcoVim.lsp.typescript_server = "ts_ls"   -- Switch from tsgo to ts_ls

-- No mouse in Neovim: clicks/drags must not move the cursor or start a
-- selection. Applied after startup because EcoVim's options.lua (which runs
-- after this file) sets mouse = "a".
vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		vim.o.mouse = ""
	end,
})

-- ─── Keep plugins on EcoVim's tested versions ────────────────────────────────
-- This config is EcoVim v5.0.0 (kept in the dotfiles repo); the committed lazy-lock.json pins every
-- plugin to versions tested together. Lazy's Update/Sync moves plugins past
-- those pins (that's what broke avante and treesitter on Neovim 0.11).
--   * On startup: one warning if installed plugins drifted from those pins.
--   * :PluginsRestore puts every plugin back, rebuilds treesitter parsers.
-- Silence the check with: vim.g.plugin_drift_check = false
local function release_lock()
	local cfg = vim.fn.stdpath("config")
	local res = vim.system({ "git", "-C", cfg, "show", "HEAD:./lazy-lock.json" }, { text = true }):wait()
	if res.code ~= 0 then return nil, nil end
	local ok, data = pcall(vim.json.decode, res.stdout)
	if not ok then return nil, nil end
	return data, res.stdout
end

local function drifted_plugins()
	local lock = release_lock()
	if not lock then return {} end
	local plugins = require("lazy.core.config").plugins
	local git = require("lazy.manage.git")
	local out = {}
	for name, entry in pairs(lock) do
		local p = plugins[name]
		if p and p._.installed then
			local info = git.info(p.dir)
			if info and info.commit and info.commit ~= entry.commit then
				table.insert(out, name)
			end
		end
	end
	table.sort(out)
	return out
end

vim.api.nvim_create_user_command("PluginsRestore", function()
	local _, raw = release_lock()
	if not raw then
		vim.notify("PluginsRestore: can't read lazy-lock.json from the config's git history", vim.log.levels.ERROR)
		return
	end
	local f = assert(io.open(vim.fn.stdpath("config") .. "/lazy-lock.json", "w"))
	f:write(raw)
	f:close()
	vim.api.nvim_create_autocmd("User", {
		pattern = "LazyRestore",
		once = true,
		callback = function()
			pcall(vim.cmd, "TSUpdate")
			vim.notify("Plugins are back on EcoVim's tested versions. Restart Neovim.", vim.log.levels.INFO, { title = "Plugins" })
		end,
	})
	vim.cmd("Lazy restore")
end, { desc = "Reset plugins to the versions pinned by this EcoVim release" })

-- UIEnter (not lazy's VeryLazy): a plugin erroring during VeryLazy can stop
-- later VeryLazy handlers, and this check must still run in that case.
vim.api.nvim_create_autocmd("UIEnter", {
	once = true,
	callback = function()
		if vim.g.plugin_drift_check == false then return end
		vim.defer_fn(function()
			local ok, list = pcall(drifted_plugins)
			if ok and #list > 0 then
				local shown = table.concat(vim.list_slice(list, 1, 4), ", ") .. (#list > 4 and ", …" or "")
				vim.notify(
					("%d plugin(s) differ from EcoVim's tested versions (%s).\nRun :PluginsRestore to fix. Avoid Lazy Update/Sync."):format(#list, shown),
					vim.log.levels.WARN,
					{ title = "Plugins" }
				)
			end
		end, 1500)
	end,
})
