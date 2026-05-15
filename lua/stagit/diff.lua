local config = require("stagit.config")
local git = require("stagit.git")
local state = require("stagit.state")
local util = require("stagit.util")

local M = {}

local ns = vim.api.nvim_create_namespace("stagit-diff")

local function ensure_highlights()
  vim.api.nvim_set_hl(0, "StagitStagedSign", { fg = "#98c379" })
  vim.api.nvim_set_hl(0, "StagitUnstagedSign", { fg = "#e5c07b" })
end

local function diffopt_with_full_context(value)
  local updated = value:gsub("context:%d+", "")
  updated = updated:gsub(",,", ",")
  updated = updated:gsub("^,", "")
  updated = updated:gsub(",$", "")

  if updated ~= "" then
    return updated .. ",context:999999"
  end

  return "context:999999"
end

local function close_window_if_valid(win)
  if util.is_valid_win(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function close_buffer_if_valid(buf)
  if util.is_valid_buf(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

local function close_active_windows()
  local session = state.active_diff
  if not session then
    return
  end

  if session.previous_diffopt then
    vim.o.diffopt = session.previous_diffopt
  end

  close_window_if_valid(session.left_win)
  close_window_if_valid(session.right_win)
  close_buffer_if_valid(session.left_buf)
  close_buffer_if_valid(session.right_buf)
  state.active_diff = nil
end

local function is_active_diff_window(win)
  local session = state.active_diff
  if not session then
    return false
  end

  return win == session.left_win or win == session.right_win
end

local function is_normal_window(win)
  if not util.is_valid_win(win) then
    return false
  end

  local config = vim.api.nvim_win_get_config(win)
  return config.relative == ""
end

local function parse_hunks(patch)
  if patch == "" then
    return {}
  end

  local header_lines = {}
  local hunks = {}
  local current = nil

  for line in (patch .. "\n"):gmatch("(.-)\n") do
    local left_start, left_count, right_start, right_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
    if left_start then
      if current then
        table.insert(hunks, current)
      end

      current = {
        lines = { line },
        left_start = tonumber(left_start),
        left_count = left_count == "" and 1 or tonumber(left_count),
        right_start = tonumber(right_start),
        right_count = right_count == "" and 1 or tonumber(right_count),
      }
    elseif current then
      table.insert(current.lines, line)
    else
      table.insert(header_lines, line)
    end
  end

  if current then
    table.insert(hunks, current)
  end

  local header = table.concat(header_lines, "\n")
  if header ~= "" then
    header = header .. "\n"
  end

  for _, hunk in ipairs(hunks) do
    hunk.patch = header .. table.concat(hunk.lines, "\n") .. "\n"
  end

  return hunks
end

local function line_anchor(hunk, side)
  local start = hunk[side .. "_start"]
  local count = hunk[side .. "_count"]

  if count == 0 then
    return start
  end

  return start
end

local function line_in_hunk(line, start, count)
  if count == 0 then
    return line == start
  end

  return line >= start and line <= (start + count - 1)
end

local function current_session()
  local session = state.active_diff
  if not session then
    return nil
  end

  local buf = vim.api.nvim_get_current_buf()
  if buf ~= session.left_buf and buf ~= session.right_buf then
    return nil
  end

  return session
end

local function current_hunk()
  local session = current_session()
  if not session then
    return nil, nil, nil
  end

  local buf = vim.api.nvim_get_current_buf()
  local side = buf == session.left_buf and "left" or "right"
  local line = vim.api.nvim_win_get_cursor(0)[1]

  for index, hunk in ipairs(session.hunks) do
    if line_in_hunk(line, hunk[side .. "_start"], hunk[side .. "_count"]) then
      return hunk, index, session
    end
  end

  return nil, nil, session
end

local function move_to_hunk(direction)
  local session = current_session()
  if not session then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local side = buf == session.left_buf and "left" or "right"
  local line = vim.api.nvim_win_get_cursor(0)[1]

  local candidate = nil
  if direction > 0 then
    for _, hunk in ipairs(session.hunks) do
      if line_anchor(hunk, side) > line then
        candidate = hunk
        break
      end
    end
    candidate = candidate or session.hunks[1]
  else
    for index = #session.hunks, 1, -1 do
      local hunk = session.hunks[index]
      if line_anchor(hunk, side) < line then
        candidate = hunk
        break
      end
    end
    candidate = candidate or session.hunks[#session.hunks]
  end

  if not candidate then
    return
  end

  local target = util.clamp_line(buf, line_anchor(candidate, side))
  vim.api.nvim_win_set_cursor(0, { target, 0 })
end

local function configure_diff_window(win)
  vim.wo[win].wrap = false
  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].signcolumn = "yes"
  vim.wo[win].scrollbind = true
  vim.wo[win].cursorbind = true
end

local function configure_diff_buffer(buf, path, lines, label)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.bo[buf].filetype = util.filetype_for(path)

  util.buf_set_lines(buf, lines)
  vim.api.nvim_buf_set_name(buf, ("stagit://%s/%s"):format(label, path))

  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
end

local function render_hunk_signs(session)
  local sign_hl = session.section == "staged" and "StagitStagedSign" or "StagitUnstagedSign"
  local sign_text = session.section == "staged" and "S" or "U"
  local buf = session.right_buf

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(buf)
  for _, hunk in ipairs(session.hunks) do
    local start = hunk.right_start
    local count = hunk.right_count
    local mark_start = count == 0 and math.min(start, math.max(line_count, 1)) or start
    local mark_end = count == 0 and mark_start or (start + count - 1)

    if line_count == 0 then
      mark_start = 1
      mark_end = 1
    end

    for line = mark_start, math.max(mark_start, mark_end) do
      local clamped = math.max(1, math.min(line, math.max(line_count, 1)))
      vim.api.nvim_buf_set_extmark(buf, ns, clamped - 1, 0, {
        sign_text = sign_text,
        sign_hl_group = sign_hl,
      })
    end
  end
end

local function buffer_map_diff_actions(buf)
  local mappings = config.get().mappings.diff

  util.set_buf_map(buf, "n", mappings.next_hunk, function()
    move_to_hunk(1)
  end, "Next hunk")
  util.set_buf_map(buf, "n", mappings.prev_hunk, function()
    move_to_hunk(-1)
  end, "Previous hunk")
  util.set_buf_map(buf, "n", mappings.stage_hunk, function()
    M.toggle_stage_hunk()
  end, "Stage or unstage hunk")
  util.set_buf_map(buf, "n", mappings.discard_hunk, function()
    M.discard_hunk()
  end, "Discard hunk")
  util.set_buf_map(buf, "n", mappings.close, function()
    M.close_active()
  end, "Close diff")
end

local function find_content_anchor_window()
  local preferred = vim.fn.win_getid(vim.fn.winnr("#"))
  if is_normal_window(preferred) and preferred ~= state.panel_win and not is_active_diff_window(preferred) then
    return preferred
  end

  local current = vim.api.nvim_get_current_win()
  if is_normal_window(current) and current ~= state.panel_win and not is_active_diff_window(current) then
    return current
  end

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_normal_window(win) and win ~= state.panel_win and not is_active_diff_window(win) then
      return win
    end
  end
end

local function prepare_diff_windows()
  local existing = state.active_diff
  if existing and util.is_valid_win(existing.left_win) then
    local left_win = existing.left_win

    pcall(vim.api.nvim_win_call, left_win, function()
      vim.cmd("diffoff")
    end)
    if util.is_valid_win(existing.right_win) then
      pcall(vim.api.nvim_win_call, existing.right_win, function()
        vim.cmd("diffoff")
      end)
    end

    close_window_if_valid(existing.right_win)
    close_buffer_if_valid(existing.right_buf)
    state.active_diff = nil

    vim.api.nvim_set_current_win(left_win)
    vim.cmd("rightbelow vsplit")
    local right_win = vim.api.nvim_get_current_win()

    return left_win, right_win
  end

  local anchor = find_content_anchor_window()
  if anchor then
    vim.api.nvim_set_current_win(anchor)
    local left_win = anchor
    vim.cmd("rightbelow vsplit")
    local right_win = vim.api.nvim_get_current_win()

    return left_win, right_win
  end

  local fallback = util.is_valid_win(state.panel_win) and state.panel_win or vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(fallback)

  vim.cmd("rightbelow vsplit")
  local left_win = vim.api.nvim_get_current_win()
  vim.cmd("rightbelow vsplit")
  local right_win = vim.api.nvim_get_current_win()

  return left_win, right_win
end

local function reopen_or_close(repo_root, path, section, notify_on_empty)
  local patch, err = git.file_patch(repo_root, path, section, 0)
  if not patch then
    util.notify(err, vim.log.levels.ERROR)
    return false
  end

  if patch == "" then
    close_active_windows()
    if notify_on_empty then
      util.notify("no diff available for " .. path, vim.log.levels.WARN)
    end
    return false
  end

  M.open_file_diff(repo_root, path, section, patch)
  return true
end

function M.open_file_diff(repo_root, path, section, patch_override)
  ensure_highlights()

  local left_lines, right_lines, left_label, right_label = git.file_snapshots(repo_root, path, section)
  if not left_lines or not right_lines then
    util.notify(("unable to diff %s; binary files are not supported"):format(path), vim.log.levels.ERROR)
    return
  end

  local patch = patch_override
  if not patch then
    patch = git.file_patch(repo_root, path, section, 0)
    if not patch then
      util.notify("unable to generate diff for " .. path, vim.log.levels.ERROR)
      return
    end
  end

  local previous_diffopt = state.active_diff and state.active_diff.previous_diffopt or vim.o.diffopt
  vim.o.diffopt = diffopt_with_full_context(previous_diffopt)

  local left_win, right_win = prepare_diff_windows()
  local left_buf = vim.api.nvim_create_buf(false, true)
  local right_buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_win_set_buf(left_win, left_buf)
  vim.api.nvim_win_set_buf(right_win, right_buf)

  configure_diff_buffer(left_buf, path, left_lines, left_label)
  configure_diff_buffer(right_buf, path, right_lines, right_label)
  configure_diff_window(left_win)
  configure_diff_window(right_win)

  buffer_map_diff_actions(left_buf)
  buffer_map_diff_actions(right_buf)

  vim.api.nvim_set_current_win(left_win)
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(right_win)
  vim.cmd("diffthis")
  vim.wo[left_win].foldenable = false
  vim.wo[right_win].foldenable = false
  pcall(vim.cmd, "syncbind")

  local session = {
    repo_root = repo_root,
    path = path,
    section = section,
    previous_diffopt = previous_diffopt,
    left_win = left_win,
    right_win = right_win,
    left_buf = left_buf,
    right_buf = right_buf,
    left_label = left_label,
    right_label = right_label,
    hunks = parse_hunks(patch),
  }

  state.active_diff = session
  render_hunk_signs(session)

  vim.api.nvim_set_current_win(right_win)
  if session.hunks[1] then
    local target = util.clamp_line(right_buf, line_anchor(session.hunks[1], "right"))
    vim.api.nvim_win_set_cursor(right_win, { target, 0 })
  end
end

function M.reopen_active()
  local session = state.active_diff
  if not session then
    return
  end

  reopen_or_close(session.repo_root, session.path, session.section, false)
end

function M.close_active()
  close_active_windows()
end

function M.toggle_stage_hunk()
  local hunk, _, session = current_hunk()
  if not hunk or not session then
    util.notify("cursor is not on a hunk", vim.log.levels.WARN)
    return
  end

  local ok
  local err
  if session.section == "staged" then
    ok, err = git.apply_patch(session.repo_root, hunk.patch, {
      cached = true,
      reverse = true,
    })
  else
    ok, err = git.apply_patch(session.repo_root, hunk.patch, {
      cached = true,
      reverse = false,
    })
  end

  if not ok then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  require("stagit.panel").refresh()
  reopen_or_close(session.repo_root, session.path, session.section, false)
end

function M.discard_hunk()
  local hunk, _, session = current_hunk()
  if not hunk or not session then
    util.notify("cursor is not on a hunk", vim.log.levels.WARN)
    return
  end

  if config.get().ui.confirm_discards then
    if not util.confirm(("Discard %s hunk in %s?"):format(session.section, session.path)) then
      return
    end
  end

  local ok
  local err
  if session.section == "staged" then
    local status, status_err = git.repo_status(session.repo_root)
    if not status then
      util.notify(status_err, vim.log.levels.ERROR)
      return
    end

    if vim.tbl_contains(status.unstaged, session.path) then
      util.notify(
        "cannot discard a staged hunk while the file also has unstaged changes; unstage the hunk instead",
        vim.log.levels.WARN
      )
      return
    end

    ok, err = git.apply_patch(session.repo_root, hunk.patch, {
      cached = true,
      reverse = true,
    })
    if ok then
      ok, err = git.apply_patch(session.repo_root, hunk.patch, {
        cached = false,
        reverse = true,
      })
    end
  else
    ok, err = git.apply_patch(session.repo_root, hunk.patch, {
      cached = false,
      reverse = true,
    })
  end

  if not ok then
    util.notify(err, vim.log.levels.ERROR)
    return
  end

  require("stagit.panel").refresh()
  reopen_or_close(session.repo_root, session.path, session.section, false)
end

return M
