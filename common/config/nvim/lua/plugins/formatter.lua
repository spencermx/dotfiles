return {
    "mhartington/formatter.nvim",
    config = function()
        local util = require("formatter.util")
        local mason_bin = vim.fn.stdpath("data") .. "/mason/packages"

        -- Detect shfmt binary name based on OS/arch
        local uname = vim.fn.system("uname -sm"):gsub("\n", "")
        local shfmt_bin
        if uname:match("Darwin.*arm") then
            shfmt_bin = "shfmt_v3.12.0_darwin_arm64"
        elseif uname:match("Darwin.*x86") then
            shfmt_bin = "shfmt_v3.12.0_darwin_amd64"
        elseif uname:match("Linux.*aarch") then
            shfmt_bin = "shfmt_v3.12.0_linux_arm64"
        else
            shfmt_bin = "shfmt_v3.12.0_linux_amd64"
        end

        local prettier = "node " .. mason_bin .. "/prettier/node_modules/prettier/bin/prettier.cjs"

        local function make_prettier(parser)
            return function()
                return {
                    exe = "node",
                    args = {
                        mason_bin .. "/prettier/node_modules/prettier/bin/prettier.cjs",
                        "--stdin-filepath",
                        util.escape_path(util.get_current_buffer_file_path()),
                        "--parser", parser
                    },
                    stdin = true
                }
            end
        end

        require("formatter").setup({
            logging = true,
            log_level = vim.log.levels.WARN,
            filetype = {
                lua = {
                    function()
                        return {
                            exe = mason_bin .. "/luaformatter/bin/lua-format",
                            args = {
                                "--indent-width=4",
                                "--column-limit=100",
                                util.escape_path(util.get_current_buffer_file_path())
                            },
                            stdin = true
                        }
                    end
                },
                cs = {
                    function()
                        return {
                            exe = mason_bin .. "/csharpier/csharpier",
                            args = {"format", util.escape_path(util.get_current_buffer_file_path())}
                        }
                    end
                },
                go = {
                    function()
                        return {
                            exe = mason_bin .. "/gofumpt/gofumpt",
                            args = {util.escape_path(util.get_current_buffer_file_path())},
                            stdin = true
                        }
                    end
                },
                css        = { make_prettier("css") },
                javascript = { make_prettier("babel") },
                javascriptreact = { make_prettier("babel") },
                typescript = { make_prettier("typescript") },
                typescriptreact = { make_prettier("typescript") },
                json       = { make_prettier("json") },
                rust = {
                    function()
                        return { exe = "rustfmt", args = { "--emit=stdout" }, stdin = true }
                    end
                },
                -- gdformat comes from gdtoolkit via pipx, not Mason, so it is
                -- looked up on PATH like rustfmt. Godot's own LSP reports
                -- documentFormatting = false, so this is the only thing that
                -- formats GDScript.
                gdscript = {
                    function()
                        return { exe = "gdformat", args = { "-" }, stdin = true }
                    end
                },
                html = {
                    function()
                        return {
                            exe = mason_bin .. "/htmlbeautifier/htmlbeautifier",
                            args = { util.escape_path(util.get_current_buffer_file_path()) },
                            stdin = false,
                            try_node_modules = false,
                            tempfile_prefix = ".formatter.",
                            remove_tempfile = true
                        }
                    end
                },
                sh = {
                    function()
                        return {
                            exe = mason_bin .. "/shfmt/" .. shfmt_bin,
                            args = { "-i", "4", "-ln", "bash", "-" },
                            stdin = true
                        }
                    end
                },
                ["*"] = {
                    require("formatter.filetypes.any").remove_trailing_whitespace
                }
            }
        })

        vim.api.nvim_set_keymap("n", "<leader>fo", ":Format<CR>",      { noremap = true, silent = true })
        vim.api.nvim_set_keymap("n", "<leader>Fo", ":FormatWrite<CR>", { noremap = true, silent = true })
    end
}
