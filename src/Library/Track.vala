/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Library {
    public class Track : GLib.Object {
        public string file_path { get; set; }
        public string title { get; set; }
        public string artist { get; set; }
        public string album { get; set; }
        public string? album_art_path { get; set; }

        public Track (
            string file_path,
            string title,
            string artist,
            string album,
            string? album_art_path
        ) {
            this.file_path = file_path;
            this.title = title;
            this.artist = artist;
            this.album = album;
            this.album_art_path = album_art_path;
        }
    }
}
