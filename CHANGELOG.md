# Changelog

Earlier entries are the release commit subjects, which is where this project's
history actually lives.

## 1.3.1 — 2026-10-03

Fixes a bug introduced in 1.3.0.

An app listed in **both** `apps.list` files — which kiwi-updater itself is, by
design — was shown as belonging only to the scope of whichever entry survived
the dedup. `kiwi list` labelled kiwi-updater `scopes=user` while it was
installed in both, so:

- the marker comparison correctly saw that the root half was behind and
  reported `update-available`,
- but `kiwi update kiwi-updater` only ever acted on the user half and answered
  "is up to date",
- so the GUI showed an update that nothing the user could do would clear.

The scopes to act on are now the ones the entry and manifest declare *plus any
scope the app is actually installed in*. Something already installed is a fact,
and it outranks what one list entry happened to say. `kiwi update
<app>` now reaches the root half of such an app, passwordlessly through the
usual wrapper.

## 1.3.0 — 2026-10-03

A full audit of 1.2.1 (see `FIXPLAN.md`), worked through one finding per
commit. `tests/repro.sh` reproduces every finding and now passes.

> **Upgrade note — only if you have the system scope.** The root-owned copy of
> kiwi could never update itself (see below), so it cannot pick this release up
> on its own. Re-run the bootstrap once:
> ```bash
> curl -fsSL https://raw.githubusercontent.com/derlocke-ng/kiwi-updater/main/get-kiwi.sh | bash -s -- --with-system
> ```
> `kiwi version` shows both copies and `kiwi doctor` checks them. Installs
> without the system scope need nothing.

### Fixed — wrong state, data loss, unwanted root prompts

- A failed installer was recorded as installed: the marker was written, kiwi
  printed "installed" and exited 0, so the next `kiwi update` saw nothing to
  do. Updates did the same and sent the "Apps updated" notification.
- A failed uninstaller still deleted the clone, leaving the app's files on disk
  with nothing left that knew how to remove them.
- `install.sh uninstall --with-system` passed `--purge` to the root half
  whether or not you asked, deleting `/etc/kiwi-updater` and
  `/var/lib/kiwi-updater` including the clones of system apps still installed.
- The root-owned kiwi never updated itself. Its system-list entry asked for the
  system scope, its manifest declared `SCOPES=user`, the intersection was
  empty — so the timer failed every six hours with "no apps matched" and the
  copy running as root never received a fix.
- A plain `kiwi update` asked for a password on behalf of system apps that
  were not installed, which on a default install meant every run.
- A background process left behind by an installer kept the scope lock, so
  every later kiwi command failed with "another kiwi is already running",
  naming a pid that was gone. Only a reboot cleared it.
- `kiwi install` with no arguments installed every app in every catalog.

### Fixed — correctness

- System apps showed "update available" for ever: the comparison was against
  the metadata clone in the user's home rather than the installed commit. The
  GUI showed an update count nothing could clear.
- `kiwi check` missed system apps that came from a catalog, reporting
  "everything is up to date" with exit 0 while an update was pending.
- "Latest release" was whatever sorted last, so a release candidate
  permanently shadowed its own release and a tag like `wip-test` beat every
  version tag.
- Two catalogs whose repos share a name shared one clone directory; removing
  one deleted the other's. An app whose URL changed was reinstalled from the
  old origin, running the old installer and reporting success.
- `--cli-only` was forgotten after one update, so a cli-only app grew a GUI.
- "Up to date" was reported when the remote could not be reached at all.
- `--purge` never reached the app's own installer.
- List files were matched by substring, so `.../foo` counted as present when
  `.../foo-bar` was listed, and purging one dropped the other.
- Installing without a systemd user session aborted half way, after the
  binaries and before the lists and the default catalog.
- A manifest saved with CRLF made the app vanish behind "no apps matched".
- The "Kiwi Tools" app folder globbed for `org.kiwinetwork.*` while every app
  uses `eu.kiwinetwork.*`, so it was always empty.

### Fixed — hardening

- The credential helper was still invoked by `git ls-remote`, which execs git
  directly and bypassed the wrapper meant to prevent exactly that.
- As root, app names were resolved through `HOME` and `XDG_CONFIG_HOME`, so
  with `sudo -E` or a preserved `HOME` root took its instructions from a list
  the calling user can write. Root now reads only root-owned files, and
  refuses one that is group- or world-writable.
- Updating kiwi ran `sudo bash ~/.local/share/.../install.sh`, a user-writable
  script, as root — with a cached sudo timestamp, without a prompt.
- Catalog URLs were used unvalidated and without `--`; transports are now
  allowlisted.
- The root wrapper's name pattern also matched `--all`, `--force` and
  `--user`, and the polkit rule's stated rationale described a program that
  takes no arguments. It has taken names since 1.1.0.
- The GUI did not escape manifest-derived strings in its detail view, so a
  description containing `&` rendered empty and a manifest could inject markup
  into the row explaining why an app wants root. `ICON`, `SCREENSHOTS` and
  `ABOUT` were joined to the repo path unchecked, so `../` read any file the
  user could read. Installing an app that needs root now asks first.

### Added

- `kiwi pin <app> <tag>` / `kiwi unpin <app>` — stay on a tag until you say
  otherwise.
- `kiwi diff <app>` — the commits, the file stat and the installer's own diff
  that an update would apply.
- `kiwi info --installer <app>` — print the script before the first install.
- `kiwi doctor` — stale locks, version skew, list-file ownership, origin
  mismatch, missing timers.
- `--dry-run` for install, update and uninstall.
- Missing `DEPENDS` are named by `kiwi info` and before an install, which the
  manifest template already promised.
- bash completion for commands, options and app names.
- `tests/repro.sh`, `tests/check-version.sh`, a CI workflow, and a `LICENSE`
  file — the README said GPL-3.0-or-later while the repo shipped no licence.

### Changed

These alter behaviour an app author or a script could rely on:

- `kiwi install` requires an app name or an explicit `--all`.
- Only tags matching `^v?[0-9]+(\.[0-9]+){0,3}$` count as releases. A repo
  whose tags are not version-shaped now follows HEAD.
- A purging uninstall calls `./install.sh uninstall --purge` and exports
  `KIWI_PURGE=1`.
- Unknown options are an error instead of being treated as app names, and
  options may appear anywhere, including before the command.
- Metadata clones are shallow and fetched in parallel (`KIWI_FETCH_JOBS`).

## 1.2.1 — 2026-10-01

Stop claiming the system scope is missing when it is installed.

## 1.2.0 — 2026-10-01

A stalled fetch could wedge every later command until reboot.

## 1.1.3 — 2026-10-01

The desktop app is Kiwi Apps, the project stays kiwi-updater.

## 1.1.2 — 2026-10-01

Ship a real icon instead of borrowing a themed one.

## 1.1.1 — 2026-10-01

The root wrapper only knew about locally-added apps.

## 1.1.0 — 2026-10-01

Updating one system app no longer updates all of them.

## 1.0.2 — 2026-10-01

Only footnote the root marker when something uses it.

## 1.0.1 — 2026-10-01

Installer referenced a desktop file and icon that no longer exist.

## 1.0.0 — 2026-10-01

App explorer, installer and updater for git catalogs.
