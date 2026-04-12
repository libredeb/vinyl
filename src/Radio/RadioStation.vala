/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Radio {
    public class RadioStation : GLib.Object {
        public string country_code { get; set; }
        public string country_name { get; set; }
        public string station_name { get; set; }
        public string stream_url { get; set; }

        public RadioStation (
            string country_code,
            string country_name,
            string station_name,
            string stream_url
        ) {
            this.country_code = country_code;
            this.country_name = country_name;
            this.station_name = station_name;
            this.stream_url = stream_url;
        }

        public string get_flag_path () {
            return Constants.FLAGS_DIR + "/" + country_code + ".png";
        }

        /**
         * Loads stations from the INI file at Constants.RADIOS_INI_PATH.
         *
         * Expected format:
         * {{{
         * [AR]
         * Name=Argentina - Radio Nacional
         * URL=http://example.com/stream
         * }}}
         *
         * The section name is the country code (used to locate the flag PNG).
         * The part before " - " in Name is the country name; the rest is the station name.
         * If there is no " - " separator, the country code is used as country name.
         */
        public static Gee.ArrayList<RadioStation> load_stations () {
            var stations = new Gee.ArrayList<RadioStation> ();
            var keyfile = new GLib.KeyFile ();

            try {
                keyfile.load_from_file (Constants.RADIOS_INI_PATH, GLib.KeyFileFlags.NONE);
            } catch (GLib.Error e) {
                warning ("Could not load radios.ini: %s", e.message);
                return stations;
            }

            var groups = keyfile.get_groups ();
            foreach (unowned string code in groups) {
                try {
                    var full_name = keyfile.get_string (code, "Name");
                    var url = keyfile.get_string (code, "URL");

                    string country_name = code;
                    string station_name = full_name;

                    var sep = full_name.index_of (" - ");
                    if (sep >= 0) {
                        country_name = full_name.substring (0, sep);
                        station_name = full_name.substring (sep + 3);
                    }

                    stations.add (new RadioStation (code, country_name, station_name, url));
                } catch (GLib.KeyFileError e) {
                    warning ("Skipping radio [%s]: %s", code, e.message);
                }
            }

            return stations;
        }
    }
}
