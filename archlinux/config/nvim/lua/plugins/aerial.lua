return {
    "stevearc/aerial.nvim",
    dependencies = {"nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons"},
    opts = {
        -- Set up Treesitter and LSP as the backends
        backends = {"treesitter", "lsp"},

        -- Auto-open Aerial when a buffer has symbols
        open_automatic = false, -- Set to `true` if you want auto-open behavior

        -- Define keybindings when Aerial attaches
        on_attach = function(bufnr)
            -- Jump between symbols using `{` and `}`
            vim.keymap.set("n", "{", "<cmd>AerialPrev<CR>", {buffer = bufnr})
            vim.keymap.set("n", "}", "<cmd>AerialNext<CR>", {buffer = bufnr})

            -- Close Aerial with `q`
            vim.keymap.set("n", "q", "<cmd>AerialClose<CR>", {buffer = bufnr})
        end,

        -- Customize Aerial's sidebar layout
        layout = {
            max_width = {40, 0.3}, -- Maximum width (40 columns or 30% of window)
            min_width = 20, -- Minimum width
            default_direction = "right" -- Open Aerial on the right side
        },

        -- Only show relevant symbols (nested grouping!)
        filter_kind = {"Class", "Struct", "Function", "Method", "Enum", "Interface", "Module"}
    },

    -- Keybinding to toggle Aerial
    keys = {{"<leader>a", "<cmd>AerialToggle!<CR>", desc = "Toggle Aerial Sidebar"}}
}
