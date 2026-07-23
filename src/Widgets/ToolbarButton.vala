/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2024 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl.Widgets {
    public class ToolbarButton : GLib.Object {
        private SDL.Video.Rect rect;
        private static SDL.Video.Texture? shared_bg_texture = null;
        private static SDL.Video.Texture? shared_bg_press_texture = null;
        private SDL.Video.Texture icon_texture;
        public bool focused = false;

        public ToolbarButton (
            SDL.Video.Renderer renderer,
            string bg_path,
            string bg_press_path,
            string icon_path,
            int x, int y,
            int w, int h
        ) throws IOError {
            this.rect = { x, y, w, h };

            if (shared_bg_texture == null) {
                var bg_surface = SDLImage.load (bg_path);
                if (bg_surface == null) {
                    throw new IOError.FAILED (SDL.get_error ());
                }
                shared_bg_texture = SDL.Video.Texture.create_from_surface (renderer, bg_surface);
                if (shared_bg_texture == null) {
                    throw new IOError.FAILED (SDL.get_error ());
                }
            }

            if (shared_bg_press_texture == null) {
                var bg_press_surface = SDLImage.load (bg_press_path);
                if (bg_press_surface == null) {
                    throw new IOError.FAILED (SDL.get_error ());
                }
                shared_bg_press_texture = SDL.Video.Texture.create_from_surface (renderer, bg_press_surface);
                if (shared_bg_press_texture == null) {
                    throw new IOError.FAILED (SDL.get_error ());
                }
            }

            // Load icon texture (unique per button)
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
            if (focused) {
                renderer.copy (shared_bg_press_texture, null, this.rect);
            } else {
                renderer.copy (shared_bg_texture, null, this.rect);
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

        public void set_x (int x) {
            this.rect.x = x;
        }

        public bool is_clicked (int x, int y) {
            return (x > this.rect.x && x < this.rect.x + this.rect.w &&
                    y > this.rect.y && y < this.rect.y + this.rect.h);
        }
    }
}
