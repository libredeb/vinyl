/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Widgets {
    public class RadioStationList : GLib.Object {
        private Gee.ArrayList<RadioStationRow> station_rows = new Gee.ArrayList<RadioStationRow> ();
        private int item_height;
        private int visible_items = 0;
        private int top_index = 0;
        public int focused_index = 0;
        public bool is_focused = false;
        private SDL.Video.Rect rect;

        public RadioStationList (
            SDL.Video.Renderer renderer,
            Gee.ArrayList<Vinyl.Radio.RadioStation> stations,
            int x, int y, int w, int h
        ) {
            this.rect = { x, y, w, h };
            int count = stations.size;
            int base_height = 80;
            this.visible_items = h / base_height;
            if (count > 0 && count <= this.visible_items) {
                this.visible_items = count;
            }
            this.item_height = h / this.visible_items;
            foreach (var station in stations) {
                station_rows.add (new RadioStationRow (renderer, station, rect.x, 0, (int) rect.w, item_height));
            }
        }

        public void scroll_up () {
            if (focused_index > 0) {
                focused_index--;
                if (focused_index < top_index) {
                    top_index = focused_index;
                }
            }
        }

        public void scroll_down () {
            if (focused_index < station_rows.size - 1) {
                focused_index++;
                if (focused_index >= top_index + visible_items) {
                    top_index = focused_index - visible_items + 1;
                }
            }
        }

        public string? active_station_code { get; set; default = null; }

        public void render (SDL.Video.Renderer renderer, SDLTTF.Font font, SDLTTF.Font small_font) {
            for (int i = top_index; i < top_index + visible_items && i < station_rows.size; i++) {
                var row = station_rows.get (i);
                row.focused = (i == focused_index) && this.is_focused;
                row.is_active = (active_station_code != null &&
                    row.station.country_code == active_station_code);
                row.rect.y = this.rect.y + ((i - top_index) * item_height);
                row.render (renderer, font, small_font);
            }
        }

        public bool is_clicked (int mouse_x, int mouse_y, out Vinyl.Radio.RadioStation? station) {
            for (int i = top_index; i < top_index + visible_items && i < station_rows.size; i++) {
                var row = station_rows.get (i);
                if (
                    mouse_x >= row.rect.x && mouse_x <= row.rect.x + row.rect.w &&
                    mouse_y >= row.rect.y && mouse_y <= row.rect.y + row.rect.h
                ) {
                    station = row.station;
                    this.focused_index = i;
                    return true;
                }
            }
            station = null;
            return false;
        }

        public Vinyl.Radio.RadioStation? get_focused_station () {
            if (focused_index >= 0 && focused_index < station_rows.size) {
                return station_rows.get (focused_index).station;
            }
            return null;
        }

        public int get_total_items () {
            return station_rows.size;
        }
    }
}
