public class Namarupa.MainIndicator : Wingpanel.Indicator {
    private TrayManager manager;
    private Gtk.Box icons_box;
    private Gtk.Stack main_stack;
    private Gee.HashMap<string, Widgets.TrayIcon> icons;

    public MainIndicator () {
        Object (code_name: "namarupa");
    }

    construct {
        icons = new Gee.HashMap<string, Widgets.TrayIcon> ();

        icons_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
            margin_start = 6,
            margin_end = 6,
            margin_top = 3,
            margin_bottom = 3
        };

        var no_icons_label = new Gtk.Label ("No Tray Icons") {
            sensitive = false,
            valign = Gtk.Align.CENTER,
            halign = Gtk.Align.CENTER,
            margin_top = 6,
            margin_bottom = 6,
            margin_start = 12,
            margin_end = 12
        };
        no_icons_label.add_css_class (Granite.STYLE_CLASS_H3_LABEL);

        main_stack = new Gtk.Stack ();
        main_stack.add_named (no_icons_label, "empty");
        main_stack.add_named (icons_box, "icons");
        main_stack.visible_child_name = "empty";

        visible = true;

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

        main_stack.visible_child_name = "icons";
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
            main_stack.visible_child_name = "empty";
        }
    }

    public override Gtk.Widget get_display_widget () {
        return new Gtk.Image.from_icon_name ("view-more-horizontal-symbolic") {
            pixel_size = 16
        };
    }

    public override Gtk.Widget? get_widget () {
        return main_stack;
    }

    public override void opened () {
    }

    public override void closed () {
    }
}

public Wingpanel.Indicator? get_indicator (GLib.Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    if (server_type != Wingpanel.IndicatorManager.ServerType.SESSION) {
        return null;
    }

    debug ("Activating Namarupa indicator");
    return new Namarupa.MainIndicator ();
}

