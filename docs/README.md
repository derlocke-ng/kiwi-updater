# kiwi-updater documentation

kiwi-updater installs open-source apps from **git catalogs** and keeps them up
to date. Its command is `kiwi`; its desktop app is **Kiwi Apps** (`kiwi-gui`).

An app is a git repository with a `kiwi.manifest` file and an `install.sh`
script. A catalog is a git repository that lists apps. kiwi clones an app,
checks out its newest release tag, runs its installer, and updates it in the
background. It updates itself the same way.

## Pages

| Page | For | What it covers |
|---|---|---|
| [Install](install.md) | everyone | supported systems, the two install modes, packages per distro, uninstalling |
| [Using kiwi](usage.md) | everyone | every command, Kiwi Apps, background updates, settings |
| [Catalogs](catalogs.md) | everyone | adding catalogs, `apps.list`, pins and overrides |
| [Security](security.md) | everyone | what runs as root, when you type a password, what kiwi checks |
| [Writing an app](app-authors.md) | app authors | `kiwi.manifest`, `install.sh`, dependencies, icons, releases |
| [Signed releases](signing.md) | app authors, maintainers | `kiwi-release`, keys, changing keys |
| [Development](development.md) | contributors | tests, CI, releasing kiwi-updater itself |

The source of these pages is the `docs/` folder of
[derlocke-ng/kiwi-updater](https://github.com/derlocke-ng/kiwi-updater).
The pages link to each other with relative links, so the folder can be built
on its own or copied into a larger site.
