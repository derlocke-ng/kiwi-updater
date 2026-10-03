# kiwi-updater — fix plan

Audit of `derlocke-ng/kiwi-updater` at commit `19cf130` (tag `v1.2.1`), 2 October 2026.
Written to be worked through with Claude Code in VS Code, one finding at a time.

Line numbers refer to `v1.2.1`. They drift as soon as you start editing, so each
finding also names the function.

## Status — worked through in 1.3.0

Phases 0 to 3 are implemented, one commit per finding, on top of `v1.2.1`.
`tests/repro.sh` reports 22 × `ok` (the original 21 plus `F11b` and `S5`, added
while fixing F11 and S5), and `shellcheck -S warning` is clean.

Phase 4 is deliberately **not** done: it is a list of improvements rather than
of defects, and none of it is needed to make the findings above go away.

Two corrections to this plan, found while working through it:

- The container package list was missing **gawk**. `fedora:latest` ships no
  `awk`, `remote_target` is built on `awk`, so in the container every app was
  simply unreachable — and checks that assert "this failed" went green for the
  wrong reason, F1 among them. `tests/repro.sh` now refuses to start when a
  tool it needs is missing, and the baseline was re-verified afterwards.
- F5 has a third bug the plan does not mention: `root_kiwi` wrote its three
  explanatory `info` lines to **stdout**, and its stdout *is* the program path
  the caller executes. A missing root copy therefore ran
  `sudo ":: This needs a root-owned copy…"` with the path appended. Fixed with
  the rest of F5.

## What is solid, and should stay as it is

- The scope split (user clone in `~/.local`, root clone in `/var/lib`) and the reasoning behind it.
- Bounded network calls and the lock wait added in 1.2.0.
- The GUI being a thin layer over `--porcelain` output.
- Comments that explain *why*. Keep writing them that way.

## How the findings were checked

| Mark | Meaning |
|---|---|
| **[run]** | Reproduced by running v1.2.1 in a sandbox (root plus an unprivileged user, local git remotes). `tests/repro.sh` reproduces it. |
| **[read]** | Found by reading the code. Not executed (no GTK or polkit in the sandbox). Confirm before fixing. |

All 21 checks in `tests/repro.sh` print `BUG` on v1.2.1.

## Files that come with this plan

| File | Put it at | Purpose |
|---|---|---|
| `FIXPLAN.md` | repo root | this plan |
| `repro.sh` | `tests/repro.sh` | prints `BUG <id>` / `ok <id>` per finding; exits non-zero while any remain |
| `reference-fixes.patch` | repo root, do not commit | a scratch implementation of F1–F19, S1 and S2 that turns all 21 checks green and applies cleanly to v1.2.1 |

The patch is a worked answer, not a merge request. It was written to prove the
fixes below are feasible and that the checks can pass. Its known gaps are listed
in the appendix. Use it as a reference per finding, or apply it on a branch and
then review and split it.

## Working with Claude Code

Suggested prompts, in order:

1. `Read FIXPLAN.md. Do Phase 0 only. Show me the diff before committing.`
2. `Fix F1 and F2 from FIXPLAN.md. Run tests/repro.sh F1 F2 in the container. One commit per finding.`
3. Continue finding by finding. After each phase: `Run the full tests/repro.sh and shellcheck, then summarise what changed.`

Rules for Claude while working on this repo:

- **Never run `tests/repro.sh` on the host.** It needs root and wipes
  `/etc/kiwi-updater`, `/var/lib/kiwi-updater` and `/usr/local/bin/kiwi`. Container only:
  ```bash
  podman run --rm -v "$PWD":/src:ro,Z fedora:latest bash -c \
    'dnf -y -q install git-core gawk util-linux shadow-utils procps-ng python3 >/dev/null && bash /src/tests/repro.sh'
  ```
  (Verified on `fedora:latest` with podman. `gawk` had to be added to the list in
  the original plan: the image ships no `awk`, so `remote_target` failed for every
  app and several checks reported `ok` only because nothing could be reached.
  `tests/repro.sh` now refuses to start when a tool it needs is missing.)
