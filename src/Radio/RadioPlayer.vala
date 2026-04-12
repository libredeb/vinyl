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

        public signal void state_changed (bool is_playing);

        public RadioPlayer () {
            playbin = Gst.ElementFactory.make ("playbin", "radio-playbin");
        }

        public void play_station (RadioStation station) {
            stop ();
            current_station = station;
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
                    case Gst.MessageType.BUFFERING:
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
