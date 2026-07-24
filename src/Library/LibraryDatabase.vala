/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Library {
    public class StoredTrackMeta : GLib.Object {
        public int64 id { get; set; }
        public string path { get; set; }
        public int64 dev { get; set; }
        public int64 inode { get; set; }
        public int64 mtime_sec { get; set; }
        public int64 size { get; set; }
        public string title { get; set; }
        public string artist { get; set; }
        public string album { get; set; }
        public string? cover_path { get; set; }
    }

    public class LibraryDatabase : GLib.Object {
        private Sqlite.Database? db;
        private string db_path;
        private Mutex db_mutex = Mutex ();

        public LibraryDatabase () {
            var data_dir = Path.build_filename (Environment.get_user_data_dir (), Config.PROJECT_NAME);
            this.db_path = Path.build_filename (data_dir, Constants.LIBRARY_DB_FILE_NAME);
        }

        public bool open () {
            try {
                var dir = File.new_for_path (Path.get_dirname (this.db_path));
                if (!dir.query_exists (null)) {
                    dir.make_directory_with_parents (null);
                }
            } catch (Error e) {
                warning ("Could not create data directory: %s", e.message);
                return false;
            }

            int rc = Sqlite.Database.open (this.db_path, out this.db);
            if (rc != Sqlite.OK) {
                warning ("Could not open library database: %d", rc);
                this.db = null;
                return false;
            }

            this.db.busy_timeout (5000);

            string err_msg;
            if (this.db.exec ("PRAGMA journal_mode=WAL;", null, out err_msg) != Sqlite.OK) {
                warning ("SQLite pragma WAL: %s", err_msg);
            }
            if (this.db.exec ("PRAGMA synchronous=NORMAL;", null, out err_msg) != Sqlite.OK) {
                warning ("SQLite pragma synchronous: %s", err_msg);
            }

            return init_schema ();
        }

        private bool init_schema () {
            string err_msg;
            const string CREATE_TBL = """
                CREATE TABLE IF NOT EXISTS tracks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    path TEXT NOT NULL UNIQUE,
                    dev INTEGER NOT NULL,
                    inode INTEGER NOT NULL,
                    mtime_sec INTEGER NOT NULL,
                    size INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    album TEXT NOT NULL,
                    cover_path TEXT,
                    favorite INTEGER NOT NULL DEFAULT 0
                );
            """;
            if (this.db.exec (CREATE_TBL, null, out err_msg) != Sqlite.OK) {
                warning ("Library schema (table): %s", err_msg);
                return false;
            }
            if (this.db.exec (
                "CREATE INDEX IF NOT EXISTS idx_tracks_dev_inode ON tracks(dev, inode);",
                null,
                out err_msg
            ) != Sqlite.OK) {
                warning ("Library schema (index): %s", err_msg);
                return false;
            }
            migrate_add_favorite_column ();
            return true;
        }

        private void migrate_add_favorite_column () {
            string err_msg;
            this.db.exec (
                "ALTER TABLE tracks ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0;",
                null,
                out err_msg
            );
        }

        public Gee.ArrayList<StoredTrackMeta> load_all_meta () {
            db_mutex.lock ();
            var list = new Gee.ArrayList<StoredTrackMeta> ();
            if (this.db == null) {
                db_mutex.unlock ();
                return list;
            }

            Sqlite.Statement stmt;
            string tail;
            string q = """
                SELECT id, path, dev, inode, mtime_sec, size, title, artist, album, cover_path
                FROM tracks
            """;
            if (this.db.prepare_v2 (q, q.length, out stmt, out tail) != Sqlite.OK) {
                db_mutex.unlock ();
                return list;
            }

            while (stmt.step () == Sqlite.ROW) {
                var row = new StoredTrackMeta ();
                row.id = stmt.column_int64 (0);
                row.path = stmt.column_text (1) ?? "";
                row.dev = stmt.column_int64 (2);
                row.inode = stmt.column_int64 (3);
                row.mtime_sec = stmt.column_int64 (4);
                row.size = stmt.column_int64 (5);
                row.title = stmt.column_text (6) ?? "";
                row.artist = stmt.column_text (7) ?? "";
                row.album = stmt.column_text (8) ?? "";
                unowned string? c = stmt.column_text (9);
                row.cover_path = (c != null && c[0] != '\0') ? (!) c : null;
                list.add (row);
            }
            db_mutex.unlock ();
            return list;
        }

        public Gee.ArrayList<Track> load_tracks_for_ui () {
            db_mutex.lock ();
            var list = new Gee.ArrayList<Track> ();
            if (this.db == null) {
                db_mutex.unlock ();
                return list;
            }

            Sqlite.Statement stmt;
            string tail;
            string q = """
                SELECT id, path, title, artist, album, cover_path, favorite
                FROM tracks
                ORDER BY artist COLLATE NOCASE, album COLLATE NOCASE, path COLLATE NOCASE
            """;
            if (this.db.prepare_v2 (q, q.length, out stmt, out tail) != Sqlite.OK) {
                db_mutex.unlock ();
                return list;
            }

            while (stmt.step () == Sqlite.ROW) {
                int64 id = stmt.column_int64 (0);
                string path = stmt.column_text (1) ?? "";
                string title = stmt.column_text (2) ?? "";
                string artist = stmt.column_text (3) ?? "";
                string album = stmt.column_text (4) ?? "";
                unowned string? c = stmt.column_text (5);
                string? cover = (c != null && c[0] != '\0') ? (!) c : null;
                bool fav = stmt.column_int (6) != 0;
                list.add (new Track (path, title, artist, album, cover, id, fav));
            }
            db_mutex.unlock ();
            return list;
        }

        public bool toggle_favorite (int64 track_id, bool favorite) {
            db_mutex.lock ();
            if (this.db == null) {
                db_mutex.unlock ();
                return false;
            }
            Sqlite.Statement stmt;
            string tail;
            string q = "UPDATE tracks SET favorite = ? WHERE id = ?;";
            if (this.db.prepare_v2 (q, q.length, out stmt, out tail) != Sqlite.OK) {
                db_mutex.unlock ();
                return false;
            }
            stmt.bind_int (1, favorite ? 1 : 0);
            stmt.bind_int64 (2, track_id);
            bool ok = stmt.step () == Sqlite.DONE;
            db_mutex.unlock ();
            return ok;
        }

        public bool delete_by_id (int64 id) {
            db_mutex.lock ();
            if (this.db == null) {
                db_mutex.unlock ();
                return false;
            }
            Sqlite.Statement stmt;
            string tail;
            string q = "DELETE FROM tracks WHERE id = ?;";
            if (this.db.prepare_v2 (q, q.length, out stmt, out tail) != Sqlite.OK) {
                db_mutex.unlock ();
                return false;
            }
            stmt.bind_int64 (1, id);
            bool ok = stmt.step () == Sqlite.DONE;
            db_mutex.unlock ();
            return ok;
        }

        public bool update_after_move (
            int64 id,
            string new_path,
            int64 dev,
            int64 inode,
            int64 mtime_sec,
            int64 size
        ) {
            db_mutex.lock ();
            if (this.db == null) {
                db_mutex.unlock ();
                return false;
            }
            Sqlite.Statement stmt;
            string tail;
            string q = """
                UPDATE tracks SET path = ?, dev = ?, inode = ?, mtime_sec = ?, size = ?
                WHERE id = ?;
            """;
            if (this.db.prepare_v2 (q, q.length, out stmt, out tail) != Sqlite.OK) {
                db_mutex.unlock ();
                return false;
            }
            stmt.bind_text (1, new_path);
            stmt.bind_int64 (2, dev);
            stmt.bind_int64 (3, inode);
            stmt.bind_int64 (4, mtime_sec);
            stmt.bind_int64 (5, size);
            stmt.bind_int64 (6, id);
            bool ok = stmt.step () == Sqlite.DONE;
            db_mutex.unlock ();
            return ok;
        }

        public bool update_metadata (
            int64 id,
            string path,
            int64 dev,
            int64 inode,
            int64 mtime_sec,
            int64 size,
            string title,
            string artist,
            string album,
            string? cover_path
        ) {
            db_mutex.lock ();
            if (this.db == null) {
                db_mutex.unlock ();
                return false;
            }
            Sqlite.Statement stmt;
            string tail;
            string q;
            if (cover_path != null) {
                q = """
                    UPDATE tracks SET path = ?, dev = ?, inode = ?, mtime_sec = ?, size = ?,
                        title = ?, artist = ?, album = ?, cover_path = ?
                    WHERE id = ?;
                """;
            } else {
                q = """
                    UPDATE tracks SET path = ?, dev = ?, inode = ?, mtime_sec = ?, size = ?,
                        title = ?, artist = ?, album = ?
                    WHERE id = ?;
                """;
            }
            if (this.db.prepare_v2 (q, q.length, out stmt, out tail) != Sqlite.OK) {
                db_mutex.unlock ();
                return false;
            }
            stmt.bind_text (1, path);
            stmt.bind_int64 (2, dev);
            stmt.bind_int64 (3, inode);
            stmt.bind_int64 (4, mtime_sec);
            stmt.bind_int64 (5, size);
            stmt.bind_text (6, title);
            stmt.bind_text (7, artist);
            stmt.bind_text (8, album);
            if (cover_path != null) {
                stmt.bind_text (9, cover_path);
                stmt.bind_int64 (10, id);
            } else {
                stmt.bind_int64 (9, id);
            }
            bool ok = stmt.step () == Sqlite.DONE;
            db_mutex.unlock ();
            return ok;
        }

        public int64 insert_track (
            string path,
            int64 dev,
            int64 inode,
            int64 mtime_sec,
            int64 size,
            string title,
            string artist,
            string album,
            string? cover_path
        ) {
            db_mutex.lock ();
            if (this.db == null) {
                db_mutex.unlock ();
                return -1;
            }
            Sqlite.Statement stmt;
            string tail;
            string q = """
                INSERT INTO tracks (path, dev, inode, mtime_sec, size, title, artist, album, cover_path)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """;
            if (this.db.prepare_v2 (q, q.length, out stmt, out tail) != Sqlite.OK) {
                db_mutex.unlock ();
                return -1;
            }
            stmt.bind_text (1, path);
            stmt.bind_int64 (2, dev);
            stmt.bind_int64 (3, inode);
            stmt.bind_int64 (4, mtime_sec);
            stmt.bind_int64 (5, size);
            stmt.bind_text (6, title);
            stmt.bind_text (7, artist);
            stmt.bind_text (8, album);
            if (cover_path != null) {
                stmt.bind_text (9, cover_path);
            } else {
                stmt.bind_null (9);
            }
            if (stmt.step () != Sqlite.DONE) {
                db_mutex.unlock ();
                return -1;
            }
            int64 row_id = this.db.last_insert_rowid ();
            db_mutex.unlock ();
            return row_id;
        }
    }
}
