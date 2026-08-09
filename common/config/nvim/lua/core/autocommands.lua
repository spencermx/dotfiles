-- lua/core/autocommands.lua
-- Folding reparse command
vim.api.nvim_create_autocmd("BufReadPost", {
    pattern = "*.js",
    callback = function()
        vim.treesitter.get_parser(0, "javascript"):parse()
        vim.cmd("normal! zx") -- Recompute folds
    end
})

vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",                          -- Trigger only for quickfix buffers
    callback = function()                    -- Function that runs when the event triggers
        vim.keymap.set("n", "<C-n>", ":cnext<CR>zz", { silent = true, desc = "Quickfix: Next entry" })
        vim.keymap.set("n", "<C-p>", ":cprevious<CR>zz", { silent = true, desc = "Quickfix: Previous entry" })
        vim.keymap.set("n", "<C-[>", ":cfirst<CR>", { silent = true, desc = "Quickfix: First entry" })
        vim.keymap.set("n", "<C-]>", ":clast<CR>", { silent = true, desc = "Quickfix: Last entry" })
    end,
})
