# Arch install — manual steps

Everything here was a comment in `install1.sh`, which contained no executable
code at all. These are the steps that come *before* `setup.sh` can run: they
happen in the Arch ISO or on first boot, before the repo is even cloned.

```sh
install1.sh
sudo pacman -S git base-devel
sudo pacman -S ly
sudo pacman -S which
sudo pacman -S alacritty
sudo pacman -S hyprland
sudo pacman -S networkmanager
sudo pacman -S kitty
sudo pacman -S grub
sudo pacman -S efibootmgr
sudo pacman -S gvim
sudo pacman -S firefox
sudo pacman -S github-cli
systemctl enable NetworkManager
systemctl enable ly

efibootmgr -b 0000 -B
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

useradd -m -G <groups> -s <shell> <username>
useradd -m -G wheel -s /bin/bash newuser

passwd newuser
grep newuser /etc/passwd

which vim
ls -s /usr/bin/vim /usr/bin/vi

visudo #uncomment wheel
```

## Get the repo

This step was missing from the original scripts entirely -- they jumped from
"install github-cli" straight to running a setup.sh that assumed the repo was
already sitting on disk. It isn't yet. None of this needs SSH keys: the
tracked `config/.gitconfig` routes GitHub HTTPS through `gh auth git-credential`,
so authenticating `gh` once is enough for both `git clone` and everything
`setup.sh` does afterward.

```sh
gh auth login
# GitHub.com -> HTTPS -> log in via browser -> account: spencermx

git clone https://github.com/spencermx/dotfiles.git ~/source/repos-spencermx/dotfiles
cd ~/source/repos-spencermx/dotfiles/linux
./setup.sh --dry-run   # see what it will do first
./setup.sh
```

## After first boot

From `install5.sh`. The git identity is set by `config/.gitconfig` once
`setup.sh --phase links` has run, so it is only needed if you are working
before that.

```sh
sudo ln -sf $(which nvim) $(which vim)
git config --global user.email "138399420+spencermx@users.noreply.github.com"
git config --global user.name "spencermx"
```
