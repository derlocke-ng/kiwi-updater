# Using kiwi

## Everyday commands

```bash
kiwi list                  # every app this machine knows about
kiwi list --check          # the same, and ask each app's repository for updates
kiwi search vpn            # find an app in every registered catalog
kiwi info <app>            # what it is, what it installs, whether it needs root
kiwi install <app>         # install an app (or several)
kiwi update                # update everything that has a new release
kiwi uninstall <app>       # remove an app; --purge also removes its settings
kiwi-gui                   # the desktop app, "Kiwi Apps"
```

`kiwi install` needs an app name, or `--all` to install every app of every
catalog. `kiwi update` without a name updates everything that is installed.

## Before you install or update

Installing an app runs that app's `install.sh`. These commands show what will
happen first:

```bash
kiwi info --installer <app>    # print the script an install would run
kiwi diff <app>                # what an update changes, including the script
kiwi install <app> --dry-run   # scope, source, version and script — and do nothing
```

To stay on a version until you decide otherwise:

```bash
kiwi pin <app> v1.2.0          # stay on v1.2.0
kiwi unpin <app>               # follow new releases again
```

## When something is wrong

```bash
kiwi doctor                    # missing tools, stale locks, version mismatch, bad list files, timers
kiwi version                   # this copy and the root-owned copy
```

`kiwi doctor` exits with a non-zero code when it finds something.

## All commands

| Command | What it does |
|---|---|
| `kiwi list [--check] [--no-sync]` | Every known app. `--check` also asks for updates; `--no-sync` stays offline. |
| `kiwi search <term>` | Search names, descriptions, components, categories, tags and URLs. |
| `kiwi info [--installer] <app>` | Details, dependencies, why it needs root; `--installer` prints the script. |
| `kiwi install <app>… \| --all` | Install. Also re-installs an installed app. |
| `kiwi update [<app>…]` | Update the named apps, or everything installed. |
| `kiwi uninstall <app>… [--purge]` | Remove; `--purge` also removes the app's settings and data. |
| `kiwi check` | Exit code `10` when updates are available, `0` when not. For scripts. |
| `kiwi diff <app>` | Commits, files and installer changes an update would bring. |
| `kiwi pin <app> <tag>` / `kiwi unpin <app>` | Stay on a version / follow releases again. |
| `kiwi add <git-url>` | Track one repository directly, without a catalog. |
| `kiwi add --system <https-url>` | Let root install and update this repository (asks for your password). |
| `kiwi catalog add <url>` / `list` / `remove <url>` | Manage catalogs. See [Catalogs](catalogs.md). |
| `kiwi sync` | Fetch catalogs and app details now. |
| `kiwi self-update` | Update kiwi itself (the background updates do this too). |
| `kiwi doctor` | Check the installation. |
| `kiwi trust --system <app>` | Forget the signing key root pinned for an app. See [Security](security.md). |
| `kiwi version` | Show the version of this copy and of the root-owned copy. |

Options can go anywhere on the line. `--` ends the options.

| Option | Effect |
|---|---|
| `--user`, `--system` | Only that part (scope) of an app. |
| `--cli-only`, `--gui` | Install without or with the app's desktop parts. kiwi remembers the choice for updates. |
| `--dry-run` | Say what would happen, change nothing. |
| `--force` | Run the installer even when nothing changed; uninstall even if the uninstaller fails. |
| `--purge` | With `uninstall`: also remove settings and data. |
| `--quiet`, `--notify` | Less output; a desktop notification after updates. |

## Scopes: the user part and the root part

Each app says in its manifest which parts it has:

- **user** — installed into `~/.local`, runs as you, never needs root;
- **system** — installed as root into `/usr/local`, `/etc` and `/var/lib`.

An app can have both. A catalog lists it once, and `kiwi list` shows one row.
An asterisk means part of it needs root:

```
NAME                 SCOPES       COMPONENTS             VERSION   STATUS
kiwi-killswitch      user+system* daemon cli gui gnome-… 0.2.3     installed
* needs root for part of the install
```

`kiwi info <app>` shows why an app needs root, before you are asked for a
password. What root may install, and when it asks, is described in
[Security](security.md).

## Kiwi Apps (the desktop app)

`kiwi-gui` shows the same apps as `kiwi list`. You can search, filter by
status and category, and open an app for its details: icon, screenshots,
README, dependencies, and the installer and update diff before they run. Pins
can be set there too.

Clicks are queued: install several apps in a row and they run one after the
other, in as few password prompts as possible. The list first shows what is
installed, then fills in which apps have updates.

Kiwi Apps needs GTK 4 and libadwaita 1.5 or newer. It uses the `kiwi` command
for everything, so whatever it shows, `kiwi` can do from a terminal.

## Background updates

The install enables one user timer, `kiwi-updater.timer`. It runs
`kiwi update --all` 10 minutes after boot and then every 6 hours, as you.

- User parts are updated directly.
- Root parts — including kiwi's own root-owned copy — are updated through the
  passwordless helper, but only to releases signed by the key root pinned for
  that app. Anything else waits for your next `kiwi update` in a terminal,
  where you type your password.
- In manual mode, the timer leaves all root parts for your next
  `kiwi update`.

There is no root timer.

Check it with `systemctl --user status kiwi-updater.timer` or `kiwi doctor`.

## Settings

kiwi reads these environment variables. Root ignores all of them except
`KIWI_UNATTENDED`.

| Variable | Default | Effect |
|---|---|---|
| `KIWI_LOCK_WAIT` | `20` | Seconds to wait when another kiwi is running (usually the timer). |
| `KIWI_NET_TIMEOUT` | `180` | Seconds before a network git call is given up. |
| `KIWI_FETCH_JOBS` | `4` | How many repositories are asked at the same time. |
| `KIWI_GUI` | detected | `0` or `1`: force installs without or with desktop parts. |
| `KIWI_UNATTENDED` | unset | `1`: never ask for a password (the timer sets this). |

## For scripts

- `kiwi check` exits `10` when updates are available.
- `kiwi list --porcelain` prints one tab-separated line per app. Fields are
  only ever added at the end, never moved:

  | # | Field | # | Field |
  |---|---|---|---|
  | 1 | name | 10 | tags |
  | 2 | scopes | 11 | clone directory |
  | 3 | components | 12 | why it needs root |
  | 4 | status | 13 | scopes it is installed in |
  | 5 | version | 14 | pinned ref |
  | 6 | repository URL | 15 | icon (manifest `ICON`) |
  | 7 | description | 16 | where the entry comes from |
  | 8 | release it would update to | 17 | root lists this source (`1`/`0`; empty for user-only apps) |
  | 9 | category | | |

  Status is one of `installed`, `update-available`, `partial`,
  `not-installed`, `unreachable`.
- `kiwi info --porcelain <app>` and `kiwi catalog list --porcelain` print
  `key=value` lines and tab-separated lines.
