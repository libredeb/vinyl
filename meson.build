project(
    'io.github.libredeb.vinyl',
    'vala', 'c',
    version: '0.1.1',
    meson_version: '>=0.56.0'
)

PROJECT_NAME = 'vinyl'
prefix = get_option('prefix')
libdir = join_paths(prefix, get_option('libdir'))
datadir = join_paths(prefix, get_option('datadir'))

VAPI_DIR = join_paths(meson.project_source_root(), 'vapi')
vala = meson.get_compiler('vala')

# Global configuration data - matches vapi/config.vapi strings
conf = configuration_data()
conf.set_quoted('PROJECT_NAME', PROJECT_NAME)
conf.set_quoted('PACKAGE_LIBDIR', libdir)
conf.set_quoted('PACKAGE_SHAREDIR', datadir)
conf.set_quoted('PACKAGE_VERSION', meson.project_version())

config_h = configure_file(
	output: 'config.h',
	configuration: conf
)

config_dep = declare_dependency(
	dependencies: vala.find_library('config', dirs: VAPI_DIR),
	sources: config_h
)

config_inc_dir = include_directories('.')

dependencies = [
    dependency('gio-2.0'),
    dependency('gee-0.8'),
    dependency('gstreamer-1.0'),
    dependency('gstreamer-pbutils-1.0'),
    dependency('gstreamer-tag-1.0'),
    dependency('gdk-pixbuf-2.0'),
    dependency('sdl2', version: '>=2.26.0'),
    dependency('SDL2_image', version: '>=2.6.0'),
    dependency('SDL2_ttf', version: '>=2.20.0'),
    dependency('taglib_c', version: '>=1.13.0')
]

gnome = import('gnome')
ValaArgs = [
    '--pkg=config',
    '--vapidir=' + VAPI_DIR
]

resources = gnome.compile_resources('resources',
  join_paths('data', meson.project_name() + '.gresources.xml'),
  source_dir: 'data'
)

sources = [
  'src/Main.vala',
  'src/Constants.vala',
  'src/Application.vala',
  'src/Utils/Screen.vala',
  'src/Widgets/IconButton.vala',
  'src/Widgets/MenuButton.vala',
  'src/Widgets/ToolbarButton.vala',
  'src/Widgets/Track.vala',
  'src/Widgets/TrackList.vala',
  'src/Widgets/NowPlaying.vala',
  'src/Library/Track.vala',
  'src/Library/MusicScanner.vala'
]

executable(
    meson.project_name(),
    resources,
    sources,
    dependencies: dependencies,
    c_args: [
        '-w'
    ],
    vala_args: ValaArgs,
    include_directories: config_inc_dir,
    install: true
)

# Install GFX icon files
gfx_files = [
    'arrow_right.png',
    'back_tb.png',
    'exit_tb.png',
    'library_icon.png',
    'play_tb.png',
    'playlist_tb.png',
    'radio_icon.png',
    'search_icon.png',
    'toolbar_button_bg.png',
    'toolbar_button_bg_press.png',
    'default_cover.png'
]
foreach gfx : gfx_files
    install_data(
        join_paths('data', 'gfx', gfx),
        install_dir: join_paths(datadir, PROJECT_NAME, 'gfx')
    )
endforeach

# Install font files
font_files = [
    'FreeSans.ttf',
    'FreeSansBold.ttf'
]
foreach font : font_files
    install_data(
        join_paths('data', 'fonts', font),
        install_dir: join_paths(datadir, PROJECT_NAME, 'fonts')
    )
endforeach

# Install the gamecontrollerdb.txt file
install_data(
    join_paths('data', 'gamecontrollerdb.txt'),
    install_dir: join_paths(datadir, PROJECT_NAME)
)

meson.add_install_script('post_install.py')
