namespace Namarupa {
    // A node of the menu tree exposed over the com.canonical.dbusmenu
    // protocol. Kept as a loose property bag since the set of properties
    // that matter differs per item type (separator/standard/checkmark/…).
    public class MenuItemNode : Object {

        public int32 id;
        public HashTable<string, Variant> properties = new HashTable<string, Variant> (str_hash, str_equal);
        public Gee.ArrayList<MenuItemNode> children = new Gee.ArrayList<MenuItemNode> ();

        public MenuItemNode (int32 id) {
            this.id = id;
        }

        public string get_string (string key, string default_value) {
            unowned Variant? val = properties.lookup (key);
            return val != null && val.is_of_type (VariantType.STRING) ? val.get_string () : default_value;
        }

        public bool get_bool (string key, bool default_value) {
            unowned Variant? val = properties.lookup (key);
            return val != null && val.is_of_type (VariantType.BOOLEAN) ? val.get_boolean () : default_value;
        }

        public int32 get_int (string key, int32 default_value) {
            unowned Variant? val = properties.lookup (key);
            return val != null && val.is_of_type (VariantType.INT32) ? val.get_int32 () : default_value;
        }
    }

    // Fetches and keeps a com.canonical.dbusmenu layout up to date and lets
    // callers activate individual entries.
    public class MenuClient : Object {
        public signal void layout_changed ();

        public string bus_name { get; construct; }
        public string object_path { get; construct; }
        public MenuItemNode? root { get; private set; }

        private DBusConnection connection;

        public MenuClient (string bus_name, string object_path) {
            Object (bus_name: bus_name, object_path: object_path);
        }

        construct {
            try {
                connection = Bus.get_sync (BusType.SESSION);

                connection.signal_subscribe (
                    bus_name, "com.canonical.dbusmenu", "LayoutUpdated", object_path, null,
                    DBusSignalFlags.NONE, on_menu_changed
                );
                connection.signal_subscribe (
                    bus_name, "com.canonical.dbusmenu", "ItemsPropertiesUpdated", object_path, null,
                    DBusSignalFlags.NONE, on_menu_changed
                );
            } catch (Error e) {
                warning ("Failed to connect to dbusmenu at %s: %s", bus_name, e.message);
            }
        }

        private void on_menu_changed (
            DBusConnection conn, string? sender, string path,
            string iface, string signal_name, Variant parameters
        ) {
            refresh.begin ();
        }

        public async void refresh () {
            try {
                var result = yield connection.call (
                    bus_name, object_path, "com.canonical.dbusmenu", "GetLayout",
                    new Variant ("(ii^as)", 0, -1, new string[0]),
                    new VariantType ("(u(ia{sv}av))"),
                    DBusCallFlags.NONE, -1
                );

                uint32 revision;
                Variant layout_variant;
                result.get ("(u@(ia{sv}av))", out revision, out layout_variant);

                root = parse_node (layout_variant);
                layout_changed ();
            } catch (Error e) {
                warning ("Failed to get dbusmenu layout for %s: %s", bus_name, e.message);
            }
        }

        // Each node is (id, properties, children). The spec types it as
        // "(ia{sv}av)", with every child boxed in a variant so the structure
        // can nest. Some servers skip the boxing for childless nodes and send
        // their empty children list as "a(ia{sv}av)" instead. Unpacking with
        // a fixed "(ia{sv}av)" format string then fails quietly: Variant.get()
        // doesn't throw on a type mismatch, it logs a g_critical and leaves
        // the id and properties blank. Reading each field by index works
        // with either shape.
        private MenuItemNode parse_node (Variant v) {
            var node = new MenuItemNode (v.get_child_value (0).get_int32 ());

            string key;
            Variant val;
            var props_iter = v.get_child_value (1).iterator ();
            while (props_iter.next ("{sv}", out key, out val)) {
                node.properties[key] = val;
            }

            var children_v = v.get_child_value (2);
            for (int i = 0; i < children_v.n_children (); i++) {
                var child_v = children_v.get_child_value (i);
                if (child_v.is_of_type (VariantType.VARIANT)) {
                    child_v = child_v.get_variant ();
                }

                node.children.add (parse_node (child_v));
            }

            return node;
        }

        public void about_to_show (int32 id) {
            send_about_to_show.begin (id);
        }

        public void activate (int32 id) {
            send_event.begin (id, "clicked");
        }

        // Tell the server its root menu was shown or hidden.
        // Some refresh their entries on "opened".
        public void opened () {
            send_event.begin (root != null ? root.id : 0, "opened");
        }

        public void closed () {
            send_event.begin (root != null ? root.id : 0, "closed");
        }

        private async void send_about_to_show (int32 id) {
            try {
                yield connection.call (
                    bus_name, object_path, "com.canonical.dbusmenu", "AboutToShow",
                    new Variant ("(i)", id), new VariantType ("(b)"), DBusCallFlags.NONE, -1
                );
            } catch (Error e) {
                warning ("AboutToShow failed for %s: %s", bus_name, e.message);
            }
        }

        private async void send_event (int32 id, string event_id) {
            try {
                yield connection.call (
                    bus_name, object_path, "com.canonical.dbusmenu", "Event",
                    new Variant (
                        "(isvu)", id, event_id, new Variant ("s", ""),
                        (uint32) (get_monotonic_time () / 1000)
                    ),
                    null, DBusCallFlags.NONE, -1
                );
            } catch (Error e) {
                warning ("Event failed for %s: %s", bus_name, e.message);
            }
        }
    }
}

