" ============================================================
"  Basic .vimrc Configuration
" ============================================================

" --- General ---
set nocompatible          " Use Vim defaults (not Vi)
set history=500           " Command history size
set encoding=utf-8        " UTF-8 encoding
set backspace=indent,eol,start  " Sensible backspace behavior

" --- UI ---
set number                " Show line numbers
set relativenumber        " Relative line numbers
set showmatch             " Highlight matching brackets
set wildmenu              " Enhanced command-line completion
set laststatus=2          " Always show status bar
set ruler                 " Show cursor position
set scrolloff=8           " Keep 8 lines above/below cursor

" --- Search ---
set hlsearch              " Highlight search results
set incsearch             " Incremental search
set ignorecase            " Case-insensitive search...
set smartcase             " ...unless query has uppercase

" --- Indentation ---
set autoindent            " Copy indent from current line
set smartindent           " Smart autoindenting
set expandtab             " Use spaces instead of tabs
set tabstop=4             " Tab = 4 spaces
set shiftwidth=4          " Indent = 4 spaces
set softtabstop=4         " Backspace deletes 4 spaces

" --- Performance ---
set lazyredraw            " Don't redraw during macros
set ttyfast               " Fast terminal connection

" --- Files ---
set noswapfile            " No swap files
set nobackup              " No backup files
set autoread              " Auto-reload changed files

" --- Syntax & Colors ---
syntax enable             " Enable syntax highlighting
set background=dark       " Dark background

" --- Key Mappings ---
let mapleader = " "       " Space as leader key

" jk to exit insert mode
inoremap jk <Esc>

" Clear search highlight with Escape
nnoremap <Esc> :nohlsearch<CR>

" Move between splits with Ctrl + hjkl
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Fix split navigation inside netrw (Lex/Ex)
augroup netrw_mappings
  autocmd!
  autocmd FileType netrw nnoremap <buffer> <C-h> <C-w>h
  autocmd FileType netrw nnoremap <buffer> <C-j> <C-w>j
  autocmd FileType netrw nnoremap <buffer> <C-k> <C-w>k
  autocmd FileType netrw nnoremap <buffer> <C-l> <C-w>l
augroup END

" Better indenting in visual mode (keeps selection)
vnoremap < <gv
vnoremap > >gv

" Tab/Shift+Tab to indent in normal and visual mode
nnoremap <Tab> >>
nnoremap <S-Tab> <<
vnoremap <Tab> >gv
vnoremap <S-Tab> <gv

" Move lines up/down with Alt+j/k
nnoremap <A-j> :m .+1<CR>==
nnoremap <A-k> :m .-2<CR>==
vnoremap <A-j> :m '>+1<CR>gv=gv
vnoremap <A-k> :m '<-2<CR>gv=gv

" --- Clipboard ---
set clipboard=unnamed " Use system clipboard by default

" --- netrw ---
let g:netrw_localcopydircmd = 'cp -r'
let g:netrw_localrmdir = '/usr/bin/rm -rf'

" Quick save and quit
nnoremap <leader>s :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>x :wq<CR>

" Open/reload vimrc
nnoremap <leader>ev :e $MYVIMRC<CR>
nnoremap <leader>sv :source $MYVIMRC<CR>
