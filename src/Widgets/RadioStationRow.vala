/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Widgets {
    public class RadioStationRow : GLib.Object {
        public Vinyl.Radio.RadioStation station { get; private set; }
        private SDL.Video.Texture? flag_texture;
        private static SDL.Video.Texture? shared_connecting_texture = null;
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

            if (shared_connecting_texture == null) {
                var conn_surface = SDLImage.load (Constants.CONNECTING_ICON_PATH);
                if (conn_surface != null) {
                    shared_connecting_texture = SDL.Video.Texture.create_from_surface (renderer, conn_surface);
                }
            }
        }

        public void render (SDL.Video.Renderer renderer, SDLTTF.Font font, SDLTTF.Font small_font) {
            if (focused) {
                renderer.set_draw_color (75, 45, 32, 255);
            } else if (is_active) {
                renderer.set_draw_color (50, 35, 15, 255);
            } else {
                renderer.set_draw_color (20, 20, 25, 255);
            }
            renderer.fill_rect (this.rect);

            var flag_h = (int)(this.rect.h * 0.6);
            var flag_w = flag_h;
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
                render_spinner (renderer);
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
            if (surface == null) return;
            var texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            if (texture == null) return;
            int tw, th;
            texture.query (null, null, out tw, out th);

            if (tw > max_width) {
                string truncated = text;
                while (truncated.length > 1) {
                    truncated = truncated.substring (0, truncated.length - 1);
                    display_text = truncated + "\xe2\x80\xa6";
                    surface = font.render (display_text, color);
                    if (surface == null) break;
                    texture = SDL.Video.Texture.create_from_surface (renderer, surface);
                    if (texture == null) break;
                    texture.query (null, null, out tw, out th);
                    if (tw <= max_width) {
                        break;
                    }
                }
            }

            int dest_y = above_baseline ? y - th : y;
            renderer.copy (texture, null, {x, dest_y, tw, th});
        }

        private void render_spinner (SDL.Video.Renderer renderer) {
            if (shared_connecting_texture == null) return;

            int tex_w, tex_h;
            shared_connecting_texture.query (null, null, out tex_w, out tex_h);

            int dest_h = 28;
            int dest_w = (int)(dest_h * ((double) tex_w / tex_h));
            int dest_x = this.rect.x + (int) this.rect.w - 20 - dest_w;
            int dest_y = this.rect.y + (int) this.rect.h / 2 - dest_h / 2;
            var dest = SDL.Video.Rect () { x = dest_x, y = dest_y, w = dest_w, h = dest_h };

            double angle = (SDL.Timer.get_ticks () * 0.18) % 360.0;
            renderer.copyex (shared_connecting_texture, null, dest, angle, null,
                SDL.Video.RendererFlip.NONE);
        }
    }
}