- Never run `install.sh`, `get-kiwi.sh`, `sudo` or `pkexec` on the host to "try something".
- One finding per commit, message in the repo's existing style (`1.2.2 — <what the user would have noticed>`).
- A fix is done when its check prints `ok` **and** no other check regressed.
- Do not change the porcelain field order. Append new fields at the end only; the GUI indexes by position.
- Keep the marker format backwards compatible: line 1 is the installed commit, then `gui=0|1`.
- No new runtime dependencies beyond bash, git, coreutils, util-linux, awk, sed, grep.
- If a fix needs a design decision this plan did not make, stop and ask.

## Invariants

These are the project's own rules. Several findings below are places where the code breaks them.

1. Root never executes a file the user can write, and never reads configuration from a path the user can write.
2. A failed step is never reported as success, in the exit code or in the marker.
3. What `kiwi info` and `kiwi list` show is what `kiwi install` and `kiwi update` will act on.
4. Nothing asks for a password unless it is about to do root work that can succeed.

---

## Phase 0 — safety net

Do this first. There are currently no tests and no CI.

1. Add `tests/repro.sh` (supplied). Confirm it reports 21 × `BUG` on the untouched tree.
2. Add `tests/check-version.sh`: fail unless `KIWI_VERSION` in `bin/kiwi`, `VERSION` in `kiwi.manifest`, and (when `HEAD` is tagged) the tag all agree. The version lives in three places today.
3. Add `.github/workflows/ci.yml` (sketch, untested):
   ```yaml
   name: ci
   on: [push, pull_request]
   jobs:
     lint:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - run: shellcheck -S warning bin/kiwi install.sh get-kiwi.sh data/kiwi-system-update templates/install.sh tests/*.sh
         - run: python3 -m py_compile gui/kiwi-gui
         - run: bash tests/check-version.sh
     repro:
       runs-on: ubuntu-latest
       container: fedora:latest
       steps:
         - run: dnf -y -q install git-core util-linux shadow-utils procps-ng python3
         - uses: actions/checkout@v4
         - run: bash tests/repro.sh
   ```
   `shellcheck -S warning` currently reports SC2034 (`SELF`, `refname`, `SYS_REPOS` unused), SC2155 (lines 492, 508), SC2115 (955) and SC2046 (1036, 1038). Fix those in this phase so lint starts green. The `repro` job stays red until Phase 2 is finished; mark it `continue-on-error: true` until then.
4. Add a `LICENSE` file. The README and manifest say GPL-3.0-or-later but the repo ships no licence text.

---

## Phase 1 — wrong state, data loss, unwanted root prompts

### F1 — a failed installer is recorded as installed [run]

- **Where:** `install_one`, `update_one` (`bin/kiwi:468-503`), called as `install_one … || rc=1` in `dispatch` (`:570-572`).
- **What happens:** bash ignores `set -e` inside a function called on the left of `||`. The installer fails, `write_marker` runs anyway, kiwi prints "installed" and exits 0. Same for updates, which also send the "Apps updated" notification.
- **Fix:** do not rely on `set -e` in these functions. Check each step: `dir="$(sync_repo …)" || return 1`, `run_installer … || { warn …; return 1; }`, and only then `write_marker`. `sync_repo` must `return 1` (not `die`, which only leaves the `$(…)` subshell) when clone, fetch or checkout fails.
- **Also:** line 482 prints "updateed". Use `${action%e}ed`.
- **Check:** `tests/repro.sh F1`

### F2 — a failed uninstaller still deletes the clone [run]

- **Where:** `uninstall_one` (`bin/kiwi:505-515`).
- **What happens:** the app's files stay on disk, the clone holding its uninstaller is removed, exit code 0. There is no clean way left to remove the app.
- **Fix:** if the uninstaller fails, keep the clone and the marker, warn, return 1. Let `--force` drop the clone anyway.
- **Check:** `tests/repro.sh F2`

### F3 — uninstalling kiwi always purges the system scope [run]

- **Where:** `install.sh:232`, `${PURGE:+--purge}`.
- **What happens:** `PURGE` is `0` or `1`, never empty, so `:+` always expands. `install.sh uninstall --with-system` without `--purge` runs the root half with `--purge` and deletes `/etc/kiwi-updater` and `/var/lib/kiwi-updater`, including the clones of every system app that is still installed. The same line runs on any interactive uninstall when the system scope exists.
- **Fix:** build an array: `root_args=(); (( PURGE )) && root_args+=(--purge)`.
- **Check:** `tests/repro.sh F3`

