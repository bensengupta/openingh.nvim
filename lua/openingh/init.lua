local utils = require("openingh.utils")
local M = {}

function M.setup()
  -- get the current working directory and set the url
  local current_buffer = vim.fn.expand("%:p:h"):gsub("%[", "\\["):gsub("%]", "\\]")
  local remote = utils.get_default_remote()
  local repo_url = vim.fn.system(string.format([[git -C "%s" config --get remote.%s.url]], current_buffer, remote))

  if repo_url:len() == 0 then
    M.is_no_git_origin = true
    vim.g.openingh = false
    return
  end

  local gh = utils.parse_gh_remote(repo_url)
  if gh == nil then
    print("Error parsing GitHub remote URL")
    vim.g.openingh = false
    return
  end

  local resolved_host = gh.host
  if gh.protocol == "ssh" then
    resolved_host = utils.resolve_ssh_host(gh.host)
  end

  M.repo_url = string.format("http://%s/%s/%s", resolved_host, gh.user_or_org, gh.reponame)
end

M.priority = { BRANCH = 1, COMMIT = 2 }

local function get_current_branch_or_commit_with_priority(priority)
  if priority == M.priority.BRANCH then
    return utils.get_current_branch_or_commit()
  elseif priority == M.priority.COMMIT then
    return utils.get_current_commit_or_branch()
  else
    return utils.get_current_branch_or_commit()
  end
end

function M.get_file_url(
  priority,
  --[[optional]]
  branch,
  --[[optional]]
  range_start,
  --[[optional]]
  range_end
)
  -- make sure to update the current directory
  M.setup()
  if M.is_no_git_origin then
    utils.print_no_remote_message()
    return
  end

  local file_path = utils.get_current_relative_file_path()

  -- if there is no buffer opened
  if file_path == "/" then
    utils.notify("There is no active file to open!", vim.log.levels.ERROR)
    return
  end

  local rev = get_current_branch_or_commit_with_priority(priority)
  if branch ~= nil then
    rev = branch
  end

  local file_page_url = M.repo_url .. "/blob/" .. rev .. file_path

  if range_start and not range_end then
    file_page_url = file_page_url .. "#L" .. range_start
  end

  if range_start and range_end then
    file_page_url = file_page_url .. "#L" .. range_start .. "-L" .. range_end
  end

  return file_page_url
end

function M.get_repo_url(priority)
  -- make sure to update the current directory
  M.setup()
  if M.is_no_git_origin then
    utils.print_no_remote_message()
    return
  end

  local url = M.repo_url .. "/tree/" .. get_current_branch_or_commit_with_priority(priority)
  return url
end

function M.open_url(url)
  if not utils.open_url(url) then
    utils.notify("Could not open the built URL " .. url, vim.log.levels.ERROR)
  end
end

return M
