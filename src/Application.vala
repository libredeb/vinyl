/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2016 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl {
    class Application {
        const int SCREEN_WIDTH = 720;
        const int SCREEN_HEIGHT = 720;
        const int TRANSITION_SPEED = 1500; // Pixels per second for animation

        private SDL.Video.Window window;
        private SDL.Video.Renderer renderer;
        private bool quit = false;

        private Vinyl.Utils.Screen current_screen = Vinyl.Utils.Screen.MAIN;
        private float screen_offset_x = 0;

        private Vinyl.Frontend.IconButton? library_button;
        private Vinyl.Frontend.IconButton? exit_button;
        private Vinyl.Frontend.IconButton? back_button;

        public int run (string[] args) {
            if (!this.init ()) {
                return 1;
            }

            if (!this.load_media ()) {
                return 1;
            }

            while (!this.quit) {
                this.handle_events ();
                this.update ();
                this.render ();
                SDL.Timer.delay (16); // Limited to ~60 FPS
            }

            this.cleanup ();
            return 0;
        }

        private bool init () {
            if (SDL.init (SDL.InitFlag.VIDEO) < 0) {
                warning ("SDL could not be initialized. Error: %s", SDL.get_error ());
                return false;
            }

            if (SDLImage.init (SDLImage.InitFlags.PNG) == 0) {
                warning ("SDL2_image could not be initialized");
                return false;
            }

            this.window = new SDL.Video.Window (
                Config.PROJECT_NAME, 0, 0,
                SCREEN_WIDTH, SCREEN_HEIGHT,
                SDL.Video.WindowFlags.SHOWN
            );
            if (window == null) {
                warning ("The window could not be created. Error: %s", SDL.get_error ());
                return false;
            }

            renderer = SDL.Video.Renderer.create (
                window, 0,
                SDL.Video.RendererFlags.ACCELERATED | SDL.Video.RendererFlags.PRESENTVSYNC
            );
            if (renderer == null) {
                warning ("The renderer could not be created. Error: %s", SDL.get_error ());
                return false;
            }

            return true;
        }

        private bool load_media () {
            try {
                library_button = new Vinyl.Frontend.IconButton (
                    renderer,
                    Constants.LIB_ICON_PATH,
                    (SCREEN_WIDTH / 2) - 105, 300, 100, 100
                );
                exit_button = new Vinyl.Frontend.IconButton (
                    renderer,
                    Constants.EXIT_ICON_PATH,
                    (SCREEN_WIDTH / 2) + 5, 300, 100, 100
                );
                back_button = new Vinyl.Frontend.IconButton (
                    renderer,
                    Constants.BACK_ICON_PATH,
                    50, 50, 50, 50
                );
            } catch (Error e) {
                warning ("Error loading gfx: %s", e.message);
                return false;
            }
            return true;
        }

        private void handle_events () {
            SDL.Event e;
            while (SDL.Event.poll (out e) != 0) {
                if (e.type == SDL.EventType.QUIT) {
                    quit = true;
                } else if (e.type == SDL.EventType.MOUSEBUTTONDOWN) {
                    int mouse_x = 0;
                    int mouse_y = 0;
                    SDL.Input.Cursor.get_state (ref mouse_x, ref mouse_y);

                    if (current_screen == Vinyl.Utils.Screen.MAIN) {
                        if (library_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY;
                        }
                        if (exit_button.is_clicked (mouse_x, mouse_y)) {
                            quit = true;
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_MAIN;
                        }
                    }
                }
            }
        }

        private void update () {
            if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY) {
                screen_offset_x -= TRANSITION_SPEED / 60.0f; // Move to the left
                if (screen_offset_x <= -SCREEN_WIDTH) {
                    screen_offset_x = -SCREEN_WIDTH;
                    current_screen = Vinyl.Utils.Screen.LIBRARY;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_MAIN) {
                screen_offset_x += TRANSITION_SPEED / 60.0f; // Move to the right
                if (screen_offset_x >= 0) {
                    screen_offset_x = 0;
                    current_screen = Vinyl.Utils.Screen.MAIN;
                }
            }
        }

        private void render () {
            renderer.set_draw_color (0, 0, 0, 255);
            renderer.clear ();

            render_main_screen ((int)screen_offset_x);
            render_library_screen ((int)screen_offset_x + SCREEN_WIDTH);

            renderer.set_viewport (null);

            renderer.present ();
        }

        private void render_main_screen (int x_offset) {
            renderer.set_viewport ({x_offset, 0, SCREEN_WIDTH, SCREEN_HEIGHT});

            renderer.set_draw_color (20, 20, 25, 255);
            renderer.fill_rect (null);

            library_button.render (renderer);
            exit_button.render (renderer);
        }

        private void render_library_screen (int x_offset) {
            renderer.set_viewport ({x_offset, 0, SCREEN_WIDTH, SCREEN_HEIGHT});

            renderer.set_draw_color (40, 40, 50, 255);
            renderer.fill_rect (null);

            back_button.render (renderer);
        }

        private void cleanup () {
            this.window.destroy ();
            SDLImage.quit ();
            SDL.quit ();
        }
    }
}
