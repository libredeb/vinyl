/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl.Frontend {
    public class ToolbarButton : GLib.Object {
        private SDL.Video.Rect rect;
        private SDL.Video.Texture bg_texture;
        private SDL.Video.Texture icon_texture;
        public bool focused = false;

        public ToolbarButton (
            SDL.Video.Renderer renderer,
            string bg_path,
            string icon_path,
            int x, int y,
            int w, int h
        ) throws IOError {
            this.rect = { x, y, w, h };

            // Load background texture
            var bg_surface = SDLImage.load (bg_path);
            if (bg_surface == null) {
                throw new IOError.FAILED (SDL.get_error ());
            }
            this.bg_texture = SDL.Video.Texture.create_from_surface (renderer, bg_surface);
            if (this.bg_texture == null) {
                throw new IOError.FAILED (SDL.get_error ());
            }

            // Load icon texture
            var icon_surface = SDLImage.load (icon_path);
            if (icon_surface == null) {
                throw new IOError.FAILED (SDL.get_error ());
            }
            this.icon_texture = SDL.Video.Texture.create_from_surface (renderer, icon_surface);
            if (this.icon_texture == null) {
                throw new IOError.FAILED (SDL.get_error ());
            }
        }

        public void render (SDL.Video.Renderer renderer) {
            // Render background
            renderer.copy (this.bg_texture, null, this.rect);

            if (focused) {
                renderer.set_draw_color (40, 40, 50, 255); // Highlight color
                renderer.fill_rect (this.rect);
            }

            // Render icon centered
            int icon_w, icon_h;
            this.icon_texture.query (null, null, out icon_w, out icon_h);
            var icon_dest_rect = SDL.Video.Rect () {
                x = (int)(this.rect.x + (this.rect.w / 2) - (icon_w / 2)),
                y = (int)(this.rect.y + (this.rect.h / 2) - (icon_h / 2)),
                w = icon_w,
                h = icon_h
            };
            renderer.copy (this.icon_texture, null, icon_dest_rect);
        }

        public bool is_clicked (int x, int y) {
            return (x > this.rect.x && x < this.rect.x + this.rect.w &&
                    y > this.rect.y && y < this.rect.y + this.rect.h);
        }
    }
}
