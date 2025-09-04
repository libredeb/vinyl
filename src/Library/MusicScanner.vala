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
                        } else if (file_path != null && (file_path.has_suffix (".mp3") || file_path.has_suffix (".flac"))) {
                            process_file (file_path);
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
                // Use ffmpeg to extract the cover. The -y flag overwrites the output file if it exists.
                var proc = new Subprocess.newv (
                    new string[] {"ffmpeg", "-i", file_path, "-an", "-vcodec", "copy", "-y", cover_path},
                    SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE
                );
                proc.wait (null); // Synchronous call for simplicity

                if (proc.get_if_exited () && proc.get_exit_status () == 0 && FileUtils.test(cover_path, FileTest.EXISTS)) {
                    return cover_path;
                }
            } catch (Error e) {
                warning ("ffmpeg command failed for '%s': %s", file_path, e.message);
            }
            
            return null;
        }
    }
}
