/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Library {
    public class MusicScanner : GLib.Object {

        private Gee.ArrayList<Track> tracks;
        private string music_dir;
        private string covers_cache_dir;

        public MusicScanner () {
            this.tracks = new Gee.ArrayList<Track> ();
            this.music_dir = Path.build_filename (Environment.get_home_dir (), "Music");
            this.covers_cache_dir = Path.build_filename (Environment.get_user_cache_dir (), "vinyl", "covers");

            try {
                var cache_dir_file = File.new_for_path (this.covers_cache_dir);
                if (!cache_dir_file.query_exists (null)) {
                    cache_dir_file.make_directory_with_parents (null);
                }
            } catch (Error e) {
                warning ("Could not create cache directory: %s", e.message);
            }
        }

        public async Gee.ArrayList<Track> scan_files () {
            var dir = File.new_for_path (this.music_dir);
            if (!dir.query_exists (null)) {
                warning ("Music directory not found: %s", this.music_dir);
                return this.tracks;
            }

            try {
                var enumerator = yield dir.enumerate_children_async (
                    "standard::name,standard::type",
                    FileQueryInfoFlags.NONE,
                    Priority.DEFAULT,
                    null
                );

                while (true) {
                    var file_infos = yield enumerator.next_files_async (10, Priority.DEFAULT, null);
                    if (file_infos.length () == 0) {
                        break;
                    }

                    foreach (var info in file_infos) {
                        var child = enumerator.get_child (info);
                        var file_path = child.get_path ();
                        if (info.get_file_type () == FileType.DIRECTORY) {
                            // For simplicity, this first version won't recurse into subdirectories.
                            // We can add recursion later.
                        } else if (file_path != null) {
                            foreach (string format in Constants.SUPPORTED_FORMATS) {
                                if (file_path.has_suffix (format)) {
                                    process_file (file_path);
                                    break;
                                }
                            }
                        }
                    }
                }
            } catch (Error e) {
                warning ("Error scanning music directory: %s", e.message);
            }

            return this.tracks;
        }

        private void process_file (string file_path) {
            var tag_file = new TagLib.File (file_path);
            if (tag_file == null) {
                warning ("Error processing file %s", file_path);
                return;
            }
            unowned TagLib.Tag tag = tag_file.tag;

            if (tag != null) {
                var title = tag.title != "" ? tag.title : Path.get_basename (file_path);
                var artist = tag.artist != "" ? tag.artist : "Unknown Artist";
                var album = tag.album != "" ? tag.album : "Unknown Album";
                string? album_art_path = save_album_art (file_path, album, artist);

                var track = new Track (file_path, title, artist, album, album_art_path);
                this.tracks.add (track);
                stdout.printf ("Found track: %s - %s\n", artist, title);
            }
        }

        private string? save_album_art (string file_path, string album, string artist) {
            string filename = "%s-%s.jpg".printf (artist.replace ("/", "_"), album.replace ("/", "_"));
            var cover_path = Path.build_filename (this.covers_cache_dir, filename);

            if (FileUtils.test (cover_path, FileTest.EXISTS)) {
                return cover_path;
            }

            try {
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

            return null;
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
