return {
    -- Mason Package Manager for installing LSPs, DAP, etc
    {
        "williamboman/mason.nvim",
        cmd = {"Mason", "MasonInstall", "MasonUninstall"}, -- Lazy-load on commands
        config = function()
            require("mason").setup({
                ui = {
                    icons = {
                        package_installed = "✓",
                        package_pending = "➜",
                        package_uninstalled = "✗"
                    }
                }
            })
        end
    }
}
