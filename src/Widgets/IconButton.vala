/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2016 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl.Frontend {
    public class IconButton {
        public SDL.Video.Rect rect { get; private set; }
        public SDL.Video.Texture texture;

        public IconButton (
            SDL.Video.Renderer renderer,
            string image_path,
            int x, int y,
            int width = 0, int height = 0
        ) {
            this.texture = SDLImage.load_texture (renderer, image_path);
            if (this.texture == null) {
                error (
                    "Image could not be loaded: %s. Error: %s",
                    image_path,
                    SDL.get_error ()
                );
            }

            int original_width, original_height;
            this.texture.query (null, null, out original_width, out original_height);

            int final_width = (width > 0) ? width : original_width;
            int final_height = (height > 0) ? height : original_height;

            this.rect = { x, y, final_width, final_height };
        }

        public void render (SDL.Video.Renderer renderer) {
            renderer.copy (this.texture, null, this.rect);
        }

        public bool is_clicked (int x, int y) {
            return (x > this.rect.x && x < this.rect.x + this.rect.w &&
                    y > this.rect.y && y < this.rect.y + this.rect.h);
        }
    }
}
