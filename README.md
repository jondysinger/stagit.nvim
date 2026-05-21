# stagit.nvim

Git manager for Neovim.

## Features

- Left-side Git panel with staged and unstaged file sections
- Full-file built-in diff views for staged and unstaged file entries
- Hunk navigation and hunk stage/unstage or discard actions inside diff buffers
- File-level stage/unstage and discard actions from the panel
- Floating commit-message popup that commits staged changes

## Requirements

- Neovim `>= 0.10`
- `git` available on `PATH`

## Installation

Use your plugin manager of choice, then configure it:

```lua
require("stagit").setup()
```

## Commands

- `:StagitToggle`
- `:StagitRefresh`
- `:StagitCommit`

## Default Mappings

Calling `setup()` installs a global toggle mapping:

- `<leader>gg`: toggle the panel

Inside the panel:

- `<CR>`: open the selected file in a diff view
- `s`: stage an unstaged file or unstage a staged file
- `d`: discard the selected file change
- `c`: open the commit popup
- `r`: refresh the panel
- `q`: close the panel

Inside a diff view:

- `]h`: next hunk
- `[h`: previous hunk
- `s`: stage an unstaged hunk or unstage a staged hunk
- `d`: discard the hunk
- `q`: close the diff view

Inside the commit popup:

- `<C-s>`: create the commit
- `q`: cancel in normal mode
- `<C-c>`: cancel in insert mode

## Highlights

The panel uses colorscheme-linked highlight groups so it follows your active Neovim palette:

- `StagitPanelBranchLabel`
- `StagitPanelBranchValue`
- `StagitPanelSection`
- `StagitPanelEmpty`
- `StagitPanelStaged`
- `StagitPanelUnstaged`

Override any of them in your config with `vim.api.nvim_set_hl()` if you want a different look.
