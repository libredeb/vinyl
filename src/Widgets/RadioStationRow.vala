/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Widgets {
    public class RadioStationRow : GLib.Object {
        public Vinyl.Radio.RadioStation station { get; private set; }
        private SDL.Video.Texture? flag_texture;
        public SDL.Video.Rect rect;
        public bool focused = false;
        public bool is_active = false;

        public RadioStationRow (
            SDL.Video.Renderer renderer,
            Vinyl.Radio.RadioStation station,
            int x, int y, int w, int h
        ) {
            this.station = station;
            this.rect = { x, y, w, h };

            var flag_path = station.get_flag_path ();
            var surface = SDLImage.load (flag_path);
            if (surface == null) {
                warning ("Could not load flag: %s – %s", flag_path, SDL.get_error ());
            } else {
                this.flag_texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            }
        }

        public void render (SDL.Video.Renderer renderer, SDLTTF.Font font, SDLTTF.Font small_font) {
            if (focused) {
                renderer.set_draw_color (53, 132, 228, 255);
            } else if (is_active) {
                renderer.set_draw_color (30, 60, 30, 255);
            } else {
                renderer.set_draw_color (20, 20, 25, 255);
            }
            renderer.fill_rect (this.rect);

            var flag_h = (int)(this.rect.h * 0.6);
            var flag_w = (int)(flag_h * 1.5);
            var flag_dest = SDL.Video.Rect () {
                x = this.rect.x + 20,
                y = (int)(this.rect.y + (this.rect.h / 2) - (flag_h / 2)),
                w = flag_w,
                h = flag_h
            };
            if (flag_texture != null) {
                renderer.copy (this.flag_texture, null, flag_dest);
            }

            int text_x = (int)(flag_dest.x + flag_dest.w + 20);
            int eq_reserve = is_active ? 50 : 0;
            int max_text_w = this.rect.x + (int) this.rect.w - text_x - 20 - eq_reserve;

            render_ellipsized (renderer, font, this.station.station_name, {255, 255, 255, 255},
                text_x, (int)(this.rect.y + (this.rect.h / 2)), max_text_w, true);

            render_ellipsized (renderer, small_font, this.station.country_name, {200, 200, 200, 255},
                text_x, (int)(this.rect.y + (this.rect.h / 2)), max_text_w, false);

            if (is_active) {
                render_eq_bars (renderer);
            }
        }

        private void render_ellipsized (
            SDL.Video.Renderer renderer,
            SDLTTF.Font font,
            string text,
            SDL.Video.Color color,
            int x, int y,
            int max_width,
            bool above_baseline
        ) {
            string display_text = text;
            var surface = font.render (display_text, color);
            var texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            int tw, th;
            texture.query (null, null, out tw, out th);

            if (tw > max_width) {
                string truncated = text;
                while (truncated.length > 1) {
                    truncated = truncated.substring (0, truncated.length - 1);
                    display_text = truncated + "…";
                    surface = font.render (display_text, color);
                    texture = SDL.Video.Texture.create_from_surface (renderer, surface);
                    texture.query (null, null, out tw, out th);
                    if (tw <= max_width) {
                        break;
                    }
                }
            }

            int dest_y = above_baseline ? y - th : y;
            renderer.copy (texture, null, {x, dest_y, tw, th});
        }

        private void render_eq_bars (SDL.Video.Renderer renderer) {
            uint ticks = SDL.Timer.get_ticks ();
            int bar_count = 4;
            int bar_w = 4;
            int bar_gap = 3;
            int max_h = (int)(this.rect.h * 0.4);
            int base_x = this.rect.x + (int) this.rect.w - 20 - (bar_count * (bar_w + bar_gap));
            int base_y = this.rect.y + ((int) this.rect.h / 2) + (max_h / 2);

            renderer.set_draw_color (46, 194, 126, 255);
            for (int i = 0; i < bar_count; i++) {
                double phase = (double)(ticks + i * 150) / 300.0;
                double norm = (GLib.Math.sin (phase) + 1.0) / 2.0;
                int bar_h = 4 + (int)(norm * (max_h - 4));
                var bar = SDL.Video.Rect () {
                    x = base_x + i * (bar_w + bar_gap),
                    y = base_y - bar_h,
                    w = bar_w,
                    h = bar_h
                };
                renderer.fill_rect (bar);
            }
        }
    }
}
