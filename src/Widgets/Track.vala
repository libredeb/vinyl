/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Widgets {
    public class Track : GLib.Object {
        public Vinyl.Library.Track track { get; private set; }
        private SDL.Video.Texture? album_art_texture;
        private static SDL.Video.Texture? favorites_on_texture = null;
        private static SDL.Video.Texture? default_cover_texture = null;
        public SDL.Video.Rect rect;
        public bool focused = false;
        private bool texture_loaded = false;

        private SDL.Video.Texture? cached_title_texture = null;
        private SDL.Video.Texture? cached_artist_texture = null;
        private int cached_title_w = 0;
        private int cached_title_h = 0;
        private int cached_artist_w = 0;
        private int cached_artist_h = 0;
        private int cached_max_text_w = -1;

        public Track (SDL.Video.Renderer renderer, Vinyl.Library.Track track, int x, int y, int w, int h) {
            this.track = track;
            this.rect = { x, y, w, h };
        }

        private void ensure_textures (SDL.Video.Renderer renderer) {
            if (texture_loaded) return;
            texture_loaded = true;

            if (track.album_art_path != null) {
                var surface = SDLImage.load (track.album_art_path);
                if (surface != null) {
                    this.album_art_texture = SDL.Video.Texture.create_from_surface (renderer, surface);
                }
            }

            if (default_cover_texture == null) {
                var def_surface = SDLImage.load (Constants.DEFAULT_COVER_ICON_PATH);
                if (def_surface != null) {
                    default_cover_texture = SDL.Video.Texture.create_from_surface (renderer, def_surface);
                }
            }

            if (favorites_on_texture == null) {
                favorites_on_texture = SDLImage.load_texture (renderer, Constants.FAVORITES_ON_ICON_PATH);
            }
        }

        private void ensure_text_textures (SDL.Video.Renderer renderer, SDLTTF.Font font, SDLTTF.Font small_font, int max_w) {
            if (cached_title_texture != null && cached_max_text_w == max_w) return;
            cached_max_text_w = max_w;

            cached_title_texture = build_text_texture (renderer, font, this.track.title, {255, 255, 255, 255}, max_w, out cached_title_w, out cached_title_h);
            cached_artist_texture = build_text_texture (renderer, small_font, this.track.artist, {200, 200, 200, 255}, max_w, out cached_artist_w, out cached_artist_h);
        }

        private static SDL.Video.Texture? build_text_texture (
            SDL.Video.Renderer renderer,
            SDLTTF.Font font,
            string text,
            SDL.Video.Color color,
            int max_width,
            out int out_w,
            out int out_h
        ) {
            out_w = 0;
            out_h = 0;
            if (text.length == 0) return null;

            string display_text = text;
            var surface = font.render (display_text, color);
            if (surface == null) return null;

            var texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            if (texture == null) return null;

            int tw, th;
            texture.query (null, null, out tw, out th);

            if (tw > max_width && text.length > 1) {
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

            out_w = tw;
            out_h = th;
            return texture;
        }

        public void render (SDL.Video.Renderer renderer, SDLTTF.Font font, SDLTTF.Font small_font) {
            ensure_textures (renderer);

            if (focused) {
                renderer.set_draw_color (75, 45, 32, 255);
            } else {
                renderer.set_draw_color (20, 20, 25, 255);
            }
            renderer.fill_rect (this.rect);

            var art_size = (int)(this.rect.h * 0.8);
            var art_dest_rect = SDL.Video.Rect () {
                x = this.rect.x + 20,
                y = (int)(this.rect.y + (this.rect.h / 2) - (art_size / 2)),
                w = art_size,
                h = art_size
            };
            unowned SDL.Video.Texture? art = album_art_texture ?? default_cover_texture;
            if (art != null) {
                renderer.copy (art, null, art_dest_rect);
            }

            int fav_area = this.track.favorite ? 45 + 10 : 0;
            int text_x = (int)(art_dest_rect.x + art_dest_rect.w + 20);
            int max_text_w = this.rect.x + (int) this.rect.w - text_x - 20 - fav_area;

            ensure_text_textures (renderer, font, small_font, max_text_w);

            if (cached_title_texture != null) {
                int dest_y = (int)(this.rect.y + (this.rect.h / 2)) - cached_title_h;
                renderer.copy (cached_title_texture, null, {text_x, dest_y, cached_title_w, cached_title_h});
            }

            if (cached_artist_texture != null) {
                int dest_y = (int)(this.rect.y + (this.rect.h / 2));
                renderer.copy (cached_artist_texture, null, {text_x, dest_y, cached_artist_w, cached_artist_h});
            }

            if (this.track.favorite && favorites_on_texture != null) {
                int fav_w = 45;
                int fav_h = 34;
                int fav_x = this.rect.x + (int) this.rect.w - fav_w - 15;
                int fav_y = (int)(this.rect.y + (this.rect.h - fav_h) / 2);
                renderer.copy (favorites_on_texture, null, {fav_x, fav_y, fav_w, fav_h});
            }
        }
    }
}
