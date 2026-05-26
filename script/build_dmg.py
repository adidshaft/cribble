#!/usr/bin/env python3
import sys

import dmgbuild


def main() -> int:
    if len(sys.argv) != 6:
        print(
            "Usage: build_dmg.py <output.dmg> <volume name> <app bundle> <background.png> <applications alias name>",
            file=sys.stderr,
        )
        return 64

    output, volume_name, app_bundle, background, applications_name = sys.argv[1:]
    app_name = app_bundle.rstrip("/").split("/")[-1]
    settings = {
        "format": "UDZO",
        "filesystem": "HFS+",
        "compression_level": 9,
        "files": [app_bundle],
        "symlinks": {applications_name: "/Applications"},
        "background": background,
        "window_rect": ((120, 120), (760, 460)),
        "default_view": "icon-view",
        "show_toolbar": False,
        "show_status_bar": False,
        "show_sidebar": False,
        "show_tab_view": False,
        "show_pathbar": False,
        "icon_size": 128,
        "text_size": 13,
        "arrange_by": None,
        "grid_spacing": 100,
        "show_icon_preview": False,
        "include_icon_view_settings": True,
        "include_list_view_settings": False,
        "icon_locations": {
            app_name: (182, 228),
            applications_name: (575, 228),
        },
    }
    dmgbuild.build_dmg(output, volume_name, settings=settings)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
