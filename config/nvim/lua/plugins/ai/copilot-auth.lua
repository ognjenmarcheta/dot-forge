-- copilot.lua on its own (not only as an avante dependency), so `:Copilot auth`
-- works on a fresh machine before avante is enabled. Inline suggestions stay
-- off: completions come through blink-copilot, chat through avante.
return {
	{
		"zbirenbaum/copilot.lua",
		cmd = "Copilot",
		event = "InsertEnter",
		opts = {
			suggestion = { enabled = false },
			panel = { enabled = false },
		},
	},
}
