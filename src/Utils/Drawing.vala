namespace Vinyl.Utils {
    public class Drawing {
        private static void draw_filled_circle (SDL.Video.Renderer renderer, int x, int y, int radius) {
            for (int dy = -radius; dy <= radius; dy++) {
                int dx = (int) GLib.Math.round (GLib.Math.sqrt (radius * radius - dy * dy));
                renderer.draw_line (x - dx, y + dy, x + dx, y + dy);
            }
        }

        public static void draw_rounded_rect (SDL.Video.Renderer renderer, SDL.Video.Rect rect) {
            int radius = (int) rect.h / 2;

            if (rect.w < rect.h) {
                draw_filled_circle (renderer, (int) rect.x + (int) rect.w / 2, (int) rect.y + radius, (int) rect.w / 2);
            } else {
                var fill_r = SDL.Video.Rect () {
                    x = (int) rect.x + radius,
                    y = rect.y,
                    w = (int) rect.w - (2 * radius),
                    h = rect.h
                };
                renderer.fill_rect (fill_r);
                draw_filled_circle (renderer, (int) rect.x + radius, (int) rect.y + radius, radius);
                draw_filled_circle (renderer, (int) rect.x + (int) rect.w - radius, (int) rect.y + radius, radius);
            }
        }

        public static void draw_rounded_rect_r (SDL.Video.Renderer renderer, SDL.Video.Rect rect, int radius) {
            if (radius <= 0) {
                renderer.fill_rect (rect);
                return;
            }
            int r = radius;
            if (r > (int) rect.h / 2) r = (int) rect.h / 2;
            if (r > (int) rect.w / 2) r = (int) rect.w / 2;

            var center = SDL.Video.Rect () {
                x = rect.x, y = (int) rect.y + r,
                w = rect.w, h = (int) rect.h - 2 * r
            };
            renderer.fill_rect (center);

            var top = SDL.Video.Rect () {
                x = (int) rect.x + r, y = rect.y,
                w = (int) rect.w - 2 * r, h = r
            };
            renderer.fill_rect (top);

            var bottom = SDL.Video.Rect () {
                x = (int) rect.x + r, y = (int) rect.y + (int) rect.h - r,
                w = (int) rect.w - 2 * r, h = r
            };
            renderer.fill_rect (bottom);

            draw_filled_circle (renderer, (int) rect.x + r, (int) rect.y + r, r);
            draw_filled_circle (renderer, (int) rect.x + (int) rect.w - 1 - r, (int) rect.y + r, r);
            draw_filled_circle (renderer, (int) rect.x + r, (int) rect.y + (int) rect.h - 1 - r, r);
            draw_filled_circle (renderer, (int) rect.x + (int) rect.w - 1 - r, (int) rect.y + (int) rect.h - 1 - r, r);
        }
    }
}
