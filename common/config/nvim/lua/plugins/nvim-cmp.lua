return {
    {
        "hrsh7th/nvim-cmp",
        event = "InsertEnter",
        dependencies = {
            "L3MON4D3/LuaSnip", -- Snippet engine
            "hrsh7th/cmp-nvim-lsp", -- LSP source
            "hrsh7th/cmp-buffer", -- Buffer source
            "hrsh7th/cmp-path", -- Path source
            "saadparwaiz1/cmp_luasnip" -- snippet completions
        },
        config = function()
            -- 1) Require cmp & luasnip
            local cmp = require("cmp")
            local luasnip = require("luasnip")

            -- 2) (Optional) Load some snippet collections
            require("luasnip.loaders.from_vscode").lazy_load()

            -- 3) Set up nvim-cmp
            cmp.setup({
                snippet = {
                    -- REQUIRED: function that expands snippets
                    expand = function(args) luasnip.lsp_expand(args.body) end
                },
                -- (Optional) Tweak appearance
                window = {
                    -- completion = cmp.config.window.bordered(),
                    -- documentation = cmp.config.window.bordered(),
                },
                -- KEY MAPPINGS
                mapping = cmp.mapping.preset.insert({
                    ["<C-b>"] = cmp.mapping.scroll_docs(-4),
                    ["<C-f>"] = cmp.mapping.scroll_docs(4),
                    ["<C-Space>"] = cmp.mapping.complete(),
                    ["<C-e>"] = cmp.mapping.abort(),
                    -- Accept currently selected item with <CR>
                    ["<CR>"] = cmp.mapping.confirm({select = true}),

                    -- Tab to navigate suggestions *or* jump through snippets
                    -- ["<Tab>"] = cmp.mapping(function(fallback)
                    --     if cmp.visible() then
                    --         cmp.select_next_item()
                    --     elseif luasnip.expand_or_jumpable() then
                    --         luasnip.expand_or_jump()
                    --     else
                    --         fallback()
                    --     end
                    -- end, {"i", "s"}),

                    -- ["<S-Tab>"] = cmp.mapping(function(fallback)
                    --     if cmp.visible() then
                    --         cmp.select_prev_item()
                    --     elseif luasnip.jumpable(-1) then
                    --         luasnip.jump(-1)
                    --     else
                    --         fallback()
                    --     end
                    -- end, {"i", "s"})
                }),
                -- SOURCES
                sources = cmp.config.sources({
                    {name = "nvim_lsp"}, {name = "luasnip"}, -- Snippet source
                    {name = "buffer"}, {name = "path"}
                })
            })

            -- (Optional) Configure completions for certain filetypes
            cmp.setup.filetype("gitcommit", {sources = cmp.config.sources({{name = "buffer"}})})

            -- (Optional) For `/` and `?` search completions
            cmp.setup.cmdline({"/", "?"}, {
                mapping = cmp.mapping.preset.cmdline(),
                sources = {{name = "buffer"}}
            })
        end
    },

    -- The additional sources as separate specs are optional when you already list them as dependencies above
    {"hrsh7th/cmp-nvim-lsp", lazy = true}, {"hrsh7th/cmp-buffer", lazy = true},
    {"hrsh7th/cmp-path", lazy = true}, {"L3MON4D3/LuaSnip", lazy = true},
    {"saadparwaiz1/cmp_luasnip", lazy = true}
}
