/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

using Gst;

namespace Vinyl.Radio {
    public class RadioPlayer : GLib.Object {
        private Gst.Element playbin;
        private bool _is_playing = false;
        private RadioStation? current_station = null;
        private string? _cached_art_path = null;

        public signal void state_changed (bool is_playing);
        public signal void album_art_changed (string? art_path);

        public RadioPlayer () {
            playbin = Gst.ElementFactory.make ("playbin", "radio-playbin");
        }

        public void play_station (RadioStation station) {
            stop ();
            current_station = station;
            _cached_art_path = null;
            album_art_changed (null);
            playbin.set_property ("uri", station.stream_url);
            play ();
        }

        public void handle_messages () {
            var bus = playbin.get_bus ();
            Gst.Message message;
            while ((message = bus.pop ()) != null) {
                switch (message.type) {
                    case Gst.MessageType.ERROR:
                        GLib.Error err;
                        string debug;
                        message.parse_error (out err, out debug);
                        stderr.printf ("  Radio stream error: %s\n", err.message);
                        stderr.printf ("  Debug info: %s\n", debug);
                        break;
                    case Gst.MessageType.TAG:
                        Gst.TagList tags;
                        message.parse_tag (out tags);
                        extract_album_art (tags);
                        break;
                    case Gst.MessageType.BUFFERING:
                        break;
                    default:
                        break;
                }
            }
        }

        private void extract_album_art (Gst.TagList tags) {
            Gst.Sample? sample = null;
            if (!tags.get_sample (Gst.Tags.IMAGE, out sample)) {
                tags.get_sample (Gst.Tags.PREVIEW_IMAGE, out sample);
            }
            if (sample == null) {
                return;
            }

            var buffer = sample.get_buffer ();
            if (buffer == null || buffer.get_size () == 0) {
                return;
            }

            Gst.MapInfo map;
            if (!buffer.map (out map, Gst.MapFlags.READ)) {
                return;
            }

            try {
                var cache_dir = GLib.Path.build_filename (
                    GLib.Environment.get_user_cache_dir (), "vinyl");
                GLib.DirUtils.create_with_parents (cache_dir, 0755);
                var art_path = GLib.Path.build_filename (cache_dir, "radio_art.img");

                GLib.FileUtils.set_data (art_path, map.data[0:map.size]);
                buffer.unmap (map);

                if (_cached_art_path != art_path || _cached_art_path == null) {
                    _cached_art_path = art_path;
                    album_art_changed (art_path);
                }
            } catch (GLib.FileError e) {
                buffer.unmap (map);
                warning ("Could not cache radio album art: %s", e.message);
            }
        }

        public void play_pause () {
            if (_is_playing) {
                playbin.set_state (Gst.State.PAUSED);
                _is_playing = false;
                state_changed (_is_playing);
            } else {
                play ();
            }
        }

        private void play () {
            var ret = playbin.set_state (Gst.State.PLAYING);
            if (ret == Gst.StateChangeReturn.ASYNC) {
                Gst.State current, pending;
                playbin.get_state (out current, out pending, 100 * Gst.MSECOND);
            }
            _is_playing = true;
            state_changed (_is_playing);
        }

        public bool is_playing () {
            return _is_playing;
        }

        public RadioStation? get_current_station () {
            return current_station;
        }

        public void stop () {
            if (playbin != null) {
                playbin.set_state (Gst.State.NULL);
                if (_is_playing) {
                    _is_playing = false;
                    state_changed (false);
                }
            }
        }

        public double get_volume () {
            double vol = 0;
            playbin.get ("volume", out vol);
            return vol;
        }

        public void set_volume (double vol) {
            playbin.set ("volume", vol);
        }
    }
}
