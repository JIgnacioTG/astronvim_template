local RUBY_MARKERS = {
  "Gemfile",
  ".ruby-version",
  "config/application.rb",
}

local function has_ruby_gemspec_file(path)
  local matches = vim.fn.globpath(path, "*.gemspec", false, true)
  return type(matches) == "table" and #matches > 0
end

local function is_ruby_project_root(path)
  for _, marker in ipairs(RUBY_MARKERS) do
    if vim.fn.filereadable(vim.fs.joinpath(path, marker)) == 1 then return true end
  end

  return has_ruby_gemspec_file(path)
end

local function ruby_project_root(path_or_bufnr)
  local filename = path_or_bufnr
  if type(path_or_bufnr) == "number" then filename = vim.api.nvim_buf_get_name(path_or_bufnr) end
  if type(path_or_bufnr) == "string" and path_or_bufnr:match "^file://" then
    filename = vim.uri_to_fname(path_or_bufnr)
  end
  if filename == "" then return nil end

  local directory = vim.fs.dirname(filename)
  if not directory then return nil end

  while directory do
    if is_ruby_project_root(directory) then return directory end

    local parent = vim.fs.dirname(directory)
    if parent == directory then break end
    directory = parent
  end

  return nil
end

local function is_ruby_project(bufnr)
  return ruby_project_root(bufnr) ~= nil
end

local RUBY_TOOLS_GROUP = vim.api.nvim_create_augroup("RubyTools", { clear = true })

---@type LazySpec[]
return {
  {
    "AstroNvim/astrolsp",
    ---@type AstroLSPOpts
    opts = function(_, opts)
      opts = opts or {}
      opts.config = opts.config or {}
      opts.config.ruby_lsp = vim.tbl_deep_extend("force", opts.config.ruby_lsp or {}, {
        cmd = { vim.fs.joinpath(vim.fn.stdpath("config"), "scripts", "ruby-lsp") },
      })

      opts.config.ruby_lsp.root_dir = function(path_or_bufnr, on_dir)
        local root = ruby_project_root(path_or_bufnr)
        if type(on_dir) == "function" then on_dir(root) end
        return root
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = RUBY_TOOLS_GROUP,
        pattern = { "ruby", "eruby" },
        callback = function(event)
          local root = ruby_project_root(event.buf)
          if not root then return end

          local config = vim.deepcopy(vim.lsp.config.ruby_lsp)
          config.root_dir = root

          vim.lsp.start(config, { bufnr = event.buf, silent = true })
        end,
      })
    end,
  },
  {
    "nvimtools/none-ls.nvim",
    opts = function(_, opts)
      local null_ls = require "null-ls"
      local rubocop = vim.fs.joinpath(vim.fn.stdpath("config"), "scripts", "rubocop")

      local function should_use_rubocop(utils)
        return is_ruby_project((utils and utils.bufnr) or 0)
      end

      opts.sources = require("astrocore").list_insert_unique(opts.sources, {
        null_ls.builtins.diagnostics.rubocop.with {
          command = rubocop,
          condition = should_use_rubocop,
        },
        null_ls.builtins.formatting.rubocop.with {
          command = rubocop,
          condition = should_use_rubocop,
        },
      })
    end,
  },
}
