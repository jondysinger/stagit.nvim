if vim.g.loaded_stagit == 1 then
  return
end

vim.g.loaded_stagit = 1

vim.api.nvim_create_user_command("StagitToggle", function()
  require("stagit.panel").toggle()
end, { desc = "Toggle the stagit panel" })

vim.api.nvim_create_user_command("StagitRefresh", function()
  require("stagit.panel").refresh()
end, { desc = "Refresh the stagit panel" })

vim.api.nvim_create_user_command("StagitCommit", function()
  require("stagit.commit").open()
end, { desc = "Open the stagit commit popup" })
