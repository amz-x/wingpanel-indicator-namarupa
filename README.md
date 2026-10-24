# ![icon](data/icon.png) Wingpanel Indicator Namarupa

![Screenshot](data/screenshot.png)

## NixOS users

1. Ensure you are using the following nixpkgs in your flake configuration [amz-x/nixpkgs/nixos-unstable-pantheon](https://github.com/amz-x/nixpkgs/tree/nixos-unstable-pantheon).

2. Enable appindicator service
```nix
systemd.user.services.indicator-application-service = {
  enable        = true;
  description   = "Indicator Application Service";
  after         = [ "graphical-session.target" ];
  wantedBy      = [ "graphical-session.target" ];
  partOf        = [ "graphical-session.target" ];
  serviceConfig = {
    ExecStart   = "${pkgs.indicator-application-gtk3}/libexec/indicator-application/indicator-application-service";
  };
};
```

3. Add the wingpanel-indicator-namarupa
```nix
services.desktopManager.pantheon.extraWingpanelIndicators = with pkgs; [
  wingpanel-indicator-namarupa
];
```

## elementary OS users

On elementary OS these are all available from the default repositories. On
Debian-based distros without them preinstalled (such as plain Ubuntu), enable
elementary's PPAs first so `apt` can find the Granite/Wingpanel packages:

```bash
sudo add-apt-repository ppa:elementaryos/stable
sudo add-apt-repository ppa:elementaryos/os-patches
sudo apt update
```

### Indicator Application

1. Install indicator-application package:

```bash
sudo apt install indicator-application -y
```

2. Setup autostart file:

```bash
mkdir -p ~/.config/autostart
cp /etc/xdg/autostart/indicator-application.desktop ~/.config/autostart/
sed -i 's/^OnlyShowIn.*/OnlyShowIn=Unity;GNOME;Pantheon;/' ~/.config/autostart/indicator-application.desktop
```

### Developers

You'll need the following dependencies:

- libglib2.0-dev
- libgee-0.8-dev
- libgranite-7-dev
- libgtk-4-dev
- libwingpanel-dev
- valac
- meson (>= 0.58)

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
