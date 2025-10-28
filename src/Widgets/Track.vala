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

            // Render title
            var title_surface = font.render (this.track.title, {255, 255, 255, 255});
            var title_texture = SDL.Video.Texture.create_from_surface (renderer, title_surface);
            int title_width, title_height;
            title_texture.query (null, null, out title_width, out title_height);
            var title_dest_rect = SDL.Video.Rect () {
                x = (int)(art_dest_rect.x + art_dest_rect.w + 20),
                y = (int)(this.rect.y + (this.rect.h / 2) - title_height),
                w = title_width,
                h = title_height
            };
            renderer.copy (title_texture, null, title_dest_rect);

            // Render artist
            var artist_surface = small_font.render (this.track.artist, {200, 200, 200, 255});
            var artist_texture = SDL.Video.Texture.create_from_surface (renderer, artist_surface);
            int artist_width, artist_height;
            artist_texture.query (null, null, out artist_width, out artist_height);
            var artist_dest_rect = SDL.Video.Rect () {
                x = (int)(art_dest_rect.x + art_dest_rect.w + 20),
                y = (int)(this.rect.y + (this.rect.h / 2)),
                w = artist_width,
                h = artist_height
            };
            renderer.copy (artist_texture, null, artist_dest_rect);
        }
    }
}
