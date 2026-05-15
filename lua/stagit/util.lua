local M = {}

function M.notify(message, level)
  vim.notify("stagit.nvim: " .. message, level or vim.log.levels.INFO)
end

function M.is_valid_buf(buf)
  return type(buf) == "number" and buf > 0 and vim.api.nvim_buf_is_valid(buf)
end

function M.is_valid_win(win)
  return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end

function M.with_modifiable(buf, fn)
  local previous = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  local ok, result = pcall(fn)
  vim.bo[buf].modifiable = previous
  if not ok then
    error(result)
  end
  return result
end

function M.confirm(prompt)
  return vim.fn.confirm(prompt, "&Yes\n&No", 2) == 1
end

function M.filetype_for(path)
  return vim.filetype.match({ filename = path }) or ""
end

function M.split_lines(text)
  if text == "" then
    return {}
  end

  local lines = vim.split(text, "\n", { plain = true, trimempty = false })
  if lines[#lines] == "" then
    table.remove(lines, #lines)
  end
  return lines
end

function M.read_file(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end

  local content = file:read("*a")
  file:close()
  return content
end

function M.buf_set_lines(buf, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if #lines == 0 then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  end
end

function M.set_buf_map(buf, mode, lhs, rhs, desc)
  if not lhs or lhs == "" then
    return
  end

  vim.keymap.set(mode, lhs, rhs, {
    buffer = buf,
    silent = true,
    nowait = true,
    desc = desc,
  })
end

function M.clamp_line(buf, line)
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count == 0 then
    return 1
  end
  return math.max(1, math.min(line, line_count))
end

function M.unique(items)
  local seen = {}
  local result = {}

  for _, item in ipairs(items) do
    if item ~= "" and not seen[item] then
      seen[item] = true
      table.insert(result, item)
    end
  end

  return result
end

function M.window_center(width, height)
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  return {
    relative = "editor",
    row = math.max(1, math.floor((lines - height) / 2)),
    col = math.max(0, math.floor((columns - width) / 2)),
    width = width,
    height = height,
  }
end

function M.path_parent(path)
  return vim.fs.dirname(path) or path
end

return M
