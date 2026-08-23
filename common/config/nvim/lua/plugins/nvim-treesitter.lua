-- nvim-treesitter `main` branch. The old `master` API (nvim-treesitter.configs,
-- ensure_installed, highlight = {enable}, incremental_selection, textobjects
-- inside setup) is gone; `branch = "main"` is required or an existing lazy
-- clone stays on whatever branch it was cloned with.
local parsers = {
    "c", "lua", "vim", "vimdoc", "query", "go", "c_sharp", "cpp", "css", "csv",
    "cmake", "dockerfile", "javascript", "java",
    -- godot_resource covers .tscn/.tres/.godot, which are the
    -- files you cannot open in an editor on a console-only box.
    "gdscript", "godot_resource"
}

return {
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        lazy = false, -- main does not support lazy-loading
        build = ":TSUpdate",
        dependencies = {"nvim-treesitter/nvim-treesitter-textobjects"},
        config = function()
            local ts = require("nvim-treesitter")
            ts.setup({}) -- default install_dir: stdpath("data") .. "/site"
            -- main builds parsers with the tree-sitter CLI (Arch: tree-sitter-cli,
            -- Debian: setup.sh puts it in ~/.local/bin). Without it every parser
            -- fails loudly on each startup, so check once here instead.
            if vim.fn.executable("tree-sitter") == 1 then
                ts.install(parsers) -- async; no-op when already installed
            else
                vim.schedule(function()
                    vim.notify("nvim-treesitter: `tree-sitter` CLI not found; parsers not installed", vim.log.levels.WARN)
                end)
            end

            -- Highlighting and indentation are provided by Neovim itself;
            -- enable them per buffer once a parser exists for the filetype.
            vim.api.nvim_create_autocmd("FileType", {
                group = vim.api.nvim_create_augroup("user_treesitter", {clear = true}),
                callback = function(args)
                    local lang = vim.treesitter.language.get_lang(args.match) or args.match
                    if not vim.treesitter.language.add(lang) then return end
                    vim.treesitter.start(args.buf, lang)
                    vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                end
            })
        end
    }, {
        "nvim-treesitter/nvim-treesitter-textobjects",
        branch = "main",
        lazy = false,
        config = function()
            require("nvim-treesitter-textobjects").setup({
                select = {lookahead = true, include_surrounding_whitespace = false},
                move = {set_jumps = true}
            })

            local select = function(query)
                return function()
                    require("nvim-treesitter-textobjects.select").select_textobject(query, "textobjects")
                end
            end
            for lhs, query in pairs({
                af = "@function.outer", ["if"] = "@function.inner",
                ac = "@class.outer", ic = "@class.inner",
                ab = "@block.outer", ib = "@block.inner"
            }) do
                vim.keymap.set({"x", "o"}, lhs, select(query), {desc = "TS select " .. query})
            end

            local move = function(fn, query)
                return function()
                    require("nvim-treesitter-textobjects.move")[fn](query, "textobjects")
                end
            end
            for lhs, spec in pairs({
                ["]m"] = {"goto_next_start", "@function.outer"},
                ["]]"] = {"goto_next_start", "@class.outer"},
                ["]M"] = {"goto_next_end", "@function.outer"},
                ["]["] = {"goto_next_end", "@class.outer"},
                ["[m"] = {"goto_previous_start", "@function.outer"},
                ["[["] = {"goto_previous_start", "@class.outer"},
                ["[M"] = {"goto_previous_end", "@function.outer"},
                ["[]"] = {"goto_previous_end", "@class.outer"}
            }) do
                vim.keymap.set({"n", "x", "o"}, lhs, move(spec[1], spec[2]), {desc = "TS " .. spec[1] .. " " .. spec[2]})
            end
        end
    }
}
