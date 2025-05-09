local M = {}

-- Notify the user that something went wrong
function M.notify(message, log_level)
  print(message)
  vim.notify({ message }, log_level, { title = "openingh.nvim" })
end

-- the missing split lua method to split a string
function M.split(string, char)
  local array = {}
  local reg = string.format("([^%s]+)", char)
  for mem in string.gmatch(string, reg) do
    table.insert(array, mem)
  end
  return array
end

-- trim extra spaces and newlines
-- useful when working with git commands returned values
function M.trim(string)
  return (string:gsub("^%s*(.-)%s*$", "%1"))
end

-- url encode
-- see: https://datatracker.ietf.org/doc/html/rfc3986#section-2.3
function M.encode_uri_component(string)
  return (string:gsub("[^%w_~%.%-]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- returns a table with the host, user/org and the reponame given a github remote url
-- nil is returned when the url cannot be parsed
function M.parse_gh_remote(url)
  -- url can be of type:
  -- http://github.com/user_or_org/reponame
  -- https://github.com/user_or_org/reponame
  -- https://gitlab.com/user_or_org/group/reponame
  -- git@some.github.com:user_or_org/reponame.git
  -- git@work:user_or_org/reponame.git
  -- ssh://git@some.github.com/user_or_org/reponame.git
  -- ssh://org-12345@some.github.com/org/reponame.git

  -- pattern reference: https://www.lua.org/manual/5.4/manual.html#6.4.1
  --
  -- notes:
  -- ^     matches beginning of the string
  -- [^@]+ matches one or more characters that are not "@"
  -- [^:]+ matches one or more characters that are not ":"
  -- (.+)  matches any character one or more times
  -- %S+   matches one or more non-whitespace characters
  --
  -- same patterns with spacing for readability:
  --   git   @ github.com : user_or_org / reponame.git
  -- ^ [^@]+ @ ([^:]+)    : (.+)        / (%S+)
  --
  --   https://  github.com / user_or_org / reponame
  -- ^ https?:// ([^/]+)    / (.+)        / (%S+)
  --
  --   ssh:// git   @ github.com / user_or_org / reponame.git
  -- ^ ssh:// [^@]+ @ ([^/]+)    / (.+)        / (%S+)
  local protocol = "ssh"
  local pattern = "^[^@]+@([^:]+):(.+)/(%S+)"
  if string.find(url, "^https?://") then
    protocol = "http"
    pattern = "^https?://([^/]+)/(.+)/(%S+)"
  elseif string.find(url, "^ssh://") then
    protocol = "ssh"
    pattern = "^ssh://[^@]+@([^/]+)/(.+)/(%S+)"
  end

  local matches = { string.find(url, pattern) }
  if matches[1] == nil then
    return nil
  end

  local _, _, host, user_or_org, reponame = unpack(matches)
  return { protocol = protocol, host = host, user_or_org = user_or_org, reponame = string.gsub(reponame, "%.git$", "") }
end

-- resolve the host with ssh
function M.resolve_ssh_host(host)
  local ssh_config = vim.fn.system("ssh -G " .. host)
  local resolved_hostname = ssh_config:match("hostname%s+(%S+)")
  if resolved_hostname then
    return resolved_hostname
  end
  return host
end

-- get the default push remote
function M.get_default_remote()
  -- will return origin by default
  local remote = vim.fn.system("git config remote.pushDefault")
  if remote == "" then
    return "origin"
  end
  return M.trim(remote)
end

-- get the remote default branch
function M.get_default_branch()
  -- will return origin/[branch_name]
  local remote = M.get_default_remote()
  local branch_with_origin = vim.fn.system("git rev-parse --abbrev-ref " .. remote .. "/HEAD")
  local branch_name = M.split(branch_with_origin, "/")[2]

  return M.trim(branch_name)
end

-- Checks if the supplied branch is available on the remote
function M.is_branch_upstreamed(branch)
  local remote = M.get_default_remote()
  local output = M.trim(vim.fn.system("git branch -r --list " .. remote .. "/" .. branch))
  if output:find(branch, 1, true) then
    return true
  end

  -- ls-remote is more expensive so only use it as a fallback
  output = M.trim(vim.fn.system("git ls-remote --exit-code --heads " .. remote .. " " .. branch))
  return output ~= ""
end

-- Get the current working branch
local function get_current_branch()
  return M.trim(vim.fn.system("git rev-parse --abbrev-ref HEAD"))
end

-- Get the commit hash of the most recent commit
local function get_current_commit_hash()
  return M.trim(vim.fn.system("git rev-parse HEAD"))
end

-- Checks if the supplied commit is available on the remote
function M.is_commit_upstreamed(commit_sha)
  local output = M.trim(vim.fn.system('git log --format="%H"'))
  return output:match(commit_sha) ~= nil
end

-- Returns the current branch or commit if they are available on remote
-- otherwise this will return the default branch of the repo
function M.get_current_branch_or_commit()
  local current_branch = get_current_branch()
  if current_branch ~= "HEAD" and M.is_branch_upstreamed(current_branch) then
    return M.encode_uri_component(current_branch)
  end

  local commit_hash = get_current_commit_hash()
  if current_branch == "HEAD" and M.is_commit_upstreamed(commit_hash) then
    return commit_hash
  end

  return M.encode_uri_component(M.get_default_branch())
end

-- Returns the current commit or branch if they are available on remote
-- otherwise this will return the default branch of the repo
-- (This function prioritizes commit than branch)
function M.get_current_commit_or_branch()
  local commit_hash = get_current_commit_hash()
  if M.is_commit_upstreamed(commit_hash) then
    return commit_hash
  end

  local current_branch = get_current_branch()
  if current_branch ~= "HEAD" and M.is_branch_upstreamed(current_branch) then
    return M.encode_uri_component(current_branch)
  end

  return M.encode_uri_component(M.get_default_branch())
end

-- get the active buf relative file path form the .git
function M.get_current_relative_file_path()
  -- we only want the active buffer name
  local absolute_file_path = vim.api.nvim_buf_get_name(0)
  local git_path = vim.fn.system("git rev-parse --show-toplevel")

  if vim.fn.has("win32") == 1 then
    absolute_file_path = string.gsub(absolute_file_path, "\\", "/")
  end

  local relative_file_path_components = M.split(string.sub(absolute_file_path, git_path:len() + 1), "/")
  local encoded_components = {}
  for i, path_component in pairs(relative_file_path_components) do
    table.insert(encoded_components, i, M.encode_uri_component(path_component))
  end

  return "/" .. table.concat(encoded_components, "/")
end

-- get the line number in the buffer
function M.get_line_number_from_buf()
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  return line_num
end

-- opens a url in the correct OS
function M.open_url(url)
  -- when running in test env store the url
  if vim.g.test then
    vim.g.OPENINGH_RESULT = url
    return true
  end

  -- order here matters
  -- wsl must come before win
  -- wsl must come before linux

  if vim.fn.has("mac") == 1 then
    vim.fn.system("open " .. url)
    return true
  end

  if vim.fn.has("wsl") == 1 then
    vim.fn.system("explorer.exe " .. url)
    return true
  end

  if vim.fn.has("win64") == 1 or vim.fn.has("win32") == 1 then
    vim.fn.system("start " .. url)
    return true
  end

  if vim.fn.has("linux") == 1 then
    vim.fn.system("xdg-open " .. url)
    return true
  end

  return false
end

function M.print_no_remote_message()
  print("There is no git origin in this repo!")
end

return M
