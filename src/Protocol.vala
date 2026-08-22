/*
 * D-Bus interfaces for the StatusNotifierItem / StatusNotifierWatcher
 * protocol, as used by "ayatana" / "appindicator" style tray icons.
 *
 * https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/
 */

namespace Namarupa {
    public struct IconPixmap {
        int width;
        int height;
        uint8[] data;
    }

    [DBus (name = "org.kde.StatusNotifierItem")]
    public interface ItemIface : Object {
        public abstract string id { owned get; }
        public abstract string title { owned get; }
        public abstract string status { owned get; }
        public abstract string icon_name { owned get; }
        public abstract IconPixmap[] icon_pixmap { owned get; }
        public abstract string icon_theme_path { owned get; }
        public abstract bool item_is_menu { get; }
        public abstract ObjectPath menu { owned get; }

        public abstract void activate (int x, int y) throws Error;
        public abstract void secondary_activate (int x, int y) throws Error;
        public abstract void context_menu (int x, int y) throws Error;
        public abstract void scroll (int delta, string orientation) throws Error;

        public signal void new_icon ();
        public signal void new_title ();
        public signal void new_status (string status);
    }

    [DBus (name = "org.kde.StatusNotifierWatcher")]
    public interface WatcherIface : Object {
        public abstract string[] registered_status_notifier_items { owned get; }
        public abstract bool is_status_notifier_host_registered { get; }
        public abstract int32 protocol_version { get; }

        public abstract void register_status_notifier_item (string service) throws Error;
        public abstract void register_status_notifier_host (string service) throws Error;

        public signal void status_notifier_item_registered (string service);
        public signal void status_notifier_item_unregistered (string service);
        public signal void status_notifier_host_registered ();
    }
}