### F4 — the root-owned kiwi never updates itself [run]

- **Where:** `app_entries` (`bin/kiwi:178`), `app_scopes` (`:210-224`), `collect_targets` (`:552`), `kiwi.manifest` (`SCOPES=user`).
- **What happens:** the system list entry for kiwi-updater gets `scope=system` as a filter, the manifest declares only `user`, the intersection is empty, the app is skipped. With no other system app the timer unit fails every six hours with "no apps matched". README line 190 says the timer "self-updates the root copy"; it does not. The copy that runs as root therefore never receives fixes on its own.
- **Fix:**
  1. A scope filter on an entry from a **local** list (not a catalog) is the administrator's decision and wins over the manifest. Mark local entries in `app_entries` (for example an internal `local=1` option) and honour it in `app_scopes`.
  2. `--all` with nothing to do is not an error: log and exit 0. Keep the error for explicitly named apps.
  3. Add a skew notice: when `/usr/local/bin/kiwi` exists and its `version` differs from the user copy, say so and name the command that fixes it.
- **Migration:** installed root copies at ≤ 1.2.1 cannot pick this fix up by themselves. The release notes must tell people with the system scope to re-run the bootstrap once: `curl … get-kiwi.sh | bash -s -- --with-system`.
- **Check:** `tests/repro.sh F4`

### F5 — `kiwi update` asks for root for apps that are not installed [run]

- **Where:** `dispatch` (`bin/kiwi:556-560`, `:597-614`); `as_root "$(root_kiwi)"` at `:613`, `:881`, `:907`, `:948`.
- **What happens:** `sys_names` collects every system-scope target without checking whether it is installed. The default catalog lists kiwi-killswitch (`SCOPES=user system`), so on a default install a plain `kiwi update` goes to "escalating for system apps" and tries to set up the system scope with a password prompt. Second bug in the same line: `die` inside `$(root_kiwi)` only leaves the subshell, so kiwi goes on to run `pkexec "" update --system …` with an empty program name.
- **Fix:** for `update` and `uninstall`, include a system target only when `is_installed system "$url"`. Capture first, then use: `rk="$(root_kiwi)" || return 1; as_root "$rk" …`. Apply the same capture at all four call sites.
- **Check:** `tests/repro.sh F5`

### F6 — anything an installer leaves running holds the lock [run]

- **Where:** `acquire_lock` (`bin/kiwi:389`), `run_installer` (`:441-447`).
- **What happens:** the lock is fd 9 and every child inherits it. If an installer starts a background process outside systemd, that process keeps the flock after kiwi exits. Every later kiwi command waits and then fails with "another kiwi is already running", naming a pid that no longer exists. This is a second route to the wedge 1.2.0 fixed for stalled fetches.
- **Fix:** close the fd for children: `bash "./$inst" "$action" 9>&-`, and the same on the `as_root`/`pkexec` calls.
- **Check:** `tests/repro.sh F6`

### F7 — `kiwi install` with no arguments installs every app in every catalog [run]

- **Where:** `bin/kiwi:1041`, `"${ARGS[@]:---all}"`.
- **Fix:** require a name or an explicit `--all` for `install`. Keep `kiwi update` with no arguments meaning "everything installed".
- **Check:** `tests/repro.sh F7`

---

## Phase 2 — correctness

### F8 — metadata clones are never refreshed; system apps show "update available" forever [run]

- **Where:** `sync_meta` (`bin/kiwi:199-207`), `cmd_list` (`:690-723`).
- **What happens:** `sync_meta` clones once and never fetches again. `cmd_list --check` compares the remote against `HEAD` of the *metadata* clone in the user's home, not against the clone the app was installed from. For a system app that means: after root updates it, the user still sees the old version and `update-available`, permanently. The GUI calls `list --porcelain --check`, so it shows "1 update ready" permanently. Apps that are not installed keep showing the version from the day they were first listed.
- **Fix:**
  1. Per scope, compare the remote target with **line 1 of that scope's marker** (`$(repos_dir "$sc")/<name>/.kiwi-installed`). The system repos are world-readable.
  2. Read name, version and description from the installed clone when the app is installed, from the metadata clone otherwise.
  3. On `list --check` and `sync`, bring metadata-only clones (no marker in them) to the commit an install would use. Never move the working tree of an installed clone outside `update`.
