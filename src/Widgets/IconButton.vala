/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2016 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl.Widgets {
    public class IconButton : GLib.Object {
        public SDL.Video.Rect rect;
        public SDL.Video.Texture texture;
        public SDL.Video.Texture? texture_disabled = null;
        public bool disabled = false;
        public bool focused = false;

        public IconButton (
            SDL.Video.Renderer renderer,
            string image_path,
            int x, int y,
            int width = 0, int height = 0,
            string? disabled_image_path = null
        ) {
            this.texture = SDLImage.load_texture (renderer, image_path);
            if (this.texture == null) {
                error (
                    "Image could not be loaded: %s. Error: %s",
                    image_path,
                    SDL.get_error ()
                );
            }

            if (disabled_image_path != null) {
                this.texture_disabled = SDLImage.load_texture (renderer, disabled_image_path);
                if (this.texture_disabled == null) {
                    warning ("Disabled image could not be loaded: %s", disabled_image_path);
                }
            }

            int original_width, original_height;
            this.texture.query (null, null, out original_width, out original_height);

            int final_width = (width > 0) ? width : original_width;
            int final_height = (height > 0) ? height : original_height;

            this.rect = { x, y, final_width, final_height };
        }

        public void render (SDL.Video.Renderer renderer) {
            if (disabled && texture_disabled != null) {
                renderer.copy (this.texture_disabled, null, this.rect);
            } else {
                renderer.copy (this.texture, null, this.rect);
            }

            if (focused) {
                renderer.set_draw_color (53, 132, 228, 255);
                var focus_rect = this.rect;
                renderer.draw_rect (focus_rect);
                focus_rect.x -= 1; focus_rect.y -= 1; focus_rect.w += 2; focus_rect.h += 2;
                renderer.draw_rect (focus_rect);
            }
        }

        public bool is_clicked (int x, int y) {
            if (disabled) {
                return false;
            }
            return (x > this.rect.x && x < this.rect.x + this.rect.w &&
                    y > this.rect.y && y < this.rect.y + this.rect.h);
        }

        public void set_texture (SDL.Video.Renderer renderer, string image_path) {
            this.texture = SDLImage.load_texture (renderer, image_path);
        }
    }
}
