vim = vim -- This line is unnecessary in Lua since `vim` is globally accessible by default.

-- Disable netrw (Netrw is a built-in file explorer in Vim. Disabling it is common when using other file explorers like Nvim-Tree.)
vim.g.loaded_netrw = 1 -- Prevents loading the core netrw plugin.
vim.g.loaded_netrwPlugin = 1 -- Prevents loading additional netrw-related functionalities.

-- General editor options
vim.opt.number = true -- Show line numbers.
vim.opt.relativenumber = true -- Show relative line numbers (useful for quickly navigating with line-based motions like `5j` or `5k`).
vim.opt.splitbelow = true -- Open horizontal splits below the current window.
vim.opt.splitright = true -- Open vertical splits to the right of the current window.
vim.opt.wrap = true -- Disable line wrapping (long lines will not break automatically).

-- Folding settings (used to collapse and expand code sections)
vim.opt.foldmethod = "expr" -- Set folding method to "expression-based," which allows dynamic folding based on syntax.
vim.opt.foldexpr = "nvim_treesitter#foldexpr()" -- Use Treesitter for folding expressions (better syntax-aware folding).
vim.opt.foldlevel = 99 -- Optional: Keep all folds open by default (99 is an arbitrary large number to prevent folds from collapsing).

-- Clipboard integration
vim.opt.clipboard = "unnamedplus" -- Use the system clipboard for copy-paste (allows seamless copy-paste between Neovim and other apps).

-- Tab and indentation settings (help enforce consistent indentation)
vim.opt.expandtab = true -- Convert tabs into spaces.
vim.opt.shiftwidth = 4 -- Number of spaces to use for each indentation level (when using `>` or auto-indenting).
vim.opt.softtabstop = 4 -- Number of spaces to be used when hitting the Tab key in insert mode.
vim.opt.tabstop = 4 -- Number of spaces per tab when displaying tab characters (helps align indentation).

-- Scrolling and virtual editing
-- vim.opt.scrolloff = 999 -- Keep at least 5 lines visible above/below the cursor while scrolling.
vim.opt.virtualedit = "block" -- Allow cursor movement in block selection mode (useful for visual-block operations).

-- Live command preview and search behavior
vim.opt.inccommand = "split" -- Show a live preview of search/replace commands in a split window.
vim.opt.ignorecase = true -- Ignore case when searching (case-insensitive search).
-- The Linux text console cannot faithfully display RGB colors. Inside tmux,
-- TERM only says screen-256color, so Debian's shell supplies an explicit
-- marker rather than making this shared config guess where it is running.
vim.opt.termguicolors = vim.env.DOTFILES_CONSOLE ~= "1"

-- Set leader key (used to create custom keybindings)
vim.g.mapleader = " " -- Set the leader key to the spacebar.

-- Save with <leader> + s
-- Quit with <leader> + x
-- Turn off highlighting from last search
vim.keymap.set("n", "<leader>s", ":w<CR>", {noremap = true, silent = true})
vim.keymap.set("n", "<leader>x", ":q<CR>", {noremap = true, silent = true})
vim.keymap.set("n", "<leader>h", ":nohlsearch<CR>")

vim.keymap.set('i', '<A-l>', '<Esc>', {noremap = true, silent = true})
------------------------------------- NEOVIM --------------------------------------------
vim.api.nvim_set_keymap("n", "<C-h>", "<C-w>h", {noremap = true}) -- navigate/resize
vim.api.nvim_set_keymap("n", "<C-j>", "<C-w>j", {noremap = true})
vim.api.nvim_set_keymap("n", "<C-k>", "<C-w>k", {noremap = true})
vim.api.nvim_set_keymap("n", "<C-l>", "<C-w>l", {noremap = true})

