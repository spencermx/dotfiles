return {
    "rcarriga/nvim-dap-ui",
    dependencies = {
        "nvim-lua/plenary.nvim", "theHamsta/nvim-dap-virtual-text", "nvim-neotest/nvim-nio"
    },
    config = function()
        local dap, dapui = require("dap"), require("dapui")
        dapui.setup()

        dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
        dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
        dap.listeners.before.event_exited["dapui_config"] = function() dapui.close() end

        vim.api.nvim_set_hl(0, "DapStoppedLine", {default = true, link = "Visual"})

        -------------------------------------- KEYBINDINGS ------------------------------------
        vim.keymap.set("n", "<Leader>de", function() dapui.eval() end, { desc = "Evaluate variable under cursor" })
        -------------------------------------- KEYBINDINGS ------------------------------------
    end
}
