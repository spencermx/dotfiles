return {
    {
        "windwp/nvim-ts-autotag",
        dependencies = {"nvim-treesitter/nvim-treesitter"},
        config = function()
            require("nvim-ts-autotag").setup({
                opts = {
                    -- Enable autotagging for specific filetypes
                    enable_close = true, -- Auto-close tags
                    enable_rename = true, -- Auto-rename paired tags
                    enable_close_on_slash = true -- Auto-close on typing `</`
                },
                -- Optionally, specify filetypes explicitly
                filetypes = {
                    "html", "javascript", "typescript", "javascriptreact", "typescriptreact",
                    "svelte", "vue", "tsx", "jsx", "xml"
                }
            })
        end
    }
}