- **Check:** `tests/repro.sh F8`

### F9 — `kiwi check` does not see system apps that come from a catalog [run]

- **Where:** `cmd_check` (`bin/kiwi:843-865`) and the legacy helpers `entries`, `raw_entries`, `scopes` (`:120-126`, `:249-272`).
- **What happens:** `check` still uses the pre-manifest model where a catalog entry without `scope=` is user-only. It reports "everything is up to date" and exits 0 while a system app has a pending update.
- **Fix:** rewrite `cmd_check` on `app_entries` plus the per-scope marker comparison from F8, sharing one helper with `cmd_list`. Then delete `entries`, `raw_entries` and `scopes`.
- **Check:** `tests/repro.sh F8` (runs F9 as part of the same setup)

### F10 — "latest release" is whatever sorts last [run]

- **Where:** `remote_target` (`bin/kiwi:347`), `get-kiwi.sh:30`.
- **What happens:** every tag is a candidate. `sort -V` puts `v2.0.0-rc1` after `v2.0.0`, so once a release candidate exists the final release is never installed. A tag called `wip-test` beats every version tag.
- **Fix:** only tags matching `^v?[0-9]+(\.[0-9]+){0,3}$` are releases. Pre-releases are reachable through `ref=` only. No matching tag means default-branch HEAD, as today. Use the same rule in `get-kiwi.sh`, and document it in the README and `templates/kiwi.manifest`.
- **Check:** `tests/repro.sh F10`

### F11 — identity is the URL basename, and collisions are silent [run]

- **Where:** `dir_name` (`bin/kiwi:274-277`), `sync_catalogs` (`:143`), `app_entries` (`:190-191`), `sync_repo` (`:452-464`), `catalog remove` (`:955`).
- **What happens:**
  - Two catalogs whose repos share a name (`org1/catalog`, `org2/catalog`) share one clone directory. The second is never cloned, its apps never appear, and removing it deletes the first one's clone.
  - Two apps with the same repo name shadow each other by catalog sort order. If the URL behind an installed name changes, `kiwi info` shows the new source while `kiwi install` fetches from the old `origin`, prints `fatal: reference is not a tree`, runs the old installer and reports success. That breaks invariant 3.
- **Fix (minimal, no directory migration):**
  1. `catalog add`: refuse when another registered catalog has the same `dir_name`, naming the existing URL.
  2. Before using a clone, compare `remote.origin.url` with the entry URL. Metadata-only clone: `git remote set-url` and refetch. Installed clone: refuse to switch silently; say where it was installed from, what the list says now, and that `kiwi uninstall <name>` is needed first.
  3. In `app_entries`, warn once when two different URLs map to the same name.
- **Check:** `tests/repro.sh F11` covers the catalog case. Add a check for the app case.

### F12 — `--cli-only` is forgotten after one update [run]

- **Where:** `write_marker` (`bin/kiwi:304-306`).
- **What happens:** the `>` redirect truncates the marker before `effective_gui` reads the old `gui=` line from it, so the flavour falls back to auto-detection. On a desktop, a cli-only install gets its GUI installed on the second update.
- **Fix:** compute the flavour and the commit into variables first, write to a temp file, `mv` into place.
- **Check:** `tests/repro.sh F12`

### F13 — "up to date" when the remote could not be reached [run]

- **Where:** `update_one` (`bin/kiwi:485-503`), `sync_repo` (`:454-464`).
- **What happens:** if `ls-remote` or `fetch` fails, HEAD has not moved, so kiwi prints "is up to date" and exits 0. Separately, the comparison uses the working-tree `HEAD` rather than the recorded commit: if a run is killed between checkout and install (the unit has `TimeoutStartSec=900`), the next run sees `HEAD == target` and never applies the update.
- **Fix:** compare against marker line 1. When the sync fails, say "could not check"; return non-zero for an app asked for by name, and only warn in `--all` mode so the timer does not fail whenever the machine is offline.
- **Check:** `tests/repro.sh F13`

### F14 — `--purge` never reaches the app [run]

