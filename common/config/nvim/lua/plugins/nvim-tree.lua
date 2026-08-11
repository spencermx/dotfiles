return {
    "nvim-tree/nvim-tree.lua",
    dependencies = "nvim-tree/nvim-web-devicons",
    config = function()
        local renderer = {
            highlight_opened_files = "name",
            indent_markers = {enable = true},
        }

        if vim.env.DOTFILES_CONSOLE == "1" then
            renderer.icons = {
                web_devicons = {
                    file = {enable = false, color = false},
                    folder = {enable = false, color = false},
                },
                show = {folder = false},
                symlink_arrow = " -> ",
                glyphs = {
                    default = "-",
                    symlink = "@",
                    bookmark = "B",
                    modified = "*",
                    hidden = ".",
                    folder = {
                        arrow_closed = ">",
                        arrow_open = "v",
                        default = "d",
                        open = "d",
                        empty = "d",
                        empty_open = "d",
                        symlink = "@",
                        symlink_open = "@",
                    },
                    git = {
                        unstaged = "M",
                        staged = "+",
                        unmerged = "U",
                        renamed = "R",
                        untracked = "?",
                        deleted = "x",
                        ignored = "i",
                    },
                },
            }
        end

        require("nvim-tree").setup({
            view = {width = 30, side = "left"},
            renderer = renderer,
            filters = {dotfiles = false},
            actions = {open_file = {quit_on_open = false}}
        })

        vim.keymap.set("n", "<leader>e", ":NvimTreeToggle<CR>", {noremap = true, silent = true})
        vim.keymap.set("n", "<leader>f", ":NvimTreeFindFile<CR>", {noremap = true, silent = true})
    end
}
