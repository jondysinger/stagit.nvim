local defaults = {
  panel = {
    width = 36,
    position = "left",
  },
  ui = {
    confirm_discards = true,
  },
  mappings = {
    panel_toggle = "<leader>gg",
    panel = {
      open_diff = "<CR>",
      stage_file = "s",
      discard_file = "d",
      commit = "c",
      refresh = "r",
      close = "q",
    },
    diff = {
      next_hunk = "]h",
      prev_hunk = "[h",
      stage_hunk = "s",
      discard_hunk = "d",
      close = "q",
    },
    commit = {
      submit = "<C-s>",
      cancel_normal = "q",
      cancel_insert = "<C-c>",
    },
  },
}

local M = {
  values = vim.deepcopy(defaults),
}

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return M.values
end

function M.get()
  return M.values
end

return M
