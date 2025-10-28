/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl.Widgets {
    public class PlayerControls : GLib.Object {
        private unowned SDL.Video.Renderer renderer;
        private int x;
        private int y;
        private int w;
        private int h;
        private SDL.Video.Texture? bg_texture;
        private SDL.Video.Texture? divider_texture;

        public IconButton? prev_button;
        public IconButton? play_pause_button;
        public IconButton? next_button;
        public IconButton? volume_down_button;
        public IconButton? volume_up_button;

        public PlayerControls (SDL.Video.Renderer renderer, int x, int y, int w, int h) {
            this.renderer = renderer;
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;

            this.bg_texture = SDLImage.load_texture (renderer, Constants.TOOLBAR_BG_PATH);
            this.divider_texture = SDLImage.load_texture (renderer, Constants.TOOLBAR_DIVIDER_PATH);

            int icon_y = this.y + (this.h - 50) / 2;

            prev_button = new IconButton (renderer, Constants.PREV_TB_ICON_PATH, this.x + 40, icon_y, 50, 50, Constants.PREV_TB_DIS_ICON_PATH);
            play_pause_button = new IconButton (renderer, Constants.PLAY_TB_ICON_PATH, this.x + 110, icon_y, 50, 50);
            next_button = new IconButton (renderer, Constants.NEXT_TB_ICON_PATH, this.x + 180, icon_y, 50, 50, Constants.NEXT_TB_DIS_ICON_PATH);

            int volume_up_x = this.x + this.w - 40 - 50;
            int volume_down_x = this.x + this.w - 40 - 50 - 200; // 200 for bar + padding
            volume_down_button = new IconButton (renderer, Constants.VOLUME_DOWN_TB_ICON_PATH, volume_down_x, icon_y, 50, 50);
            volume_up_button = new IconButton (renderer, Constants.VOLUME_UP_TB_ICON_PATH, volume_up_x, icon_y, 50, 50);
        }

        public void update_state (int current_track, int total_tracks) {
            prev_button.disabled = (current_track == 0);
            next_button.disabled = (current_track >= total_tracks - 1);
        }

        public void render () {
            if (bg_texture != null) {
                renderer.copy (bg_texture, null, {this.x, this.y, this.w, this.h});
            } else {
                renderer.set_draw_color (15, 15, 20, 255);
                renderer.fill_rect ({ this.x, this.y, this.w, this.h });
            }

            prev_button.render (renderer);
            play_pause_button.render (renderer);
            next_button.render (renderer);
            volume_down_button.render (renderer);
            volume_up_button.render (renderer);

            if (divider_texture != null) {
                int divider_y = this.y + (this.h - 50) / 2;
                renderer.copy (divider_texture, null, {this.x + 99, divider_y, 2, 50});
                renderer.copy (divider_texture, null, {this.x + 169, divider_y, 2, 50});
            }

            // Render volume bar
            int bar_y = this.y + (this.h - 10) / 2;
            int bar_x = (int)volume_down_button.rect.x + (int)volume_down_button.rect.w + 10;
            int bar_width = (int)volume_up_button.rect.x - bar_x - 10;
            renderer.set_draw_color (80, 80, 90, 255);
            renderer.fill_rect ({ bar_x, bar_y, bar_width, 10 });
        }
    }
}
