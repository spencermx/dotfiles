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

      -- Optionally enable any remaining servers manually if needed
      -- vim.lsp.enable({ "pyright" })  -- auto-enabled if not excluded
    end,
  },
  { "neovim/nvim-lspconfig", lazy = true },
}
