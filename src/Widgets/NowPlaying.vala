/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2016 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl.Widgets {
    public class NowPlaying : Object {
        private unowned SDL.Video.Renderer renderer;
        private Vinyl.Library.Track track;
        private SDL.Video.Texture? cover_texture;

        private int x;
        private int y;
        private int width;
        private int height;

        public NowPlaying (
            SDL.Video.Renderer renderer,
            Vinyl.Library.Track track,
            int x, int y, int width, int height
        ) {
            this.renderer = renderer;
            this.track = track;
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;

            if (track.album_art_path != null) {
                var surface = SDLImage.load (track.album_art_path);
                if (surface != null) {
                    this.cover_texture = SDL.Video.Texture.create_from_surface (renderer, surface);
                } else {
                    warning ("Error loading cover image: %s", SDL.get_error ());
                    this.cover_texture = null;
                }
            }
        }

        public void render (
            SDL.Video.Renderer renderer,
            SDLTTF.Font? font,
            SDLTTF.Font? font_bold,
            SDLTTF.Font? font_small
        ) {
            // Render cover
            int art_size = 400;
            int art_x = this.x + (this.width - art_size) / 2;
            int art_y = this.y + 40;
            if (cover_texture != null) {
                renderer.copy (cover_texture, null, {art_x, art_y, art_size, art_size});
            } else {
                // Render placeholder
                renderer.set_draw_color (50, 50, 60, 255);
                renderer.fill_rect ({art_x, art_y, art_size, art_size});
            }

            // Render track info
            int info_y = art_y + art_size + 30;
            render_text_centered (track.title, info_y, true, font_bold);
            info_y += 50;
            render_text_centered (track.artist, info_y, false, font);
            info_y += 40;
            render_text_centered (track.album, info_y, false, font_small);

            // Render progress bar
            int progress_y = info_y + 50;
            int progress_width = this.width - 140;
            int progress_x = this.x + 70;

            var progress_bar_bg = SDL.Video.Rect () { x = progress_x, y = progress_y, w = progress_width, h = 10 };
            renderer.set_draw_color (80, 80, 90, 255);
            renderer.fill_rect (progress_bar_bg);

            // TODO: Calculate progress based on actual playback time
            var progress_bar_fg = SDL.Video.Rect () { x = progress_x, y = progress_y, w = progress_width / 2, h = 10 };
            renderer.set_draw_color (0, 150, 255, 255);
            renderer.fill_rect (progress_bar_fg);

            // Render timestamps
            render_text (this.x + 70, progress_y + 20, false, font_small, "1:09");
            render_text_right_aligned (this.x + 70 + progress_width, progress_y + 20, false, font_small, "-2:09");
        }

        private void render_text (int x, int y, bool is_bold, SDLTTF.Font? font, string text) {
            if (font == null) {
                return;
            }
            var surface = font.render (text, {255, 255, 255, 255});
            var texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            int text_width = 0;
            int text_height = 0;
            texture.query (null, null, out text_width, out text_height);
            renderer.copy (texture, null, {x, y, text_width, text_height});
        }

        private void render_text_centered (string text, int y, bool is_bold, SDLTTF.Font? font) {
            if (font == null) {
                return;
            }
            var surface = font.render (text, {255, 255, 255, 255});
            var texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            int text_width = 0;
            int text_height = 0;
            texture.query (null, null, out text_width, out text_height);
            int x = this.x + (this.width - text_width) / 2;
            renderer.copy (texture, null, {x, y, text_width, text_height});
        }

        private void render_text_right_aligned (int x, int y, bool is_bold, SDLTTF.Font? font, string text) {
            if (font == null) {
                return;
            }
            var surface = font.render (text, {255, 255, 255, 255});
            var texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            int text_width = 0;
            int text_height = 0;
            texture.query (null, null, out text_width, out text_height);
            renderer.copy (texture, null, {x - text_width, y, text_width, text_height});
        }
    }
}
