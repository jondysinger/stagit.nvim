local config = require("stagit.config")
local git = require("stagit.git")
local state = require("stagit.state")
local util = require("stagit.util")

local M = {}

local function resolve_repo_root()
  if state.panel_repo_root then
    return state.panel_repo_root
  end

  if state.active_diff and state.active_diff.repo_root then
    return state.active_diff.repo_root
  end

  local current_name = vim.api.nvim_buf_get_name(0)
  if vim.startswith(current_name, "stagit://") then
    return git.find_repo_root(vim.fn.getcwd())
  end
  return git.find_repo_root(current_name ~= "" and current_name or vim.fn.getcwd())
end

local function current_row()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  return state.panel_rows[line]
end

local function ensure_panel_buffer()
  if util.is_valid_buf(state.panel_buf) then
    return state.panel_buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  state.panel_buf = buf

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "stagit-panel"

  local mappings = config.get().mappings.panel
  util.set_buf_map(buf, "n", mappings.open_diff, function()
    M.open_selected_diff()
  end, "Open diff")
  util.set_buf_map(buf, "n", mappings.stage_file, function()
    M.stage_selected_file()
  end, "Stage or unstage file")
  util.set_buf_map(buf, "n", mappings.discard_file, function()
    M.discard_selected_file()
  end, "Discard file changes")
  util.set_buf_map(buf, "n", mappings.commit, function()
    require("stagit.commit").open()
  end, "Open commit popup")
  util.set_buf_map(buf, "n", mappings.refresh, function()
    M.refresh()
  end, "Refresh panel")
  util.set_buf_map(buf, "n", mappings.close, function()
    M.close()
  end, "Close panel")

  return buf
end

local function ensure_panel_window()
  if util.is_valid_win(state.panel_win) then
    return state.panel_win
  end

  local width = config.get().panel.width

  vim.cmd("topleft vertical new")
  local win = vim.api.nvim_get_current_win()
  state.panel_win = win

  vim.api.nvim_win_set_width(win, width)
  vim.wo[win].winfixwidth = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].foldcolumn = "0"

  vim.api.nvim_win_set_buf(win, ensure_panel_buffer())
  return win
end

local function set_panel_lines(status)
  local lines = {
    "Branch: " .. status.branch,
    "",
    "Staged:",
  }

  state.panel_rows = {}

  if #status.staged == 0 then
    table.insert(lines, "  (none)")
  else
    for _, path in ipairs(status.staged) do
      table.insert(lines, "  " .. path)
      state.panel_rows[#lines] = {
        type = "file",
        path = path,
        section = "staged",
      }
    end
  end

  table.insert(lines, "")
  table.insert(lines, "Unstaged:")

  if #status.unstaged == 0 then
    table.insert(lines, "  (none)")
  else
    for _, path in ipairs(status.unstaged) do
      table.insert(lines, "  " .. path)
      state.panel_rows[#lines] = {
        type = "file",
        path = path,
        section = "unstaged",
      }
    end
  end

  local buf = ensure_panel_buffer()
  util.with_modifiable(buf, function()
    util.buf_set_lines(buf, lines)
  end)
  vim.bo[buf].modifiable = false
end

local function refresh_active_diff_if_needed(path)
  local session = state.active_diff
  if not session or session.path ~= path then
    return
  end

  require("stagit.diff").reopen_active()
end

local function panel_confirm(prompt)
  if not config.get().ui.confirm_discards then
    return true
  end
  return util.confirm(prompt)
end

function M.open()
  local repo_root = resolve_repo_root()
  if not repo_root then
    util.notify("not inside a git repository", vim.log.levels.ERROR)
    return
  end

  local ok, err = git.ensure_available(repo_root)
  if not ok then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  state.panel_repo_root = repo_root
  local win = ensure_panel_window()
  vim.api.nvim_set_current_win(win)
  M.refresh()
end

function M.close()
  if util.is_valid_win(state.panel_win) then
    vim.api.nvim_win_close(state.panel_win, true)
  end
  state.panel_win = nil
end

function M.toggle()
  if util.is_valid_win(state.panel_win) then
    M.close()
  else
    M.open()
  end
end

function M.refresh()
  local repo_root = resolve_repo_root()
  if not repo_root then
    util.notify("not inside a git repository", vim.log.levels.ERROR)
    return
  end

  state.panel_repo_root = repo_root
  ensure_panel_window()

  local status, err = git.repo_status(repo_root)
  if not status then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  set_panel_lines(status)
end

function M.open_selected_diff()
  local row = current_row()
  if not row or row.type ~= "file" then
    return
  end

  require("stagit.diff").open_file_diff(state.panel_repo_root, row.path, row.section)
end

function M.stage_selected_file()
  local row = current_row()
  if not row or row.type ~= "file" then
    return
  end

  local ok
  local err

  if row.section == "staged" then
    ok, err = git.unstage_file(state.panel_repo_root, row.path)
  else
    ok, err = git.stage_file(state.panel_repo_root, row.path)
  end

  if not ok then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  M.refresh()
  refresh_active_diff_if_needed(row.path)
end

function M.discard_selected_file()
  local row = current_row()
  if not row or row.type ~= "file" then
    return
  end

  local prompt
  local ok
  local err

  if row.section == "staged" then
    prompt = ("Discard all changes for %s?"):format(row.path)
  else
    prompt = ("Discard unstaged changes for %s?"):format(row.path)
  end

  if not panel_confirm(prompt) then
    return
  end

  if row.section == "staged" then
    ok, err = git.discard_all_file(state.panel_repo_root, row.path)
  else
    ok, err = git.discard_worktree_file(state.panel_repo_root, row.path)
  end

  if not ok then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  M.refresh()
  refresh_active_diff_if_needed(row.path)
end

return M
