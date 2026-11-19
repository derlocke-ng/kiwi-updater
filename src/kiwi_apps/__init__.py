"""Kiwi Apps — the desktop app of kiwi-updater (`kiwi-gui`).

It shows what `kiwi list` shows and does everything through the `kiwi`
command. Its shared parts (header bar, menu, About, Preferences, icon
chooser, window size, job strip) are the kit from kiwi-template, in kit/,
copied unchanged.
"""

from pathlib import Path

from .kit import AppInfo

__version__ = "2.9.0"
APP = "kiwi-updater"  # the folder names: ~/.config/kiwi-updater, ~/.local/share/kiwi-updater
APP_ID = "eu.kiwinetwork.KiwiUpdater"
NAME = "Kiwi Apps"
HOMEPAGE = "https://github.com/derlocke-ng/kiwi-updater"

# install.sh puts data/ next to the package (the stock icon alone); in a
# checkout it is data/icons, two levels up.
_HERE = Path(__file__).resolve().parent
_ICON = f"{APP_ID}.svg"
STOCK_ICON = next(
    (p for p in (_HERE.parent / "data" / _ICON, _HERE.parent.parent / "data" / "icons" / _ICON)
     if p.is_file()),
    _HERE / _ICON,
)

INFO = AppInfo(
    app=APP,
    app_id=APP_ID,
    name=NAME,
    version=__version__,
    description="Install and update open-source apps from git catalogs",
    homepage=HOMEPAGE,
    docs="https://kiwi-network.eu/docs/desktop/kiwi-updater/",
    glyph="updater",
    stock_icon=STOCK_ICON,
)
