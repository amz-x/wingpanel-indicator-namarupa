// Shows every StatusNotifierItem side by side directly in the panel. Each
// TrayIcon owns its own popover menu, so the indicator itself has none.
public class Namarupa.MainIndicator : Wingpanel.Indicator {
    private TrayManager manager;
    private Gtk.Box icons_box;
    private Gee.HashMap<string, Widgets.TrayIcon> icons;

    public MainIndicator () {
        Object (code_name: "namarupa");
    }

    construct {
        icons = new Gee.HashMap<string, Widgets.TrayIcon> ();
        icons_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
            valign = Gtk.Align.CENTER
        };

        // Wingpanel opens the indicator popover on any press its entry
        // receives. Presses on an icon are claimed by its menu button; claim
        // the rest (gaps, padding) here so no empty popover is shown.
        var click_controller = new Gtk.GestureClick ();
        click_controller.pressed.connect (() => {
            click_controller.set_state (Gtk.EventSequenceState.CLAIMED);
        });
        icons_box.add_controller (click_controller);

        visible = false;

        manager = new TrayManager ();
        manager.item_added.connect (on_item_added);
        manager.item_removed.connect (on_item_removed);
        manager.start ();
    }

    private void on_item_added (string bus_name, string object_path) {

        // Skip the legacy network applet if it's also registered separately.
        if (object_path.has_suffix ("nm_applet")) {
            return;
        }

        var key = bus_name + object_path;
        if (icons.has_key (key)) {
            return;
        }

        var tray_icon = new Widgets.TrayIcon (bus_name, object_path);
        icons[key] = tray_icon;
        icons_box.append (tray_icon);

        visible = true;
    }

    private void on_item_removed (string bus_name, string object_path) {
        var key = bus_name + object_path;
        var tray_icon = icons[key];
        if (tray_icon == null) {
            return;
        }

        icons.unset (key);
        icons_box.remove (tray_icon);

        if (icons.is_empty) {
            visible = false;
        }
    }

    public override Gtk.Widget get_display_widget () {
        return icons_box;
    }

    public override Gtk.Widget? get_widget () {
        return null;
    }

    public override void opened () {
    }

    public override void closed () {
    }
}

public Wingpanel.Indicator? get_indicator (GLib.Module module, Wingpanel.ServerType server_type) {
    if (server_type == Wingpanel.ServerType.GREETER) {
        return null;
    }

    debug ("Activating Namarupa indicator");
    return new Namarupa.MainIndicator ();
}

