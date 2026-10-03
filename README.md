# kiwi-updater

Install and update open-source apps from **git catalogs**, on Fedora Silverblue /
Bluefin and other ostree systems. An app is just a git repo with a
`kiwi.manifest` and an `install.sh`; `kiwi` clones it, checks out its latest
release tag, runs its installer, and keeps it updated in the background —
including itself.

No accounts, no store, no vendor. A catalog is a repo you can read, fork and
send a pull request to.

- **`kiwi`** — the CLI (needs `git`, coreutils, `util-linux` for `flock`, and
  `awk`; all are in the Silverblue/Bluefin base image)
- **`kiwi-gui`** — the desktop app, **Kiwi Apps** in your app grid: search,
  filter and browse the catalogs, with a detail view per app
- **releases are git tags** — apps follow their latest *version* tag, meaning
  one shaped like `v1.2.3`. Pre-releases and scratch tags are never picked up
  by accident; untagged repos follow HEAD
- **catalogs** — add as many as you like, managed through ordinary git
- **systemd timers** — background updates for user apps and, opt-in, system apps

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/derlocke-ng/kiwi-updater/main/get-kiwi.sh | bash
```

That is **100 % user-level** — `~/.local`, no root, no password. Add the
optional system scope (one root prompt) if you want apps that install services:

```bash
curl -fsSL .../get-kiwi.sh | bash -s -- --with-system
```

Then register a catalog:

```bash
kiwi catalog add https://github.com/derlocke-ng/kiwi-catalog.git
kiwi list
```

## Use

```bash
kiwi list [--check]        # everything this machine knows about
kiwi search vpn            # find an app across every registered catalog
kiwi info kiwi-killswitch  # what it installs, and whether it needs root
kiwi install <app>         # a name, or an explicit --all
kiwi update                # everything with a new release
kiwi uninstall <app>       # --purge also drops its config
kiwi-gui                   # the desktop app ("Kiwi Apps")
```

Before you run something, and when something goes wrong:

```bash
kiwi info --installer <app> # print the script an install would run
kiwi diff <app>             # what an update would change, installer included
kiwi pin <app> v1.2.0       # stay there; kiwi unpin <app> to follow releases
kiwi install <app> --dry-run # scope, URL, ref, installer path — and do nothing
kiwi doctor                 # stale locks, version skew, bad list files, timers
```

## One app, one line — even when it needs root

Some apps are only a binary in `~/.local/bin`. Others — a VPN kill switch, say —
are a root daemon **and** a desktop app **and** a GNOME extension. Those halves
install in different places with different privileges, and that distinction is
real: **root must never execute a file the user can write**, so system apps are
cloned as root into `/var/lib` and user apps into `~/.local`.

What you should not have to care about is *expressing* it. The app declares it:

```ini
COMPONENTS=daemon cli gui gnome-extension
SCOPES=user system
ROOT_REASON=installs a root firewall daemon, its D-Bus policy and two systemd units
```

A catalog lists that app **once**. `kiwi` reads the manifest, installs each half
correctly, and shows one row:

```
NAME                 SCOPES       COMPONENTS             VERSION   STATUS
kiwi-killswitch      user+system* daemon cli gui gnome-… 0.1.0     installed
* needs root for part of the install
```

Before asking for your password it tells you what the password is *for* — that
is what `ROOT_REASON` is. `kiwi info <app>` shows it any time.

`scope=` on a catalog line still exists, but only as a **filter**: "on this
machine, install just the user half". It is not a declaration.

## The app convention

Put a [`kiwi.manifest`](templates/kiwi.manifest) and an
[`install.sh`](templates/install.sh) in your repo root:

```ini
NAME=my-tool
DESCRIPTION=Short description
# COMPONENTS: cli gui daemon service gnome-extension config …
COMPONENTS=cli
# SCOPES: user, system, or both
SCOPES=user
VERSION=0.1.0
HOMEPAGE=https://…
LICENSE=GPL-3.0-or-later
INSTALLER=install.sh
```

A value runs to the end of the line — comments go on their own line, never
after a value. A description may legitimately contain a `#`, so kiwi cannot
strip trailing comments. Copied with `COMPONENTS=cli  # … gui …` on one line,
the comment became part of the value and the app was treated as having a GUI.

