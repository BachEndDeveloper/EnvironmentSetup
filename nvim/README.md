# Neovim / LazyVim config

My [LazyVim](https://www.lazyvim.org/) configuration, vendored so a new machine gets the same
**set** of plugins, extras, LSPs and tooling I run — installed at their **latest** versions at the
time the setup script runs (deliberately *not* pinned). The config files declare *what* to install;
LazyVim resolves the current versions.

> **Why no `lazy-lock.json`?** The lockfile pins exact plugin commits. I want the newest LazyVim +
> plugins whenever I set up a machine, so the lockfile is intentionally omitted and the script runs
> `:Lazy sync` (install latest) instead of `:Lazy restore` (checkout pinned commits).

## Files

- `init.lua`, `lua/config/*.lua`, `lua/plugins/*.lua` — the LazyVim starter layout plus my
  customizations.
- `lazyvim.json` — enabled LazyVim **extras** (language/plugin bundles from `:LazyExtras`). This is
  what defines most of "the packages/extras I have installed."
- `lua/plugins/mason-tools.lua` — the **LSP servers, formatters and tools** I have installed via
  Mason (`csharp-language-server`, `csharpier`, `json-lsp`, `lua-language-server`,
  `markdown-oxide`, `shfmt`, `stylua`, `tree-sitter-cli`) plus the lspconfig wiring for the servers
  that aren't pulled in by a LazyVim extra. On a fresh machine Mason installs these automatically.
- `stylua.toml`, `.neoconf.json`, `.gitignore` — formatter / LSP / ignore config.

## What the Mac setup script does

`01 - Setup Mac Environment.sh` (needs `neovim` + `ripgrep`, installed via the Brewfile):

1. Backs up any existing `~/.config/nvim` to `~/.config/nvim.backup-<timestamp>`.
2. Copies this folder into `~/.config/nvim`.
3. Runs `nvim --headless "+Lazy! sync" +qa` to install the **latest** LazyVim and every plugin the
   config declares (extras + custom specs), writing a fresh `lazy-lock.json` into `~/.config/nvim`.
4. On the **first interactive `nvim` launch**, Mason auto-installs the tools listed in
   `mason-tools.lua` (`ensure_installed`). Watch the bottom-right for progress, or run `:Mason`.

## Updating this vendored copy

After changing your live config, refresh the repo copy from `~/.config/nvim`:

```sh
cd ~/.config/nvim
cp init.lua lazyvim.json stylua.toml .neoconf.json .gitignore \
   /path/to/EnvironmentSetup/nvim/
cp lua/config/*.lua  /path/to/EnvironmentSetup/nvim/lua/config/
cp lua/plugins/*.lua /path/to/EnvironmentSetup/nvim/lua/plugins/   # keep mason-tools.lua
```

`lazy-lock.json` is intentionally **not** vendored (see the note at the top) — don't copy it in.

If you enable a new LazyVim extra (`:LazyExtras`), commit the updated `lazyvim.json`. If you install
new LSPs/formatters via `:Mason`, add their package names to `ensure_installed` in `mason-tools.lua`
(list them with `ls ~/.local/share/nvim/mason/packages`).
