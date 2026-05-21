local config = require("stagit.config")
local git = require("stagit.git")
local state = require("stagit.state")
local util = require("stagit.util")

local M = {}

local function resolve_repo_root()
  if state.panel_repo_root then
    return state.panel_repo_root
  end

  local current_name = vim.api.nvim_buf_get_name(0)
  return git.find_repo_root(current_name ~= "" and current_name or vim.fn.getcwd())
end

local function close_commit_window()
  if state.commit and util.is_valid_win(state.commit.win) then
    vim.api.nvim_win_close(state.commit.win, true)
  end
  state.commit = nil
end

local function submit_message()
  if not state.commit or not util.is_valid_buf(state.commit.buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.commit.buf, 0, -1, false)
  local message = vim.trim(table.concat(lines, "\n"))
  if message == "" then
    util.notify("commit message cannot be empty", vim.log.levels.WARN)
    return
  end

  local tempname = vim.fn.tempname()
  vim.fn.writefile(lines, tempname)

  local ok, err = git.commit(state.commit.repo_root, tempname)
  vim.fn.delete(tempname)

  if not ok then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  close_commit_window()
  require("stagit.panel").refresh()
  util.notify("commit created")
end

function M.close()
  close_commit_window()
end

function M.open(repo_root)
  repo_root = repo_root or resolve_repo_root()
  if not repo_root then
    util.notify("not inside a git repository", vim.log.levels.ERROR)
    return
  end

  close_commit_window()

  local mappings = config.get().mappings.commit
  local width = math.min(80, math.max(50, vim.o.columns - 8))
  local height = math.min(14, math.max(8, vim.o.lines - 8))
  local geometry = util.window_center(width, height)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = geometry.relative,
    row = geometry.row,
    col = geometry.col,
    width = geometry.width,
    height = geometry.height,
    border = "rounded",
    title = (" stagit commit · %s to submit "):format(mappings.submit),
    title_pos = "center",
    style = "minimal",
  })

  state.commit = {
    repo_root = repo_root,
    buf = buf,
    win = win,
  }

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "gitcommit"
  vim.wo[win].wrap = true

  util.buf_set_lines(buf, {
    "",
  })

  util.set_buf_map(buf, "n", mappings.submit, submit_message, "Submit commit")
  util.set_buf_map(buf, "i", mappings.submit, function()
    vim.schedule(submit_message)
  end, "Submit commit")
  util.set_buf_map(buf, "n", mappings.cancel_normal, function()
    M.close()
  end, "Cancel commit")
  util.set_buf_map(buf, "i", mappings.cancel_insert, function()
    vim.schedule(function()
      M.close()
    end)
  end, "Cancel commit")

  vim.cmd("startinsert")
end

return M