`kiwi` runs your installer once **per declared scope**, with:

| env var | value |
|---|---|
| `KIWI_SCOPE` | `user` or `system` |
| `KIWI_PREFIX` | `~/.local` or `/usr/local` |
| `KIWI_APP_DIR` | absolute path of the clone |
| `KIWI_ACTION` | `install` \| `update` \| `uninstall` |
| `KIWI_GUI` | `0` on a headless machine, or with `--cli-only` |
| `KIWI_PURGE` | `1` when the user asked for `--purge` (uninstall only) |

On a purging uninstall your script is also called as `./install.sh uninstall
--purge`, so you can branch on either. Without `--purge`, leave the user's
configuration where it is.

A dual-scope installer branches on `KIWI_SCOPE` and does only that half each
time. `COMPONENTS` containing `gui` is what makes `kiwi` skip desktop parts
where there is no GTK stack.

Release by tagging: `git tag v1.3.0 && git push --tags`.

A tag counts as a release only if it matches `^v?[0-9]+(\.[0-9]+){0,3}$` —
`v1`, `v1.2`, `1.2.3` and `v1.2.3.4` all qualify. `v2.0.0-rc1`, `nightly` and
`wip-test` do not, so a pre-release never overtakes the release it precedes.
Someone who wants one can ask for it by name with `ref=v2.0.0-rc1` on their
`apps.list` line. A repo with no version tag follows its default branch.

## Catalogs

A catalog is a git repo with an `apps.list` and, optionally, a
`catalog.manifest` describing itself:

```ini
NAME=kiwi-catalog
DESCRIPTION=The Kiwi Network app catalog — open source, no accounts, no lock-in
HOMEPAGE=https://github.com/derlocke-ng/kiwi-catalog
MAINTAINER=derlocke-ng
```

```bash
kiwi catalog add https://github.com/you/your-catalog.git
kiwi catalog list
kiwi catalog remove <url>
```

Local `apps.list` entries always beat catalog entries, so a machine can pin or
override anything.

### Trust

Installing an app **runs that repo's `install.sh`**, and an app declaring the
system scope runs it **as root**. `kiwi` says so when you add a catalog, and
`kiwi info` tells you what an app is before you install it. Catalogs are curated
by whoever maintains them — they are not audited. Add catalogs you trust, the
same way you would add a package repository.

## Choosing what you run

Installing an app runs that repo's `install.sh`, as root when it declares the
system scope. None of this changes that — it exists to make the choice
deliberate rather than automatic.

Shipped in 1.3.0:

- [x] **`kiwi pin <app> <tag>` / `kiwi unpin`** — the existing `ref=` entry
      option as a first-class command, so code only changes when you say so.
      The cheapest real protection there is.
- [x] **`kiwi diff <app>`** — what changed between the installed commit and the
      one an update would move you to, *before* updating. For a catalog of
      small tools this is the strong one: a forty-line installer change is
      something you can actually read, so the installer's diff is shown in
      full.
- [x] **`kiwi info --installer <app>`** — the script that is about to run,
      before the first install.

Still planned:

- [ ] **A hosted registry of trusted catalogs** — `kiwi catalog browse` listing
      known catalogs with their maintainer, so catalogs can be discovered
      instead of pasted from somewhere. Catalogs stay opt-in either way.
- [ ] **Signature verification** — `signer=<fingerprint>` on a registry entry,
      checked with `git verify-tag` before an installer runs.

A note on that last one, because it is easy to oversell: a signature proves a
tag was made by someone holding a particular key. With a pinned fingerprint
that catches an account takeover, a repo transfer, or a typosquatted URL. It
does **not** catch a maintainer who ships something malicious — that signature
is perfectly valid — nor a stolen key, nor an installer that fetches more code
at install time. Signing narrows *who may publish*; it says nothing about *what
the published thing does*. Pinning and diffs are the ones that let you see the
change.