vim.api.nvim_set_keymap("n", "<S-Left>", "<C-w><", {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<S-Right>", "<C-w>>", {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<S-Down>", "<C-w>-", {noremap = true, silent = true})
vim.api.nvim_set_keymap("n", "<S-Up>", "<C-w>+", {noremap = true, silent = true})

vim.keymap.set("n", "<C-a>v", "<C-w>v", {noremap = true, silent = true})
vim.keymap.set("n", "<C-a>s", "<C-w>s", {noremap = true, silent = true})
vim.keymap.set("n", "<C-a>x", ":q<CR>", {noremap = true, silent = true})

vim.keymap.set("i", "<A-s>", "<C-y>", {noremap = true, silent = true})
vim.keymap.set("i", "<A-d>", "<C-e>", {noremap = true, silent = true})
------------------------------------- NEOVIM --------------------------------------------

-- OVERRIDES Default 4 space convention to use 2 spaces for javascript, typescript, etc
------------------------------------- Spacing -----------------------------------------
-- TypeScript/JavaScript specific settings
vim.api.nvim_create_autocmd("FileType", {
    pattern = {"typescript", "javascript", "typescriptreact", "javascriptreact"},
    callback = function()
        -- Set buffer-local options for 2-space indentation
        vim.bo.shiftwidth = 2
        vim.bo.softtabstop = 2
        vim.bo.tabstop = 2
    end
})
------------------------------------- Spacing -----------------------------------------

------------------------------------- Quickfix ----------------------------------------
vim.keymap.set("n", "]q", "<cmd>cnext<CR>", {noremap = true, silent = true}) -- Next Quickfix entry
vim.keymap.set("n", "[q", "<cmd>cprev<CR>", {noremap = true, silent = true}) -- Previous Quickfix entry
vim.keymap.set("n", "<leader>qo", "<cmd>copen<CR>", {noremap = true, silent = true}) -- Open Quickfix List
vim.keymap.set("n", "<leader>qc", "<cmd>cclose<CR>", {noremap = true, silent = true}) -- Close Quickfix List
------------------------------------- Quickfix ----------------------------------------

------------------------------------- NUMBER ----------------------------------------
vim.keymap.set("n", "<leader>n", function()
    if vim.wo.number or vim.wo.relativenumber then
        vim.wo.number = false
        vim.wo.relativenumber = false
    else
        vim.wo.number = true
        vim.wo.relativenumber = true
    end
end, {desc = "Toggle line numbers (off / relative)", noremap = true, silent = true})
------------------------------------- NUMBER ----------------------------------------

------------------------------------- RELOAD ----------------------------------------
vim.keymap.set("n", "<leader>l", ":e<CR>", {noremap = true, silent = true}) -- Close Quickfix List

-- vim.api.nvim_create_autocmd("BufWritePost", {
--   pattern = "meals_daily",
--   callback = function()
--     vim.cmd("!python3 update.py")
--   end,
--   desc = "Run update.py after saving meals_daily",
-- })

vim.keymap.set("n", "<leader>mu", function()
    -- Save the current file first
    vim.cmd("write")

    vim.fn.jobstart({"python3", "update.py"}, {
        cwd = vim.fn.getcwd(),
        stdout_buffered = true,
        on_stdout = function(_, data) if data then print(table.concat(data, "\n")) end end,
        on_stderr = function(_, data)
            if data and data[1] ~= "" then
                print("update.py error:\n" .. table.concat(data, "\n"))
            end
        end,
        on_exit = function()
            vim.schedule(function()
                vim.cmd("edit") -- Reload file after script modifies it
            end)
        end
    })
end, {desc = "Save, run update.py, reload"})


------------------------------------- COPILOT ----------------------------------------
vim.o.completeopt = 'menuone,noinsert,noselect,popup'


------------------------------------- ESCAPE ----------------------------------------
vim.keymap.set('i', 'jk', '<Esc>', { noremap = true, silent = true })


------------------------------------- Rust File Type ----------------------------------------
--- This disables textwidth for Rust files to prevent automatic line wrapping after 99 characters. 
vim.api.nvim_create_autocmd("FileType", {
  pattern = "rust",
  callback = function()
    vim.opt_local.textwidth = 0
  end,
})

--vim.opt.cursorline = true  -- Always highlight the current line
