/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2016 Juan Pablo Lozano <libredeb@gmail.com>
 */

using Gst;

namespace Vinyl {
    public class Player : GLib.Object {
        private Gst.Element playbin;
        private bool _is_playing = false;
        private Gee.ArrayList<Library.Track> playlist;
        private int current_track_index = 0;

        public signal void state_changed (bool is_playing);

        public Player (Gee.ArrayList<Library.Track> playlist, int start_index) {
            this.playlist = playlist;
            this.current_track_index = start_index;

            playbin = Gst.ElementFactory.make ("playbin", "playbin");
            var track = playlist.get (start_index);
            playbin.set_property ("uri", "file://" + track.file_path);
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
                        // Using stderr for errors is fine
                        stderr.printf ("  Error from GStreamer: %s\n", err.message);
                        stderr.printf ("  Debugging info: %s\n", debug);
                        break;
                    case Gst.MessageType.EOS:
                        // Optional: handle end of stream
                        break;
                    default:
                        break;
                }
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
                playbin.get_state(out current, out pending, 100 * Gst.MSECOND); // Shorter timeout
            }
            _is_playing = true;
            state_changed (_is_playing);
        }

        public void play_next () {
            if (current_track_index < playlist.size - 1) {
                current_track_index++;
                play_track (current_track_index);
            }
        }

        public void play_previous () {
            if (current_track_index > 0) {
                current_track_index--;
                play_track (current_track_index);
            }
        }

        private void play_track (int index) {
            bool was_playing = _is_playing;
            stop ();
            var track = playlist.get (index);
            playbin.set_property ("uri", "file://" + track.file_path);
            if (was_playing) {
                play ();
            }
        }

        public int get_current_track_index () {
            return current_track_index;
        }

        public Library.Track get_current_track () {
            return playlist.get (current_track_index);
        }

        public bool is_playing () {
            return _is_playing;
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

        public int64 get_position () {
            int64 pos = 0;
            if (playbin != null) {
                playbin.query_position (Gst.Format.TIME, out pos);
            }
            return pos;
        }

        public int64 get_duration () {
            int64 dur = 0;
            if (playbin != null) {
                playbin.query_duration (Gst.Format.TIME, out dur);
            }
            return dur;
        }

        public void seek (int64 position) {
            playbin.seek_simple (Gst.Format.TIME, Gst.SeekFlags.FLUSH, position);
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