## Why the split layout

| piece | location | why |
|---|---|---|
| `kiwi`, `kiwi-gui`, user apps | `~/.local` | no root, survives an ostree rebase |
| root-owned `kiwi` copy (opt-in) | `/usr/local/bin` (= writable `/var/usrlocal`) | the **root** update timer must never execute a *user-writable* file, or any process running as you could edit it and become root on the next tick |
| system app repos / config | `/var/lib`, `/etc` | writable on ostree, root-owned |

The immutable `/usr` is never touched. If you never install a system app,
nothing outside your home is ever written.

## Background updates

| unit | scope | what |
|---|---|---|
| `kiwi-updater.timer` (user) | user | `kiwi update --all --user` every 6 h + a notification |
| `kiwi-updater-system.timer` (opt-in) | root | `kiwi update --all --system` every 6 h, and self-updates the root copy |

> **Upgrading from 1.2.1 or earlier with the system scope installed:** the root
> copy could not update itself before 1.3.0, so it cannot pick this release up
> on its own. Re-run the bootstrap once:
> ```bash
> curl -fsSL .../get-kiwi.sh | bash -s -- --with-system
> ```
> `kiwi version` shows both copies, and `kiwi update` warns while they differ.
> Installs without the system scope need nothing.

### Root, and when you are asked for a password

| | needs root | asks for a password |
|---|---|---|
| anything in the user scope | no | no |
| **updating** a system app | yes | **no** — polkit authorises one fixed-purpose helper for active `wheel` sessions |
| **installing** a system app | yes | yes |
| **uninstalling** a system app | yes | yes |

A plain `kiwi install` never touches root: the default install is entirely
`~/.local`, and the system scope only exists if you set it up with
`--with-system`. Only an app that declares `SCOPES=… system` needs it, and
`kiwi info <app>` tells you why before you are asked.

Passwordless system *updates* go through `/usr/local/libexec/kiwi-system-update`,
which the polkit rule authorises by exact path. It takes app names but treats
them as a **selection**: every name must look like a name (never an option) and
must already appear in the root-owned `/etc/kiwi-updater/apps.list` or a
catalog registered for root, and anything else is refused — so the worst a
caller can ask for is an update of an app the administrator already trusts.
With no names it updates everything, which is what the background timer wants.

The rule requires an **active** session in `wheel`, not a local one: VM and
remote desktop sessions can report as non-local.

## Notes

- `kiwi check` exits `10` when updates are available (script-friendly).
- `kiwi list` fetches app metadata the first time so it can show descriptions
  and components; `--no-sync` skips that. `kiwi list --check` and `kiwi sync`
  also bring those cached clones up to the release an install would use, so a
  listing describes what you would get rather than what was current when the
  app was first seen.
- Whether an app has an update is decided by comparing the remote against the
  commit recorded in each scope's own marker file, so a system app updated by
  root shows as up to date for the user too.
- `kiwi install` needs an app name or an explicit `--all`. `kiwi update` with
  no arguments means everything already installed.
- Concurrent runs are prevented with per-scope lock files. A command waits
  briefly (`KIWI_LOCK_WAIT`, 20s) rather than failing instantly, since the
  usual collision is the background timer; if it still cannot get the lock it
  names the host and pid holding it. Every network git call is bounded by
  `KIWI_NET_TIMEOUT` (180s) so a stalled fetch cannot hold the lock forever.
- The GUI is a thin layer over `kiwi list --porcelain` — the CLI is the single
  source of truth. It shows which scopes an app is actually installed in, can
  pin and unpin, and shows an app's installer and an update's diff before you
  run either.
- `kiwi list --porcelain` fields are positional and only ever appended to, so
  anything parsing it keeps working. Field 13 is the scopes an app is installed
  in, 14 is its pin.

## License

GPL-3.0-or-later — see [LICENSE](LICENSE).

Release notes are in [CHANGELOG.md](CHANGELOG.md); the 1.3.0 audit that
produced most of them is in [FIXPLAN.md](FIXPLAN.md).
