-- Captures the LSP servers, formatters and tools I have installed via Mason,
-- so a fresh machine reproduces them automatically instead of me installing
-- each one by hand with :MasonInstall.
--
-- `ensure_installed` uses Mason *package* names (as shown by :Mason). The
-- lspconfig `servers` block below makes the language servers that aren't
-- pulled in by a LazyVim extra actually attach to buffers.
--
-- Regenerate the tool list after adding tools:
--   ls ~/.local/share/nvim/mason/packages
return {
  -- Install the exact Mason packages I use.
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "csharp-language-server", -- C# LSP (csharp_ls)
        "csharpier",              -- C# formatter
        "json-lsp",               -- JSON LSP (jsonls)
        "lua-language-server",    -- Lua LSP (lua_ls)
        "markdown-oxide",         -- Markdown LSP (markdown_oxide)
        "shfmt",                  -- shell formatter
        "stylua",                 -- Lua formatter
        "tree-sitter-cli",        -- treesitter parser compiler
      },
    },
  },

  -- Wire up the language servers that aren't configured by a LazyVim extra,
  -- so they attach automatically once Mason has installed them.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        csharp_ls = {},
        jsonls = {},
        markdown_oxide = {},
        -- lua_ls is already configured by LazyVim core.
      },
    },
  },
}
