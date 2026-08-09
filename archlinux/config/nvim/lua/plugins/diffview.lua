return {
    "sindrets/diffview.nvim",
    dependencies = "nvim-lua/plenary.nvim",
    config = function()
        require("diffview").setup({
            enhanced_diff_hl = true, -- better syntax highlighting
            view = {default = {layout = "diff2_horizontal"}}
        })

        ------------------------------------- DiffView -----------------------------------------
        vim.api.nvim_set_keymap("n", "<leader>do", ":DiffviewOpen<CR>",
                                {noremap = true, silent = true})
        vim.api.nvim_set_keymap("n", "<leader>dc", ":DiffviewClose<CR>",
                                {noremap = true, silent = true})
        vim.api.nvim_set_keymap("n", "<leader>dt", ":DiffviewToggleFiles<CR>",
                                {noremap = true, silent = true})

        -- For stronger diff colors
        vim.cmd([[
          hi DiffAdd    guifg=#00ff00 guibg=#005500
          hi DiffChange guifg=#cccccc guibg=#2B5B77
          hi DiffDelete guifg=#ff0000 guibg=#550000
          hi DiffText   guifg=#00ffff guibg=#004444
        ]])
        ------------------------------------- DiffView -----------------------------------------
    end
}
