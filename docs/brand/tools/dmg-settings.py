# dmgbuild settings for the Stillbreak installer window (see docs/brand/).
# Usage: dmgbuild -s docs/brand/tools/dmg-settings.py \
#          -D app=.build/Stillbreak.app -D background=docs/brand/dmg-background.tiff \
#          Stillbreak dist/Stillbreak-<version>.dmg
import os

app = defines["app"]  # noqa: F821  (dmgbuild injects `defines`)
app_name = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]  # noqa: F821
window_rect = ((200, 200), (660, 432))  # size includes the 32 px title bar, leaving a 660x400 content area
icon_size = 128
text_size = 13
icon_locations = {app_name: (165, 205), "Applications": (495, 205)}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
