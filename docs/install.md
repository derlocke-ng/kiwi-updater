# Install

## Supported systems

Every push to kiwi-updater runs the full test suite and a real install over
the network on these systems.

| System | kiwi and CLI apps | GUIs (GTK 4, libadwaita 1.5+) | Updates of root apps without a password |
|---|---|---|---|
| Fedora Silverblue, Bluefin, Fedora | yes | yes | yes, for the `wheel` group |
| Debian 13, Ubuntu 24.04 | yes | yes | yes, for the `sudo` group |
| Arch, openSUSE Tumbleweed | yes | yes | yes, for the `wheel` group |
| Alpine | yes, with the GNU tools (see below) | yes | yes, with polkit installed |

Also tested, but not on every push:

| System | kiwi and CLI apps | GUIs | Updates of root apps without a password |
|---|---|---|---|
| Debian 12 | yes | no — libadwaita 1.2 is too old | yes, for the `sudo` group |
| Ubuntu 22.04 | yes | no — libadwaita 1.1 is too old | no — polkit 0.105 is too old; kiwi uses manual mode |
| WSL2 | not tested yet | through WSLg, not tested yet | not tested yet |

When a GUI cannot run, kiwi installs the command-line part of an app and says
why. When a tool is missing, kiwi names the package for your distribution.

## Install kiwi

**Recommended.** The user part plus the root part, with one password prompt:

```bash
curl -fsSL https://raw.githubusercontent.com/derlocke-ng/kiwi-updater/main/get-kiwi.sh | bash
```

**Minimal.** Only your home directory (`~/.local`). No root and no password,
ever:

```bash
curl -fsSL https://raw.githubusercontent.com/derlocke-ng/kiwi-updater/main/get-kiwi.sh | bash -s -- --minimal
```

**Manual mode.** The root part without the passwordless updates. Every change
to a root app then asks for your password:

```bash
curl -fsSL https://raw.githubusercontent.com/derlocke-ng/kiwi-updater/main/get-kiwi.sh | bash -s -- --with-system=manual
```

`--with-system=auto` switches back. Both switches are one command and can be
run at any time.

`get-kiwi.sh` clones kiwi-updater, checks that the newest release is signed by
kiwi-updater's release key, and runs that release's `install.sh`. It refuses a
release that is not signed by that key. See [Security](security.md).

The [Kiwi Network catalog](https://github.com/derlocke-ng/kiwi-catalog) is
registered during the install. Try:

```bash
kiwi list
kiwi-gui
```

### What goes where

| Part | Location |
|---|---|
| `kiwi`, `kiwi-release`, `kiwi-gui` | `~/.local/bin` |
| Your lists and catalogs | `~/.config/kiwi-updater/` |
| Clones of your apps | `~/.local/share/kiwi-updater/repos/` |
| Background updates | `~/.config/systemd/user/kiwi-updater.timer` |
| The root-owned copy of kiwi (root part only) | `/usr/local/bin/kiwi` |
| Root's lists, catalogs and pinned keys | `/etc/kiwi-updater/` |
| Clones of root apps | `/var/lib/kiwi-updater/repos/` |
| The passwordless update helper (auto mode) | `/usr/local/libexec/kiwi-system-update` and `/etc/polkit-1/rules.d/50-kiwi-updater.rules` |

Without the root part, nothing outside your home directory is written. On
Fedora Atomic systems `/usr` stays untouched; `/usr/local`, `/etc` and
`/var/lib` are writable there.

### Apps with a root part

Some apps have a root part, for example kiwi-killswitch (a firewall daemon
plus a desktop app). On a minimal install, `kiwi install kiwi-killswitch` sets
up the root part of kiwi first, with one password prompt.

## Packages per distribution

kiwi needs bash, git, GNU coreutils, util-linux (for `flock`), findutils and
awk. To check signatures of root apps it also needs `ssh-keygen`. Most
desktops have all of these already.

| Need | Fedora | Debian, Ubuntu | Arch | openSUSE | Alpine |
|---|---|---|---|---|---|
| kiwi | `git` (+ `gawk` in minimal images) | `git` | `git` | `git-core` (+ `findutils` in minimal images) | `bash git coreutils util-linux findutils sed grep` |
| signatures | `openssh-clients` | `openssh-client` | `openssh` | `openssh-clients` | `openssh-keygen` |
| Kiwi Apps | `python3-gobject libadwaita gtk4` | `python3-gi gir1.2-adw-1 gir1.2-gtk-4.0` | `python-gobject libadwaita gtk4` | `python3-gobject typelib-1_0-Adw-1 typelib-1_0-Gtk-4_0` | `py3-gobject3 libadwaita gtk4.0` |

On Fedora Silverblue and Bluefin everything is in the base image.

`kiwi pkg-hint <git|ssh-keygen|gui|gnu-tools>` prints the install command for
the system you are on.

### Alpine

Alpine uses BusyBox, which lacks options kiwi needs (`realpath -e`,
`flock -w`, `find -uid`). Install the GNU tools first:

```bash
doas apk add bash git coreutils util-linux findutils sed grep openssh-keygen
```

Without them, kiwi stops at once and prints this line.

### `~/.local/bin` on your PATH

Arch and Alpine do not put `~/.local/bin` on your `PATH`. Debian does it from
your next login. The installer tells you when it is missing. To add it:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

### Without systemd

On systems without a systemd user session (Alpine with OpenRC, WSL without
systemd, containers), kiwi installs normally but cannot run its background
updates. Run `kiwi update` yourself, or from cron.

## Uninstall

```bash
bash ~/.local/share/kiwi-updater/repos/kiwi-updater/install.sh uninstall
```

This removes kiwi from your home directory. Run from a terminal on a machine
with the root part, it removes that too, with your password. Your lists and the clones stay; add
`--purge` to remove them too. Apps you installed stay installed — uninstall
them first with `kiwi uninstall <app>` if you want them gone.
