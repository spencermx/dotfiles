return {
    {
        "nvim-telescope/telescope.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-telescope/telescope-ui-select.nvim",  -- Added for vim.ui.select integration
        },
        config = function()
            require("telescope").setup({
                defaults = {
                    mappings = {
                        i = {["<C-j>"] = "move_selection_next", ["<C-k>"] = "move_selection_previous"}
                    }
                },
                pickers = {
                    current_buffer_fuzzy_find = {
                        preview = {
                            check_mime_type = false, -- Don't try to detect file type
                            filesize_limit = 25, -- Handle larger buffers
                            timeout = 250 -- Give more time to render
                        }
                    }
                },
                extensions = {
                    ["ui-select"] = {
                        require("telescope.themes").get_dropdown(),  -- Optional: Use dropdown theme for selections
                    },
                },
            })

            -- Load the ui-select extension to override vim.ui.select
            require("telescope").load_extension("ui-select")

            ------------------------------------- TELESCOPE -----------------------------------------
            local builtin = require("telescope.builtin")
            vim.keymap.set("n", "<leader>ff", builtin.find_files, {})
            vim.keymap.set("n", "<leader>fg", builtin.live_grep, {})
            vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
            vim.keymap.set("n", "<leader>fh", builtin.help_tags, {})
            vim.keymap.set("n", "<leader>/", builtin.current_buffer_fuzzy_find, {})
            ------------------------------------- TELESCOPE -----------------------------------------
        end
    },
}
