# Install

## Supported systems

Every push to kiwi-updater runs the full test suite and a real install over
the network on these systems.

| System | kiwi and CLI apps | GUIs (GTK 4, libadwaita 1.5+) | Updates of root apps without a password |
|---|---|---|---|
| Fedora Silverblue, Bluefin, Fedora | yes | yes | yes, for the `wheel` group |
| Debian 13, Ubuntu 24.04 and 26.04 | yes | yes | yes, for the `sudo` group |
| Arch, openSUSE Tumbleweed | yes | yes | yes, for the `wheel` group |
| Alpine | yes, with the GNU tools (see below) | yes | yes, with polkit installed |

Also tested, but not on every push:

| System | kiwi and CLI apps | GUIs | Updates of root apps without a password |
|---|---|---|---|
| Debian 12 | yes | no — libadwaita 1.2 is too old | yes, for the `sudo` group |
| openSUSE Leap 16.1 Immutable | yes | not tested yet | no — the image has no `wheel` or `sudo` group; kiwi uses manual mode |
| Ubuntu 22.04 | yes | no — libadwaita 1.1 is too old | no — polkit 0.105 is too old; kiwi uses manual mode |
| WSL2 | not tested yet | through WSLg, not tested yet | not tested yet |

kiwi 2.5.3 was also installed and used on desktop VMs (GNOME or KDE, a user
in the admin group) of Ubuntu 24.04 and 26.04, Debian 12 and 13, Fedora 45,
Arch, openSUSE Tumbleweed and openSUSE Leap 16.1 Immutable: installing kiwi,
setting up the root part, installing an app with a root part and an app that
needs a package.

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
awk. To check the signatures of root apps it needs `ssh-keygen`. For
passwordless updates of root apps it needs `pkexec`. Kiwi Apps, the desktop
app, needs GTK 4 and libadwaita for Python. Most desktops have almost all of
this already.

Copy the line for your system, then run the install command from
[Install kiwi](#install-kiwi). Each line installs everything above, including
Kiwi Apps.

**Fedora Silverblue, Bluefin, other Fedora Atomic systems:** everything is in
the base image. Nothing to install.

**Fedora:**

```bash
sudo dnf install git curl openssh-clients polkit python3-gobject libadwaita gtk4
```

**Debian 13, Ubuntu 24.04 and 26.04:**

```bash
sudo apt install git curl openssh-client pkexec python3-gi gir1.2-adw-1 gir1.2-gtk-4.0
```

**Debian 12, Ubuntu 22.04** (no Kiwi Apps; their libadwaita is too old):

```bash
sudo apt install git curl openssh-client pkexec
```

**Arch:**

```bash
sudo pacman -S --needed git curl openssh polkit python-gobject libadwaita gtk4
```

**openSUSE Tumbleweed and Leap:** `pkexec` is a package of its own there and
is not installed by default. Without it, every change to a root app asks for
your password.

```bash
sudo zypper install git-core curl openssh-clients pkexec python3-gobject typelib-1_0-Adw-1 typelib-1_0-Gtk-4_0
```

**openSUSE Leap Immutable, Aeon, Kalpa:** the system is read-only and changes
with `transactional-update`. Restart afterwards.

```bash
sudo transactional-update pkg install git-core curl openssh-clients pkexec python3-gobject typelib-1_0-Adw-1 typelib-1_0-Gtk-4_0
```

**Alpine:** see [Alpine](#alpine) below.

`kiwi pkg-hint <need>…` prints the install command for the system you are on.
A need is `git`, `ssh-keygen`, `pkexec`, `gui`, `gnu-tools`, a command, or a
package name.

### Packages that apps need

An app names the commands it needs (`DEPENDS` in its manifest). When one is
missing, kiwi shows the install command for your system and asks before it
installs anything:

```text
kiwi-killswitch needs nft, which is not installed:
  sudo zypper install nftables iproute2 NetworkManager python3 python3-gobject
Install them now? [y/N]
```

To install such packages without being asked, turn on the setting
`auto-deps` (see [Settings](usage.md#settings)). kiwi never installs packages
during a background update. On read-only systems (Fedora Atomic with
`rpm-ostree`, openSUSE Leap Immutable with `transactional-update`) it always
asks, because the packages are only there after a restart.

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
