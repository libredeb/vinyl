/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Widgets {
    public class OnScreenKeyboard : GLib.Object {
        public const string KEY_BACKSPACE = "\b";
        public const string KEY_SPACE = " ";

        private Gee.ArrayList<Gee.ArrayList<string>> rows;
        public int focused_row = 0;
        public int focused_col = 0;
        public bool is_focused = false;
        private SDL.Video.Rect rect;
        private int margin_x = 10;
        private int margin_y = 8;
        private int key_spacing_x = 4;
        private int key_spacing_y = 6;
        private int max_cols = 10;
        private int key_radius = 6;

        private SDL.Video.Texture? backspace_icon = null;
        private SDL.Video.Texture? space_icon = null;
        private bool textures_loaded = false;
        private int letter_height = -1;

        public OnScreenKeyboard (int x, int y, int w, int h) {
            this.rect = { x, y, w, h };
            build_layout ();
        }

        private string get_lang_prefix () {
            Intl.setlocale (GLib.LocaleCategory.ALL, "");
            string? locale = Intl.setlocale (GLib.LocaleCategory.MESSAGES, null);
            if (locale == null || locale.length < 2) {
                return "en";
            }
            return locale.substring (0, 2).down ();
        }

        private void build_layout () {
            rows = new Gee.ArrayList<Gee.ArrayList<string>> ();

            string lang_prefix = get_lang_prefix ();

            var num_row = new Gee.ArrayList<string> ();
            for (int i = 1; i <= 9; i++) {
                num_row.add (i.to_string ());
            }
            num_row.add ("0");
            rows.add (num_row);

            var layouts = new Gee.HashMap<string, string> ();
            layouts.set ("es", "QWERTYUIOP-ASDFGHJKLÑ-ZXCVBNM");
            layouts.set ("fr", "AZERTYUIOP-QSDFGHJKLM-WXCVBN");
            layouts.set ("de", "QWERTZUIOPÜ-ASDFGHJKLÖÄ-YXCVBNM");
            layouts.set ("pt", "QWERTYUIOP-ASDFGHJKLÇ-ZXCVBNM");
            layouts.set ("en", "QWERTYUIOP-ASDFGHJKL-ZXCVBNM");

            string layout = layouts.has_key (lang_prefix) ? layouts.get (lang_prefix) : layouts.get ("en");
            string[] row_strings = layout.split ("-");

            max_cols = 10;
            foreach (string rs in row_strings) {
                int count = (int) rs.char_count ();
                if (count > max_cols) max_cols = count;
            }

            foreach (string row_str in row_strings) {
                var row = new Gee.ArrayList<string> ();
                int len = (int) row_str.char_count ();
                for (int i = 0; i < len; i++) {
                    unichar c = row_str.get_char (row_str.index_of_nth_char (i));
                    row.add (c.to_string ());
                }
                rows.add (row);
            }

            rows.get (rows.size - 1).add (KEY_BACKSPACE);

            var space_row = new Gee.ArrayList<string> ();
            space_row.add (KEY_SPACE);
            rows.add (space_row);
        }

        private void ensure_textures (SDL.Video.Renderer renderer) {
            if (textures_loaded) return;
            textures_loaded = true;
            backspace_icon = SDLImage.load_texture (renderer, Constants.CLEAR_KEY_ICON_PATH);
            space_icon = SDLImage.load_texture (renderer, Constants.SPACE_BAR_ICON_PATH);
        }

        private void get_key_dimensions (out int key_w, out int key_h) {
            int available_w = (int) rect.w - 2 * margin_x;
            key_w = (available_w - (max_cols - 1) * key_spacing_x) / max_cols;

            int num_rows = rows.size;
            int available_h = (int) rect.h - 2 * margin_y;
            key_h = (available_h - (num_rows - 1) * key_spacing_y) / num_rows;
        }

        private int get_row_offset (int row_index, int row_size, int key_w) {
            if (row_index == 0 || row_index == rows.size - 1) return 0;
            int total_row_w = row_size * key_w + (row_size - 1) * key_spacing_x;
            int total_max_w = max_cols * key_w + (max_cols - 1) * key_spacing_x;
            return (total_max_w - total_row_w) / 2;
        }

        public void render (SDL.Video.Renderer renderer, SDLTTF.Font font) {
            ensure_textures (renderer);

            if (letter_height < 0) {
                var ref_s = font.render ("A", {255, 255, 255, 255});
                if (ref_s != null) {
                    letter_height = ref_s.h;
                } else {
                    letter_height = 20;
                }
            }

            renderer.set_draw_color (10, 10, 12, 255);
            renderer.fill_rect (rect);

            int key_w, key_h;
            get_key_dimensions (out key_w, out key_h);
            int available_w = (int) rect.w - 2 * margin_x;

            for (int r = 0; r < rows.size; r++) {
                var row = rows.get (r);
                int y = rect.y + margin_y + r * (key_h + key_spacing_y);
                int row_offset = get_row_offset (r, row.size, key_w);

                for (int c = 0; c < row.size; c++) {
                    string key = row.get (c);
                    int x = rect.x + margin_x + row_offset + c * (key_w + key_spacing_x);
                    int this_key_w = key_w;

                    if (key == KEY_SPACE) {
                        this_key_w = available_w;
                        x = rect.x + margin_x;
                    }

                    var key_rect = SDL.Video.Rect () {
                        x = x, y = y, w = this_key_w, h = key_h
                    };

                    bool is_key_focused = is_focused && r == focused_row && c == focused_col;
                    if (is_key_focused) {
                        renderer.set_draw_color (255, 156, 17, 255);
                    } else {
                        renderer.set_draw_color (50, 50, 55, 255);
                    }
                    Vinyl.Utils.Drawing.draw_rounded_rect_r (renderer, key_rect, key_radius);

                    if (key == KEY_BACKSPACE && backspace_icon != null) {
                        int icon_size = letter_height;
                        int ix = x + (this_key_w - icon_size) / 2;
                        int iy = y + (key_h - icon_size) / 2;
                        renderer.copy (backspace_icon, null, {ix, iy, icon_size, icon_size});
                    } else if (key == KEY_SPACE && space_icon != null) {
                        int icon_size = letter_height;
                        int ix = x + (this_key_w - icon_size) / 2;
                        int iy = y + (key_h - icon_size) / 2;
                        renderer.copy (space_icon, null, {ix, iy, icon_size, icon_size});
                    } else {
                        SDL.Video.Color text_color;
                        if (is_key_focused) {
                            text_color = {0, 0, 0, 255};
                        } else {
                            text_color = {255, 255, 255, 255};
                        }

                        var surface = font.render (key, text_color);
                        if (surface != null) {
                            var texture = SDL.Video.Texture.create_from_surface (renderer, surface);
                            if (texture != null) {
                                int tw, th;
                                texture.query (null, null, out tw, out th);
                                int tx = x + (this_key_w - tw) / 2;
                                int ty = y + (key_h - th) / 2;
                                renderer.copy (texture, null, {tx, ty, tw, th});
                            }
                        }
                    }
                }
            }
        }

        public string get_focused_key () {
            if (focused_row >= 0 && focused_row < rows.size) {
                var row = rows.get (focused_row);
                if (focused_col >= 0 && focused_col < row.size) {
                    return row.get (focused_col);
                }
            }
            return "";
        }

        public void move_left () {
            if (focused_col > 0) {
                focused_col--;
            }
        }

        public void move_right () {
            if (focused_row >= 0 && focused_row < rows.size) {
                var row = rows.get (focused_row);
                if (focused_col < row.size - 1) {
                    focused_col++;
                }
            }
        }

        /** Returns false if already at the top row. */
        public bool move_up () {
            if (focused_row > 0) {
                focused_row--;
                var row = rows.get (focused_row);
                if (focused_col >= row.size) {
                    focused_col = row.size - 1;
                }
                return true;
            }
            return false;
        }

        public void move_down () {
            if (focused_row < rows.size - 1) {
                focused_row++;
                var row = rows.get (focused_row);
                if (focused_col >= row.size) {
                    focused_col = row.size - 1;
                }
            }
        }

        public string? handle_click (int mouse_x, int mouse_y) {
            int key_w, key_h;
            get_key_dimensions (out key_w, out key_h);
            int available_w = (int) rect.w - 2 * margin_x;

            for (int r = 0; r < rows.size; r++) {
                var row = rows.get (r);
                int y = rect.y + margin_y + r * (key_h + key_spacing_y);
                int row_offset = get_row_offset (r, row.size, key_w);

                for (int c = 0; c < row.size; c++) {
                    string key = row.get (c);
                    int x = rect.x + margin_x + row_offset + c * (key_w + key_spacing_x);
                    int this_key_w = key_w;

                    if (key == KEY_SPACE) {
                        this_key_w = available_w;
                        x = rect.x + margin_x;
                    }

                    if (mouse_x >= x && mouse_x <= x + this_key_w &&
                        mouse_y >= y && mouse_y <= y + key_h) {
                        focused_row = r;
                        focused_col = c;
                        return key;
                    }
                }
            }
            return null;
        }
    }
}
