return {
    "github/copilot.vim",
    lazy = false, -- Load immediately (if using Lazy.nvim)
    config = function()
        -- Disable default Tab mapping to avoid conflicts
        vim.g.copilot_no_tab_map = true
        vim.keymap.set('i', '<S-Tab>', 'copilot#Accept("\\<S-Tab>")',
                       {expr = true, replace_keycodes = false})

        vim.api.nvim_set_keymap('i', '<S-Tab>', 'copilot#Accept("<CR>")',
                                {expr = true, silent = true})

        vim.keymap.set("i", "<C-k>", "<Plug>(copilot-next)",
                       {silent = true, desc = "Next Copilot suggestion"})

        vim.keymap.set("i", "<C-j>", "<Plug>(copilot-previous)",
                       {silent = true, desc = "Previous Copilot suggestion"})

        vim.keymap.set("i", "<C-h>", "<Plug>(copilot-dismiss)",
                       {silent = true, desc = "Dismiss Copilot suggestion"})
    end
}
