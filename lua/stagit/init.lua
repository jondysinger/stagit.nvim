local config = require("stagit.config")

local M = {}

function M.setup(opts)
  local values = config.setup(opts)

  if values.mappings.panel_toggle then
    vim.keymap.set("n", values.mappings.panel_toggle, function()
      require("stagit.panel").toggle()
    end, { desc = "Toggle the stagit panel" })
  end
end

return M