- **Where:** `run_installer` (`bin/kiwi:435-448`), `uninstall_one` (`:516-522`), README line 48, `templates/install.sh`.
- **What happens:** README says `--purge` "also drops its config". The code only removes the URL from the local list; the installer is called as `install.sh uninstall` with nothing else. Apps in the catalog (ensconce) already implement `uninstall --purge` and never receive it.
- **Fix:** on a purging uninstall pass `--purge` as the second argument and export `KIWI_PURGE=1`. Add both to the README env table and to `templates/install.sh`.
- **Check:** `tests/repro.sh F14`

### F15 — list files are matched by substring and rewritten in place [run]

- **Where:** `grep -qF` / `grep -vF` at `bin/kiwi:519`, `:885`, `:911`, `:951-954`; `install.sh:83`, `:129`, `:187`.
- **What happens:** with `…/foo-bar` listed, `kiwi add …/foo` says "already in". Purging `…/foo` also deletes the `…/foo-bar` line. The rewrite is `cat tmp > file`, which leaves a truncated list if interrupted.
- **Fix:** two helpers, `list_has file url` and `list_drop file url`, comparing the first field exactly after stripping a trailing `/` and `.git`. Write to a temp file in the same directory and `mv`.
- **Check:** `tests/repro.sh F15`

### F16 — password prompt, then "unknown app" [run]

- **Where:** escalation in `dispatch` (`bin/kiwi:613`); `resolve` as root.
- **What happens:** the user side resolves a name from the user's catalogs and escalates by name. Root resolves the name again from root-owned lists only. For an app that only a user-level catalog lists, the user authenticates and root answers "unknown app". Root refusing is correct; asking first is the bug (invariant 4).
- **Fix:** before escalating an install, check that the **URL** is present in `/etc/kiwi-updater/apps.list` or in a catalog under `/var/lib/kiwi-updater/catalogs` (both world-readable). If not, do not prompt; print the exact `kiwi catalog add --system <url>` or `kiwi add --system <url>` to run. Matching on URL also closes the gap where the user is shown one repo's `ROOT_REASON` and root installs a different repo with the same name.
- **Check:** `tests/repro.sh F16`

### F17 — the installer stops halfway without a systemd user session [run]

- **Where:** `install.sh:123-124` (and `:174-175` for root).
- **What happens:** under `set -e`, a failing `systemctl --user` (ssh without lingering, containers, `su -`) aborts after the binaries are copied and before the lists, default catalog and self-registration exist.
- **Fix:** treat the timer as optional. On failure say that background updates are not enabled and print the command to enable them later, then continue.
- **Check:** `tests/repro.sh F17`

### F18 — manifest parsing is too literal [run]

- **Where:** `manifest_get` (`bin/kiwi:287-291`), README lines 92-93.
- **What happens:**
  - A manifest saved with CRLF gives `SCOPES=user\r`, which matches no scope. The app is skipped and the error is "no apps matched (is your apps.list empty?)".
  - The README example puts comments on the value lines (`COMPONENTS=cli   # cli gui daemon …`). Copied literally, the comment becomes part of the value, and because it contains "gui" the app is treated as having a GUI component.
  - Tabs and control characters in values go straight into the tab-separated porcelain and onto the terminal.
- **Fix:** in `manifest_get` strip `\r` and control characters, turn tabs into spaces, trim trailing whitespace. Do not add inline-comment parsing (descriptions may contain `#`); move the README comments onto their own lines. Validate `NAME` against `^[A-Za-z0-9][A-Za-z0-9._-]*$` and fall back to the directory name when it does not match.
- **Check:** `tests/repro.sh F18`

### F19 — the "Kiwi Tools" app folder can never contain anything [run]

- **Where:** `sync_app_folder` (`bin/kiwi:637`, comment at `:625`).
- **What happens:** it globs `org.kiwinetwork.*.desktop`. Kiwi's own entry and kiwi-killswitch both use `eu.kiwinetwork.*`.
- **Fix:** glob `eu.kiwinetwork.*.desktop`.
- **Check:** `tests/repro.sh F19`

---

## Phase 3 — hardening

### S1 — the credential helper is still used on `ls-remote` [run]

- **Where:** `git()` wrapper (`bin/kiwi:74`), `remote_target` (`:334`).
- **What happens:** `timeout … git ls-remote` executes the git binary, not the shell function that adds `-c credential.helper=`. For any URL that answers 401, the user's helper (keyring, `gh`, a stored token) is invoked. The comment above the wrapper promises this never happens.
- **Fix:** set it through the environment so every git child gets it: `export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=` (git ≥ 2.31). The shell function can then go.
- **Check:** `tests/repro.sh S1`

