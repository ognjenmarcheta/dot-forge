return {
	{
		"ravitemer/mcphub.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim", -- Required for Job and HTTP requests
		},
		-- comment the following line to ensure hub will be ready at the earliest
		cmd = "MCPHub", -- lazy load by default
		-- Linux: `npm install -g` needs sudo with a system Node, so install mcp-hub
		-- inside the plugin folder instead (bundled binary, no root needed).
		build = "bundled_build.lua",
		config = function()
			require("mcphub").setup({
				use_bundled_binary = true,
				extensions = {
					avante = {
						make_slash_commands = true, -- make /slash commands from MCP server prompts
					},
				},
			})
		end,
	},
}
