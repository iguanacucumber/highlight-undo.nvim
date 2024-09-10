local api = vim.api
local M = {
	config = {
		highlight_for_count = true, -- Should '3p' or '5u' be highlighted
		duration = 300, -- Time in ms for the highlight
		after_keymaps = function() end, -- Any keymaps you might wanna add after the keymaps set by this plugin
		actions = {
			Undo = {
				disabled = false, -- Useful when debugging
				fg = "#dcd7ba", -- colors
				bg = "#2d4f67",
				mode = "n", -- The mode(s)
				keymap = "u", -- mapping
				cmd = "undo", -- Vim command
				opts = {}, -- silent = true, desc = "", ...
			},
			Redo = { keymap = "<C-r>", cmd = "redo" }, -- Actions can be made as easely as this
			Pasted = {
				keymap = "p",
				cmd = "put",
				cmd_args = function() -- This function needs to return a string as a parameter to cmd (or it can do stuff just after the command)
					return vim.v.register -- Return the register
				end,
			},
			InlinePasted = {
				keymap = "P",
				cmd = function()
					local line = vim.api.nvim_get_current_line() -- Get the current line
					local cursor_pos = vim.api.nvim_win_get_cursor(0) -- Get the cursor position (row, col)
					local col = cursor_pos[2]

					local clipboard_data = vim.fn.getreg(vim.v.register)

					-- Insert clipboard data at the cursor position
					local new_line = line:sub(1, col) .. clipboard_data .. line:sub(col + 1)
					vim.api.nvim_set_current_line(new_line)
				end,
			},
		},
	},
	timer = vim.uv.new_timer(),
	should_detach = true,
	current_hlgroup = nil,
}

local usage_namespace = api.nvim_create_namespace("highlight_action")

function M.call_original_keymap(map)
	if type(map) == "string" then
		vim.cmd(map)
	elseif type(map) == "function" then
		map()
	end
end

function M.on_bytes(
	ignored, ---@diagnostic disable-line
	bufnr, ---@diagnostic disable-line
	changedtick, ---@diagnostic disable-line
	start_row, ---@diagnostic disable-line
	start_column, ---@diagnostic disable-line
	byte_offset, ---@diagnostic disable-line
	old_end_row, ---@diagnostic disable-line
	old_end_col, ---@diagnostic disable-line
	old_end_byte, ---@diagnostic disable-line
	new_end_row, ---@diagnostic disable-line
	new_end_col, ---@diagnostic disable-line
	new_end_byte ---@diagnostic disable-line
)
	if M.should_detach then
		return true
	end
	-- defer highligh till after changes take place..
	local num_lines = api.nvim_buf_line_count(0)
	local end_row = start_row + new_end_row
	local end_col = start_column + new_end_col
	if end_row >= num_lines then
		-- we are past the last line. highligh till the last column
		end_col = #api.nvim_buf_get_lines(0, -2, -1, false)[1]
	end
	vim.schedule(function()
		vim.highlight.range(
			bufnr,
			usage_namespace,
			M.current_hlgroup,
			{ start_row, start_column },
			{ end_row, end_col }
		)
		M.clear_highlights(bufnr)
	end)
	--detach
	-- return true
end

function M.highlight_action(bufnr, hlgroup, command)
	M.current_hlgroup = hlgroup
	api.nvim_buf_attach(bufnr, false, {
		on_bytes = M.on_bytes,
	})
	M.should_detach = false
	if M.config.highlight_for_count then
		for _ = 1, vim.v.count1 do
			command()
		end
	else
		command()
	end
	M.should_detach = true
end

function M.clear_highlights(bufnr)
	M.timer:stop()
	M.timer:start(
		M.config.duration,
		0,
		vim.schedule_wrap(function()
			api.nvim_buf_clear_namespace(bufnr, usage_namespace, 0, -1)
		end)
	)
end

---makes highlight-undo respect `foldopen=undo` (#18)
local function openFoldsOnUndo()
	if vim.tbl_contains(vim.opt.foldopen:get(), "undo") then
		vim.cmd.normal({ "zv", bang = true })
	end
end

function M.setup(config)
	M.config = vim.tbl_deep_extend("keep", config or {}, M.config)

	local function KeymapHighlights(action)
		local type = M.config.actions[action]

		if type.fg == nil then
			type.fg = "#dcd7ba"
		end

		if type.bg == nil then
			type.bg = "#2d4f67"
		end

		if type.mode == nil then
			type.mode = "n"
		end

		if type.opts == nil then
			type.opts = {}
		end

		if type.disabled then
			return
		end

		api.nvim_set_hl(0, "Highlight" .. action, { fg = type.fg, bg = type.bg })
		vim.keymap.set(type.mode, type.keymap, function()
			if M.config.highlight_for_count or vim.v.count == 0 then
				-- Highlight action and run the original keymap command
				M.highlight_action(0, "Highlight" .. action, function()
					if type.cmd_args ~= nil then
						M.call_original_keymap(type.cmd .. type.cmd_args())
					else
						M.call_original_keymap(type.cmd)
					end
				end)
			else
				-- Handle the case where the count is used, e.g., '3p'
				local keys = vim.api.nvim_replace_termcodes(vim.v.count .. type.keymap, true, false, true)
				vim.api.nvim_feedkeys(keys, "n", false)
			end

			-- Handle undo/redo special case for opening folds
			if action == "Undo" or action == "Redo" then
				openFoldsOnUndo()
			end
		end, type.opts)
	end

	-- Iterate over all actions and apply keymap highlights
	for key in pairs(M.config.actions) do
		KeymapHighlights(key)
	end

	M.config.after_keymaps()
end
return M
