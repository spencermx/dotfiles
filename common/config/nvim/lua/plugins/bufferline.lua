return {
    "akinsho/bufferline.nvim",
    version = "*", 
    dependencies = "nvim-tree/nvim-web-devicons",
    lazy = false, -- Load immediately (if using Lazy.nvim)
    config = function()
        vim.opt.termguicolors = true
        require("bufferline").setup{}
    end
}
