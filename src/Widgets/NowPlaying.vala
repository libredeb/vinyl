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
        private SDL.Video.Rect progress_bar_rect;

        private float progress = 0.5f; // 0.0 to 1.0
        private SDL.Video.Texture? progressbar_slider_texture;

        private int x;
        private int y;
        private int width;
        private int height;

        private string current_time_str = "0:00";
        private string remaining_time_str = "0:00";

        private const int MARQUEE_PADDING = 40;
        private const int MARQUEE_GAP = 80;
        private const double MARQUEE_SPEED = 50.0;

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
            this.player_controls.update_seek_state (0, 0);

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
            player_controls.update_seek_state (position, duration);
            update_time_display (position, duration);
        }

        /** After a relative seek, {@link progress} is already correct; do not use pipeline position yet. */
        public void sync_ui_after_relative_seek (Vinyl.Player player) {
            int64 duration = player.get_duration ();
            if (duration <= 0) {
                return;
            }
            int64 position = (int64) (duration * (double) this.progress);
            if (position > duration) {
                position = duration;
            }
            player_controls.update_seek_state (position, duration);
            update_time_display (position, duration);
        }

        private void update_time_display (int64 position, int64 duration) {
            var pos_seconds = position / Gst.SECOND;
            var dur_seconds = duration / Gst.SECOND;
            int64 rem_seconds = dur_seconds - pos_seconds;
            if (rem_seconds < 0) {
                rem_seconds = 0;
            }

            this.current_time_str = (pos_seconds / 60).to_string () + ":" +
                "%02d".printf ((int) (pos_seconds % 60));
            this.remaining_time_str = "-" + (rem_seconds / 60).to_string () + ":" +
                "%02d".printf ((int) (rem_seconds % 60));
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

            progress_bar_rect = SDL.Video.Rect () { x = progress_x, y = progress_y, w = progress_width, h = 9 };
            renderer.set_draw_color (80, 80, 90, 255);
            Vinyl.Utils.Drawing.draw_rounded_rect (renderer, progress_bar_rect);

            // Filled width follows self.progress (kept in sync via update_progress).
            int progress_width_pixels = (int) (progress_width * progress);
            var progress_bar_fg = SDL.Video.Rect () {
                x = progress_x, y = progress_y, w = progress_width_pixels, h = 9
            };
            renderer.set_draw_color (255, 157, 17, 255);
            if (progress_width_pixels > 0) {
                Vinyl.Utils.Drawing.draw_rounded_rect (renderer, progress_bar_fg);
            }

            // Render slider
            if (progressbar_slider_texture != null) {
                int slider_width = 0;
                int slider_height = 0;
                progressbar_slider_texture.query (null, null, out slider_width, out slider_height);
                int slider_x = progress_x + progress_width_pixels - (slider_width / 2);
                int slider_y = progress_y + 4 - (slider_height / 2);
                renderer.copy (progressbar_slider_texture, null, {slider_x, slider_y, slider_width, slider_height});
            }

            // Render timestamps
            render_text (this.x + 70, progress_y + 20, false, font_small, current_time_str);
            render_text_right_aligned (
                this.x + 70 + progress_width, progress_y + 20, false, font_small, remaining_time_str);

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

            int max_width = this.width - MARQUEE_PADDING * 2;
            if (text_width <= max_width) {
                int tx = this.x + (this.width - text_width) / 2;
                renderer.copy (texture, null, {tx, y, text_width, text_height});
            } else {
                render_marquee (texture, text_width, text_height, y, max_width);
            }
        }

        private void render_marquee (
            SDL.Video.Texture texture,
            int text_width, int text_height,
            int y, int max_width
        ) {
            int area_x = this.x + MARQUEE_PADDING;
            int cycle_width = text_width + MARQUEE_GAP;
            uint ticks = SDL.Timer.get_ticks ();
            int offset = (int) ((ticks * MARQUEE_SPEED / 1000.0) % cycle_width);

            render_marquee_copy (texture, text_width, text_height, y, area_x, max_width, -offset);
            render_marquee_copy (texture, text_width, text_height, y, area_x, max_width, -offset + cycle_width);
        }

        private void render_marquee_copy (
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
