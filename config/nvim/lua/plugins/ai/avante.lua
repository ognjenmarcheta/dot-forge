return {
	{
		"yetone/avante.nvim",
		-- Newer avante refuses to start on Neovim < 0.12. Pin the last version
		-- that works on 0.11 so Lazy Update can't move it; unpinned on 0.12+.
		commit = vim.fn.has("nvim-0.12") == 0 and "865cee5f80db8b7959592f23f174acac36f8be8d" or nil,
		enabled = EcoVim.plugins.ai.avante.enabled,
		-- avante talks to Copilot; until you've signed in (`:Copilot auth`,
		-- then restart) it errors on every start, so only load it after that.
		cond = function()
			local dir = (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")) .. "/github-copilot/"
			return vim.uv.fs_stat(dir .. "apps.json") ~= nil or vim.uv.fs_stat(dir .. "hosts.json") ~= nil
		end,
		lazy = false,
		version = false,
		opts = {
			provider = "copilot",
			-- provider = "claude",
			mode = "agentic", -- The default mode for interaction. "agentic" uses tools to automatically generate code, "legacy" uses the old planning method to generate code.
			auto_suggestions_provider = "copilot",
			behaviour = {
				auto_apply_diff_after_generation = false,
				auto_focus_sidebar = true,
				auto_set_highlight_group = true,
				auto_set_keymaps = true,
				auto_suggestions = false,
				enable_cursor_planning_mode = true,
				jump_result_buffer_on_finish = false,
				minimize_diff = true, -- Whether to remove unchanged lines when applying a code block
				support_paste_from_clipboard = true,
			},
			hints = { enabled = true },
			providers = {
				copilot = {
					model = "claude-opus-4.5",
					-- model = "grok-code-fast-1",
					disable_tools = false,
					extra_request_body = {
						max_tokens = 200000,
					},
				},
			},
			-- system_prompt as function ensures LLM always has latest MCP server state
			-- This is evaluated for every message, even in existing chats
			system_prompt = function()
				local ok, mcphub = pcall(require, "mcphub")
				if not ok then return "" end
				local hub = mcphub.get_hub_instance()
				return hub and hub:get_active_servers_prompt() or ""
			end,
			-- Using function prevents requiring mcphub before it's loaded
			custom_tools = function()
				local ok, ext = pcall(require, "mcphub.extensions.avante")
				if not ok then return {} end
				return { ext.mcp_tool() }
			end,
		},
		-- Install avante's native libs from the prebuilt GitHub release (no Rust
		-- toolchain needed). avante's own download script still points at the old
		-- yetone/avante.nvim repo and doesn't follow GitHub's redirect to
		-- avante-corp/avante.nvim, so download the matching release asset here.
		-- Falls back to a cargo build only if that fails and cargo is installed.
		build = function(plugin)
			local dir = plugin.dir
			local function run(cmd) return vim.system(cmd, { cwd = dir, text = true }):wait() end
			local res
			local ok_v, version = pcall(dofile, dir .. "/lua/avante/version.lua")
			if ok_v and type(version) == "string" then
				-- newer avante: build.sh <version> downloads into lua/
				res = run({ "bash", dir .. "/build.sh", version })
			else
				-- older avante: release tarball goes into build/
				run({ "git", "fetch", "--tags", "--quiet", "origin" })
				local tag = vim.trim(run({ "git", "describe", "--tags", "--abbrev=0" }).stdout or "")
				local sysname = vim.uv.os_uname().sysname == "Darwin" and "darwin" or "linux"
				local arch = vim.uv.os_uname().machine:gsub("arm64", "aarch64")
				local url = ("https://github.com/avante-corp/avante.nvim/releases/download/%s/avante_lib-%s-%s-luajit.tar.gz")
					:format(tag, sysname, arch)
				vim.fn.mkdir(dir .. "/build", "p")
				res = run({ "sh", "-c", ("curl -fsSL '%s' | tar -xz -C build && echo '%s' > build/.tag"):format(url, tag) })
			end
			if res.code ~= 0 and vim.fn.executable("cargo") == 1 then
				res = run({ "make", "BUILD_FROM_SOURCE=true" })
			end
			if res.code ~= 0 then
				error("avante.nvim build failed:\n" .. (res.stderr or "") .. (res.stdout or ""))
			end
		end,
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			"nvim-tree/nvim-web-devicons",
			"zbirenbaum/copilot.lua",
			{
				-- support for image pasting
				"HakonHarnes/img-clip.nvim",
				event = "VeryLazy",
				opts = {
					-- recommended settings
					default = {
						embed_image_as_base64 = false,
						prompt_for_file_name = false,
						drag_and_drop = {
							insert_mode = true,
						},
						-- required for Windows users
						use_absolute_path = true,
					},
				},
			},
			"MeanderingProgrammer/render-markdown.nvim",
		},
	},
}
