/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Library {
    /** One audio file found on disk (non-symlink). */
    class DiskFileHit : GLib.Object {
        public string path { get; private set; }
        public int64 dev { get; private set; }
        public int64 inode { get; private set; }
        public int64 mtime_sec { get; private set; }
        public int64 size { get; private set; }

        public DiskFileHit (
            string path,
            int64 dev,
            int64 inode,
            int64 mtime_sec,
            int64 size
        ) {
            this.path = path;
            this.dev = dev;
            this.inode = inode;
            this.mtime_sec = mtime_sec;
            this.size = size;
        }
    }

    public class MusicScanner : GLib.Object {
        private LibraryDatabase db;
        private string covers_cache_dir;

        public MusicScanner (LibraryDatabase database) {
            this.db = database;
            this.covers_cache_dir = Path.build_filename (
                Environment.get_user_cache_dir (),
                Config.PROJECT_NAME,
                Constants.COVERS_CACHE_DIR_NAME
            );

            try {
                var cache_dir_file = File.new_for_path (this.covers_cache_dir);
                if (!cache_dir_file.query_exists (null)) {
                    cache_dir_file.make_directory_with_parents (null);
                }
            } catch (Error e) {
                warning ("Could not create cache directory: %s", e.message);
            }
        }

        public static string? resolve_music_directory () {
            unowned string? xdg = Environment.get_user_special_dir (UserDirectory.MUSIC);
            if (xdg != null && xdg != "" && FileUtils.test (xdg, FileTest.IS_DIR)) {
                return xdg;
            }
            string home = Environment.get_home_dir ();
            string p = Path.build_filename (home, "Music");
            if (FileUtils.test (p, FileTest.IS_DIR)) {
                return p;
            }
            return null;
        }

        /**
         * Loads tracks from the database immediately usable by the UI; reconciles with disk
         * (recursive, symlinks skipped) and persists changes in batched transactions.
         */
        /**
         * Synchronous library sync — designed to be called from a background Thread.
         * Scans the music directory, reconciles with the DB, and returns the updated track list.
         */
        public Gee.ArrayList<Track> sync_library_blocking () {
            var hits = new Gee.ArrayList<DiskFileHit> ();
            string? music_root = resolve_music_directory ();

            if (music_root != null) {
                if (FileUtils.test (music_root, FileTest.IS_SYMLINK)) {
                    warning ("Music root is a symbolic link, skipping scan: %s", music_root);
                } else if (FileUtils.test (music_root, FileTest.IS_DIR)) {
                    var root = File.new_for_path (music_root);
                    collect_audio_files_sync (root, hits);
                }
            } else {
                warning ("No music directory found (XDG MUSIC, ~/Music).");
            }

            reconcile_disk_with_db (hits);

            return this.db.load_tracks_for_ui ();
        }

        private void collect_audio_files_sync (
            File root,
            Gee.ArrayList<DiskFileHit> hits
        ) {
            var pending = new Gee.LinkedList<File> ();
            pending.add (root);

            while (!pending.is_empty) {
                File dir = pending.remove_at (0);

                try {
                    var enumerator = dir.enumerate_children (
                        "standard::name,standard::type,standard::is-symlink,standard::size,"
                        + "unix::inode,unix::device,time::modified",
                        FileQueryInfoFlags.NONE,
                        null
                    );

                    FileInfo? info = null;
                    while ((info = enumerator.next_file (null)) != null) {
                        if (info.get_is_symlink ()) {
                            continue;
                        }

                        var child = enumerator.get_child (info);
                        var ft = info.get_file_type ();

                        if (ft == FileType.DIRECTORY) {
                            pending.add (child);
                        } else if (ft == FileType.REGULAR) {
                            string? p = child.get_path ();
                            if (p == null) {
                                continue;
                            }
                            if (!is_supported_audio (p)) {
                                continue;
                            }

                            int64 mtime_sec = file_info_mtime_sec (info, p);
                            int64 size = info.get_size ();
                            int64 dev = 0;
                            int64 inode = 0;
                            if (info.has_attribute ("unix::device")) {
                                dev = info.get_attribute_uint32 ("unix::device");
                            }
                            if (info.has_attribute ("unix::inode")) {
                                inode = (int64) info.get_attribute_uint64 ("unix::inode");
                            }

                            hits.add (new DiskFileHit (p, dev, inode, mtime_sec, size));
                        }
                    }
                } catch (Error e) {
                    warning ("Error scanning directory %s: %s", dir.get_path (), e.message);
                }
            }
        }

        private static int64 file_info_mtime_sec (FileInfo info, string path) {
            var dt = info.get_modification_date_time ();
            if (dt != null) {
                return dt.to_unix ();
            }
            try {
                var f = File.new_for_path (path);
                var inf = f.query_info ("time::modified", FileQueryInfoFlags.NONE, null);
                var dt2 = inf.get_modification_date_time ();
                if (dt2 != null) {
                    return dt2.to_unix ();
                }
            } catch (Error e) {
                /* ignore */
            }
            return 0;
        }

        private static bool is_supported_audio (string file_path) {
            foreach (string format in Constants.SUPPORTED_FORMATS) {
                if (file_path.has_suffix (format)) {
                    return true;
                }
            }
            return false;
        }

        private static bool inode_valid (int64 dev, int64 inode) {
            return dev != 0 && inode != 0;
        }

        private static string inode_key (int64 dev, int64 inode) {
            return dev.to_string () + ":" + inode.to_string ();
        }

        private void reconcile_disk_with_db (Gee.ArrayList<DiskFileHit> hits) {
            var meta_rows = this.db.load_all_meta ();
            var by_path = new Gee.HashMap<string, StoredTrackMeta> ();
            var by_inode = new Gee.HashMap<string, Gee.ArrayList<StoredTrackMeta>> ();

            foreach (var row in meta_rows) {
                by_path.set (row.path, row);
                if (inode_valid (row.dev, row.inode)) {
                    string ik = inode_key (row.dev, row.inode);
                    if (!by_inode.has_key (ik)) {
                        by_inode.set (ik, new Gee.ArrayList<StoredTrackMeta> ());
                    }
                    by_inode.get (ik).add (row);
                }
            }

            var seen_paths = new Gee.HashSet<string> ();
            foreach (var h in hits) {
                seen_paths.add (h.path);
            }

            if (!this.db.transaction_begin ()) {
                warning ("library transaction BEGIN failed");
                return;
            }

            foreach (var hit in hits) {
                apply_hit (hit, seen_paths, by_path, by_inode);
            }

            /* After moves, paths in DB differ from the initial meta snapshot; re-read rows. */
            var after_rows = this.db.load_all_meta ();
            foreach (var row in after_rows) {
                if (!seen_paths.contains (row.path)) {
                    this.db.delete_by_id (row.id);
                }
            }

            if (!this.db.transaction_commit ()) {
                warning ("library transaction COMMIT failed");
                this.db.transaction_rollback ();
            }
        }

        private void apply_hit (
            DiskFileHit hit,
            Gee.HashSet<string> seen_paths,
            Gee.HashMap<string, StoredTrackMeta> by_path,
            Gee.HashMap<string, Gee.ArrayList<StoredTrackMeta>> by_inode
        ) {
            StoredTrackMeta? by_p = by_path.get (hit.path);

            if (by_p != null) {
                if (by_p.mtime_sec == hit.mtime_sec && by_p.size == hit.size) {
                    return;
                }
                read_tags_and_update (hit, by_p.id);
                return;
            }

            if (inode_valid (hit.dev, hit.inode)) {
                string ikey = inode_key (hit.dev, hit.inode);
                if (by_inode.has_key (ikey)) {
                    var inode_rows = by_inode.get (ikey);
                    /* Move/rename: same inode, DB path no longer on disk, new path in this scan. */
                    StoredTrackMeta? orphan = null;
                    foreach (var row in inode_rows) {
                        if (!seen_paths.contains (row.path)) {
                            orphan = row;
                            break;
                        }
                    }
                    if (orphan != null && orphan.path != hit.path) {
                        if (this.db.update_after_move (
                                orphan.id, hit.path, hit.dev, hit.inode, hit.mtime_sec, hit.size)) {
                            by_path.unset (orphan.path);
                            orphan.path = hit.path;
                            orphan.mtime_sec = hit.mtime_sec;
                            orphan.size = hit.size;
                            orphan.dev = hit.dev;
                            orphan.inode = hit.inode;
                            by_path.set (orphan.path, orphan);
                        }
                        return;
                    }
                }
            }

            read_tags_and_insert (hit);
        }

        private void read_tags_and_insert (DiskFileHit hit) {
            Track? t = build_track_from_file (hit.path);
            if (t == null) {
                return;
            }
            int64 id = this.db.insert_track (
                hit.path,
                hit.dev,
                hit.inode,
                hit.mtime_sec,
                hit.size,
                t.title,
                t.artist,
                t.album,
                t.album_art_path
            );
            if (id < 0) {
                warning ("insert_track failed for %s", hit.path);
            }
        }

        private void read_tags_and_update (DiskFileHit hit, int64 row_id) {
            Track? t = build_track_from_file (hit.path);
            if (t == null) {
                return;
            }
            if (!this.db.update_metadata (
                row_id,
                hit.path,
                hit.dev,
                hit.inode,
                hit.mtime_sec,
                hit.size,
                t.title,
                t.artist,
                t.album,
                t.album_art_path
            )) {
                warning ("update_metadata failed for %s", hit.path);
            }
        }

        private Track? build_track_from_file (string file_path) {
            var tag_file = new TagLib.File (file_path);
            if (tag_file == null) {
                warning ("TagLib could not open %s", file_path);
                return null;
            }
            unowned TagLib.Tag tag = tag_file.tag;
            if (tag == null) {
                return null;
            }

            var title = tag.title != "" ? tag.title : Path.get_basename (file_path);
            var artist = tag.artist != "" ? tag.artist : _("Unknown Artist");
            var album = tag.album != "" ? tag.album : _("Unknown Album");
            string? album_art_path = save_album_art (file_path, album, artist);

            return new Track (file_path, title, artist, album, album_art_path, -1);
        }

        private string? save_album_art (string file_path, string album, string artist) {
            string filename = "%s-%s.jpg".printf (artist.replace ("/", "_"), album.replace ("/", "_"));
            var cover_path = Path.build_filename (this.covers_cache_dir, filename);

            if (FileUtils.test (cover_path, FileTest.EXISTS)) {
                return cover_path;
            }

            try {
                Vinyl.ensure_gst ();
                var discoverer = new Gst.PbUtils.Discoverer ((Gst.ClockTime) (5 * Gst.SECOND));
                var info = discoverer.discover_uri ("file://" + file_path);
                unowned Gst.TagList? tag_list = info.get_tags ();
                if (tag_list != null) {
                    var sample = get_cover_sample (tag_list);
                    if (sample != null) {
                        var buffer = sample.get_buffer ();
                        if (buffer != null) {
                            var pixbuf = get_pixbuf_from_buffer (buffer);
                            if (pixbuf != null) {
                                pixbuf.savev (cover_path, "jpeg", new string[]{"quality"}, new string[]{"100"});
                                if (FileUtils.test (cover_path, FileTest.EXISTS)) {
                                    return cover_path;
                                }
                            }
                        }
                    }
                }
            } catch (Error e) {
                warning ("GStreamer discoverer failed for '%s': %s", file_path, e.message);
            }

            if (file_path.has_suffix (".wav")) {
                string? wav_result = extract_cover_from_wav_id3 (file_path, cover_path);
                if (wav_result != null) {
                    return wav_result;
                }
            }

            return null;
        }

        /**
         * Fallback for WAV files: GStreamer's wavparse does not expose APIC
         * frames from the ID3v2 chunk embedded in RIFF containers.
         * This method manually parses the RIFF structure to find the "ID3 "
         * chunk and extracts the cover image from it.
         */
        private string? extract_cover_from_wav_id3 (string file_path, string cover_path) {
            try {
                var file = File.new_for_path (file_path);
                var input_stream = file.read (null);
                var dis = new DataInputStream (input_stream);
                dis.byte_order = DataStreamByteOrder.LITTLE_ENDIAN;

                uint8[] header = new uint8[12];
                size_t bytes_read;
                dis.read_all (header, out bytes_read, null);
                if (bytes_read < 12) return null;

                if (header[0] != 'R' || header[1] != 'I' || header[2] != 'F' || header[3] != 'F') {
                    return null;
                }
                if (header[8] != 'W' || header[9] != 'A' || header[10] != 'V' || header[11] != 'E') {
                    return null;
                }

                uint32 riff_size = (uint32) header[4]
                    | ((uint32) header[5] << 8)
                    | ((uint32) header[6] << 16)
                    | ((uint32) header[7] << 24);

                int64 pos = 12;
                int64 end_pos = (int64) riff_size + 8;

                while (pos < end_pos) {
                    uint8[] chunk_hdr = new uint8[8];
                    dis.read_all (chunk_hdr, out bytes_read, null);
                    if (bytes_read < 8) break;

                    uint32 chunk_size = (uint32) chunk_hdr[4]
                        | ((uint32) chunk_hdr[5] << 8)
                        | ((uint32) chunk_hdr[6] << 16)
                        | ((uint32) chunk_hdr[7] << 24);

                    pos += 8;

                    bool is_id3 = (chunk_hdr[0] == 'I' || chunk_hdr[0] == 'i')
                               && (chunk_hdr[1] == 'D' || chunk_hdr[1] == 'd')
                               && (chunk_hdr[2] == '3' || chunk_hdr[2] == '3')
                               && chunk_hdr[3] == ' ';

                    if (is_id3 && chunk_size > 10) {
                        uint8[] id3_data = new uint8[chunk_size];
                        dis.read_all (id3_data, out bytes_read, null);
                        if (bytes_read < chunk_size) break;

                        uint8[]? img = parse_id3v2_apic_image (id3_data);
                        if (img != null && img.length > 0) {
                            FileUtils.set_data (cover_path, img);
                            if (FileUtils.test (cover_path, FileTest.EXISTS)) {
                                return cover_path;
                            }
                        }
                        return null;
                    }

                    uint32 skip = chunk_size + (chunk_size % 2);
                    dis.skip (skip, null);
                    pos += skip;
                }
            } catch (Error e) {
                warning ("WAV ID3 cover extraction failed for '%s': %s", file_path, e.message);
            }

            return null;
        }

        private uint8[]? parse_id3v2_apic_image (uint8[] id3_data) {
            if (id3_data.length < 10) return null;
            if (id3_data[0] != 'I' || id3_data[1] != 'D' || id3_data[2] != '3') {
                return null;
            }

            uint8 version_major = id3_data[3];
            uint8 flags = id3_data[5];

            uint32 tag_size = ((uint32) id3_data[6] << 21)
                            | ((uint32) id3_data[7] << 14)
                            | ((uint32) id3_data[8] << 7)
                            | ((uint32) id3_data[9]);

            uint32 pos = 10;

            if ((flags & 0x40) != 0 && pos + 4 <= id3_data.length) {
                uint32 ext_size = ((uint32) id3_data[10] << 24)
                                | ((uint32) id3_data[11] << 16)
                                | ((uint32) id3_data[12] << 8)
                                | ((uint32) id3_data[13]);
                pos += ext_size;
            }

            uint32 frame_end = 10 + tag_size;
            if (frame_end > id3_data.length) {
                frame_end = (uint32) id3_data.length;
            }

            while (pos + 10 < frame_end) {
                if (id3_data[pos] == 0) break;

                bool is_apic = id3_data[pos] == 'A'
                            && id3_data[pos + 1] == 'P'
                            && id3_data[pos + 2] == 'I'
                            && id3_data[pos + 3] == 'C';

                uint32 frame_size;
                if (version_major == 4) {
                    frame_size = ((uint32) id3_data[pos + 4] << 21)
                               | ((uint32) id3_data[pos + 5] << 14)
                               | ((uint32) id3_data[pos + 6] << 7)
                               | ((uint32) id3_data[pos + 7]);
                } else {
                    frame_size = ((uint32) id3_data[pos + 4] << 24)
                               | ((uint32) id3_data[pos + 5] << 16)
                               | ((uint32) id3_data[pos + 6] << 8)
                               | ((uint32) id3_data[pos + 7]);
                }

                pos += 10;

                if (is_apic && frame_size > 0 && pos + frame_size <= frame_end) {
                    return extract_image_from_apic_frame (id3_data, pos, frame_size);
                }

                pos += frame_size;
            }

            return null;
        }

        private uint8[]? extract_image_from_apic_frame (uint8[] data, uint32 offset, uint32 size) {
            uint32 pos = offset;
            uint32 end = offset + size;

            if (pos >= end) return null;

            uint8 encoding = data[pos];
            pos++;

            while (pos < end && data[pos] != 0) pos++;
            pos++;

            if (pos >= end) return null;
            pos++;

            if (encoding == 0 || encoding == 3) {
                while (pos < end && data[pos] != 0) pos++;
                pos++;
            } else {
                while (pos + 1 < end) {
                    if (data[pos] == 0 && data[pos + 1] == 0) break;
                    pos += 2;
                }
                pos += 2;
            }

            if (pos >= end) return null;

            uint32 img_size = end - pos;
            uint8[] image = data[pos:pos + img_size];

            return image;
        }

        private Gst.Sample? get_cover_sample (Gst.TagList tag_list) {
            Gst.Sample? cover_sample = null;
            Gst.Sample sample;
            for (int i = 0; tag_list.get_sample_index (Gst.Tags.IMAGE, i, out sample); i++) {
                var caps = sample.get_caps ();
                unowned Gst.Structure caps_struct = caps.get_structure (0);
                int image_type = Gst.Tag.ImageType.UNDEFINED;
                caps_struct.get_enum ("image-type", typeof (Gst.Tag.ImageType), out image_type);
                if (image_type == Gst.Tag.ImageType.UNDEFINED && cover_sample == null) {
                    cover_sample = sample;
                } else if (image_type == Gst.Tag.ImageType.FRONT_COVER) {
                    return sample;
                }
            }

            return cover_sample;
        }

        private Gdk.Pixbuf? get_pixbuf_from_buffer (Gst.Buffer buffer) {
            Gst.MapInfo map_info;

            if (!buffer.map (out map_info, Gst.MapFlags.READ)) {
                warning ("Could not map memory buffer");
                return null;
            }

            Gdk.Pixbuf pix = null;

            try {
                var loader = new Gdk.PixbufLoader ();

                if (loader.write (map_info.data) && loader.close ()) {
                    pix = loader.get_pixbuf ();
                }
            } catch (Error err) {
                warning ("Error processing image data: %s", err.message);
            }

            buffer.unmap (map_info);

            return pix;
        }
    }
}
