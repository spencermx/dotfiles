return {
    "tpope/vim-fugitive",
    config = function()
        ------------------------------------- FUGITIVE -----------------------------------------
        vim.keymap.set("n", "<leader>gs", ":G<CR>", {desc = "Git Status"})
        vim.keymap.set("n", "<leader>gc", ":Gcommit<CR>", {desc = "Git Commit"})
        vim.keymap.set("n", "<leader>gp", ":Git push<CR>", {desc = "Git Push"})
        vim.keymap.set("n", "<leader>gl", ":Glog<CR>", {desc = "Git Log (Quickfix)"})
        vim.keymap.set("n", "<leader>gd", ":Gdiffsplit<CR>", {desc = "Git Diff Split"})
        vim.keymap.set("n", "<leader>gw", ":Gwrite<CR>", {desc = "Git Add Current Buffer"})
        ------------------------------------- FUGITIVE -----------------------------------------
    end
}
