return {
    "rebelot/kanagawa.nvim",
    config = function()
        if vim.env.DOTFILES_CONSOLE ~= "1" then
            vim.cmd.colorscheme("kanagawa-wave")
            return
        end

        -- Kanagawa's subtle RGB shades collapse into one another on the Linux
        -- text console. Habamax ships with Neovim and defines cterm colors for
        -- the standard and Treesitter highlight groups, so syntax highlighting
        -- remains intact without pretending this display supports true color.
        vim.cmd.colorscheme("habamax")

        -- Make structural UI elements deliberately obvious. Plugin highlight
        -- groups fall back to the standard groups unless named here.
        vim.cmd([[
            highlight WinSeparator          cterm=bold ctermfg=14 ctermbg=NONE
            highlight VertSplit             cterm=bold ctermfg=14 ctermbg=NONE
            highlight NvimTreeWinSeparator  cterm=bold ctermfg=14 ctermbg=NONE
            highlight FloatBorder           cterm=bold ctermfg=14 ctermbg=NONE
            highlight StatusLine            cterm=bold ctermfg=0  ctermbg=7
            highlight StatusLineNC          cterm=NONE ctermfg=8  ctermbg=0
            highlight CursorLineNr          cterm=bold ctermfg=11 ctermbg=NONE
            highlight LineNr                cterm=NONE ctermfg=8  ctermbg=NONE
            highlight Comment               cterm=NONE ctermfg=10 ctermbg=NONE
            highlight @comment               cterm=NONE ctermfg=10 ctermbg=NONE
            highlight Visual                cterm=NONE ctermfg=NONE ctermbg=4
            highlight NvimTreeCursorLine    cterm=NONE ctermfg=NONE ctermbg=8
        ]])
    end,
}
