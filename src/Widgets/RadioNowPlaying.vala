/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl.Widgets {
    public class RadioNowPlaying : Object {
        private unowned SDL.Video.Renderer renderer;
        private Vinyl.Radio.RadioStation station;
        private SDL.Video.Texture? cover_texture;
        public PlayerControls player_controls;

        private int x;
        private int y;
        private int width;
        private int height;

        private int current_station_index;
        private int total_stations;

        private unowned Vinyl.Radio.RadioPlayer? radio_player;
        private ulong album_art_signal_id = 0;

        public RadioNowPlaying (
            SDL.Video.Renderer renderer,
            Vinyl.Radio.RadioStation station,
            int x, int y, int width, int height,
            int current_station_index, int total_stations,
            Vinyl.Radio.RadioPlayer player
        ) {
            this.renderer = renderer;
            this.station = station;
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;
            this.current_station_index = current_station_index;
            this.total_stations = total_stations;

            load_default_cover ();
            connect_player (player);

            this.player_controls = new PlayerControls (renderer, x, y + height - 100, width, 100);
            this.player_controls.update_state (current_station_index, total_stations);
            this.player_controls.rewind_button.disabled = true;
            this.player_controls.forward_button.disabled = true;
        }

        public void update_station (Vinyl.Radio.RadioStation new_station, int index, int total) {
            this.station = new_station;
            this.current_station_index = index;
            this.total_stations = total;
            this.player_controls.update_state (index, total);
            this.player_controls.rewind_button.disabled = true;
            this.player_controls.forward_button.disabled = true;
            load_default_cover ();
        }

        public void update_cover (string? art_path) {
            if (art_path != null) {
                var surface = SDLImage.load (art_path);
                if (surface != null) {
                    this.cover_texture = SDL.Video.Texture.create_from_surface (renderer, surface);
                    return;
                }
            }
            load_default_cover ();
        }

        /**
         * Connects to the RadioPlayer's album_art_changed signal so the
         * cover texture is updated automatically when GStreamer TAG
         * messages provide embedded images from the stream metadata.
         */
        private void connect_player (Vinyl.Radio.RadioPlayer player) {
            this.radio_player = player;
            this.album_art_signal_id = player.album_art_changed.connect (
                on_metadata_album_art);
        }

        private void on_metadata_album_art (string? art_path) {
            update_cover (art_path);
        }

        public void disconnect_player () {
            if (radio_player != null && album_art_signal_id > 0) {
                radio_player.disconnect (album_art_signal_id);
                album_art_signal_id = 0;
            }
            radio_player = null;
        }

        private void load_default_cover () {
            var surface = SDLImage.load (Constants.RADIO_NOART_REMOTE_ICON_PATH);
            if (surface != null) {
                this.cover_texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            } else {
                this.cover_texture = null;
            }
        }

        public void render (
            SDL.Video.Renderer renderer,
            SDLTTF.Font? font,
            SDLTTF.Font? font_bold,
            SDLTTF.Font? font_small
        ) {
            int art_size = 250;
            int art_x = this.x + (this.width - art_size) / 2;
            int art_y = this.y + 80;
            if (cover_texture != null) {
                renderer.copy (cover_texture, null, {art_x, art_y, art_size, art_size});
            } else {
                renderer.set_draw_color (50, 50, 60, 255);
                renderer.fill_rect ({art_x, art_y, art_size, art_size});
            }

            int info_y = art_y + art_size + 30;
            render_text_centered (station.station_name, info_y, true, font_bold);
            info_y += 45;
            render_text_centered (station.country_name, info_y, false, font);

            player_controls.render ();
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

            int max_width = this.width - 80;
            if (text_width > max_width) {
                text_width = max_width;
            }
            int tx = this.x + (this.width - text_width) / 2;
            renderer.copy (texture, null, {tx, y, text_width, text_height});
        }
    }
}
