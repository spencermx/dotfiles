return {
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end,
  },
  {
    "mason-org/mason-lspconfig.nvim",  -- Note: repository moved to mason-org organization
    event = { "BufReadPre", "BufNewFile" },
    -- :GodotLspStop is defined down in config(), which without this only runs
    -- once a file is open -- exactly not the session where you want to shut
    -- the headless editors down.
    cmd = { "GodotLspStop" },
    dependencies = {
      "williamboman/mason.nvim",
      "neovim/nvim-lspconfig",
      "hrsh7th/cmp-nvim-lsp",
      "Issafalcon/lsp-overloads.nvim",
    },
    config = function()
      -- Shared capabilities (including cmp-nvim-lsp integration)
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)

      -- Shared on_attach function (unchanged except remove print statements if desired)
      local on_attach = function(client, bufnr)
        -- print("rust_analyzer attached to buffer " .. bufnr)  -- optional debug
        local bufopts = { noremap = true, silent = true, buffer = bufnr }

        -- Core LSP keybindings (unchanged)
        vim.keymap.set("n", "gD", vim.lsp.buf.declaration, bufopts)
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, bufopts)
        vim.keymap.set("n", "gi", vim.lsp.buf.implementation, bufopts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, bufopts)
        vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, bufopts)

        -- Workspace management (unchanged)
        vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, bufopts)
        vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, bufopts)
        vim.keymap.set("n", "<leader>wl", function()
          print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
        end, bufopts)

        -- Code actions, rename, format (unchanged)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, bufopts)
        vim.keymap.set("n", "<leader>ci", vim.lsp.buf.code_action, bufopts)
        vim.keymap.set("n", "<leader>f", function()
          vim.lsp.buf.format { async = true }
        end, bufopts)

        -- Information and diagnostics (unchanged)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, bufopts)
        vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, bufopts)
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, bufopts)
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, bufopts)
        vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, bufopts)

        -- lsp-overloads integration (unchanged)
        if client.server_capabilities.signatureHelpProvider then
          require("lsp-overloads").setup(client, {
            ui = {
              border = "rounded",
              close_events = { "CursorMoved", "BufHidden", "InsertLeave" },
              floating_window_above_cur_line = true,
            },
            keymaps = {
              next_signature = "<C-j>",
              previous_signature = "<C-k>",
              next_parameter = "<C-l>",
              previous_parameter = "<C-h>",
              close_signature = "<M-x>",
            },
          })
        end
      end

      -- Global diagnostics configuration (unchanged)
      vim.diagnostic.config({
        virtual_text = true,
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = { border = "rounded", source = "always" },
      })

      -- mason-lspconfig setup: install servers and auto-enable non-excluded ones
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls", "pyright", "bashls", "omnisharp", "rust_analyzer", "ts_ls" },
        automatic_enable = {
          exclude = { "lua_ls", "bashls", "ts_ls", "omnisharp", "rust_analyzer" },
        },
      })

      -- Apply custom configurations via vim.lsp.config() for excluded/manual servers
      vim.lsp.config("lua_ls", {
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
          },
        },
      })

      vim.lsp.config("bashls", {
        capabilities = capabilities,
        on_attach = on_attach,
        filetypes = { "sh", "bash" },
        single_file_support = true,
      })

      vim.lsp.config("ts_ls", {
        capabilities = capabilities,
        on_attach = on_attach,
        init_options = { hostInfo = "neovim" },
      })

      vim.lsp.config("omnisharp", {
        capabilities = capabilities,
        on_attach = on_attach,
        cmd = { "OmniSharp", "--languageserver", "--hostPID", tostring(vim.fn.getpid()) },
        root_dir = require("lspconfig.util").root_pattern("*.csproj", "*.sln"),
        env = {
          DOTNET_ROOT = "/opt/dotnet",
        },
      })

      vim.lsp.config("rust_analyzer", {
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
          ["rust-analyzer"] = {
            cargo = { allFeatures = true },
            procMacro = { enable = true },
            diagnostics = {
              disabled = { "unused_variables" },
            },
          },
        },
      })

      -- Godot ships its own language server inside the engine, so Mason has
      -- nothing to install and ensure_installed must not list it. The server
      -- exists only while an editor is running on the project, and this
      -- machine has no display server, so the editor is started headless:
      --
      --   godot --headless --editor --path <root> --lsp-port <port>
      --
      -- Verified on the console-only Debian machine at Godot 4.7.1: the port
      -- binds in about three seconds with no display server present, and the
      -- server advertises completion, definition, declaration, hover, document
      -- symbols, references and rename. It advertises documentFormatting as
      -- false, which is why gdformat is wired up separately in formatter.lua.
      --
      -- One editor per project root, started on demand. The port is not fixed
      -- at 6005 because a second project opened later would collide on it; a
      -- running editor's own command line is instead the source of truth for
      -- its port, so other Neovim sessions rediscover it rather than starting
      -- a duplicate. Editors are detached and outlive Neovim, which makes the
      -- next session attach instantly; :GodotLspStop kills them.

      -- Which TCP ports are being listened on, straight from the kernel.
      --
      -- Two more obvious approaches do not work here. libuv's bind() reports
      -- occupied ports as free, because EADDRINUSE only surfaces at listen();
      -- it hands a second project the first project's port. An async connect
      -- probe is accurate but its callback never runs while this code blocks
      -- inside the LSP cmd hook, so the wait always times out. A synchronous
      -- ss call needs no event loop and is right in any context.
      local function listening_ports()
        local ports = {}
        for _, line in ipairs(vim.fn.systemlist({ "ss", "-ltnH" })) do
          local addr = vim.split(line, "%s+", { trimempty = true })[4]
          local port = addr and addr:match(":(%d+)$")
          if port then
            -- Keyed by port only: a wildcard listener also owns 127.0.0.1.
            ports[tonumber(port)] = true
          end
        end
        return ports
      end

      -- uv.sleep rather than vim.wait, for the same reason: no event loop.
      local function wait_until_listening(port, timeout)
        for _ = 1, math.ceil(timeout / 250) do
          if listening_ports()[port] then
            return true
          end
          vim.uv.sleep(250)
        end
        return false
      end

      -- Port of the headless editor already serving `root`, if there is one.
      -- An editor started by hand without --lsp-port is on Godot's default.
      local function godot_lsp_running_port(root)
        for _, line in ipairs(vim.fn.systemlist({ "pgrep", "-af", "godot" })) do
          local exe, args = line:match("^%d+%s+(%S+)%s*(.*)$")
          if exe and vim.fs.basename(exe) == "godot" and args:find("--path " .. root, 1, true) then
            return tonumber(args:match("%-%-lsp%-port%s+(%d+)")) or 6005
          end
        end
      end

      local function godot_lsp_port(root)
        local port = godot_lsp_running_port(root)
        if port then
          return port
        end

        local godot = vim.fn.exepath("godot")
        if godot == "" then
          error("gdscript: no godot binary on PATH")
        end

        local taken = listening_ports()
        for candidate = 6005, 6055 do
          -- +100 is this editor's debug adapter port, so it must be free too.
          if not taken[candidate] and not taken[candidate + 100] then
            port = candidate
            break
          end
        end
        if not port then
          error("gdscript: no free LSP port in 6005-6055")
        end

        vim.system({
          godot,
          "--headless",
          "--editor",
          "--path",
          root,
          "--lsp-port",
          tostring(port),
          -- Every editor also opens a debug adapter, default 6006. Without a
          -- distinct one, the second project's DAP dies on a busy port.
          "--dap-port",
          tostring(port + 100),
        }, { detach = true, stdout = false, stderr = false })

        -- The editor imports assets before it binds, so the first buffer in a
        -- cold project blocks for a few seconds. Later buffers reuse it.
        if not wait_until_listening(port, 30000) then
          error("gdscript: godot editor for " .. root .. " never bound port " .. port)
        end
        return port
      end

      vim.lsp.config("gdscript", {
        capabilities = capabilities,
        on_attach = on_attach,
        cmd = function(dispatchers, config)
          local root = config and config.root_dir
            or vim.fs.root(vim.api.nvim_buf_get_name(0), { "project.godot" })
          if not root then
            error("gdscript: buffer is not inside a Godot project")
          end
          return vim.lsp.rpc.connect("127.0.0.1", godot_lsp_port(root))(dispatchers)
        end,
        filetypes = { "gdscript" },
        -- project.godot only: the editor needs a real project, and .git or a
        -- bare .godot would hand it a root it cannot open.
        root_markers = { "project.godot" },
      })
      vim.lsp.enable("gdscript")

      vim.api.nvim_create_user_command("GodotLspStop", function()
        local killed = 0
        for _, line in ipairs(vim.fn.systemlist({ "pgrep", "-af", "godot" })) do
          local pid, cmdline = line:match("^(%d+)%s+(.*)$")
          -- --headless --editor together means a language server host, never a
          -- game or an export run.
          if cmdline and cmdline:find("--headless", 1, true) and cmdline:find("--editor", 1, true) then
            vim.uv.kill(tonumber(pid), "sigterm")
            killed = killed + 1
          end
        end
        vim.notify(("gdscript: stopped %d headless editor(s)"):format(killed))
      end, { desc = "Stop the headless Godot editors hosting the GDScript LSP" })

      -- Optionally enable any remaining servers manually if needed
      -- vim.lsp.enable({ "pyright" })  -- auto-enabled if not excluded
    end,
  },
  { "neovim/nvim-lspconfig", lazy = true },
}
