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

        private SDLTTF.Font? font;
        private SDLTTF.Font? font_bold;
        private SDLTTF.Font? font_small;

        private Vinyl.Utils.Screen current_screen = Vinyl.Utils.Screen.MAIN;
        private float screen_offset_x = 0;

        private Vinyl.Frontend.ToolbarButton? exit_button;
        private Vinyl.Frontend.ToolbarButton? back_button;

        private Gee.ArrayList<Vinyl.Frontend.MenuButton> main_menu_buttons;
        private Gee.ArrayList<Object> focusable_widgets;
        private int focused_widget_index = 0;
        private SDL.Input.GameController? controller;
        private uint last_joy_move = 0; // For joystick move delay
        private bool is_track_list_focused = false;

        private Vinyl.Widgets.TrackList? track_list;

        public int run (string[] args) {
            if (!this.init ()) {
                return 1;
            }

            if (!this.load_media ()) {
                return 1;
            }

            Gee.ArrayList<Vinyl.Library.Track> tracks = null;
            var loop = new MainLoop ();

            var music_scanner = new Vinyl.Library.MusicScanner ();
            music_scanner.scan_files.begin ((obj, res) => {
                tracks = music_scanner.scan_files.end (res);
                loop.quit ();
            });

            loop.run ();

            if (tracks != null) {
                track_list = new Vinyl.Widgets.TrackList (
                    renderer,
                    tracks,
                    0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90
                );
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
            if (SDL.init (SDL.InitFlag.VIDEO | SDL.InitFlag.GAMECONTROLLER) < 0) {
                warning ("SDL could not be initialized. Error: %s", SDL.get_error ());
                return false;
            }

            if (SDLImage.init (SDLImage.InitFlags.PNG) == 0) {
                warning ("SDL2_image could not be initialized");
                return false;
            }

            if (SDLTTF.init () == -1) {
                warning ("SDL2_ttf could not be initialized");
                return false;
            }

            // Load controller mappings
            var controller_db_path = Constants.VINYL_DATADIR + "/gamecontrollerdb.txt";
            if (FileUtils.test (controller_db_path, FileTest.EXISTS)) {
                SDL.Input.GameController.load_mapping_file (controller_db_path);
            }

            int num_controllers = SDL.Input.GameController.count ();
            if (
                (num_controllers < 1) ||
                (!SDL.Input.GameController.is_game_controller (0))
            ) {
                warning (num_controllers < 1
                    ? "No game controller detected"
                    : "Game controller is not compatible"
                );
            } else {
                controller = new SDL.Input.GameController (0);
                if (controller == null) {
                    warning ("Unable to open game controller: %s", SDL.get_error ());
                    return false;
                }
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
                font = new SDLTTF.Font (Constants.FONT_PATH, 24);
                font_bold = new SDLTTF.Font (Constants.FONT_BOLD_PATH, 38);
                font_small = new SDLTTF.Font (Constants.FONT_PATH, 18);

                exit_button = new Vinyl.Frontend.ToolbarButton (
                    renderer,
                    Constants.TOOLBAR_BUTTON_BG_PATH,
                    Constants.EXIT_TB_ICON_PATH,
                    20, 20, 80, 50 // Compact size
                );
                back_button = new Vinyl.Frontend.ToolbarButton (
                    renderer,
                    Constants.TOOLBAR_BUTTON_BG_PATH,
                    Constants.BACK_TB_ICON_PATH,
                    20, 20, 80, 50 // Compact size
                );

                main_menu_buttons = new Gee.ArrayList<Vinyl.Frontend.MenuButton> ();
                main_menu_buttons.add (new Vinyl.Frontend.MenuButton (
                    renderer, Constants.LIBRARY_ICON_PATH, "Mi Música",
                    0, 120, SCREEN_WIDTH, 120
                ));
                main_menu_buttons.add (new Vinyl.Frontend.MenuButton (
                    renderer, Constants.RADIO_ICON_PATH, "Radio",
                    0, 240, SCREEN_WIDTH, 120
                ));
                main_menu_buttons.add (new Vinyl.Frontend.MenuButton (
                    renderer, Constants.SEARCH_ICON_PATH, "Buscar",
                    0, 360, SCREEN_WIDTH, 120
                ));

                // Set focus on the first button by default
                focusable_widgets = new Gee.ArrayList<Object> ();
                focusable_widgets.add (exit_button);
                focusable_widgets.add_all (main_menu_buttons);
                focused_widget_index = 1;

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
                        if (exit_button.is_clicked (mouse_x, mouse_y)) {
                            quit = true;
                        }

                        for (var i = 0; i < main_menu_buttons.size; i++) {
                            var button = main_menu_buttons.get (i);
                            if (button.is_clicked (mouse_x, mouse_y)) {
                                focused_widget_index = focusable_widgets.index_of (button);
                                stdout.printf ("Button '%s' clicked!\n", button.text);

                                // Example of screen transition
                                if (button.text == "Mi Música") {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY;
                                }
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_MAIN;
                        }
                    }
                } else if (e.type == SDL.EventType.CONTROLLERBUTTONDOWN) {
                    if (current_screen == Vinyl.Utils.Screen.MAIN) {
                        uint current_time = SDL.Timer.get_ticks ();
                        switch (e.cbutton.button) {
                            case SDL.Input.GameController.Button.DPAD_UP:
                                if (current_time > last_joy_move + 200) {
                                    focused_widget_index--;
                                    if (focused_widget_index < 0) {
                                        focused_widget_index = focusable_widgets.size - 1;
                                    }
                                    last_joy_move = current_time;
                                }
                                break;
                            case SDL.Input.GameController.Button.DPAD_DOWN:
                                if (current_time > last_joy_move + 200) {
                                    focused_widget_index++;
                                    if (focused_widget_index >= focusable_widgets.size) {
                                        focused_widget_index = 0;
                                    }
                                    last_joy_move = current_time;
                                }
                                break;
                            case SDL.Input.GameController.Button.B:
                                var widget = focusable_widgets.get (focused_widget_index);
                                if (widget is Vinyl.Frontend.MenuButton) {
                                    var button = (Vinyl.Frontend.MenuButton) widget;
                                    stdout.printf ("Button '%s' activated!\n", button.text);
                                    if (button.text == "Mi Música") {
                                        current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY;
                                    }
                                } else if (widget is Vinyl.Frontend.ToolbarButton) {
                                    var button = (Vinyl.Frontend.ToolbarButton) widget;
                                    if (button == exit_button) {
                                        quit = true;
                                    }
                                }
                                break;
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                        switch (e.cbutton.button) {
                            case SDL.Input.GameController.Button.A:
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_MAIN;
                                break;
                            case SDL.Input.GameController.Button.B:
                                if (back_button.focused) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_MAIN;
                                }
                                break;
                        }
                    }
                } else if (e.type == SDL.EventType.CONTROLLERAXISMOTION) {
                    uint current_time = SDL.Timer.get_ticks ();
                    if (current_screen == Vinyl.Utils.Screen.MAIN) {
                        // Vertical axis motion
                        if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTY) {
                            if (e.caxis.value < -8000) { // Up
                                if (current_time > last_joy_move + 200) {
                                    focused_widget_index--;
                                    if (focused_widget_index < 0) {
                                        focused_widget_index = focusable_widgets.size - 1;
                                    }
                                    last_joy_move = current_time;
                                }
                            } else if (e.caxis.value > 8000) { // Down
                                if (current_time > last_joy_move + 200) {
                                    focused_widget_index++;
                                    if (focused_widget_index >= focusable_widgets.size) {
                                        focused_widget_index = 0;
                                    }
                                    last_joy_move = current_time;
                                }
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                        if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTY) {
                            if (e.caxis.value < -8000) { // Up
                                if (current_time > last_joy_move + 200) {
                                    if (is_track_list_focused) {
                                        if (track_list.focused_index == 0) {
                                            is_track_list_focused = false;
                                        } else {
                                            track_list.scroll_up ();
                                        }
                                    }
                                    last_joy_move = current_time;
                                }
                            } else if (e.caxis.value > 8000) { // Down
                                if (current_time > last_joy_move + 200) {
                                    if (is_track_list_focused) {
                                        track_list.scroll_down ();
                                    } else {
                                        is_track_list_focused = true;
                                    }
                                    last_joy_move = current_time;
                                }
                            }
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
            update_focus ();
        }

        private void render () {
            renderer.set_draw_color (0, 0, 0, 255);
            renderer.clear ();

            render_main_screen ((int)screen_offset_x);
            render_library_screen ((int)screen_offset_x + SCREEN_WIDTH);

            render_header ();

            renderer.set_viewport (null);

            renderer.present ();
        }

        private void render_main_screen (int x_offset) {
            renderer.set_viewport ({x_offset, 0, SCREEN_WIDTH, SCREEN_HEIGHT});

            renderer.set_draw_color (20, 20, 25, 255);
            renderer.fill_rect (null);

            foreach (var button in main_menu_buttons) {
                button.render (renderer, font_bold);
            }
        }

        private void render_library_screen (int x_offset) {
            var viewport = SDL.Video.Rect () { x = x_offset, y = 0, w = SCREEN_WIDTH, h = SCREEN_HEIGHT };
            renderer.set_viewport (viewport);

            renderer.set_draw_color (40, 40, 50, 255);
            renderer.fill_rect (null);

            if (track_list != null) {
                track_list.render (renderer, font, font_small);
            }
        }

        private void render_header () {
            // Draw header background
            renderer.set_viewport ({0, 0, SCREEN_WIDTH, 90});
            renderer.set_draw_color (10, 10, 12, 255);
            renderer.fill_rect (null);

            // Draw title and buttons based on screen
            if (current_screen == Vinyl.Utils.Screen.MAIN || current_screen == Vinyl.Utils.Screen.TRANSITION_TO_MAIN) {
                render_text ("vinyl", (SCREEN_WIDTH / 2) - 50, 25, true);
                exit_button.render (renderer);
            } else if (
                current_screen == Vinyl.Utils.Screen.LIBRARY ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY
            ) {
                render_text ("Mi Música", (SCREEN_WIDTH / 2) - 80, 25, true);
                back_button.render (renderer);
            }
        }

        private void update_focus () {
            if (current_screen == Vinyl.Utils.Screen.MAIN) {
                for (var i = 0; i < focusable_widgets.size; i++) {
                    var widget = focusable_widgets.get (i);
                    bool is_focused = (i == focused_widget_index);

                    if (widget is Vinyl.Frontend.MenuButton) {
                        ((Vinyl.Frontend.MenuButton) widget).focused = is_focused;
                    } else if (widget is Vinyl.Frontend.ToolbarButton) {
                        ((Vinyl.Frontend.ToolbarButton) widget).focused = is_focused;
                    }
                }
                if (back_button != null) {
                    back_button.focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                // Unfocus all main screen widgets
                foreach (var widget in focusable_widgets) {
                    if (widget is Vinyl.Frontend.MenuButton) {
                        ((Vinyl.Frontend.MenuButton) widget).focused = false;
                    } else if (widget is Vinyl.Frontend.ToolbarButton) {
                        ((Vinyl.Frontend.ToolbarButton) widget).focused = false;
                    }
                }

                if (back_button != null) {
                    back_button.focused = !is_track_list_focused;
                }
                if (track_list != null) {
                    track_list.is_focused = is_track_list_focused;
                }
            }
        }

        private void render_text (string text, int x, int y, bool is_bold = false) {
            SDL.Video.Surface text_surface;
            if (is_bold) {
                text_surface = font_bold.render (text, {255, 255, 255, 255});
            } else {
                text_surface = font.render (text, {255, 255, 255, 255});
            }
            var text_texture = SDL.Video.Texture.create_from_surface (renderer, text_surface);
            int text_width = 0;
            int text_height = 0;
            text_texture.query (null, null, out text_width, out text_height);
            renderer.copy (text_texture, null, {x, y, text_width, text_height});
        }

        private void cleanup () {
            // Release references to all widgets and fonts.
            // This allows the GC to call the free_functions for the textures and fonts
            // before we call the SDL_Quit functions.
            exit_button = null;
            back_button = null;
            main_menu_buttons.clear ();
            main_menu_buttons = null;
            focusable_widgets.clear ();
            focusable_widgets = null;
            font = null;
            font_bold = null;
            font_small = null;

            // Close controller
            if (controller != null) {
                controller = null;
            }

            // Release references to renderer and window
            renderer = null;
            window = null;

            // Now that all SDL objects should be freed by the GC, quit the subsystems
            SDLTTF.quit ();
            SDLImage.quit ();
            SDL.quit ();
        }
    }
}
