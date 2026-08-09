return {
    "mfussenegger/nvim-dap",
    config = function()
local dap = require("dap")

        -- Chrome lives somewhere different on every platform, and this used to
        -- be hardcoded to /usr/sbin/google-chrome-stable -- a path that is
        -- wrong on macOS and wrong on most Linux installs too. Probing means a
        -- missing Chrome fails at launch with an empty string rather than
        -- silently pointing at nothing.
        local function chrome_binary()
            local candidates = {
                "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                "/usr/bin/google-chrome-stable",
                "/usr/bin/google-chrome",
                "/usr/sbin/google-chrome-stable",
            }
            for _, p in ipairs(candidates) do
                if vim.fn.executable(p) == 1 then return p end
            end
            return vim.fn.exepath("google-chrome-stable")
        end
        ------------------------------------- PYTHON ---------------------------------------
        dap.adapters.python = {
            type = "executable",
            command = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python",
            args = {"-m", "debugpy.adapter"}
        }

        dap.configurations.python = {
            {
                name = "Launch current file",
                type = "python",
                request = "launch",
                program = "${file}",
                cwd = "${workspaceFolder}",
                console = "integratedTerminal",
                pythonPath = function()
                    local mason_python = vim.fn.stdpath("data") ..
                                             "/mason/packages/debugpy/venv/bin/python"
                    if vim.fn.executable(mason_python) == 1 then
                        return mason_python
                    else
                        return "python3"
                    end
                end
            }, {
                name = "Launch with arguments",
                type = "python",
                request = "launch",
                program = "${file}",
                cwd = "${workspaceFolder}",
                console = "integratedTerminal",
                args = function()
                    local args_string = vim.fn.input("Arguments: ")
                    return vim.split(args_string, " ", {trimempty = true})
                end,
                pythonPath = function()
                    local mason_python = vim.fn.stdpath("data") ..
                                             "/mason/packages/debugpy/venv/bin/python"
                    if vim.fn.executable(mason_python) == 1 then
                        return mason_python
                    else
                        return "python3"
                    end
                end
            }
        }
        ------------------------------------- PYTHON ---------------------------------------

        ------------------------------------- RUST -----------------------------------------
        dap.adapters.codelldb = {
            type = "server",
            port = "${port}",
            executable = {
                command = vim.fn.stdpath("data") ..
                    "/mason/packages/codelldb/extension/adapter/codelldb",
                args = {"--port", "${port}"}
            }
        }

        dap.configurations.rust = {
            {
                name = "Debug Crateeeee",
                type = "codelldb",
                request = "launch",
                program = function()
                    local cargo_toml = vim.fn.readfile("Cargo.toml")
                    if not cargo_toml or vim.tbl_isempty(cargo_toml) then
                        vim.notify("Cargo.toml not found or empty", vim.log.levels.ERROR)
                        return ""
                    end
                    local toml = table.concat(cargo_toml, "\n")
                    local crate_name = vim.fn.matchstr(toml, [[name\s*=\s*"\zs[^"]\+\ze"]])
                    if crate_name == "" then
                        vim.notify("Could not parse crate name from Cargo.toml",
                                   vim.log.levels.ERROR)
                        return ""
                    end

                    local deps_path = vim.fn.getcwd() .. "/target/debug/deps/"
                    if not vim.fn.isdirectory(deps_path) then
                        vim.notify(string.format("Directory '%s' not found", deps_path),
                                   vim.log.levels.ERROR)
                        return ""
                    end

                    -- Find all files matching <crate>-<hash>
                    local pattern = string.format("%s%s-*", deps_path, crate_name)
                    local matching_files = vim.fn.globpath(deps_path, crate_name .. "-*", 0, 1) -- 0: files only, 1: return list

                    if #matching_files == 0 then
                        vim.notify(
                            string.format("No files matching '%s-*' found in %s", crate_name,
                                          deps_path), vim.log.levels.ERROR)
                        return ""
                    end

                    -- Filter for the executable: size > 0 and executable permission (contains 'x')
                    local candidates = {}
                    for _, file in ipairs(matching_files) do
                        local size = vim.fn.getfsize(file)
                        local perm = vim.fn.getfperm(file)
                        if size > 0 and perm:match("x") then
                            table.insert(candidates, {path = file, size = size})
                        end
                    end

                    if #candidates == 0 then
                        vim.notify(string.format("No executable found matching '%s-*' in %s",
                                                 crate_name, deps_path), vim.log.levels.ERROR)
                        return ""
                    elseif #candidates > 1 then
                        -- If multiple, select the largest by size
                        table.sort(candidates, function(a, b)
                            return a.size > b.size
                        end)
                        vim.notify(
                            string.format("Multiple candidates found; selecting largest: %s",
                                          candidates[1].path), vim.log.levels.WARN)
                    end

                    local executable_path = candidates[1].path
                    vim.notify(string.format("Selected executable: %s", executable_path),
                               vim.log.levels.INFO)
                    return executable_path
                end,
                cwd = "${workspaceFolder}",
                stopOnEntry = false,
                initCommands = {
                    'command script import "' .. vim.fn.stdpath("config") .. '/rust_prettifier_for_lldb.py"',
                    [[type category enable Rust]],
                },
            },
            {
                name = "Debug Test Binary",
                type = "codelldb",
                request = "launch",
                program = function()
                    local prefix = vim.fn.expand("%:t:r") -- Extracts the filename stem (e.g., "math_tests" from "math_tests.rs")
                    local path = vim.fn.getcwd() .. "/target/debug/deps/"
                    return vim.fn.input("Path to executable: ", path .. prefix .. "-", "file")
                end,
                cwd = "${workspaceFolder}",
                stopOnEntry = false
            }, {
                name = "Launch current file",
                type = "codelldb",
                request = "launch",
                program = function()
                    return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/",
                                        "file")
                end,
                cwd = "${workspaceFolder}",
                stopOnEntry = false
            }, {
                name = "Launch with arguments",
                type = "codelldb",
                request = "launch",
                program = function()
                    return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/",
                                        "file")
                end,
                args = function()
                    local args_string = vim.fn.input("Arguments: ")
                    return vim.split(args_string, " ", {trimempty = true})
                end,
                cwd = "${workspaceFolder}",
                stopOnEntry = false
            }
        }
        ------------------------------------- RUST -----------------------------------------

        ------------------------------------- RUST GDB -------------------------------------
        -- Rust Debug Adapter (rust-gdb)
        -- dap.adapters.gdb = {
        --     type = "executable",
        --     command = "rust-gdb",
        --     args = {"-q", "--interpreter=dap"} -- Quiet mode, DAP interpreter
        -- }
        --
        -- -- Rust Debug Configuration
        -- dap.configurations.rust = {
        --     {
        --         name = "Launch Rust GDB",
        --         type = "gdb",
        --         request = "launch",
        --         program = function()
        --             -- Use vim.notify to display notes
        --             vim.notify("---------- Rust Debugging Notes ----------\n" ..
        --                            "command: cargo build\n" .. "command: cargo test\n" ..
        --                            "command: cargo test --no-run\n" ..
        --                            "command: RUSTFLAGS=\"-Awarnings\" cargo test --lib -- --format pretty\n" ..
        --                            "command: ~/.config/nvim/lua/plugins/nvim-dap.lua\n" ..
        --                            "command: current directoy: " .. vim.fn.getcwd(),
        --                        vim.log.levels.INFO, {title = "Rust DAP Notes"})
        --
        --             local cwd = vim.fn.getcwd()
        --             local crate_name = vim.fn.fnamemodify(cwd, ":t")
        --             local debug_main = cwd .. "/target/debug/" .. crate_name
        --             local debug_tests_dir = cwd .. "/target/debug/deps/"
        --
        --             local choice = vim.fn.inputlist({
        --                 "Choose binary to debug:", "1. Main Binary", "2. Test Binary"
        --             })
        --
        --             if choice == 1 then
        --                 if vim.fn.executable(debug_main) == 1 then
        --                     return debug_main
        --                 else
        --                     error("Main binary not found. Run 'cargo build' first.")
        --                 end
        --             elseif choice == 2 then
        --                 local all_matches = vim.fn.glob(debug_tests_dir .. crate_name .. "-*")
        --                 all_matches = vim.split(all_matches, "\n", {trimempty = true})
        --
        --                 -- Filter out files ending with ".d"
        --                 local test_binaries = vim.tbl_filter(function(name)
        --                     return not vim.endswith(name, ".d")
        --                 end, all_matches)
        --
        --                 if #test_binaries > 0 then
        --                     return test_binaries[1]
        --                 else
        --                     error("Test binary not found. Run 'cargo test --no-run' first.")
        --                 end
        --             else
        --                 error("Invalid choice.")
        --             end
        --         end,
        --         cwd = "${workspaceFolder}",
        --         stopOnEntry = false,
        --         args = {}
        --     }
        -- }
        ------------------------------------- RUST GDB -------------------------------------

        ------------------------------------- JAVASCRIPT -----------------------------------
        -- Adapter for server-side (Node.js/Next.js)
        dap.adapters["pwa-node"] = {
            type = "server",
            host = "localhost",
            port = "${port}",
            executable = {
                command = "node",
                args = {
                    vim.fn.stdpath("data") ..
                        "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js", "${port}"
                }
            }
        }

        dap.adapters["pwa-chrome"] = {
            type = "server",
            host = "localhost",
            port = "${port}",
            executable = {
                command = "node",
                args = {
                    vim.fn.stdpath("data") ..
                        "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js", "${port}"
                }
            }
        }

        -- Configurations for TypeScript-based languages (suitable for Next.js)
        local js_based_languages = {
            "typescript", "javascript", "typescriptreact", "javascriptreact"
        }
        for _, language in ipairs(js_based_languages) do
            dap.configurations[language] = {
                -- Server-side: Attach to running Next.js (run with --inspect)
                {
                    name = "Next.js: Debug Server-Side",
                    type = "pwa-node",
                    request = "attach",
                    port = 9231, -- Next.js often uses ports 9230 and 9231; adjust if needed
                    address = "localhost",
                    skipFiles = {"<node_internals>/**", "node_modules/**"},
                    cwd = "${workspaceFolder}",
                    sourceMaps = true
                }, {
                    name = "Next.js: Launch and Debug Client-Side (Temporary Profile)", -- A new temp profile will be used i.e. no extension no data persist in the launced chrome instance on relaunch
                    type = "pwa-chrome",
                    request = "launch",
                    url = "http://localhost:3000", -- Adjust to match your Next.js development server URL if necessary
                    webRoot = "${workspaceFolder}",
                    sourceMaps = true,
                    skipFiles = {"<node_internals>/**", "node_modules/**"},
                    runtimeExecutable = chrome_binary(), -- Specify the path to your Chrome executable if not in PATH (e.g., "/usr/bin/google-chrome")
                    userDataDir = false -- Enables a temporary user data directory to avoid conflicts with existing sessions
                },

                -- /usr/sbin/google-chrome-stable --remote-debugging-port=9222 --user-data-dir=~/.chrome-debug-profile http://localhost:3000
                -- google-chrome-stable --user-data-dir=~/.chrome-debug-profile http://localhost:3000
                {
                    name = "Next.js: Launch Client-Side (Custom Profile)", -- A custom profile will be used so that extensions and data will persist in the launched chrome instance on relaunch
                    type = "pwa-chrome",
                    request = "launch",
                    url = "http://localhost:3000",
                    webRoot = "${workspaceFolder}",
                    sourceMaps = true,
                    skipFiles = {"<node_internals>/**", "node_modules/**"},
                    runtimeExecutable = chrome_binary(),
                    userDataDir = vim.fn.expand("~/.chrome-debug-profile"),
                    runtimeArgs = {"--remote-debugging-port=9222"},
                    trace = true,
                    timeout = 30000
                }
            }
        end
        ------------------------------------- JAVASCRIPT -----------------------------------

        ------------------------------------- KEYBINDINGS ------------------------------------
        local dap = require("dap")
        local map = vim.keymap.set
        -- Continue / Start debugging
        map("n", "<leader>dd", function() dap.continue() end, {desc = "DAP Continue/Start"})
        map("n", "<C-n>", function() dap.step_over() end, {desc = "DAP Step Over"})
        map("n", "<C-m>", function() dap.step_into() end, {desc = "DAP Step Into"})
        map("n", "<C-p>", function() dap.step_out() end, {desc = "DAP Step Out"})
        map("n", "<leader>b", function() dap.toggle_breakpoint() end,
            {desc = "DAP Toggle Breakpoint"})
        map("n", "<leader>dc", function() dap.clear_breakpoints() end,
            {desc = "DAP Clear All Breakpoints"})
        map("n", "<leader>B",
            function() dap.set_breakpoint(vim.fn.input("Breakpoint condition: ")) end,
            {desc = "DAP Set Conditional Breakpoint"})
        map("n", "<leader>dr", function() dap.repl.open() end, {desc = "DAP Open REPL"})
        ------------------------------------- KEYBINDINGS ------------------------------------
    end
}
