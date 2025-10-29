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
    }
}
