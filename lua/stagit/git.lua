local util = require("stagit.util")

local M = {}

local function run_git(args, opts)
  opts = opts or {}

  local command = { "git" }
  vim.list_extend(command, args)

  local result = vim.system(command, {
    cwd = opts.cwd,
    text = true,
    stdin = opts.stdin,
  }):wait()

  local stdout = result.stdout or ""
  local stderr = vim.trim(result.stderr or "")

  if result.code ~= 0 then
    return nil, (stderr ~= "" and stderr or "git command failed"), result.code
  end

  return stdout, nil, result.code
end

local function parse_nul_list(output)
  if output == "" then
    return {}
  end

  local items = {}
  for item in output:gmatch("([^%z]+)") do
    table.insert(items, item)
  end
  return items
end

local function get_command_cwd(start_path)
  local path = start_path

  if not path or path == "" then
    return vim.fn.getcwd()
  end

  if path:match("^%w[%w+.-]*://") then
    return vim.fn.getcwd()
  end

  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == "directory" then
    return path
  end

  if stat and stat.type == "file" then
    return util.path_parent(path)
  end

  return vim.fn.getcwd()
end

local function is_missing_blob_error(err)
  return err:find("exists on disk, but not in", 1, true)
    or err:find("pathspec", 1, true)
    or err:find("does not exist", 1, true)
    or err:find("bad revision", 1, true)
    or err:find("invalid object name", 1, true)
end

function M.find_repo_root(start_path)
  local cwd = get_command_cwd(start_path)
  local stdout = run_git({ "rev-parse", "--show-toplevel" }, { cwd = cwd })
  if not stdout then
    return nil
  end
  return vim.trim(stdout)
end

function M.ensure_available(repo_root)
  local _, err = run_git({ "rev-parse", "--show-toplevel" }, { cwd = repo_root or vim.fn.getcwd() })
  if err then
    return false, err
  end
  return true
end

function M.current_branch(repo_root)
  local stdout = run_git({ "branch", "--show-current" }, { cwd = repo_root })
  if stdout and vim.trim(stdout) ~= "" then
    return vim.trim(stdout)
  end

  stdout = run_git({ "rev-parse", "--abbrev-ref", "HEAD" }, { cwd = repo_root })
  return stdout and vim.trim(stdout) or "(detached)"
end

function M.repo_status(repo_root)
  local staged_output, staged_err = run_git({
    "diff",
    "--cached",
    "--name-only",
    "-z",
    "--diff-filter=ACDMRTUXB",
    "--",
  }, { cwd = repo_root })
  if not staged_output then
    return nil, staged_err
  end

  local unstaged_output, unstaged_err = run_git({
    "diff",
    "--name-only",
    "-z",
    "--diff-filter=ACDMRTUXB",
    "--",
  }, { cwd = repo_root })
  if not unstaged_output then
    return nil, unstaged_err
  end

  local untracked_output, untracked_err = run_git({
    "ls-files",
    "--others",
    "--exclude-standard",
    "-z",
  }, { cwd = repo_root })
  if not untracked_output then
    return nil, untracked_err
  end

  local staged = util.unique(parse_nul_list(staged_output))
  local unstaged = util.unique(vim.list_extend(parse_nul_list(unstaged_output), parse_nul_list(untracked_output)))

  table.sort(staged)
  table.sort(unstaged)

  return {
    branch = M.current_branch(repo_root),
    staged = staged,
    unstaged = unstaged,
  }
end

local function read_revision(repo_root, spec)
  local output, err = run_git({ "show", spec }, {
    cwd = repo_root,
  })
  if output == nil then
    if is_missing_blob_error(err) then
      return ""
    end
    return nil, err
  end

  if output:find("\0", 1, true) then
    return nil, "binary files are not supported"
  end

  return output
end

local function read_worktree_file(repo_root, path)
  local content = util.read_file(vim.fs.joinpath(repo_root, path))
  if content == nil then
    return ""
  end

  if content:find("\0", 1, true) then
    return nil, "binary files are not supported"
  end

  return content
end

function M.file_snapshots(repo_root, path, section)
  local left_label
  local right_label
  local left_content
  local right_content

  if section == "staged" then
    left_label = "HEAD"
    right_label = "INDEX"
    left_content = read_revision(repo_root, "HEAD:" .. path)
    right_content = read_revision(repo_root, ":" .. path)
  else
    left_label = "INDEX"
    right_label = "WORKTREE"
    left_content = read_revision(repo_root, ":" .. path)
    right_content = read_worktree_file(repo_root, path)
  end

  if left_content == nil then
    return nil, nil, left_label, right_label
  end

  if right_content == nil then
    return nil, nil, left_label, right_label
  end

  return util.split_lines(left_content), util.split_lines(right_content), left_label, right_label
end

function M.file_patch(repo_root, path, section, unified)
  local args = {
    "diff",
    "--no-ext-diff",
    "--no-color",
    "--src-prefix=a/",
    "--dst-prefix=b/",
    ("-U%d"):format(unified or 0),
  }

  if section == "staged" then
    table.insert(args, "--cached")
  end

  vim.list_extend(args, { "--", path })

  local output, err = run_git(args, { cwd = repo_root })
  if output == nil then
    return nil, err
  end

  return output
end

function M.stage_file(repo_root, path)
  local _, err = run_git({ "add", "--", path }, { cwd = repo_root })
  return err == nil, err
end

function M.unstage_file(repo_root, path)
  local _, err = run_git({ "restore", "--staged", "--", path }, { cwd = repo_root })
  return err == nil, err
end

function M.discard_worktree_file(repo_root, path)
  local _, err = run_git({ "restore", "--worktree", "--", path }, { cwd = repo_root })
  return err == nil, err
end

function M.discard_all_file(repo_root, path)
  local _, err = run_git({ "restore", "--source=HEAD", "--staged", "--worktree", "--", path }, { cwd = repo_root })
  return err == nil, err
end

function M.apply_patch(repo_root, patch, opts)
  opts = opts or {}

  local args = {
    "apply",
    "--whitespace=nowarn",
    "--unidiff-zero",
    "-",
  }

  if opts.reverse then
    table.insert(args, 3, "--reverse")
  end

  if opts.cached then
    table.insert(args, 3, "--cached")
  end

  local _, err = run_git(args, {
    cwd = repo_root,
    stdin = patch,
  })

  return err == nil, err
end

function M.commit(repo_root, message_file)
  local _, err = run_git({ "commit", "--file", message_file }, { cwd = repo_root })
  return err == nil, err
end

return M
