# Neovim / LazyVim config

My full [LazyVim](https://www.lazyvim.org/) configuration, vendored so a new machine gets the
exact same plugins, LSPs and tooling — not just a blank starter.

## Files

- `init.lua`, `lua/config/*.lua`, `lua/plugins/*.lua` — the LazyVim starter layout plus my
  customizations.
- `lazyvim.json` — enabled LazyVim **extras** (language/plugin bundles from `:LazyExtras`).
- `lazy-lock.json` — the **pinned plugin versions**. Restoring against this lockfile reproduces the
  exact plugin commits I'm running.
- `lua/plugins/mason-tools.lua` — the **LSP servers, formatters and tools** I have installed via
  Mason (`csharp-language-server`, `csharpier`, `json-lsp`, `lua-language-server`,
  `markdown-oxide`, `shfmt`, `stylua`, `tree-sitter-cli`) plus the lspconfig wiring for the servers
  that aren't pulled in by a LazyVim extra. On a fresh machine Mason installs these automatically.
- `stylua.toml`, `.neoconf.json`, `.gitignore` — formatter / LSP / ignore config.

## What the Mac setup script does

`01 - Setup Mac Environment.sh` (needs `neovim` + `ripgrep`, installed via the Brewfile):

1. Backs up any existing `~/.config/nvim` to `~/.config/nvim.backup-<timestamp>`.
2. Copies this folder into `~/.config/nvim`.
3. Runs `nvim --headless "+Lazy! restore" +qa` to install plugins at the versions pinned in
   `lazy-lock.json`.
4. On the **first interactive `nvim` launch**, Mason auto-installs the tools listed in
   `mason-tools.lua` (`ensure_installed`). Watch the bottom-right for progress, or run `:Mason`.

## Updating this vendored copy

After changing your live config, refresh the repo copy from `~/.config/nvim`:

```sh
cd ~/.config/nvim
cp init.lua lazyvim.json lazy-lock.json stylua.toml .neoconf.json .gitignore \
   /path/to/EnvironmentSetup/nvim/
cp lua/config/*.lua  /path/to/EnvironmentSetup/nvim/lua/config/
cp lua/plugins/*.lua /path/to/EnvironmentSetup/nvim/lua/plugins/   # keep mason-tools.lua
```

If you install new LSPs/formatters via `:Mason`, add their package names to
`ensure_installed` in `mason-tools.lua` (list them with `ls ~/.local/share/nvim/mason/packages`).
