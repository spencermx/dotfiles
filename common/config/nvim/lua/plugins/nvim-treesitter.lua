return {
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        -- event = {"BufReadPost", "BufNewFile"},
        dependencies = {"nvim-treesitter/nvim-treesitter-textobjects"},
        config = function()
            require("nvim-treesitter.config").setup({
                ensure_installed = {
                    "c", "lua", "vim", "vimdoc", "query", "go", "c_sharp", "cpp", "css", "csv",
                    "cmake", "dockerfile", "javascript", "java",
                    -- godot_resource covers .tscn/.tres/.godot, which are the
                    -- files you cannot open in an editor on a console-only box.
                    "gdscript", "godot_resource"
                },

                auto_install = true,
                indent = {enable = true},
                highlight = {enable = true},

                -- Enable incremental selection
                incremental_selection = {
                    enable = true,
                    keymaps = {
                        -- init_selection = "<Leader>ss", -- Start selection
                        -- node_incremental = "<Leader>se", -- Expand selection
                        -- scope_incremental = "<Leader>sb", -- Bigger scope
                        -- node_decremental = "<Leader>sr" -- Reduce selection
                    }
                    -- keymaps = {
                    --     init_selection = "gnn", -- start incremental selection
                    --     node_incremental = "grn", -- increment to the upper named parent
                    --     scope_incremental = "grc", -- increment to the upper scope
                    --     node_decremental = "grm" -- decrement to the previous node
                    -- }
                },
                textobjects = {
                    select = {
                        enable = true,
                        keymaps = {
                            ["af"] = "@function.outer",
                            ["if"] = "@function.inner",
                            ["ac"] = "@class.outer",
                            ["ic"] = "@class.inner",
                            ["ab"] = "@block.outer",
                            ["ib"] = "@block.inner"
                        },

                        lookahead = true,
                        include_surrounding_whitespace = false
                    },

                    move = {
                        enable = true,
                        set_jumps = true,
                        goto_next_start = {["]m"] = "@function.outer", ["]]"] = "@class.outer"},
                        goto_next_end = {["]M"] = "@function.outer", ["]["] = "@class.outer"},
                        goto_previous_start = {["[m"] = "@function.outer", ["[["] = "@class.outer"},
                        goto_previous_end = {["[M"] = "@function.outer", ["[]"] = "@class.outer"}
                    }
                }
            })

        end
    }, {"nvim-treesitter/nvim-treesitter-textobjects", lazy = false}
}
