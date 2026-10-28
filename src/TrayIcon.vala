namespace Namarupa.Widgets {
    // A menu row that opens a submenu page. Styled like Wingpanel.PopoverMenuItem,
    // which can't be used here since it pops down its popover when clicked.
    private class SubmenuItem : Gtk.Button {
        class construct {
            set_css_name ("modelbutton");
        }

        public SubmenuItem (string text) {
            var label = new Gtk.Label (text) {
                hexpand = true,
                xalign = 0
            };

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            box.append (label);
            box.append (new Gtk.Image.from_icon_name ("pan-end-symbolic"));

            child = box;
            accessible_role = MENU_ITEM;
            update_property (Gtk.AccessibleProperty.LABEL, text, -1);
        }
    }

    // A single StatusNotifierItem, rendered as its icon with a popover menu
    // built live from its (optional) com.canonical.dbusmenu layout.
    // Rendered as a bare image with a click gesture rather than a button, so
    // no button styling (frame, hover background) is drawn around the icon.
    public class TrayIcon : Granite.Bin {

        public string bus_name { get; construct; }
        public string object_path { get; construct; }

        private ItemIface? proxy;
        private MenuClient? menu_client;
        private Gtk.Image icon;
        private Gtk.Box menu_box;
        private Gtk.Box submenu_box;
        private Granite.BackButton back_button;
        private Gtk.Stack menu_stack;
        private Gtk.Popover popover_widget;

        // Labels leading from the root to the open submenu page. Items are
        // tracked by label rather than id since some servers (e.g. NordVPN's)
        // rebuild their whole menu with fresh ids on every state change.
        private string[] submenu_path = {};

        public TrayIcon (string bus_name, string object_path) {
            Object (bus_name: bus_name, object_path: object_path);
        }

        construct {

            icon = new Gtk.Image.from_icon_name ("image-missing") {
                pixel_size = 16,
                margin_top = 4,
                margin_bottom = 4,
                margin_start = 6,
                margin_end = 6
            };

            menu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                margin_top = 3,
                margin_bottom = 3
            };

            back_button = new Granite.BackButton ("") {
                halign = Gtk.Align.START,
                margin_start = 6,
                margin_end = 6,
                margin_bottom = 3
            };

            submenu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var submenu_page = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                margin_top = 3,
                margin_bottom = 3
            };

            submenu_page.append (back_button);

            // Submenus can be long in some applications, so cap the
            // page height and scroll instead of growing past the screen.
            submenu_page.append (new Gtk.ScrolledWindow () {
                child = submenu_box,
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                propagate_natural_height = true,
                propagate_natural_width = true,
                max_content_height = 480
            });

            // Submenus are pages of the one popover rather than popovers of
            // their own: a nested popover is parented to its menu row, which a
            // layout update can destroy while the popover is still mapped.
            menu_stack = new Gtk.Stack () {
                hhomogeneous = false,
                vhomogeneous = false,
                interpolate_size = true,
                transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT
            };
            menu_stack.add_named (menu_box, "root");
            menu_stack.add_named (submenu_page, "submenu");

            popover_widget = new Gtk.Popover () {
                child = menu_stack
            };

            popover_widget.set_parent (this);

            // Granite.BackButton activates "navigation.pop" (normally provided by
            // Adw.NavigationView) and is insensitive while no such action exists.
            var pop_action = new SimpleAction ("pop", null);
            pop_action.activate.connect (close_submenu);

            var navigation_actions = new SimpleActionGroup ();
            navigation_actions.add_action (pop_action);
            popover_widget.insert_action_group ("navigation", navigation_actions);

            var shortcuts = new Gtk.ShortcutController () {
                scope = Gtk.ShortcutScope.LOCAL
            };

            shortcuts.add_shortcut (new Gtk.Shortcut (
                Gtk.ShortcutTrigger.parse_string ("<alt>Left"),
                new Gtk.NamedAction ("navigation.pop")
            ));

            popover_widget.add_controller (shortcuts);

            child = icon;

            var click = new Gtk.GestureClick ();
            click.released.connect (() => {
                popover_widget.popup ();

                // An autohide popover focuses its first child when shown, which
                // draws that row highlighted. Clear it; arrow keys still move
                // focus into the menu from here.
                var root = popover_widget.get_root ();
                if (root != null) {
                    root.set_focus (null);
                }
            });
            add_controller (click);

            popover_widget.notify["visible"].connect (() => {

              if (popover_widget.visible) {

                    if (menu_client != null) {
                        menu_client.opened ();
                    }

                    rebuild_menu ();

                  } else {

                    submenu_path = {};
                    menu_stack.set_visible_child_full ("root", Gtk.StackTransitionType.NONE);

                    if (menu_client != null) {
                        menu_client.closed ();
                    }
                }
            });

            connect_proxy.begin ();
        }

        public void close () {
            popover_widget.popdown ();
        }

        public override void dispose () {
            if (popover_widget != null) {
                popover_widget.unparent ();
                popover_widget = null;
            }

            base.dispose ();
        }

        private async void connect_proxy () {
            try {
                // Items announce changes with NewIcon/NewTitle/NewStatus rather than
                // PropertiesChanged, so a property cache would keep serving the first
                // values. Without it every property read is fetched from the item.
                proxy = yield Bus.get_proxy (BusType.SESSION, bus_name, object_path, DBusProxyFlags.DO_NOT_LOAD_PROPERTIES);
            } catch (Error e) {
                warning ("Failed to connect to StatusNotifierItem %s%s: %s", bus_name, object_path, e.message);
                return;
            }

            update_icon ();
            update_tooltip ();

            proxy.new_icon.connect (update_icon);
            proxy.new_title.connect (update_tooltip);
            proxy.new_status.connect (() => update_tooltip ());

            string? menu_path = proxy.menu;
            if (menu_path != null && menu_path != "" && menu_path != "/") {
                menu_client = new MenuClient (bus_name, menu_path);
                menu_client.layout_changed.connect (() => {
                    if (popover_widget.visible) {
                        rebuild_menu ();
                    }
                });
            }
        }

        private void update_icon () {

            string? name = proxy.icon_name;

            // Some items pass an absolute icon file path as IconName.
            if (name != null && Path.is_absolute (name)) {
                if (FileUtils.test (name, FileTest.EXISTS)) {
                    icon.set_from_file (name);
                    return;
                }
            } else if (name != null && name != "") {

                string? theme_path = proxy.icon_theme_path;
                if (theme_path != null && theme_path != "") {
                    // Electron apps all name their icon "status_icon_0" and
                    // differ only by IconThemePath. Look in the item's own path first:
                    // through the shared icon theme the first registered path would
                    // win for every one of them.
                    var file = find_icon_file (theme_path, name);
                    if (file != null) {
                        icon.set_from_file (file);
                        return;
                    }

                    Gtk.IconTheme.get_for_display (Gdk.Display.get_default ()).add_search_path (theme_path);
                }

                icon.set_from_icon_name (name);
                return;
            }

            var pixmaps = proxy.icon_pixmap;
            if (pixmaps != null && pixmaps.length > 0) {
                var texture = pixmap_to_texture (pixmaps[pixmaps.length - 1]);
                if (texture != null) {
                    icon.set_from_paintable (texture);
                    return;
                }
            }

            icon.set_from_icon_name ("image-missing");
        }

        private string? find_icon_file (string dir, string name) {
            foreach (unowned string ext in new string[] { "png", "svg", "xpm" }) {
                var path = Path.build_filename (dir, "%s.%s".printf (name, ext));
                if (FileUtils.test (path, FileTest.IS_REGULAR)) {
                    return path;
                }
            }

            return null;
        }

        private Gdk.Texture? pixmap_to_texture (IconPixmap pixmap) {
            if (pixmap.width <= 0 || pixmap.height <= 0 || pixmap.data.length < pixmap.width * pixmap.height * 4) {
                return null;
            }

            // Source pixels are big-endian ARGB32 (A R G B bytes); convert to R G B A.
            var bytes = new uint8[pixmap.data.length];
            for (int i = 0; i < pixmap.data.length; i += 4) {
                bytes[i] = pixmap.data[i + 1];
                bytes[i + 1] = pixmap.data[i + 2];
                bytes[i + 2] = pixmap.data[i + 3];
                bytes[i + 3] = pixmap.data[i];
            }

            return new Gdk.MemoryTexture (
                pixmap.width, pixmap.height, Gdk.MemoryFormat.R8G8B8A8,
                new Bytes.take (bytes), pixmap.width * 4
            );
        }

        private void update_tooltip () {
            tooltip_text = display_name ();
        }

        // The item's title, falling back to its id. Electron apps leave the
        // title empty and use ids like "Claude_status_icon_1", so the
        // "_status_icon_N" suffix is dropped to leave just the app name.
        private string display_name () {
            string? title = proxy.title;
            if (title != null && title != "") {
                return title;
            }

            string id = proxy.id ?? "";
            try {
                var name = new Regex ("_?status_icon_\\d+$").replace (id, -1, 0, "");
                if (name != "") {
                    return name;
                }
            } catch (RegexError e) {
                warning ("Failed to normalize id %s: %s", id, e.message);
            }

            return id;
        }

        private void rebuild_menu () {
            clear_box (menu_box);

            if (menu_client == null) {
                var activate_item = new Wingpanel.PopoverMenuItem.with_text (display_name ());
                activate_item.clicked.connect (() => {
                    popover_widget.popdown ();
                    try {
                        proxy.activate (0, 0);
                    } catch (Error e) {
                        warning ("Activate failed for %s: %s", bus_name, e.message);
                    }
                });
                menu_box.append (activate_item);
                return;
            }

            if (menu_client.root == null) {
                menu_client.refresh.begin ();
                return;
            }

            populate_menu_box (menu_box, menu_client.root.children);
            rebuild_submenu ();
        }

        // Rebuilds the open submenu page from the current layout, falling back
        // to the root page if that submenu no longer exists.
        private void rebuild_submenu () {
            if (submenu_path.length == 0) {
                return;
            }

            var node = find_submenu (submenu_path);
            if (node == null) {
                submenu_path = {};
                menu_stack.visible_child_name = "root";
                return;
            }

            back_button.label = submenu_path.length > 1
                ? clean_label (submenu_path[submenu_path.length - 2])
                : display_name ();

            clear_box (submenu_box);
            populate_menu_box (submenu_box, node.children);
        }

        private MenuItemNode? find_submenu (string[] path) {
            MenuItemNode? node = menu_client.root;
            foreach (unowned string label in path) {
                MenuItemNode? next = null;
                foreach (var child in node.children) {
                    if (is_submenu (child) && child.get_string ("label", "") == label) {
                        next = child;
                        break;
                    }
                }

                if (next == null) {
                    return null;
                }

                node = next;
            }

            return node;
        }

        private void open_submenu (MenuItemNode node) {
            menu_client.about_to_show (node.id);

            submenu_path += node.get_string ("label", "");
            rebuild_submenu ();
            menu_stack.visible_child_name = "submenu";
        }

        private void close_submenu () {
            if (submenu_path.length <= 1) {
                submenu_path = {};
                menu_stack.visible_child_name = "root";
                return;
            }

            submenu_path = submenu_path[0:submenu_path.length - 1];
            rebuild_submenu ();
        }

        private static bool is_submenu (MenuItemNode node) {
            return node.get_string ("children-display", "") == "submenu" && node.children.size > 0;
        }

        private static string clean_label (string label) {
            return label.replace ("_", "");
        }

        private void populate_menu_box (Gtk.Box box, Gee.ArrayList<MenuItemNode> nodes) {
            foreach (var node in nodes) {
                var widget = build_menu_widget (node);
                if (widget != null) {
                    box.append (widget);
                }
            }
        }

        private Gtk.Widget? build_menu_widget (MenuItemNode node) {
            if (!node.get_bool ("visible", true)) {
                return null;
            }

            if (node.get_string ("type", "standard") == "separator") {
                return new Gtk.Separator (Gtk.Orientation.HORIZONTAL) {
                    margin_top = 3,
                    margin_bottom = 3
                };
            }

            var label = clean_label (node.get_string ("label", ""));
            var enabled = node.get_bool ("enabled", true);
            var toggle_type = node.get_string ("toggle-type", "");

            if (is_submenu (node)) {
                var submenu_item = new SubmenuItem (label) {
                    sensitive = enabled
                };
                submenu_item.clicked.connect (() => open_submenu (node));

                return submenu_item;
            }

            if (toggle_type == "checkmark" || toggle_type == "radio") {
                var check = new Gtk.CheckButton.with_label (label) {
                    active = node.get_int ("toggle-state", 0) == 1,
                    sensitive = enabled,
                    margin_start = 12,
                    margin_end = 12,
                    margin_top = 3,
                    margin_bottom = 3
                };
                check.toggled.connect (() => menu_client.activate (node.id));

                return check;
            }

            var item = new Wingpanel.PopoverMenuItem.with_text (label) {
                sensitive = enabled
            };
            item.clicked.connect (() => {
                popover_widget.popdown ();
                menu_client.activate (node.id);
            });

            return item;
        }

        private void clear_box (Gtk.Box box) {
            var child = box.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                box.remove (child);
                child = next;
            }
        }
    }
}

