project(
  'namarupa',
  'vala', 'c',
  version: '2.0.0',
  meson_version: '>=0.58'
)

add_project_arguments(
  '-DG_LOG_DOMAIN="com.github.amz-x.wingpanel-indicator-namarupa"',
  language: 'c'
)

prefix = get_option('prefix')
libdir = prefix / get_option('libdir')

wingpanel_dep = dependency('wingpanel-9')

shared_module(
  meson.project_name(),
  'src/Protocol.vala',
  'src/MenuClient.vala',
  'src/Watcher.vala',
  'src/TrayIcon.vala',
  'src/Indicator.vala',
  dependencies: [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gio-2.0'),
    dependency('gio-unix-2.0'),
    dependency('gee-0.8'),
    dependency('granite-7'),
    dependency('gtk4'),
    wingpanel_dep,
  ],
  install: true,
  install_dir: wingpanel_dep.get_variable('indicatorsdir', pkgconfig_define: ['libdir', libdir]),
)

