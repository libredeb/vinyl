# Vinyl - A Fullscreen Music Experience

[![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPL%203.0--or--later-green.svg)](https://opensource.org/licenses/GPL-3.0)
[![Code Style](https://img.shields.io/badge/code%20style-Vala-purple.svg)](https://wiki.gnome.org/Projects/Vala)

![icon](./data/icons/128/vinyl.svg)

A desktop music player that provides a beautiful, fullscreen interface to your music library. It's built for those who appreciate a clean aesthetic and intuitive control. Whether you prefer using your keyboard or a gamepad, Vinyl offers a seamless way to navigate your tunes without ever needing to reach for a mouse.

We created Vinyl for music lovers who want to truly connect with their music, bringing back the intentionality of listening to a record.

## Compilation

   1. Install dependencies:
   * For Ubuntu:
      ```sh
      sudo apt-get install meson ninja-build valac libvala-*-dev libsdl2-dev libsdl2-image-dev libtagc0-dev python3 python3-wheel python3-setuptools
      ```
   * For Fedora:
      ```sh
      sudo dnf install meson ninja-build vala libvala-devel sdl2-compat-devel SDL2_image-devel taglib-devel python3 python3-wheel python3-setuptools
      ```
   * For Arch Linux:
      ```sh
      sudo pacman -Sy meson ninja vala sdl2 sdl2_image taglib python python-wheel python-setuptools
      ```
   2. Clone this repository into your machine
      ```sh
      git clone https://github.com/libredeb/vinyl.git
      cd vinyl/
      ```
   3. Create a build folder:
      ```sh
      meson setup build --prefix=/usr
      ```
   4. Compile Vinyl:
      ```sh
      cd build
      ninja
      ```
   5. Install Vinyl in the system:
      ```sh
      sudo ninja install
      ```
   6. (OPTIONAL) Uninstall Vinyl:
      ```sh
      sudo ninja uninstall
      ```

## Developer Section

### Linting

To lint Vala code, you can use [vala-lint](https://github.com/vala-lang/vala-lint), a tool designed to detect potential issues and enforce coding style in Vala projects.

Read the instructions to install it on your local machine.

**Usage**

Run `io.elementary.vala-lint` command in your project source code directory:

```sh
io.elementary.vala-lint src/
```

### Validating AppStream Syntax

To ensure your [AppStream XML file](data/io.github.libredeb.vinyl.appdata.xml.in) is correctly structured, use the `appstream-util` tool from the [AppStream project](https://www.freedesktop.org/software/appstream/docs/).

**Installation**

```sh
sudo apt install appstream
```

**Usage**

Run the following command to validate the syntax of your AppStream XML file:

```sh
appstreamcli validate --pedantic data/io.github.libredeb.vinyl.appdata.xml.in
```

## License

This project is licensed under the GNU General Public License v3.0 or later - see the [COPYING](COPYING) file for details.

⭐ If you like Vinyl, leave me a star on GitHub!