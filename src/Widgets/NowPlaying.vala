/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2016 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl.Widgets {
    public class NowPlaying : Object {
        private unowned SDL.Video.Renderer renderer;
        private Vinyl.Library.Track track;
        private SDL.Video.Texture? cover_texture;
        public PlayerControls player_controls;
        public bool progress_bar_focused = false;
        private SDL.Video.Rect progress_bar_rect;

        private float progress = 0.5f; // 0.0 to 1.0
        private SDL.Video.Texture? progressbar_slider_texture;

        private int x;
        private int y;
        private int width;
        private int height;

        private string current_time_str = "0:00";
        private string remaining_time_str = "0:00";

        public NowPlaying (
            SDL.Video.Renderer renderer,
            Vinyl.Library.Track track,
            int x, int y, int width, int height,
            int current_track_index, int total_tracks
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
            this.player_controls = new PlayerControls (renderer, x, y + height - 100, width, 100);
            this.player_controls.update_state (current_track_index, total_tracks);

            this.progressbar_slider_texture = SDLImage.load_texture (renderer, Constants.PROGRESSBAR_SLIDER_PATH);
            if (this.progressbar_slider_texture == null) {
                warning ("Error loading progressbar slider image: %s", SDL.get_error ());
            }
        }

        public void update_track (Vinyl.Library.Track new_track) {
            this.track = new_track;
            if (track.album_art_path != null) {
                var surface = SDLImage.load (track.album_art_path);
                if (surface != null) {
                    this.cover_texture = SDL.Video.Texture.create_from_surface (renderer, surface);
                } else {
                    warning ("Error loading cover image: %s", SDL.get_error ());
                    this.cover_texture = null;
                }
            } else {
                this.cover_texture = null;
            }
        }

        public void update_progress (int64 position, int64 duration) {
            if (duration > 0) {
                this.progress = (float)position / (float)duration;
            } else {
                this.progress = 0;
            }

            // Update time strings
            var pos_seconds = position / Gst.SECOND;
            var dur_seconds = duration / Gst.SECOND;
            var rem_seconds = dur_seconds - pos_seconds;

            this.current_time_str = (pos_seconds / 60).to_string() + ":" + "%02d".printf((int)(pos_seconds % 60));
            this.remaining_time_str = "-" + (rem_seconds / 60).to_string() + ":" + "%02d".printf((int)(rem_seconds % 60));
        }

        public void seek (float amount, Vinyl.Player player) {
            this.progress += amount;
            if (this.progress < 0) {
                this.progress = 0;
            }
            if (this.progress > 1) {
                this.progress = 1;
            }
            var duration = player.get_duration ();
            if (duration > 0) {
                var new_position = (int64) (duration * this.progress);
                player.seek (new_position);
            }
        }

        public void set_progress (float new_progress, Vinyl.Player player) {
            if (new_progress < 0) {
                new_progress = 0;
            }
            if (new_progress > 1) {
                new_progress = 1;
            }
            this.progress = new_progress;
            var duration = player.get_duration ();
            if (duration > 0) {
                var new_position = (int64) (duration * this.progress);
                player.seek (new_position);
            }
        }

        public bool is_progress_bar_clicked (int mouse_x, int mouse_y, out float new_progress) {
            // Make the clickable area a bit taller for easier clicking
            var clickable_rect = SDL.Video.Rect () {
                x = progress_bar_rect.x,
                y = progress_bar_rect.y - 10,
                w = progress_bar_rect.w,
                h = progress_bar_rect.h + 20
            };

            if (
                mouse_x >= clickable_rect.x && mouse_x <= clickable_rect.x + clickable_rect.w &&
                mouse_y >= clickable_rect.y && mouse_y <= clickable_rect.y + clickable_rect.h
            ) {

                if (clickable_rect.w > 0) {
                    new_progress = (float) (mouse_x - clickable_rect.x) / (float) clickable_rect.w;
                    if (new_progress < 0) {
                        new_progress = 0;
                    }
                    if (new_progress > 1) {
                        new_progress = 1;
                    }
                    return true;
                }
            }

            new_progress = 0;
            return false;
        }

        public void render (
            SDL.Video.Renderer renderer,
            SDLTTF.Font? font,
            SDLTTF.Font? font_bold,
            SDLTTF.Font? font_small
        ) {
            // Render cover
            int art_size = 300;
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
            int info_y = art_y + art_size + 20;
            render_text_centered (track.title, info_y, true, font_bold);
            info_y += 40;
            render_text_centered (track.artist, info_y, false, font);
            info_y += 30;
            render_text_centered (track.album, info_y, false, font_small);

            // Render progress bar
            int progress_y = info_y + 30;
            int progress_width = this.width - 140;
            int progress_x = this.x + 70;

            progress_bar_rect = SDL.Video.Rect () { x = progress_x, y = progress_y, w = progress_width, h = 10 };
            if (progress_bar_focused) {
                renderer.set_draw_color (120, 120, 130, 255);
            } else {
                renderer.set_draw_color (80, 80, 90, 255);
            }
            renderer.fill_rect (progress_bar_rect);

            // TODO: Calculate progress based on actual playback time
            int progress_width_pixels = (int)(progress_width * progress);
            var progress_bar_fg = SDL.Video.Rect () { x = progress_x, y = progress_y, w = progress_width_pixels, h = 10 };
            renderer.set_draw_color (0, 150, 255, 255);
            renderer.fill_rect (progress_bar_fg);

            // Render slider
            if (progressbar_slider_texture != null) {
                int slider_width = 0;
                int slider_height = 0;
                progressbar_slider_texture.query (null, null, out slider_width, out slider_height);
                int slider_x = progress_x + progress_width_pixels - (slider_width / 2);
                int slider_y = progress_y + 5 - (slider_height / 2);
                renderer.copy (progressbar_slider_texture, null, {slider_x, slider_y, slider_width, slider_height});
            }

            // Render timestamps
            render_text (this.x + 70, progress_y + 20, false, font_small, current_time_str);
            render_text_right_aligned (this.x + 70 + progress_width, progress_y + 20, false, font_small, remaining_time_str);

            player_controls.render ();
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
