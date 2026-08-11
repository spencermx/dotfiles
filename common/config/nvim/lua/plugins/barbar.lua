return {
    "romgrk/barbar.nvim",
    dependencies = {
        'lewis6991/gitsigns.nvim', -- OPTIONAL: for git status
        'nvim-tree/nvim-web-devicons' -- OPTIONAL: for file icons
    },
    init = function() vim.g.barbar_auto_setup = false end,
    opts = function()
        if vim.env.DOTFILES_CONSOLE ~= "1" then
            return {}
        end
        return {
            icons = {
                button = "x",
                filetype = {enabled = false},
                modified = {button = "*"},
                pinned = {button = "P", filename = true},
                separator = {left = "|", right = ""},
                inactive = {separator = {left = "|", right = ""}},
            },
        }
    end,
    config = function(_, opts)
        require('barbar').setup(opts)

        if vim.env.DOTFILES_CONSOLE == "1" then
            -- Barbar computes RGB-oriented defaults after the colorscheme has
            -- loaded. Override them here so inactive tabs remain readable.
            vim.cmd([[
                highlight! BufferCurrent          cterm=bold ctermfg=15 ctermbg=4
                highlight! BufferCurrentBtn       cterm=bold ctermfg=15 ctermbg=4
                highlight! BufferCurrentMod       cterm=bold ctermfg=11 ctermbg=4
                highlight! BufferCurrentModBtn    cterm=bold ctermfg=11 ctermbg=4
                highlight! BufferInactive         cterm=NONE ctermfg=7 ctermbg=0
                highlight! BufferInactiveBtn      cterm=NONE ctermfg=8 ctermbg=0
                highlight! BufferInactiveMod      cterm=NONE ctermfg=11 ctermbg=0
                highlight! BufferInactiveModBtn   cterm=NONE ctermfg=11 ctermbg=0
                highlight! BufferVisible          cterm=NONE ctermfg=15 ctermbg=8
                highlight! BufferVisibleBtn       cterm=NONE ctermfg=15 ctermbg=8
            ]])
        end

        local map = vim.keymap.set
        local key_opts = {noremap = true, silent = true}

        -- Move to previous/next
        map('n', '<A-,>', '<Cmd>BufferPrevious<CR>', key_opts)
        map('n', '<A-.>', '<Cmd>BufferNext<CR>', key_opts)

        -- Re-order to previous/next
        map('n', '<A-<>', '<Cmd>BufferMovePrevious<CR>', key_opts)
        map('n', '<A->>', '<Cmd>BufferMoveNext<CR>', key_opts)

        -- Pin/unpin buffer
        map('n', '<A-p>', '<Cmd>BufferPin<CR>', key_opts)

        -- Close buffer
        map('n', '<A-c>', '<Cmd>BufferClose<CR>', key_opts)

        -- Magic buffer-picking mode
        map('n', '<C-p>', '<Cmd>BufferPick<CR>', key_opts)
        map('n', '<C-s-p>', '<Cmd>BufferPickDelete<CR>', key_opts)

        -- Sort automatically by...
        -- map('n', '<Space>bb', '<Cmd>BufferOrderByBufferNumber<CR>', key_opts)
        -- map('n', '<Space>bn', '<Cmd>BufferOrderByName<CR>', key_opts)
        -- map('n', '<Space>bd', '<Cmd>BufferOrderByDirectory<CR>', key_opts)
        -- map('n', '<Space>bl', '<Cmd>BufferOrderByLanguage<CR>', key_opts)
        -- map('n', '<Space>bw', '<Cmd>BufferOrderByWindowNumber<CR>', key_opts)
    end,
    version = '^1.0.0' -- optional: only update when a new 1.x version is released
}
