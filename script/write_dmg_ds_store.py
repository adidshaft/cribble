#!/usr/bin/env python3
import os
import sys

from ds_store import DSStore
from mac_alias import Alias


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "Usage: write_dmg_ds_store.py <mount> <background.png> <app name> <applications alias>",
            file=sys.stderr,
        )
        return 64

    mount_path, background_path, app_name, applications_name = sys.argv[1:]
    ds_store_path = os.path.join(mount_path, ".DS_Store")

    background_alias = Alias.for_file(background_path)
    window_options = {
        "ContainerShowSidebar": False,
        "ShowSidebar": False,
        "ShowToolbar": False,
        "ShowStatusBar": False,
        "ShowTabView": False,
        "ShowPathbar": False,
        "WindowBounds": "{{120, 120}, {760, 460}}",
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
    }
    icon_view_options = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundImageAlias": background_alias.to_bytes(),
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": 13.0,
        "iconSize": 128.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }

    with DSStore.open(ds_store_path, "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = window_options
        store["."]["icvp"] = icon_view_options
        store["."]["icvl"] = ("type", "icnv")
        store[app_name]["Iloc"] = (182, 228)
        store[applications_name]["Iloc"] = (575, 228)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
