# terminal-filetype.nvim

A neovim plugin that parses terminal ansi escape sequences and annotates the buffer with colors

This plugin is based on [norcalli/nvim-terminal.lua](https://github.com/norcalli/nvim-terminal.lua)

```lua
{
    "samsze0/terminal-filetype.nvim",
    config = function()
        require("terminal-filetype").setup({})
    end,
    dependencies = {
        "samsze0/utils.nvim",
    }
}
```

## License

MIT