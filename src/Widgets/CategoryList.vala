/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Widgets {
    public class CategoryList : GLib.Object {
        private Gee.ArrayList<string> items = new Gee.ArrayList<string> ();
        private SDL.Video.Texture? arrow_texture;
        private bool use_initials = false;
        private SDL.Video.Texture?[] item_textures;
        private bool has_item_textures = false;
        private SDL.Video.Texture? default_icon_texture;
        private int item_height;
        private int visible_items = 0;
        private int top_index = 0;
        public int focused_index = 0;
        public bool is_focused = false;
        private SDL.Video.Rect rect;

        private const string ELLIPSIS = "\u2026";

        public CategoryList (
            SDL.Video.Renderer renderer,
            Gee.ArrayList<string> names,
            int x, int y, int w, int h,
            bool use_initials = false,
            Gee.HashMap<string, string?>? cover_paths = null
        ) {
            this.rect = { x, y, w, h };
            this.items.add_all (names);
            this.use_initials = use_initials;

            int base_height = 120;
            this.visible_items = h / base_height;
            if (this.visible_items < 1) {
                this.visible_items = 1;
            }
            this.item_height = h / this.visible_items;

            this.item_textures = new SDL.Video.Texture?[this.items.size];
            if (cover_paths != null) {
                this.has_item_textures = true;
                for (int i = 0; i < this.items.size; i++) {
                    string name = this.items.get (i);
                    if (cover_paths.has_key (name) && cover_paths.get (name) != null) {
                        var surface = SDLImage.load (cover_paths.get (name));
                        if (surface != null) {
                            this.item_textures[i] =
                                SDL.Video.Texture.create_from_surface (renderer, surface);
                        }
                    }
                }
                var default_surface = SDLImage.load (Constants.DEFAULT_COVER_ICON_PATH);
                if (default_surface != null) {
                    this.default_icon_texture =
                        SDL.Video.Texture.create_from_surface (renderer, default_surface);
                }
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
                if (use_initials) {
                    renderer.set_draw_color (245, 197, 24, 255);
                    renderer.fill_rect (icon_dest);
                    string initials = get_initials (items.get (i));
                    var init_surface = font.render (initials, {40, 40, 40, 255});
                    if (init_surface != null) {
                        var init_texture = SDL.Video.Texture.create_from_surface (renderer, init_surface);
                        if (init_texture != null) {
                            int itw, ith;
                            init_texture.query (null, null, out itw, out ith);
                            int ix = (int) icon_dest.x + ((int) icon_dest.w - itw) / 2;
                            int iy = (int) icon_dest.y + ((int) icon_dest.h - ith) / 2;
                            renderer.copy (init_texture, null, {ix, iy, itw, ith});
                        }
                    }
                } else if (has_item_textures) {
                    if (item_textures[i] != null) {
                        renderer.copy (item_textures[i], null, icon_dest);
                    } else if (default_icon_texture != null) {
                        renderer.copy (default_icon_texture, null, icon_dest);
                    }
                }

                int text_x = (int) icon_dest.x + (int) icon_dest.w + 40;
                int max_tw = (int) row_rect.w - text_x - 90;
                render_ellipsized (renderer, font, items.get (i), {255, 255, 255, 255},
                    text_x, (int)(row_y + (item_height / 2)), max_tw);

                if (arrow_texture != null) {
                    renderer.copy (arrow_texture, null, {
                        (int)(row_rect.x + row_rect.w - 50 - 40),
                        (int)(row_y + (item_height / 2) - (16)),
                        24, 32
                    });
                }
            }
        }

        private string get_initials (string name) {
            var parts = name.split (" ");
            var sb = new StringBuilder ();
            foreach (unowned string part in parts) {
                if (part.length > 0 && sb.len < 2) {
                    sb.append (part.get_char (0).to_string ().up ());
                }
            }
            if (sb.len == 0) {
                return "?";
            }
            return sb.str;
        }

        private void render_ellipsized (
            SDL.Video.Renderer renderer,
            SDLTTF.Font font,
            string text,
            SDL.Video.Color color,
            int x, int center_y,
            int max_width
        ) {
            string display_text = text;
            var surface = font.render (display_text, color);
            if (surface == null) return;
            var texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            if (texture == null) return;
            int tw, th;
            texture.query (null, null, out tw, out th);

            if (tw > max_width) {
                string truncated = text;
                while (truncated.length > 1) {
                    truncated = truncated.substring (0, truncated.length - 1);
                    display_text = truncated + ELLIPSIS;
                    surface = font.render (display_text, color);
                    if (surface == null) return;
                    texture = SDL.Video.Texture.create_from_surface (renderer, surface);
                    if (texture == null) return;
                    texture.query (null, null, out tw, out th);
                    if (tw <= max_width) {
                        break;
                    }
                }
            }

            int dest_y = center_y - (th / 2);
            renderer.copy (texture, null, {x, dest_y, tw, th});
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
