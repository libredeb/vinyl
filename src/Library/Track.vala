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
        /** SQLite row id; used to keep playback in sync after library refresh. */
        public int64 db_row_id { get; set; default = -1; }
        public bool favorite { get; set; default = false; }

        public Track (
            string file_path,
            string title,
            string artist,
            string album,
            string? album_art_path,
            int64 db_row_id = -1,
            bool favorite = false
        ) {
            this.file_path = file_path;
            this.title = title;
            this.artist = artist;
            this.album = album;
            this.album_art_path = album_art_path;
            this.db_row_id = db_row_id;
            this.favorite = favorite;
        }
    }
}
