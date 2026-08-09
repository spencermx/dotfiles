return {
    {
        "CopilotC-Nvim/CopilotChat.nvim",
        dependencies = {{"nvim-lua/plenary.nvim", branch = "master"}},
        build = "make tiktoken",
        opts = {
            mappings = {submit_prompt = {normal = '<S-s>', insert = '<S-s>'}}
        },
        config = function(_, opts)
            local chat = require("CopilotChat")
            chat.setup(opts)

            vim.api.nvim_set_hl(0, 'CopilotChatHeader', {fg = '#7C3AED', bold = true})
            vim.api.nvim_set_hl(0, 'CopilotChatSeparator', {fg = '#374151'})

            vim.keymap.set({'n'}, '<leader>co', chat.toggle, {desc = 'AI Toggle'})
            vim.keymap.set({'i'}, '<C-o>', chat.toggle, {desc = 'AI Toggle'})
            vim.keymap.set({'v'}, '<leader>co', chat.open, {desc = 'AI Open'})
            vim.keymap.set({'n'}, '<leader>cx', chat.reset, {desc = 'AI Reset'})
            vim.keymap.set({'n'}, '<leader>cs', chat.stop, {desc = 'AI Stop'})
            vim.keymap.set({'n'}, '<leader>cm', chat.select_model, {desc = 'AI Models'})
            vim.keymap.set({'n', 'v'}, '<leader>cp', chat.select_prompt, {desc = 'AI Prompts'})
        end
    }
}
