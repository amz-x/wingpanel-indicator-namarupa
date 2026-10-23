namespace Namarupa.Widgets {
    // A single StatusNotifierItem, rendered as its icon with a popover menu
    // built live from its (optional) com.canonical.dbusmenu layout.
    // Gtk.MenuButton is a final GTK4 class and can't be subclassed directly,
    // so wrap one instead (Granite.Bin is a plain single-child container).
    public class TrayIcon : Granite.Bin {
        public string bus_name { get; construct; }
        public string object_path { get; construct; }

        private ItemIface? proxy;
        private MenuClient? menu_client;
        private Gtk.Image icon;
        private Gtk.Box menu_box;
        private Gtk.Popover popover_widget;
        private Gtk.MenuButton menu_button;

        public TrayIcon (string bus_name, string object_path) {
            Object (bus_name: bus_name, object_path: object_path);
        }

        construct {
            icon = new Gtk.Image.from_icon_name ("image-missing") {
                pixel_size = 16
            };

            menu_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                margin_top = 3,
                margin_bottom = 3
            };

            popover_widget = new Gtk.Popover () {
                child = menu_box
            };

            menu_button = new Gtk.MenuButton () {
                child = icon,
                popover = popover_widget,
                always_show_arrow = false
            };
            menu_button.add_css_class ("flat");

            child = menu_button;

            // Wingpanel's indicator entry claims every press it sees, which
            // cancels the menu button's own click (it only fires on release).
            // Claim presses first, in the capture phase, and handle them here.
            var click_controller = new Gtk.GestureClick () {
                button = 0,
                propagation_phase = Gtk.PropagationPhase.CAPTURE
            };
            click_controller.pressed.connect (() => {
                click_controller.set_state (Gtk.EventSequenceState.CLAIMED);

                if (click_controller.get_current_button () == Gdk.BUTTON_MIDDLE) {
                    secondary_activate ();
                } else if (popover_widget.visible) {
                    popover_widget.popdown ();
                } else {
                    menu_button.popup ();
                }
            });
            add_controller (click_controller);

            popover_widget.notify["visible"].connect (() => {
                if (popover_widget.visible) {
                    rebuild_menu ();
                }
            });

            connect_proxy.begin ();
        }

        private async void connect_proxy () {
            try {
                proxy = yield Bus.get_proxy (BusType.SESSION, bus_name, object_path, DBusProxyFlags.NONE);
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

        private void secondary_activate () {
            if (proxy == null) {
                return;
            }

            try {
                proxy.secondary_activate (0, 0);
            } catch (Error e) {
                warning ("SecondaryActivate failed for %s: %s", bus_name, e.message);
            }
        }

        private void update_icon () {
            string? name = proxy.icon_name;
            if (name != null && name != "") {
                string? theme_path = proxy.icon_theme_path;
                if (theme_path != null && theme_path != "") {
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
            string? title = proxy.title;
            tooltip_text = (title != null && title != "") ? title : proxy.id;
        }

        private void rebuild_menu () {
            clear_box (menu_box);

            if (proxy == null) {
                return;
            }

            if (menu_client == null) {
                var activate_item = new Wingpanel.PopoverMenuItem.with_text (
                    (proxy.title != null && proxy.title != "") ? proxy.title : proxy.id
                );
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

            var label = node.get_string ("label", "").replace ("_", "");
            var enabled = node.get_bool ("enabled", true);
            var toggle_type = node.get_string ("toggle-type", "");

            if (node.get_string ("children-display", "") == "submenu" && node.children.size > 0) {
                var submenu_item = new Wingpanel.PopoverMenuItem.with_text (label) {
                    sensitive = enabled
                };
                submenu_item.clicked.connect (() => {
                    menu_client.about_to_show (node.id);
                    show_submenu (submenu_item, node);
                });

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

        private void show_submenu (Gtk.Widget relative_to, MenuItemNode node) {
            var sub_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                margin_top = 3,
                margin_bottom = 3
            };
            populate_menu_box (sub_box, node.children);

            var sub_popover = new Gtk.Popover () {
                child = sub_box,
                has_arrow = false,
                position = Gtk.PositionType.RIGHT
            };
            sub_popover.set_parent (relative_to);
            sub_popover.popup ();
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

