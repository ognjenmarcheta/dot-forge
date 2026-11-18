-- Headless Neovim smoke test (used by `dot doctor --nvim` and CI):
--   nvim --headless --cmd "luafile tests/nvim-smoke.lua"
-- Starts the config, opens a TypeScript file, and exits non-zero if anything
-- reported an error or the pinned behaviour is off.

local errors = {}
local function capture(level, msg)
	if (level or 0) >= vim.log.levels.ERROR then
		table.insert(errors, (tostring(msg):gsub("\n", " ")):sub(1, 300))
	end
end

local function hook_notify()
	local orig = vim.notify
	vim.notify = function(msg, level, opts)
		capture(level, msg)
		return orig(msg, level, opts)
	end
end
hook_notify()

vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		hook_notify() -- notifier plugins replace vim.notify during startup
		vim.api.nvim_exec_autocmds("UIEnter", {}) -- headless has no UI; lazy's VeryLazy waits for it
		local file = vim.fn.tempname() .. ".ts"
		vim.fn.writefile({ "export const answer: number = 42" }, file)
		vim.cmd.edit(file)

		vim.defer_fn(function()
			local out = {}
			local function check(okv, label)
				table.insert(out, (okv and "ok   " or "FAIL ") .. label)
				if not okv then table.insert(errors, label) end
			end
			local v = vim.version()
			check(v.major == 0 and v.minor == 11, ("Neovim %d.%d.%d (must be 0.11.x)"):format(v.major, v.minor, v.patch))
			check(vim.o.mouse == "", "mouse is off")
			check(vim.fn.maparg("<Up>", "n") == "", "plain arrows move (no multi-cursor on <Up>)")
			local lazy_ok, lazy = pcall(require, "lazy")
			check(lazy_ok, "lazy.nvim loaded")
			if lazy_ok then
				local n = #lazy.plugins()
				check(n > 90, ("%d plugins configured"):format(n))
			end
			for line in vim.api.nvim_exec2("messages", { output = true }).output:gmatch("[^\n]+") do
				if line:match("^E%d+:") or line:match("^Error") or line:match("stack traceback") then
					table.insert(errors, line:sub(1, 300))
				end
			end
			for _, l in ipairs(out) do io.stdout:write(l .. "\n") end
			if #errors > 0 then
				io.stdout:write("errors:\n")
				for _, e in ipairs(errors) do io.stdout:write("  " .. e .. "\n") end
				vim.cmd("cquit 1")
			else
				vim.cmd("qall!")
			end
		end, tonumber(vim.env.NVIM_SMOKE_WAIT_MS or "15000"))
	end,
})