### S2 — root trusts `HOME` and `XDG_CONFIG_HOME` [run]

- **Where:** path setup (`bin/kiwi:18`, `:48-53`), `catalog_urls` (`:132`), `app_entries` (`:173`).
- **What happens:** as root, `app_entries` still reads the "user" list, located through `HOME`/`XDG_CONFIG_HOME`. `pkexec` and the systemd unit sanitise these, and Fedora's default sudoers resets them. With `sudo -E`, an `env_keep` entry, or a distro that preserves `HOME`, root resolves app names from a list the user can write, and local entries win over catalogs. In the sandbox, a leaked `XDG_CONFIG_HOME` was enough to make root run an installer from the user's list.
- **Fix:** when `EUID` is 0, do not derive anything from the environment: read only `/etc/kiwi-updater` and `/var/lib/kiwi-updater`. Refuse a list file that is not owned by root or is group/world-writable. `kiwi add` as root without `--system` should mean `--system` or fail, not write to a root "user" list.
- **Check:** `tests/repro.sh S2`

### S3 — interactive self-update runs a user-writable script as root [read]

- **Where:** `install.sh:230-232` (`as_root bash "$SELF" "$ACTION"`), `root_kiwi` (`bin/kiwi:41`).
- **What happens:** on a terminal, when the system scope exists, updating kiwi runs `sudo bash ~/.local/share/…/install.sh update`, which also copies the user checkout's `bin/kiwi` to `/usr/local/bin/kiwi`. That is exactly what invariant 1 forbids, and with a cached sudo timestamp it happens without a prompt.
- **Fix (after F4):** for `update`, call the root-owned path instead: `pkexec /usr/local/libexec/kiwi-system-update kiwi-updater`. For `uninstall`: `as_root /usr/local/bin/kiwi uninstall --system kiwi-updater`. Bootstrap (`install --with-system`) stays a password-gated exception; say so in the README's "Why the split layout" section. Better still, have the root half clone its own copy from the origin URL and install from that, so `/usr/local/bin/kiwi` is always an upstream commit.

### S4 — URLs from catalogs are used unvalidated [read]

- **Where:** every `git clone`/`ls-remote` call site (`bin/kiwi:150`, `:204`, `:334`, `:458`), `cmd_add`, `catalog add`.
- **What happens:** nothing checks scheme or shape, and URLs are passed without `--`. `kiwi list` clones every entry of every catalog before the user has chosen to install anything, and the root timer does the same as root. No exploit was demonstrated; git blocks `ext::` by default. This is defence in depth.
- **Fix:** one `valid_url` used everywhere. Accept `https://` always, and absolute local paths only from local lists (needed for tests and development). Reject a leading `-`, whitespace, control characters, and a basename of `.` or `..`. Put `--` before every URL argument. As root, also export `GIT_ALLOW_PROTOCOL=https:file`.

### S5 — the passwordless wrapper and its documentation [read, regex run]

- **Where:** `data/kiwi-system-update:45`, `data/polkit/50-kiwi-updater.rules:3-4,11`, README line 197.
- **What happens:**
  - The name pattern `^[A-Za-z0-9._-]+$` accepts `--all`, `--force`, `--user`. A name must also be in the known list, so this needs a trusted repo whose manifest `NAME` looks like an option. Cheap to close.
  - The polkit rule's comment still says the wrapper "takes no arguments and always runs `kiwi update --all --system`". Since 1.1.0 it takes names. A security rule with a wrong rationale gets edited wrongly later.
  - README says "local `wheel` users"; the rule deliberately does not require `subject.local`.
- **Fix:** pattern `^[A-Za-z0-9][A-Za-z0-9._-]*$`. Teach kiwi's option loop `--` as end of options and call `kiwi update --system --quiet -- "$@"`. Rewrite the polkit comment to describe the validated-selection design. Change README to "active `wheel` sessions".

### S6 — GUI [read]

