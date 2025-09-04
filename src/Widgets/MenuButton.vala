/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */

namespace Vinyl.Frontend {
    public class MenuButton : GLib.Object {
        private SDL.Video.Texture icon_texture;
        private SDL.Video.Texture arrow_texture;
        private SDL.Video.Rect button_rect;
        public string text;
        public bool focused = false;

        public MenuButton (SDL.Video.Renderer renderer, string icon_path, string text, int x, int y, int w, int h) throws IOError {
            this.text = text;
            this.button_rect = { x, y, w, h };

            var surface = SDLImage.load (icon_path);
            if (surface == null) {
                throw new IOError.FAILED (SDL.get_error ());
            }
            this.icon_texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            if (icon_texture == null) {
                throw new IOError.FAILED (SDL.get_error ());
            }

            var arrow_surface = SDLImage.load (Constants.ARROW_RIGHT_ICON_PATH);
            if (arrow_surface == null) {
                throw new IOError.FAILED (SDL.get_error ());
            }
            this.arrow_texture = SDL.Video.Texture.create_from_surface (renderer, arrow_surface);
            if (arrow_texture == null) {
                throw new IOError.FAILED (SDL.get_error ());
            }
        }

        public void render (SDL.Video.Renderer renderer, SDLTTF.Font font) {
            if (focused) {
                renderer.set_draw_color (40, 40, 50, 255); // Highlight color
            } else {
                renderer.set_draw_color (20, 20, 25, 255); // Default background color
            }
            renderer.fill_rect (this.button_rect);

            // Render icon
            var icon_h = (int)(this.button_rect.h * 0.6);
            var icon_w = icon_h;
            var icon_dest_rect = SDL.Video.Rect () {
                x = this.button_rect.x + 40,
                y = (int)(this.button_rect.y + (this.button_rect.h / 2) - (icon_h / 2)),
                w = icon_w,
                h = icon_h
            };
            renderer.copy (this.icon_texture, null, icon_dest_rect);

            // Render text
            var text_surface = font.render (this.text, {255, 255, 255, 255});
            var text_texture = SDL.Video.Texture.create_from_surface (renderer, text_surface);
            int text_width = 0;
            int text_height = 0;
            text_texture.query (null, null, out text_width, out text_height);
            var text_dest_rect = SDL.Video.Rect () {
                x = (int)(icon_dest_rect.x + icon_dest_rect.w + 40),
                y = (int)(this.button_rect.y + (this.button_rect.h / 2) - (text_height / 2)),
                w = text_width,
                h = text_height
            };
            renderer.copy (text_texture, null, text_dest_rect);

            // Render arrow
            var arrow_dest_rect = SDL.Video.Rect () {
                x = (int)(this.button_rect.x + this.button_rect.w - 50 - 40), // 50 is width, 40 is padding
                y = (int)(this.button_rect.y + (this.button_rect.h / 2) - (30 / 2)), // 30 is height
                w = 30,
                h = 30
            };
            renderer.copy (this.arrow_texture, null, arrow_dest_rect);
        }

        public bool is_clicked (int x, int y) {
            return (x > this.button_rect.x &&
                    x < this.button_rect.x + this.button_rect.w &&
                    y > this.button_rect.y &&
                    y < this.button_rect.y + this.button_rect.h);
        }
    }
}
