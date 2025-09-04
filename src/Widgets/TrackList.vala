/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Widgets {
    public class TrackList : GLib.Object {
        private Gee.ArrayList<Track> track_widgets = new Gee.ArrayList<Track> ();
        private int item_height = 80;
        private int visible_items = 0;
        private int top_index = 0; // The index of the first visible item
        public int focused_index = 0;
        public bool is_focused = false;
        private SDL.Video.Rect rect;

        public TrackList (
            SDL.Video.Renderer renderer,
            Gee.ArrayList<Vinyl.Library.Track> tracks,
            int x, int y, int w, int h
        ) {
            this.rect = { x, y, w, h };
            this.visible_items = h / item_height;
            foreach (var track in tracks) {
                track_widgets.add (new Track (renderer, track, x, 0, w, item_height));
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
            if (focused_index < track_widgets.size - 1) {
                focused_index++;
                if (focused_index >= top_index + visible_items) {
                    top_index = focused_index - visible_items + 1;
                }
            }
        }

        public void render (SDL.Video.Renderer renderer, SDLTTF.Font font, SDLTTF.Font small_font) {
            for (int i = top_index; i < top_index + visible_items && i < track_widgets.size; i++) {
                var widget = track_widgets.get (i);
                widget.focused = (i == focused_index) && this.is_focused;
                widget.rect.y = this.rect.y + ((i - top_index) * item_height);
                widget.render (renderer, font, small_font);
            }
        }

        public int get_total_items () {
            return track_widgets.size;
        }
    }
}