- **Where:** `gui/kiwi-gui`.
- **Markup:** `Adw.ActionRow` titles and subtitles are Pango markup by default. `_make_row` and the catalog rows escape; the detail dialog does not (`:337`, `:340`, `:358-361`, `:375`, `:405`, and the group description at `:351`). A description containing `&` renders empty; a manifest can inject markup into the "why it wants root" row. Wrap every manifest-derived string in `GLib.markup_escape_text`.
- **Paths:** `ICON`, `SCREENSHOTS` and `ABOUT` are joined to the repo dir unchecked (`:310`, `:318`, `:385`). An absolute path or `../` reads any file the user can read into the dialog. Resolve with `os.path.realpath` and require the result to stay inside the repo dir.
- **Stdin:** `Popen` inherits stdin (`:1011`, `:1033`). Started from a terminal, `as_root` sees a tty, picks `sudo`, and the password prompt appears in that terminal while the window looks hung. Pass `stdin=subprocess.DEVNULL` so `pkexec` is used.
- **Confirmation:** "Install" on a card runs immediately, including for apps that need root. Show `ROOT_REASON` in a confirmation dialog first for system-scope apps.
- **Cosmetic:** for dual-scope apps the list shows "(cli-only) (cli-only)" (`bin/kiwi:716-718` appends once per scope).

---

## Phase 4 — make it better

In rough order of value:

1. **The README's own roadmap**, which is the right one: `kiwi pin`/`unpin`, `kiwi diff <app>`, `kiwi info --installer <app>`. `diff` becomes straightforward once F8 and F13 make the marker the record of what is installed.
2. **`--dry-run`** for install, update and uninstall: print scope, URL, ref and installer path, run nothing.
3. **`kiwi doctor`**: stale lock, version skew between user and root copy (F4), list file ownership (S2), origin mismatch (F11), missing timer (F17).
4. **`DEPENDS` in the CLI.** `templates/kiwi.manifest` says kiwi "shows what is missing before installing". Only `info --porcelain` does. Show it in plain `kiwi info` and warn before `install`.
5. **Cheaper metadata.** Listing clones every app in full, one after another. Use `--depth 1` for metadata-only clones and fetch in parallel. Longer term, let a catalog ship a generated index (name, description, version, scopes per app) so browsing needs no per-app clone.
6. **Arguments.** Unknown `--flags` are treated as app names ("unknown app: --frce"); flags before the command fail. Reject unknown options, accept `--version`.
7. **Small things.** `notify-send --app-name="Kiwi Updater"` while the app is called "Kiwi Apps". `After=network-online.target` in the *user* unit has no effect. README line 12 says the CLI needs "only git + coreutils"; it also needs util-linux (`flock`). `get-kiwi.sh`: wrap the body in `main() { … }; main "$@"` so a truncated download cannot run half a script.
8. **Docs.** A `CHANGELOG.md` built from the release commit subjects, and bash completion for app names from `kiwi list --porcelain --no-sync`.

---

## Release

- Phase 1 is a patch release with a **manual step** for system-scope users (F4 migration). Put it at the top of the notes.
- F7 (bare `install`), F10 (tag rule) and F14 (`--purge` argument) change behaviour that app authors or scripts may rely on. Make that a minor version and name all three in the notes.
- Before tagging: `tests/check-version.sh`, full `tests/repro.sh` in the container, then one real install on a Silverblue/Bluefin VM with and without `--with-system`. The sandbox cannot exercise polkit, the systemd timers or the GUI.

---

## Appendix — the reference patch

`reference-fixes.patch` changes `bin/kiwi` and `install.sh` only (165 insertions, 56 deletions). With it, all 21 checks pass and the normal flows (catalog add, list, search, info, install, update, check, dual-scope install as user and root, offline timer run, uninstall with and without `--purge`) still behave in the sandbox.

Known gaps, deliberately left for the real implementation:

- S3, S4, S5, S6 and everything in the GUI, wrapper and polkit rule are untouched.
- F11: only the catalog collision is handled, not app-name collisions or a changed origin.
- F8: metadata is refreshed on `list --check` only, not on `kiwi sync`.
- F18: `NAME` is not validated; the README example is not corrected.
- S2: as root the user list is pointed at `/dev/null`, so `kiwi add` as root without `--system` silently does nothing. Ownership and mode of list files are not checked.
- F4: no skew notice; the migration is not automated.
- The legacy helpers (`entries`, `raw_entries`, `scopes`) and the `git()` function are still present.
- `get-kiwi.sh`, README and `templates/` are not updated.
