# ![icon](data/icon.png) Wingpanel Indicator Namarupa

![Screenshot](data/screenshot.png)

## For developers

You'll need the following dependencies:

- libglib2.0-dev
- libgee-0.8-dev
- libgranite-7-dev
- libgtk-4-dev
- libwingpanel-dev
- valac
- meson (>= 0.58)

On elementary OS these are all available from the default repositories. On
Debian-based distros without them preinstalled (such as plain Ubuntu), enable
elementary's PPAs first so `apt` can find the Granite/Wingpanel packages:

```bash
sudo add-apt-repository ppa:elementaryos/stable
sudo add-apt-repository ppa:elementaryos/os-patches
sudo apt update
```

Then install the build dependencies with:

```bash
sudo apt install libglib2.0-dev libgee-0.8-dev libgranite-7-dev libgtk-4-dev libwingpanel-dev valac meson
```

Run meson to configure the build environment and then ninja to build and install:

```bash
meson build --prefix=/usr
cd build
ninja
ninja install
```

Reboot (`reboot`) or kill Wingpanel (`killall io.elementary.wingpanel`)

To uninstall with ninja:

- Open a terminal in the build folder.
- Run `sudo ninja uninstall`

Reboot (`reboot`) or kill Wingpanel (`killall io.elementary.wingpanel`)

## Credits

This indicator descends from a chain of earlier forks. Thanks to the previous
authors whose work this is built on:

- [elementary LLC](https://elementary.io) — original Ayatana compatibility indicator
- [Adam Bieńkowski (donadigo)](https://github.com/donadigo/wingpanel-indicator-namarupa) — original Namarupa fork
- Paulo Galardi — contributor to the original fork
- [Lafydev](https://github.com/Lafydev/wingpanel-indicator-namarupa) — maintained fork
- [lenemter](https://github.com/lenemter/wingpanel-indicator-namarupa) — maintained fork
