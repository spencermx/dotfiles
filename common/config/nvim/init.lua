-- Make sure Lazy.nvim (or your plugin manager) is in the runtime path.
vim.opt.rtp:prepend("~/.local/share/nvim/lazy/lazy.nvim")

-- Load "core" modules
require("core.options") -- General settings
require("core.autocommands") -- Auto command settings

-- Initialize plugins
require("plugins.init") -- Calls Lazy.nvim and sets up all plugins

vim.keymap.set('i', '<C-;>',
               function() vim.print(vim.inspect(vim.api.nvim_buf_get_keymap(0, 'i'))) end,
               {desc = 'Print active insert mode mappings'})

require('core.keymaps')
