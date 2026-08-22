namespace Namarupa {
    /*
     * Tracks StatusNotifierItems registered on the session bus. If nobody
     * else owns "org.kde.StatusNotifierWatcher" yet we host it ourselves;
     * either way we then connect to it as a client, since that works
     * whether the watcher turned out to be ours or another process'.
     */
    public class TrayManager : Object {

        public signal void item_added (string bus_name, string object_path);
        public signal void item_removed (string bus_name, string object_path);

        private DBusConnection connection;
        private WatcherService? hosted_watcher;
        private WatcherIface? watcher_proxy;
        private Gee.HashSet<string> known_items = new Gee.HashSet<string> ();

        public void start () {
            init.begin ();
        }

        private async void init () {
            try {
                connection = yield Bus.get (BusType.SESSION);
            } catch (Error e) {
                warning ("Failed to connect to the session bus: %s", e.message);
                return;
            }

            Bus.own_name_on_connection (
                connection, "org.kde.StatusNotifierWatcher", BusNameOwnerFlags.NONE,
                on_watcher_name_acquired, null
            );

            yield connect_watcher_proxy ();
        }

        private void on_watcher_name_acquired (DBusConnection connection, string name) {
            hosted_watcher = new WatcherService (connection);
            try {
                connection.register_object ("/StatusNotifierWatcher", hosted_watcher);
            } catch (Error e) {
                warning ("Failed to register StatusNotifierWatcher: %s", e.message);
            }
        }

        private async void connect_watcher_proxy () {
            try {
                watcher_proxy = yield Bus.get_proxy (
                    BusType.SESSION, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                    DBusProxyFlags.NONE
                );
            } catch (Error e) {
                warning ("Failed to connect to StatusNotifierWatcher: %s", e.message);
                return;
            }

            watcher_proxy.status_notifier_item_registered.connect (on_item_registered);
            watcher_proxy.status_notifier_item_unregistered.connect (on_item_unregistered);

            try {
                watcher_proxy.register_status_notifier_host (connection.unique_name);
            } catch (Error e) {
                warning ("Failed to register as a StatusNotifierHost: %s", e.message);
            }

            foreach (unowned string service in watcher_proxy.registered_status_notifier_items) {
                on_item_registered (service);
            }

            // Some StatusNotifierWatcher implementations (e.g. Ayatana's
            // indicator-application-service) never actually emit
            // StatusNotifierItemRegistered/-Unregistered, even though the
            // RegisteredStatusNotifierItems property does stay up to date.
            // Poll it as a fallback so newly launched apps' tray icons show
            // up without requiring a wingpanel restart.
            Timeout.add_seconds (3, () => {
                poll_registered_items.begin ();
                return true;
            });
        }

        private async void poll_registered_items () {
            try {
                var result = yield connection.call (
                    "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
                    "org.freedesktop.DBus.Properties", "Get",
                    new Variant ("(ss)", "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"),
                    new VariantType ("(v)"), DBusCallFlags.NONE, -1
                );

                Variant items_variant;
                result.get ("(v)", out items_variant);

                var live_items = new Gee.HashSet<string> ();
                foreach (unowned string service in items_variant.get_strv ()) {
                    live_items.add (service);
                }

                foreach (var service in live_items) {
                    if (!known_items.contains (service)) {
                        on_item_registered (service);
                    }
                }

                foreach (var service in known_items.to_array ()) {
                    if (!live_items.contains (service)) {
                        on_item_unregistered (service);
                    }
                }
            } catch (Error e) {
                warning ("Failed to poll registered StatusNotifierItems: %s", e.message);
            }
        }

        private void on_item_registered (string service) {
            var parts = split_service (service);
            if (parts == null) {
                return;
            }

            if (!known_items.add (service)) {
                return;
            }

            item_added (parts[0], parts[1]);
        }

        private void on_item_unregistered (string service) {
            var parts = split_service (service);
            if (parts == null) {
                return;
            }

            if (!known_items.remove (service)) {
                return;
            }

            item_removed (parts[0], parts[1]);
        }

        // Services are advertised as "<bus name><object path>", e.g.
        // ":1.42/StatusNotifierItem". Split back into the two parts.
        private string[]? split_service (string service) {
            var idx = service.index_of ("/");
            if (idx <= 0) {
                return null;
            }

            return { service[0:idx], service[idx:service.length] };
        }
    }

    [DBus (name = "org.kde.StatusNotifierWatcher")]
    public class WatcherService : Object {
        private Gee.HashSet<string> items = new Gee.HashSet<string> ();
        private unowned DBusConnection connection;

        public string[] registered_status_notifier_items {
            owned get { return items.to_array (); }
        }

        public bool is_status_notifier_host_registered { get; private set; default = true; }
        public int32 protocol_version { get { return 0; } }

        public signal void status_notifier_item_registered (string service);
        public signal void status_notifier_item_unregistered (string service);
        public signal void status_notifier_host_registered ();

        public WatcherService (DBusConnection connection) {
            this.connection = connection;
        }

        public void register_status_notifier_item (string service, GLib.BusName sender) throws Error {
            string object_path = service.has_prefix ("/") ? service : "/StatusNotifierItem";
            string full_service = "%s%s".printf ((string) sender, object_path);

            if (!items.add (full_service)) {
                return;
            }

            uint watch_id = 0;
            watch_id = Bus.watch_name_on_connection (
                connection, sender, BusNameWatcherFlags.NONE, null,
                () => {
                    if (items.remove (full_service)) {
                        status_notifier_item_unregistered (full_service);
                    }

                    Bus.unwatch_name (watch_id);
                }
            );

            status_notifier_item_registered (full_service);
        }

        public void register_status_notifier_host (string service) throws Error {
            status_notifier_host_registered ();
        }
    }
}

