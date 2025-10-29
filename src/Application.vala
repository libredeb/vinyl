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

        private Vinyl.Widgets.ToolbarButton? exit_button;
        private Vinyl.Widgets.ToolbarButton? back_button;
        private Vinyl.Widgets.ToolbarButton? playlist_button;

        private Gee.ArrayList<Vinyl.Widgets.MenuButton> main_menu_buttons;
        private Gee.ArrayList<Object> focusable_widgets;
        private int focused_widget_index = 0;
        private SDL.Input.GameController? controller;
        private uint last_joy_move = 0; // For joystick move delay
        private bool is_track_list_focused = false;
        private Vinyl.Player? player = null;
        private uint last_progress_update = 0;

        private Vinyl.Widgets.TrackList? track_list;
        private Vinyl.Widgets.NowPlaying? now_playing_widget;
        private Gee.ArrayList<Object>? now_playing_focusable_widgets;
        private int now_playing_focused_widget_index = 0;

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
                if (player != null) {
                    player.handle_messages ();
                }
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

                exit_button = new Vinyl.Widgets.ToolbarButton (
                    renderer,
                    Constants.TOOLBAR_BUTTON_BG_PATH,
                    Constants.TOOLBAR_BUTTON_BG_PRESS_PATH,
                    Constants.EXIT_TB_ICON_PATH,
                    20, 20, 80, 50 // Compact size
                );
                back_button = new Vinyl.Widgets.ToolbarButton (
                    renderer,
                    Constants.TOOLBAR_BUTTON_BG_PATH,
                    Constants.TOOLBAR_BUTTON_BG_PRESS_PATH,
                    Constants.BACK_TB_ICON_PATH,
                    20, 20, 80, 50 // Compact size
                );

                playlist_button = new Vinyl.Widgets.ToolbarButton (
                    renderer,
                    Constants.TOOLBAR_BUTTON_BG_PATH,
                    Constants.TOOLBAR_BUTTON_BG_PRESS_PATH,
                    Constants.PLAYLIST_TB_ICON_PATH,
                    SCREEN_WIDTH - 100, 20, 80, 50
                );

                main_menu_buttons = new Gee.ArrayList<Vinyl.Widgets.MenuButton> ();
                main_menu_buttons.add (new Vinyl.Widgets.MenuButton (
                    renderer, Constants.LIBRARY_ICON_PATH, "music", "My Music",
                    0, 120, SCREEN_WIDTH, 120
                ));
                main_menu_buttons.add (new Vinyl.Widgets.MenuButton (
                    renderer, Constants.RADIO_ICON_PATH, "radio", "Radio",
                    0, 240, SCREEN_WIDTH, 120
                ));
                main_menu_buttons.add (new Vinyl.Widgets.MenuButton (
                    renderer, Constants.SEARCH_ICON_PATH, "search", "Search",
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
                                if (button.id == "music") {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY;
                                }
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_MAIN;
                        }
                        Vinyl.Library.Track? track = null;
                        if (track_list != null && track_list.is_clicked (mouse_x, mouse_y, out track)) {
                            if (track != null) {
                                now_playing_widget = new Vinyl.Widgets.NowPlaying (
                                    renderer,
                                    track,
                                    0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90,
                                    track_list.focused_index, track_list.get_total_items ()
                                );
                                now_playing_focusable_widgets = new Gee.ArrayList<Object> ();
                                now_playing_focusable_widgets.add (back_button);
                                now_playing_focusable_widgets.add (playlist_button);
                                now_playing_focusable_widgets.add (now_playing_widget);
                                now_playing_focusable_widgets.add (now_playing_widget.player_controls.prev_button);
                                now_playing_focusable_widgets.add (now_playing_widget.player_controls.play_pause_button);
                                now_playing_focusable_widgets.add (now_playing_widget.player_controls.next_button);
                                now_playing_focusable_widgets.add (now_playing_widget.player_controls.volume_down_button);
                                now_playing_focusable_widgets.add (now_playing_widget.player_controls.volume_up_button);
                                now_playing_focused_widget_index = 4; // Focus play button
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                                if (player != null) {
                                    player.stop ();
                                }
                                player = new Vinyl.Player (track_list.get_tracks (), track_list.focused_index);
                                player.play_pause ();
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY;
                        } else if (playlist_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN;
                        } else if (now_playing_widget != null) {
                            float new_progress;
                            if (now_playing_widget.is_progress_bar_clicked (mouse_x, mouse_y, out new_progress)) {
                                if (player != null) {
                                    now_playing_widget.set_progress (new_progress, player);
                                }
                            }
                            var controls = now_playing_widget.player_controls;
                            if (controls.play_pause_button.is_clicked (mouse_x, mouse_y)) {
                                if (player != null) {
                                    player.play_pause ();
                                }
                            } else if (controls.next_button.is_clicked (mouse_x, mouse_y)) {
                                if (player != null) {
                                    player.play_next ();
                                    now_playing_widget.update_track (player.get_current_track ());
                                    if (track_list != null) {
                                        track_list.focused_index = player.get_current_track_index ();
                                        now_playing_widget.player_controls.update_state (player.get_current_track_index (), track_list.get_total_items ());
                                    }
                                }
                            } else if (controls.prev_button.is_clicked (mouse_x, mouse_y)) {
                                if (player != null) {
                                    player.play_previous ();
                                    now_playing_widget.update_track (player.get_current_track ());
                                    if (track_list != null) {
                                        track_list.focused_index = player.get_current_track_index ();
                                        now_playing_widget.player_controls.update_state (player.get_current_track_index (), track_list.get_total_items ());
                                    }
                                }
                            }
                            // Note: Add logic for prev, next, volume buttons if needed
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
                            case SDL.Input.GameController.Button.A:
                                var widget = focusable_widgets.get (focused_widget_index);
                                if (widget is Vinyl.Widgets.MenuButton) {
                                    var button = (Vinyl.Widgets.MenuButton) widget;
                                    stdout.printf ("Button '%s' activated!\n", button.text);
                                    if (button.id == "music") {
                                        current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY;
                                    }
                                } else if (widget is Vinyl.Widgets.ToolbarButton) {
                                    var button = (Vinyl.Widgets.ToolbarButton) widget;
                                    if (button == exit_button) {
                                        quit = true;
                                    }
                                }
                                break;
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                        switch (e.cbutton.button) {
                            case SDL.Input.GameController.Button.A:
                                if (is_track_list_focused && track_list != null) {
                                    var track = track_list.get_focused_track ();
                                    if (track != null) {
                                        now_playing_widget = new Vinyl.Widgets.NowPlaying (
                                            renderer,
                                            track,
                                            0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90,
                                            track_list.focused_index, track_list.get_total_items ()
                                        );
                                        now_playing_focusable_widgets = new Gee.ArrayList<Object> ();
                                        now_playing_focusable_widgets.add (back_button);
                                        now_playing_focusable_widgets.add (playlist_button);
                                        now_playing_focusable_widgets.add (now_playing_widget);
                                        now_playing_focusable_widgets.add (now_playing_widget.player_controls.prev_button);
                                        now_playing_focusable_widgets.add (now_playing_widget.player_controls.play_pause_button);
                                        now_playing_focusable_widgets.add (now_playing_widget.player_controls.next_button);
                                        now_playing_focusable_widgets.add (now_playing_widget.player_controls.volume_down_button);
                                        now_playing_focusable_widgets.add (now_playing_widget.player_controls.volume_up_button);
                                        now_playing_focused_widget_index = 4; // Focus play button
                                        current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                                        if (player != null) {
                                            player.stop ();
                                        }
                                        player = new Vinyl.Player (track_list.get_tracks (), track_list.focused_index);
                                        player.play_pause ();
                                    }
                                } else {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_MAIN;
                                }
                                break;
                            case SDL.Input.GameController.Button.B:
                                if (back_button.focused) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_MAIN;
                                }
                                break;
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                        switch (e.cbutton.button) {
                            case SDL.Input.GameController.Button.B:
                                current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY;
                                break;
                            case SDL.Input.GameController.Button.A:
                                if (now_playing_focusable_widgets != null) {
                                    var widget = now_playing_focusable_widgets.get (now_playing_focused_widget_index);
                                    if (widget == back_button) {
                                        current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY;
                                    } else if (widget == playlist_button) {
                                        current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN;
                                    } else if (widget == now_playing_widget.player_controls.play_pause_button) {
                                        if (player != null) {
                                            player.play_pause ();
                                        }
                                    } else if (widget == now_playing_widget.player_controls.next_button) {
                                        if (player != null) {
                                            player.play_next ();
                                            now_playing_widget.update_track (player.get_current_track ());
                                            if (track_list != null) {
                                                track_list.focused_index = player.get_current_track_index ();
                                                now_playing_widget.player_controls.update_state (player.get_current_track_index (), track_list.get_total_items ());
                                            }
                                        }
                                    } else if (widget == now_playing_widget.player_controls.prev_button) {
                                        if (player != null) {
                                            player.play_previous ();
                                            now_playing_widget.update_track (player.get_current_track ());
                                            if (track_list != null) {
                                                track_list.focused_index = player.get_current_track_index ();
                                                now_playing_widget.player_controls.update_state (player.get_current_track_index (), track_list.get_total_items ());
                                            }
                                        }
                                    }
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
                    } else if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                        if (now_playing_focusable_widgets != null) {
                            if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTX) {
                                if (current_time > last_joy_move + 200) {
                                    last_joy_move = current_time;
                                    if (now_playing_focused_widget_index <= 1) { // Top bar
                                        now_playing_focused_widget_index = (now_playing_focused_widget_index == 0) ? 1 : 0;
                                    } else if (now_playing_focused_widget_index == 2) { // Progress bar
                                        if (e.caxis.value < -8000) {
                                            now_playing_widget.seek (-0.02f, player);
                                        } else if (e.caxis.value > 8000) {
                                            now_playing_widget.seek (0.02f, player);
                                        }
                                    } else { // Player controls
                                        if (e.caxis.value < -8000) { // Left
                                            now_playing_focused_widget_index--;
                                            if (now_playing_focused_widget_index < 3) {
                                                now_playing_focused_widget_index = now_playing_focusable_widgets.size - 1;
                                            }
                                        } else if (e.caxis.value > 8000) { // Right
                                            now_playing_focused_widget_index++;
                                            if (now_playing_focused_widget_index >= now_playing_focusable_widgets.size) {
                                                now_playing_focused_widget_index = 3;
                                            }
                                        }
                                    }
                                }
                            } else if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTY) {
                                if (current_time > last_joy_move + 200) {
                                    last_joy_move = current_time;
                                    if (e.caxis.value < -8000) { // Up
                                        if (now_playing_focused_widget_index >= 3) { // From Player to Progress
                                            now_playing_focused_widget_index = 2;
                                        } else if (now_playing_focused_widget_index == 2) { // From Progress to Top
                                            now_playing_focused_widget_index = 0;
                                        }
                                    } else if (e.caxis.value > 8000) { // Down
                                        if (now_playing_focused_widget_index <= 1) { // From Top to Progress
                                            now_playing_focused_widget_index = 2;
                                        } else if (now_playing_focused_widget_index == 2) { // From Progress to Player
                                            now_playing_focused_widget_index = 4;
                                        }
                                    }
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
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING) {
                screen_offset_x -= TRANSITION_SPEED / 60.0f; // Move to the left
                if (screen_offset_x <= -SCREEN_WIDTH * 2) {
                    screen_offset_x = -SCREEN_WIDTH * 2;
                    current_screen = Vinyl.Utils.Screen.NOW_PLAYING;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY) {
                screen_offset_x += TRANSITION_SPEED / 60.0f; // Move to the right
                if (screen_offset_x >= -SCREEN_WIDTH) {
                    screen_offset_x = -SCREEN_WIDTH;
                    current_screen = Vinyl.Utils.Screen.LIBRARY;
                    now_playing_widget = null;
                    now_playing_focusable_widgets = null;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN) {
                screen_offset_x += TRANSITION_SPEED / 60.0f; // Move to the right
                if (screen_offset_x >= 0) {
                    screen_offset_x = 0;
                    current_screen = Vinyl.Utils.Screen.MAIN;
                    now_playing_widget = null;
                    now_playing_focusable_widgets = null;
                }
            }
            update_focus ();

            if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                if (player != null && now_playing_widget != null) {
                    // Update play/pause icon
                    if (player.is_playing()) {
                        now_playing_widget.player_controls.play_pause_button.set_texture (renderer, Constants.VINYL_DATADIR + "/gfx/toolbar_pause.png");
                    } else {
                        now_playing_widget.player_controls.play_pause_button.set_texture (renderer, Constants.VINYL_DATADIR + "/gfx/toolbar_play.png");
                    }

                    // Update progress bar every second
                    var now = SDL.Timer.get_ticks ();
                    if (now - last_progress_update > 1000) {
                        var position = player.get_position ();
                        var duration = player.get_duration ();
                        now_playing_widget.update_progress (position, duration);
                        last_progress_update = now;
                    }
                }
            }
        }

        private void render () {
            renderer.set_draw_color (0, 0, 0, 255);
            renderer.clear ();

            render_main_screen ((int)screen_offset_x);
            render_library_screen ((int)screen_offset_x + SCREEN_WIDTH);
            render_now_playing_screen ((int)screen_offset_x + SCREEN_WIDTH * 2);

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

        private void render_now_playing_screen (int x_offset) {
            var viewport = SDL.Video.Rect () { x = x_offset, y = 0, w = SCREEN_WIDTH, h = SCREEN_HEIGHT };
            renderer.set_viewport (viewport);

            renderer.set_draw_color (30, 30, 35, 255);
            renderer.fill_rect (null);

            if (now_playing_widget != null) {
                now_playing_widget.render (renderer, font, font_bold, font_small);
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
                render_text ("My Music", (SCREEN_WIDTH / 2) - 80, 25, true);
                back_button.render (renderer);
            } else if (
                current_screen == Vinyl.Utils.Screen.NOW_PLAYING ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY
            ) {
                if (track_list != null) {
                    var text = "Now Playing • %d of %d".printf (track_list.focused_index + 1, track_list.get_total_items ());
                    render_text (text, (SCREEN_WIDTH / 2) - 150, 25, true);
                }
                back_button.render (renderer);
                playlist_button.render (renderer);
            }
        }

        private void update_focus () {
            if (current_screen == Vinyl.Utils.Screen.MAIN) {
                for (var i = 0; i < focusable_widgets.size; i++) {
                    var widget = focusable_widgets.get (i);
                    bool is_focused = (i == focused_widget_index);

                    if (widget is Vinyl.Widgets.MenuButton) {
                        ((Vinyl.Widgets.MenuButton) widget).focused = is_focused;
                    } else if (widget is Vinyl.Widgets.ToolbarButton) {
                        ((Vinyl.Widgets.ToolbarButton) widget).focused = is_focused;
                    }
                }
                if (back_button != null) {
                    back_button.focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                // Unfocus all main screen widgets
                foreach (var widget in focusable_widgets) {
                    if (widget is Vinyl.Widgets.MenuButton) {
                        ((Vinyl.Widgets.MenuButton) widget).focused = false;
                    } else if (widget is Vinyl.Widgets.ToolbarButton) {
                        ((Vinyl.Widgets.ToolbarButton) widget).focused = false;
                    }
                }

                if (back_button != null) {
                    back_button.focused = !is_track_list_focused;
                }
                if (track_list != null) {
                    track_list.is_focused = is_track_list_focused;
                }
            } else if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                if (now_playing_focusable_widgets != null) {
                    for (var i = 0; i < now_playing_focusable_widgets.size; i++) {
                        var widget = now_playing_focusable_widgets.get(i);
                        bool is_focused = (i == now_playing_focused_widget_index);
                        if (widget is Vinyl.Widgets.IconButton) {
                            ((Vinyl.Widgets.IconButton) widget).focused = is_focused;
                        } else if (widget is Vinyl.Widgets.ToolbarButton) {
                            ((Vinyl.Widgets.ToolbarButton) widget).focused = is_focused;
                        } else if (widget is Vinyl.Widgets.NowPlaying) {
                            ((Vinyl.Widgets.NowPlaying) widget).progress_bar_focused = is_focused;
                        }
                    }
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
            if (player != null) {
                player.stop ();
            }

            // Release references to all widgets and fonts.
            // This allows the GC to call the free_functions for the textures and fonts
            // before we call the SDL_Quit functions.
            exit_button = null;
            back_button = null;
            main_menu_buttons.clear ();
            main_menu_buttons = null;
            focusable_widgets.clear ();
            focusable_widgets = null;
            if (now_playing_focusable_widgets != null) {
                now_playing_focusable_widgets.clear ();
                now_playing_focusable_widgets = null;
            }
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
