/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Widgets {
    public class CategoryList : GLib.Object {
        private Gee.ArrayList<string> items = new Gee.ArrayList<string> ();
        private SDL.Video.Texture? icon_texture;
        private SDL.Video.Texture? arrow_texture;
        private int item_height;
        private int visible_items = 0;
        private int top_index = 0;
        public int focused_index = 0;
        public bool is_focused = false;
        private SDL.Video.Rect rect;

        private const int MARQUEE_GAP = 80;
        private const double MARQUEE_SPEED = 50.0;

        public CategoryList (
            SDL.Video.Renderer renderer,
            string icon_path,
            Gee.ArrayList<string> names,
            int x, int y, int w, int h
        ) {
            this.rect = { x, y, w, h };
            this.items.add_all (names);

            int base_height = 120;
            this.visible_items = h / base_height;
            if (this.visible_items < 1) {
                this.visible_items = 1;
            }
            this.item_height = h / this.visible_items;

            var surface = SDLImage.load (icon_path);
            if (surface != null) {
                this.icon_texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            }
            var arrow_surface = SDLImage.load (Constants.ARROW_RIGHT_ICON_PATH);
            if (arrow_surface != null) {
                this.arrow_texture = SDL.Video.Texture.create_from_surface (renderer, arrow_surface);
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
            if (focused_index < items.size - 1) {
                focused_index++;
                if (focused_index >= top_index + visible_items) {
                    top_index = focused_index - visible_items + 1;
                }
            }
        }

        public void render (SDL.Video.Renderer renderer, SDLTTF.Font font) {
            for (int i = top_index; i < top_index + visible_items && i < items.size; i++) {
                bool row_focused = (i == focused_index) && this.is_focused;
                int row_y = this.rect.y + ((i - top_index) * item_height);
                var row_rect = SDL.Video.Rect () {
                    x = this.rect.x, y = row_y,
                    w = this.rect.w, h = item_height
                };

                if (row_focused) {
                    renderer.set_draw_color (40, 40, 50, 255);
                } else {
                    renderer.set_draw_color (20, 20, 25, 255);
                }
                renderer.fill_rect (row_rect);

                var icon_h = (int)(item_height * 0.6);
                var icon_w = icon_h;
                var icon_dest = SDL.Video.Rect () {
                    x = row_rect.x + 40,
                    y = (int)(row_y + (item_height / 2) - (icon_h / 2)),
                    w = icon_w, h = icon_h
                };
                if (icon_texture != null) {
                    renderer.copy (icon_texture, null, icon_dest);
                }

                var text_surface = font.render (items.get (i), {255, 255, 255, 255});
                if (text_surface != null) {
                    var text_texture = SDL.Video.Texture.create_from_surface (renderer, text_surface);
                    if (text_texture != null) {
                        int tw, th;
                        text_texture.query (null, null, out tw, out th);
                        int text_x = (int) icon_dest.x + (int) icon_dest.w + 40;
                        int max_tw = (int) row_rect.w - text_x - 90;
                        int text_y = (int)(row_y + (item_height / 2) - (th / 2));
                        if (tw <= max_tw) {
                            renderer.copy (text_texture, null, {text_x, text_y, tw, th});
                        } else {
                            render_marquee (renderer, text_texture, tw, th, text_x, text_y, max_tw);
                        }
                    }
                }

                if (arrow_texture != null) {
                    renderer.copy (arrow_texture, null, {
                        (int)(row_rect.x + row_rect.w - 50 - 40),
                        (int)(row_y + (item_height / 2) - (22)),
                        44, 44
                    });
                }
            }
        }

        private void render_marquee (
            SDL.Video.Renderer renderer,
            SDL.Video.Texture texture,
            int text_width, int text_height,
            int area_x, int y, int max_width
        ) {
            int cycle_width = text_width + MARQUEE_GAP;
            uint ticks = SDL.Timer.get_ticks ();
            int offset = (int) ((ticks * MARQUEE_SPEED / 1000.0) % cycle_width);

            render_marquee_copy (renderer, texture, text_width, text_height, y, area_x, max_width, -offset);
            render_marquee_copy (renderer, texture, text_width, text_height, y, area_x, max_width, -offset + cycle_width);
        }

        private void render_marquee_copy (
            SDL.Video.Renderer renderer,
            SDL.Video.Texture texture,
            int tw, int th,
            int y,
            int area_x, int area_w,
            int rel_x
        ) {
            if (rel_x >= area_w || rel_x + tw <= 0) {
                return;
            }
            int src_x = (rel_x < 0) ? -rel_x : 0;
            int dst_x = area_x + int.max (rel_x, 0);
            int vis_w = int.min (tw - src_x, area_w - int.max (rel_x, 0));
            if (vis_w <= 0) {
                return;
            }
            renderer.copy (texture, {src_x, 0, vis_w, th}, {dst_x, y, vis_w, th});
        }

        public bool is_clicked (int mouse_x, int mouse_y, out string? name) {
            for (int i = top_index; i < top_index + visible_items && i < items.size; i++) {
                int row_y = this.rect.y + ((i - top_index) * item_height);
                if (mouse_x >= this.rect.x && mouse_x <= this.rect.x + this.rect.w &&
                    mouse_y >= row_y && mouse_y <= row_y + item_height) {
                    name = items.get (i);
                    this.focused_index = i;
                    return true;
                }
            }
            name = null;
            return false;
        }

        public string? get_focused_item () {
            if (focused_index >= 0 && focused_index < items.size) {
                return items.get (focused_index);
            }
            return null;
        }

        public int get_total_items () {
            return items.size;
        }
    }
}
