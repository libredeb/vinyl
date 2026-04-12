/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Widgets {
    public class Track : GLib.Object {
        public Vinyl.Library.Track track { get; private set; }
        private SDL.Video.Texture? album_art_texture;
        public SDL.Video.Rect rect;
        public bool focused = false;

        public Track (SDL.Video.Renderer renderer, Vinyl.Library.Track track, int x, int y, int w, int h) {
            this.track = track;
            this.rect = { x, y, w, h };
            SDL.Video.Surface? surface = null;

            if (track.album_art_path != null) {
                surface = SDLImage.load (track.album_art_path);
                if (surface == null) {
                    warning ("Could not load album art: %s", SDL.get_error ());
                }
            }

            if (surface == null) { // If album art failed or didn't exist, load default
                surface = SDLImage.load (Constants.DEFAULT_COVER_ICON_PATH);
                if (surface == null) {
                    warning ("Could not load default album art icon: %s", SDL.get_error ());
                }
            }

            if (surface != null) {
                this.album_art_texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            }
        }

        public void render (SDL.Video.Renderer renderer, SDLTTF.Font font, SDLTTF.Font small_font) {
            if (focused) {
                renderer.set_draw_color (53, 132, 228, 255); // Highlight color #3584e4
            } else {
                renderer.set_draw_color (20, 20, 25, 255); // Default background color
            }
            renderer.fill_rect (this.rect);

            // Render album art
            var art_size = (int)(this.rect.h * 0.8);
            var art_dest_rect = SDL.Video.Rect () {
                x = this.rect.x + 20,
                y = (int)(this.rect.y + (this.rect.h / 2) - (art_size / 2)),
                w = art_size,
                h = art_size
            };
            if (album_art_texture != null) {
                renderer.copy (this.album_art_texture, null, art_dest_rect);
            }

            int text_x = (int)(art_dest_rect.x + art_dest_rect.w + 20);
            int max_text_w = this.rect.x + (int) this.rect.w - text_x - 20;

            render_ellipsized (renderer, font, this.track.title, {255, 255, 255, 255},
                text_x, (int)(this.rect.y + (this.rect.h / 2)), max_text_w, true);

            render_ellipsized (renderer, small_font, this.track.artist, {200, 200, 200, 255},
                text_x, (int)(this.rect.y + (this.rect.h / 2)), max_text_w, false);
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
    }
}
