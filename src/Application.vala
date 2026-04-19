/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2016 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl {
    class Application {
        const int SCREEN_WIDTH = 720;
        const int SCREEN_HEIGHT = 720;
        /** Pixels per second; each frame moves by this value / 60 (~60 FPS). One 720px slide ≈ 0.24s. */
        const int TRANSITION_SPEED = 3000;

        private SDL.Video.Window window;
        private SDL.Video.Renderer renderer;
        private SDL.Video.Texture canvas;
        private bool quit = false;
        private bool windowed = false;

        private int display_offset_x = 0;
        private int display_offset_y = 0;
        private int display_scaled_size = SCREEN_WIDTH;

        private SDLTTF.Font? font;
        private SDLTTF.Font? font_bold;
        private SDLTTF.Font? font_small;

        private Vinyl.Utils.Screen current_screen = Vinyl.Utils.Screen.MAIN;
        private float screen_offset_x = 0;

        private Vinyl.Widgets.ToolbarButton? exit_button;
        private Vinyl.Widgets.ToolbarButton? back_button;
        private Vinyl.Widgets.ToolbarButton? sync_button;
        private Vinyl.Widgets.ToolbarButton? playlist_button;
        private Vinyl.Widgets.ToolbarButton? now_playing_button;

        private Gee.ArrayList<Vinyl.Widgets.MenuButton> main_menu_buttons;
        private Gee.ArrayList<Object> focusable_widgets;
        private int focused_widget_index = 0;
        private SDL.Input.GameController? controller;
        private uint last_joy_move = 0; // For joystick move delay
        private bool axis_y_active = false;
        private bool axis_x_active = false;
        private Vinyl.Utils.InputAction? held_direction = null;
        private uint held_direction_since = 0;
        private bool is_track_list_focused = false;
        /** 0 = back, 1 = sync, 2 = now_playing toolbar (only when is_playing). */
        private int library_header_focus = 0;
        /** Main screen: focus on header toolbar (exit vs now playing) instead of menu body. */
        private bool main_toolbar_focused = false;
        /** 0 = exit, 1 = now_playing (only when is_playing). */
        private int main_toolbar_index = 0;
        private Vinyl.Player? player = null;
        private uint last_progress_update = 0;
        private bool is_playing = false;
        private Vinyl.Library.LibraryDatabase? library_db;
        private Vinyl.Library.MusicScanner? music_scanner;
        private bool is_syncing = false;

        private Vinyl.Widgets.TrackList? track_list;
        private Vinyl.Widgets.NowPlaying? now_playing_widget;
        private Gee.ArrayList<Object>? now_playing_focusable_widgets;
        private int now_playing_focused_widget_index = 0;

        private Vinyl.Widgets.RadioStationList? radio_station_list;
        private Vinyl.Radio.RadioPlayer? radio_player;
        private bool is_radio_list_focused = false;
        /** 0 = back, 1 = now_playing toolbar (only when music is_playing). */
        private int radio_header_focus = 0;

        private Vinyl.Widgets.RadioNowPlaying? radio_now_playing_widget;
        private Gee.ArrayList<Object>? radio_now_playing_focusable_widgets;
        private int radio_now_playing_focused_widget_index = 0;
        private bool is_radio_playing = false;

        private Gee.ArrayList<Vinyl.Widgets.MenuButton> library_menu_buttons;
        private int library_menu_focused_index = 0;
        private bool library_menu_toolbar_focused = false;
        /** 0 = back, 1 = now_playing (only when any_playing). */
        private int library_menu_header_focus = 0;

        private string library_category = "all_songs";
        private bool is_category_browsing = false;
        private Vinyl.Widgets.CategoryList? category_list;
        private bool is_category_list_focused = false;
        /** 0 = back, 1 = now_playing (only when any_playing). */
        private int category_header_focus = 0;

        private string search_text = "";
        private Vinyl.Widgets.OnScreenKeyboard? search_keyboard;
        private Vinyl.Widgets.TrackList? search_track_list;
        private SDL.Video.Texture? clear_all_icon = null;
        /** Search focus zone: 0=header, 1=clear-btn, 2=results, 3=keyboard. */
        private int search_focus_zone = 3;
        private int search_header_focus = 0;
        private bool now_playing_return_to_search = false;

        public int run (string[] args) {
            foreach (var arg in args) {
                if (arg == "-w" || arg == "--windowed") {
                    this.windowed = true;
                }
            }

            if (!this.init ()) {
                return 1;
            }

            if (!this.load_media ()) {
                return 1;
            }

            library_db = new Vinyl.Library.LibraryDatabase ();
            if (!library_db.open ()) {
                warning ("Library database could not be opened; continuing with an empty library.");
            }

            var tracks = library_db.load_tracks_for_ui ();
            track_list = new Vinyl.Widgets.TrackList (
                renderer,
                tracks,
                0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90
            );

            search_track_list = new Vinyl.Widgets.TrackList (
                renderer,
                new Gee.ArrayList<Vinyl.Library.Track> (),
                0, 170, SCREEN_WIDTH, 220
            );
            search_keyboard = new Vinyl.Widgets.OnScreenKeyboard (0, 400, SCREEN_WIDTH, 320);
            clear_all_icon = SDLImage.load_texture (renderer, Constants.CLEAR_ALL_ICON_PATH);

            var stations = Vinyl.Radio.RadioStation.load_stations ();
            radio_station_list = new Vinyl.Widgets.RadioStationList (
                renderer,
                stations,
                0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90
            );
            radio_player = new Vinyl.Radio.RadioPlayer ();
            radio_player.state_changed.connect (on_radio_state_changed);

            music_scanner = new Vinyl.Library.MusicScanner (library_db);
            trigger_sync_library ();

            while (!this.quit) {
                if (player != null) {
                    player.handle_messages ();
                }
                if (radio_player != null) {
                    radio_player.handle_messages ();
                }
                this.handle_events ();
                this.process_held_dpad ();
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

            var window_flags = this.windowed
                ? SDL.Video.WindowFlags.SHOWN
                : SDL.Video.WindowFlags.FULLSCREEN_DESKTOP;
            this.window = new SDL.Video.Window (
                Config.PROJECT_NAME,
                (int) SDL.Video.Window.POS_CENTERED, (int) SDL.Video.Window.POS_CENTERED,
                SCREEN_WIDTH, SCREEN_HEIGHT,
                window_flags
            );
            if (window == null) {
                warning ("The window could not be created. Error: %s", SDL.get_error ());
                return false;
            }

            renderer = SDL.Video.Renderer.create (
                window, -1,
                SDL.Video.RendererFlags.SOFTWARE
            );
            if (renderer == null) {
                warning ("The renderer could not be created. Error: %s", SDL.get_error ());
                return false;
            }

            canvas = SDL.Video.Texture.create (
                renderer,
                SDL.Video.PixelRAWFormat.RGBA8888,
                (int) SDL.Video.TextureAccess.TARGET,
                SCREEN_WIDTH, SCREEN_HEIGHT
            );
            if (canvas == null) {
                warning ("The canvas texture could not be created. Error: %s", SDL.get_error ());
                return false;
            }

            recalculate_display_scaling ();

            return true;
        }

        private void recalculate_display_scaling () {
            int phys_w, phys_h;
            renderer.get_output_size (out phys_w, out phys_h);

            double scale = double.min (
                (double) phys_w / SCREEN_WIDTH,
                (double) phys_h / SCREEN_HEIGHT
            );
            display_scaled_size = (int) (SCREEN_WIDTH * scale);
            display_offset_x = (phys_w - display_scaled_size) / 2;
            display_offset_y = (phys_h - display_scaled_size) / 2;
        }

        private void map_mouse_to_logical (ref int x, ref int y) {
            x = (int) (((double) (x - display_offset_x)) / display_scaled_size * SCREEN_WIDTH);
            y = (int) (((double) (y - display_offset_y)) / display_scaled_size * SCREEN_HEIGHT);
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

                sync_button = new Vinyl.Widgets.ToolbarButton (
                    renderer,
                    Constants.TOOLBAR_BUTTON_BG_PATH,
                    Constants.TOOLBAR_BUTTON_BG_PRESS_PATH,
                    Constants.SYNC_TB_ICON_PATH,
                    SCREEN_WIDTH - 190, 20, 80, 50
                );

                playlist_button = new Vinyl.Widgets.ToolbarButton (
                    renderer,
                    Constants.TOOLBAR_BUTTON_BG_PATH,
                    Constants.TOOLBAR_BUTTON_BG_PRESS_PATH,
                    Constants.PLAYLIST_TB_ICON_PATH,
                    SCREEN_WIDTH - 100, 20, 80, 50
                );

                now_playing_button = new Vinyl.Widgets.ToolbarButton (
                    renderer,
                    Constants.TOOLBAR_BUTTON_BG_PATH,
                    Constants.TOOLBAR_BUTTON_BG_PRESS_PATH,
                    Constants.NOW_PLAYING_TB_ICON_PATH,
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

                library_menu_buttons = new Gee.ArrayList<Vinyl.Widgets.MenuButton> ();
                library_menu_buttons.add (new Vinyl.Widgets.MenuButton (
                    renderer, Constants.ALL_SONGS_ICON_PATH, "all_songs", "All Songs",
                    0, 120, SCREEN_WIDTH, 120
                ));
                library_menu_buttons.add (new Vinyl.Widgets.MenuButton (
                    renderer, Constants.FAVORITES_ICON_PATH, "favorites", "Favorites",
                    0, 240, SCREEN_WIDTH, 120
                ));
                library_menu_buttons.add (new Vinyl.Widgets.MenuButton (
                    renderer, Constants.ARTISTS_ICON_PATH, "artists", "Artists",
                    0, 360, SCREEN_WIDTH, 120
                ));
                library_menu_buttons.add (new Vinyl.Widgets.MenuButton (
                    renderer, Constants.ALBUMS_ICON_PATH, "albums", "Albums",
                    0, 480, SCREEN_WIDTH, 120
                ));

                // Menu entries first (vertical flow), exit last so D-pad down advances logically
                focusable_widgets = new Gee.ArrayList<Object> ();
                focusable_widgets.add_all (main_menu_buttons);
                focusable_widgets.add (exit_button);
                focused_widget_index = 0;

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
                    map_mouse_to_logical (ref mouse_x, ref mouse_y);

                    if (current_screen == Vinyl.Utils.Screen.MAIN) {
                        if (exit_button.is_clicked (mouse_x, mouse_y)) {
                            quit = true;
                        }

                        for (var i = 0; i < main_menu_buttons.size; i++) {
                            var button = main_menu_buttons.get (i);
                            if (button.is_clicked (mouse_x, mouse_y)) {
                                focused_widget_index = focusable_widgets.index_of (button);

                                if (button.id == "music") {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY_MENU;
                                } else if (button.id == "radio") {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO;
                                } else if (button.id == "search") {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_SEARCH;
                                }
                            }
                        }

                        if (now_playing_button.is_clicked (mouse_x, mouse_y)) {
                            if (is_radio_playing && radio_now_playing_widget != null) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
                            } else if (player != null && player.is_playing ()) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY_MENU) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_LIBRARY_MENU_TO_MAIN;
                        }

                        for (var i = 0; i < library_menu_buttons.size; i++) {
                            var lm_button = library_menu_buttons.get (i);
                            if (lm_button.is_clicked (mouse_x, mouse_y)) {
                                library_menu_focused_index = i;
                                activate_library_category (lm_button.id);
                            }
                        }

                        if (now_playing_button.is_clicked (mouse_x, mouse_y)) {
                            if (is_radio_playing && radio_now_playing_widget != null) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
                            } else if (player != null && player.is_playing ()) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.CATEGORY_LIST) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_CATEGORY_LIST_TO_LIBRARY_MENU;
                        }
                        string? clicked_name = null;
                        if (category_list != null &&
                            category_list.is_clicked (mouse_x, mouse_y, out clicked_name)) {
                            if (clicked_name != null) {
                                select_category_item ();
                            }
                        }
                        if (now_playing_button.is_clicked (mouse_x, mouse_y)) {
                            if (is_radio_playing && radio_now_playing_widget != null) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
                            } else if (player != null && player.is_playing ()) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_LIBRARY_TO_LIBRARY_MENU;
                        }
                        Vinyl.Library.Track? track = null;
                        if (track_list != null && track_list.is_clicked (mouse_x, mouse_y, out track)) {
                            if (track != null) {
                                stop_radio ();
                                now_playing_return_to_search = false;
                                now_playing_widget = new Vinyl.Widgets.NowPlaying (
                                    renderer,
                                    track,
                                    0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90,
                                    track_list.focused_index, track_list.get_total_items ()
                                );
                                build_now_playing_focusable_widgets ();
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                                if (player != null) {
                                    player.stop ();
                                }
                                player = new Vinyl.Player (track_list.get_tracks (), track_list.focused_index);
                                player.state_changed.connect (on_player_state_changed);
                                player.play_pause ();
                                now_playing_widget.player_controls.update_volume (player.get_volume ());
                            }
                        }

                        if (sync_button != null && sync_button.is_clicked (mouse_x, mouse_y)) {
                            trigger_sync_library ();
                        }

                        if (now_playing_button.is_clicked (mouse_x, mouse_y) && is_playing) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            if (now_playing_return_to_search) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_SEARCH;
                            } else {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY;
                            }
                        } else if (playlist_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN;
                        } else if (now_playing_widget != null &&
                                   now_playing_widget.favorite_button.is_clicked (mouse_x, mouse_y)) {
                            toggle_current_track_favorite ();
                        } else if (now_playing_widget != null) {
                            var controls = now_playing_widget.player_controls;
                            if (controls.prev_button.is_clicked (mouse_x, mouse_y)) {
                                if (player != null) {
                                    player.play_previous ();
                                    now_playing_widget.update_track (player.get_current_track ());
                                    sync_track_list_focus_from_player ();
                                }
                            } else if (controls.rewind_button.is_clicked (mouse_x, mouse_y)) {
                                if (player != null) {
                                    now_playing_widget.seek (-0.05f, player);
                                    apply_seek_ui_sync ();
                                }
                            } else if (controls.play_pause_button.is_clicked (mouse_x, mouse_y)) {
                                if (player != null) {
                                    player.play_pause ();
                                }
                            } else if (controls.forward_button.is_clicked (mouse_x, mouse_y)) {
                                if (player != null) {
                                    now_playing_widget.seek (0.05f, player);
                                    apply_seek_ui_sync ();
                                }
                            } else if (controls.next_button.is_clicked (mouse_x, mouse_y)) {
                                if (player != null) {
                                    player.play_next ();
                                    now_playing_widget.update_track (player.get_current_track ());
                                    sync_track_list_focus_from_player ();
                                }
                            }
                            // Note: Add logic for prev, next, volume buttons if needed
                            else if (controls.volume_down_button.is_clicked (mouse_x, mouse_y)) {
                                if (player != null) {
                                    var volume = player.get_volume ();
                                    volume -= 0.1;
                                    if (volume < 0.0) volume = 0.0;
                                    player.set_volume (volume);
                                    controls.update_volume (volume);
                                }
                            } else if (controls.volume_up_button.is_clicked (mouse_x, mouse_y)) {
                                if (player != null) {
                                    var volume = player.get_volume ();
                                    volume += 0.1;
                                    if (volume > 1.0) volume = 1.0;
                                    player.set_volume (volume);
                                    controls.update_volume (volume);
                                }
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.RADIO) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_TO_MAIN;
                        }
                        Vinyl.Radio.RadioStation? clicked_station = null;
                        if (radio_station_list != null &&
                            radio_station_list.is_clicked (mouse_x, mouse_y, out clicked_station)) {
                            if (clicked_station != null && radio_player != null) {
                                start_radio (clicked_station);
                            }
                        }
                        if (now_playing_button.is_clicked (mouse_x, mouse_y)) {
                            if (is_radio_playing && radio_now_playing_widget != null) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
                            } else if (is_playing) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.RADIO_NOW_PLAYING) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_RADIO;
                        } else if (playlist_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_MAIN;
                        } else if (radio_now_playing_widget != null) {
                            var controls = radio_now_playing_widget.player_controls;
                            if (controls.prev_button.is_clicked (mouse_x, mouse_y)) {
                                radio_play_previous ();
                            } else if (controls.play_pause_button.is_clicked (mouse_x, mouse_y)) {
                                if (radio_player != null) {
                                    radio_player.play_pause ();
                                }
                            } else if (controls.next_button.is_clicked (mouse_x, mouse_y)) {
                                radio_play_next ();
                            } else if (controls.volume_down_button.is_clicked (mouse_x, mouse_y)) {
                                if (radio_player != null) {
                                    var volume = radio_player.get_volume ();
                                    volume -= 0.1;
                                    if (volume < 0.0) volume = 0.0;
                                    radio_player.set_volume (volume);
                                    controls.update_volume (volume);
                                }
                            } else if (controls.volume_up_button.is_clicked (mouse_x, mouse_y)) {
                                if (radio_player != null) {
                                    var volume = radio_player.get_volume ();
                                    volume += 0.1;
                                    if (volume > 1.0) volume = 1.0;
                                    radio_player.set_volume (volume);
                                    controls.update_volume (volume);
                                }
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.SEARCH) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_SEARCH_TO_MAIN;
                        }
                        if (now_playing_button.is_clicked (mouse_x, mouse_y) && (is_playing || is_radio_playing)) {
                            if (is_radio_playing && radio_now_playing_widget != null) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
                            } else if (is_playing) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                            }
                        }
                        // Clear-all icon (inside input, right portion)
                        if (search_text.length > 0 &&
                            mouse_x >= 655 && mouse_x <= 705 &&
                            mouse_y >= 105 && mouse_y <= 160) {
                            search_text = "";
                            update_search_results ();
                        }
                        // Search results
                        Vinyl.Library.Track? s_track = null;
                        if (search_track_list != null &&
                            search_track_list.is_clicked (mouse_x, mouse_y, out s_track)) {
                            if (s_track != null) {
                                play_search_result (s_track);
                            }
                        }
                        // On-screen keyboard
                        if (search_keyboard != null) {
                            string? key = search_keyboard.handle_click (mouse_x, mouse_y);
                            if (key != null) {
                                process_keyboard_key (key);
                            }
                        }
                    }
                } else if (e.type == SDL.EventType.MOUSEWHEEL) {
                    if (current_screen == Vinyl.Utils.Screen.SEARCH && search_track_list != null) {
                        if (e.wheel.y > 0) {
                            search_track_list.scroll_up ();
                        } else if (e.wheel.y < 0) {
                            search_track_list.scroll_down ();
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY && track_list != null) {
                        if (e.wheel.y > 0) {
                            track_list.scroll_up ();
                        } else if (e.wheel.y < 0) {
                            track_list.scroll_down ();
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.RADIO && radio_station_list != null) {
                        if (e.wheel.y > 0) {
                            radio_station_list.scroll_up ();
                        } else if (e.wheel.y < 0) {
                            radio_station_list.scroll_down ();
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY_MENU && library_menu_buttons != null) {
                        if (e.wheel.y > 0) {
                            if (library_menu_focused_index > 0) {
                                library_menu_focused_index--;
                                library_menu_toolbar_focused = false;
                            }
                        } else if (e.wheel.y < 0) {
                            if (library_menu_focused_index < library_menu_buttons.size - 1) {
                                library_menu_focused_index++;
                                library_menu_toolbar_focused = false;
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.CATEGORY_LIST && category_list != null) {
                        if (e.wheel.y > 0) {
                            category_list.scroll_up ();
                        } else if (e.wheel.y < 0) {
                            category_list.scroll_down ();
                        }
                    }
                } else if (e.type == SDL.EventType.KEYDOWN) {
                    bool search_key_handled = false;
                    if (current_screen == Vinyl.Utils.Screen.SEARCH) {
                        int sym = (int) e.key.keysym.sym;
                        if (sym >= 97 && sym <= 122) {
                            search_text += ((unichar) (sym - 32)).to_string ();
                            update_search_results ();
                            search_key_handled = true;
                        } else if (sym >= 48 && sym <= 57) {
                            search_text += ((unichar) sym).to_string ();
                            update_search_results ();
                            search_key_handled = true;
                        } else if (e.key.keysym.sym == SDL.Input.Keycode.BACKSPACE) {
                            if (search_text.length > 0) {
                                search_text = remove_last_char (search_text);
                                update_search_results ();
                            }
                            search_key_handled = true;
                        } else if (e.key.keysym.sym == SDL.Input.Keycode.ESCAPE) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_SEARCH_TO_MAIN;
                            search_key_handled = true;
                        } else if (e.key.keysym.sym == SDL.Input.Keycode.SPACE) {
                            search_text += " ";
                            update_search_results ();
                            search_key_handled = true;
                        }
                    }
                    if (!search_key_handled) {
                    Vinyl.Utils.InputAction? kb_action = null;
                    switch (e.key.keysym.sym) {
                        case SDL.Input.Keycode.UP:
                            kb_action = Vinyl.Utils.InputAction.UP; break;
                        case SDL.Input.Keycode.DOWN:
                            kb_action = Vinyl.Utils.InputAction.DOWN; break;
                        case SDL.Input.Keycode.LEFT:
                            kb_action = Vinyl.Utils.InputAction.LEFT; break;
                        case SDL.Input.Keycode.RIGHT:
                            kb_action = Vinyl.Utils.InputAction.RIGHT; break;
                        case SDL.Input.Keycode.RETURN:
                        case SDL.Input.Keycode.SPACE:
                            kb_action = Vinyl.Utils.InputAction.CONFIRM; break;
                        case SDL.Input.Keycode.ESCAPE:
                        case SDL.Input.Keycode.BACKSPACE:
                            kb_action = Vinyl.Utils.InputAction.BACK; break;
                        default:
                            break;
                    }
                    if (kb_action != null) {
                        handle_input_action (kb_action);
                    }
                    } // end if (!search_key_handled)
                } else if (e.type == SDL.EventType.CONTROLLERBUTTONDOWN) {
                    Vinyl.Utils.InputAction? cb_action = null;
                    switch (e.cbutton.button) {
                        case SDL.Input.GameController.Button.DPAD_UP:
                            cb_action = Vinyl.Utils.InputAction.UP; break;
                        case SDL.Input.GameController.Button.DPAD_DOWN:
                            cb_action = Vinyl.Utils.InputAction.DOWN; break;
                        case SDL.Input.GameController.Button.DPAD_LEFT:
                            cb_action = Vinyl.Utils.InputAction.LEFT; break;
                        case SDL.Input.GameController.Button.DPAD_RIGHT:
                            cb_action = Vinyl.Utils.InputAction.RIGHT; break;
                        case SDL.Input.GameController.Button.A:
                            cb_action = Vinyl.Utils.InputAction.CONFIRM; break;
                        case SDL.Input.GameController.Button.B:
                            cb_action = Vinyl.Utils.InputAction.BACK; break;
                    }
                    if (cb_action != null) {
                        set_held_direction (cb_action);
                        handle_input_action (cb_action);
                    }
                } else if (e.type == SDL.EventType.CONTROLLERBUTTONUP) {
                    switch (e.cbutton.button) {
                        case SDL.Input.GameController.Button.DPAD_UP:
                        case SDL.Input.GameController.Button.DPAD_DOWN:
                        case SDL.Input.GameController.Button.DPAD_LEFT:
                        case SDL.Input.GameController.Button.DPAD_RIGHT:
                            held_direction = null;
                            break;
                    }
                } else if (e.type == SDL.EventType.CONTROLLERAXISMOTION) {
                    Vinyl.Utils.InputAction? axis_action = null;
                    if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTY) {
                        bool in_zone = e.caxis.value < -8000 || e.caxis.value > 8000;
                        if (in_zone) {
                            Vinyl.Utils.InputAction dir = (e.caxis.value < -8000)
                                ? Vinyl.Utils.InputAction.UP
                                : Vinyl.Utils.InputAction.DOWN;
                            if (!axis_y_active) {
                                axis_action = dir;
                            }
                            axis_y_active = true;
                            set_held_direction (dir);
                        } else {
                            if (axis_y_active) {
                                clear_held_direction_if (Vinyl.Utils.InputAction.UP);
                                clear_held_direction_if (Vinyl.Utils.InputAction.DOWN);
                            }
                            axis_y_active = false;
                        }
                    } else if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTX) {
                        bool in_zone = e.caxis.value < -8000 || e.caxis.value > 8000;
                        if (in_zone) {
                            Vinyl.Utils.InputAction dir = (e.caxis.value < -8000)
                                ? Vinyl.Utils.InputAction.LEFT
                                : Vinyl.Utils.InputAction.RIGHT;
                            if (!axis_x_active) {
                                axis_action = dir;
                            }
                            axis_x_active = true;
                            set_held_direction (dir);
                        } else {
                            if (axis_x_active) {
                                clear_held_direction_if (Vinyl.Utils.InputAction.LEFT);
                                clear_held_direction_if (Vinyl.Utils.InputAction.RIGHT);
                            }
                            axis_x_active = false;
                        }
                    }
                    if (axis_action != null) {
                        handle_input_action (axis_action);
                    }
                }
            }
        }

        private void set_held_direction (Vinyl.Utils.InputAction action) {
            if (action == Vinyl.Utils.InputAction.UP ||
                action == Vinyl.Utils.InputAction.DOWN ||
                action == Vinyl.Utils.InputAction.LEFT ||
                action == Vinyl.Utils.InputAction.RIGHT) {
                held_direction = action;
                held_direction_since = SDL.Timer.get_ticks ();
            }
        }

        private void clear_held_direction_if (Vinyl.Utils.InputAction action) {
            if (held_direction == action) {
                held_direction = null;
            }
        }

        private void process_held_dpad () {
            if (held_direction == null || !is_in_scrollable_list ()) {
                return;
            }
            uint now = SDL.Timer.get_ticks ();
            if (now > held_direction_since + 200) {
                handle_input_action (held_direction);
            }
        }

        private void update () {
            if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY_MENU) {
                screen_offset_x -= TRANSITION_SPEED / 60.0f;
                if (screen_offset_x <= -SCREEN_WIDTH) {
                    screen_offset_x = -SCREEN_WIDTH;
                    current_screen = Vinyl.Utils.Screen.LIBRARY_MENU;
                    library_menu_focused_index = 0;
                    library_menu_toolbar_focused = false;
                    main_toolbar_focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_LIBRARY_MENU_TO_MAIN) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                if (screen_offset_x >= 0) {
                    screen_offset_x = 0;
                    current_screen = Vinyl.Utils.Screen.MAIN;
                    main_toolbar_focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_CATEGORY_LIST) {
                screen_offset_x -= TRANSITION_SPEED / 60.0f;
                if (screen_offset_x <= -SCREEN_WIDTH * 2) {
                    screen_offset_x = -SCREEN_WIDTH * 2;
                    current_screen = Vinyl.Utils.Screen.CATEGORY_LIST;
                    is_category_list_focused = false;
                    category_header_focus = 0;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_CATEGORY_LIST_TO_LIBRARY_MENU) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                if (screen_offset_x >= -SCREEN_WIDTH) {
                    screen_offset_x = -SCREEN_WIDTH;
                    current_screen = Vinyl.Utils.Screen.LIBRARY_MENU;
                    library_menu_toolbar_focused = false;
                    is_category_browsing = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY) {
                screen_offset_x -= TRANSITION_SPEED / 60.0f;
                float lib_target = is_category_browsing
                    ? -SCREEN_WIDTH * 3
                    : -SCREEN_WIDTH * 2;
                if (screen_offset_x <= lib_target) {
                    screen_offset_x = lib_target;
                    current_screen = Vinyl.Utils.Screen.LIBRARY;
                    is_track_list_focused = false;
                    library_header_focus = 0;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_LIBRARY_TO_LIBRARY_MENU) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                if (is_category_browsing) {
                    if (screen_offset_x >= -SCREEN_WIDTH * 2) {
                        screen_offset_x = -SCREEN_WIDTH * 2;
                        current_screen = Vinyl.Utils.Screen.CATEGORY_LIST;
                        is_category_list_focused = false;
                        category_header_focus = 0;
                    }
                } else {
                    if (screen_offset_x >= -SCREEN_WIDTH) {
                        screen_offset_x = -SCREEN_WIDTH;
                        current_screen = Vinyl.Utils.Screen.LIBRARY_MENU;
                        library_menu_focused_index = 0;
                        library_menu_toolbar_focused = false;
                    }
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_MAIN) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                if (screen_offset_x >= 0) {
                    screen_offset_x = 0;
                    current_screen = Vinyl.Utils.Screen.MAIN;
                    main_toolbar_focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING) {
                screen_offset_x -= TRANSITION_SPEED / 60.0f;
                float np_target;
                if (now_playing_return_to_search) {
                    np_target = -SCREEN_WIDTH * 2;
                } else if (is_category_browsing) {
                    np_target = -SCREEN_WIDTH * 4;
                } else {
                    np_target = -SCREEN_WIDTH * 3;
                }
                if (screen_offset_x <= np_target) {
                    screen_offset_x = np_target;
                    current_screen = Vinyl.Utils.Screen.NOW_PLAYING;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                float back_target = is_category_browsing
                    ? -SCREEN_WIDTH * 3
                    : -SCREEN_WIDTH * 2;
                if (screen_offset_x >= back_target) {
                    screen_offset_x = back_target;
                    current_screen = Vinyl.Utils.Screen.LIBRARY;
                    is_track_list_focused = false;
                    library_header_focus = is_playing ? 2 : 0;
                    if (library_category == "favorites" && track_list != null) {
                        var all = get_all_tracks ();
                        var favs = new Gee.ArrayList<Vinyl.Library.Track> ();
                        foreach (var t in all) {
                            if (t.favorite) {
                                favs.add (t);
                            }
                        }
                        track_list.reload_tracks (renderer, favs);
                    }
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                if (screen_offset_x >= 0) {
                    screen_offset_x = 0;
                    current_screen = Vinyl.Utils.Screen.MAIN;
                    main_toolbar_focused = is_playing;
                    main_toolbar_index = is_playing ? 1 : 0;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_RADIO) {
                screen_offset_x -= TRANSITION_SPEED / 60.0f;
                if (screen_offset_x <= -SCREEN_WIDTH) {
                    screen_offset_x = -SCREEN_WIDTH;
                    current_screen = Vinyl.Utils.Screen.RADIO;
                    is_radio_list_focused = false;
                    radio_header_focus = 0;
                    main_toolbar_focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_TO_MAIN) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                if (screen_offset_x >= 0) {
                    screen_offset_x = 0;
                    current_screen = Vinyl.Utils.Screen.MAIN;
                    main_toolbar_focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING) {
                screen_offset_x -= TRANSITION_SPEED / 60.0f;
                if (screen_offset_x <= -SCREEN_WIDTH * 2) {
                    screen_offset_x = -SCREEN_WIDTH * 2;
                    current_screen = Vinyl.Utils.Screen.RADIO_NOW_PLAYING;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_RADIO) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                if (screen_offset_x >= -SCREEN_WIDTH) {
                    screen_offset_x = -SCREEN_WIDTH;
                    current_screen = Vinyl.Utils.Screen.RADIO;
                    is_radio_list_focused = false;
                    radio_header_focus = 0;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_MAIN) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                if (screen_offset_x >= 0) {
                    screen_offset_x = 0;
                    current_screen = Vinyl.Utils.Screen.MAIN;
                    main_toolbar_focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_SEARCH) {
                screen_offset_x -= TRANSITION_SPEED / 60.0f;
                if (screen_offset_x <= -SCREEN_WIDTH) {
                    screen_offset_x = -SCREEN_WIDTH;
                    current_screen = Vinyl.Utils.Screen.SEARCH;
                    search_focus_zone = 3;
                    main_toolbar_focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_SEARCH_TO_MAIN) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                if (screen_offset_x >= 0) {
                    screen_offset_x = 0;
                    current_screen = Vinyl.Utils.Screen.MAIN;
                    main_toolbar_focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_SEARCH) {
                screen_offset_x += TRANSITION_SPEED / 60.0f;
                if (screen_offset_x >= -SCREEN_WIDTH) {
                    screen_offset_x = -SCREEN_WIDTH;
                    current_screen = Vinyl.Utils.Screen.SEARCH;
                    search_focus_zone = 3;
                }
            }
            update_focus ();

            if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                if (player != null && now_playing_widget != null) {
                    if (player.is_playing ()) {
                        now_playing_widget.player_controls.play_pause_button.set_texture (
                            renderer, Constants.PAUSE_TB_ICON_PATH);
                    } else {
                        now_playing_widget.player_controls.play_pause_button.set_texture (
                            renderer, Constants.PLAY_TB_ICON_PATH);
                    }

                    var now = SDL.Timer.get_ticks ();
                    if (now - last_progress_update > 1000) {
                        var position = player.get_position ();
                        var duration = player.get_duration ();
                        now_playing_widget.update_progress (position, duration);
                        last_progress_update = now;
                    }
                }
            }

            if (current_screen == Vinyl.Utils.Screen.RADIO_NOW_PLAYING) {
                if (radio_player != null && radio_now_playing_widget != null) {
                    if (radio_player.is_playing ()) {
                        radio_now_playing_widget.player_controls.play_pause_button.set_texture (
                            renderer, Constants.PAUSE_TB_ICON_PATH);
                    } else {
                        radio_now_playing_widget.player_controls.play_pause_button.set_texture (
                            renderer, Constants.PLAY_TB_ICON_PATH);
                    }
                }
            }
        }

        private void render () {
            renderer.render_target = canvas;
            renderer.set_draw_color (0, 0, 0, 255);
            renderer.clear ();

            render_main_screen ((int)screen_offset_x);

            if (current_screen == Vinyl.Utils.Screen.RADIO ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_RADIO ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_TO_MAIN ||
                current_screen == Vinyl.Utils.Screen.RADIO_NOW_PLAYING ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_RADIO ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_MAIN) {
                render_radio_screen ((int)screen_offset_x + SCREEN_WIDTH);
                render_radio_now_playing_screen ((int)screen_offset_x + SCREEN_WIDTH * 2);
            } else if (is_in_search_graph ()) {
                render_search_screen ((int)screen_offset_x + SCREEN_WIDTH);
                render_now_playing_screen ((int)screen_offset_x + SCREEN_WIDTH * 2);
            } else if (is_category_browsing) {
                render_library_menu_screen ((int)screen_offset_x + SCREEN_WIDTH);
                render_category_list_screen ((int)screen_offset_x + SCREEN_WIDTH * 2);
                render_library_screen ((int)screen_offset_x + SCREEN_WIDTH * 3);
                render_now_playing_screen ((int)screen_offset_x + SCREEN_WIDTH * 4);
            } else {
                render_library_menu_screen ((int)screen_offset_x + SCREEN_WIDTH);
                render_library_screen ((int)screen_offset_x + SCREEN_WIDTH * 2);
                render_now_playing_screen ((int)screen_offset_x + SCREEN_WIDTH * 3);
            }

            render_header ();

            renderer.set_viewport (null);

            renderer.render_target = null;
            renderer.set_draw_color (0, 0, 0, 255);
            renderer.clear ();
            var dest = SDL.Video.Rect () {
                x = display_offset_x,
                y = display_offset_y,
                w = display_scaled_size,
                h = display_scaled_size
            };
            renderer.copy (canvas, null, dest);
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

        private void render_library_menu_screen (int x_offset) {
            renderer.set_viewport ({x_offset, 0, SCREEN_WIDTH, SCREEN_HEIGHT});

            renderer.set_draw_color (20, 20, 25, 255);
            renderer.fill_rect (null);

            foreach (var button in library_menu_buttons) {
                button.render (renderer, font_bold);
            }
        }

        private void render_category_list_screen (int x_offset) {
            renderer.set_viewport ({x_offset, 0, SCREEN_WIDTH, SCREEN_HEIGHT});

            renderer.set_draw_color (20, 20, 25, 255);
            renderer.fill_rect (null);

            if (category_list != null) {
                category_list.render (renderer, font_bold);
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

        private void render_radio_screen (int x_offset) {
            var viewport = SDL.Video.Rect () { x = x_offset, y = 0, w = SCREEN_WIDTH, h = SCREEN_HEIGHT };
            renderer.set_viewport (viewport);

            renderer.set_draw_color (40, 40, 50, 255);
            renderer.fill_rect (null);

            if (radio_station_list != null) {
                radio_station_list.render (renderer, font, font_small);
            }
        }

        private void render_radio_now_playing_screen (int x_offset) {
            var viewport = SDL.Video.Rect () { x = x_offset, y = 0, w = SCREEN_WIDTH, h = SCREEN_HEIGHT };
            renderer.set_viewport (viewport);

            renderer.set_draw_color (30, 30, 35, 255);
            renderer.fill_rect (null);

            if (radio_now_playing_widget != null) {
                radio_now_playing_widget.render (renderer, font, font_bold, font_small);
            }
        }

        private bool is_in_scrollable_list () {
            return (current_screen == Vinyl.Utils.Screen.LIBRARY && is_track_list_focused) ||
                   (current_screen == Vinyl.Utils.Screen.CATEGORY_LIST && is_category_list_focused) ||
                   (current_screen == Vinyl.Utils.Screen.RADIO && is_radio_list_focused) ||
                   (current_screen == Vinyl.Utils.Screen.SEARCH && search_focus_zone >= 2);
        }

        private bool is_in_search_graph () {
            switch (current_screen) {
                case Vinyl.Utils.Screen.SEARCH:
                case Vinyl.Utils.Screen.TRANSITION_TO_SEARCH:
                case Vinyl.Utils.Screen.TRANSITION_FROM_SEARCH_TO_MAIN:
                case Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_SEARCH:
                    return true;
                case Vinyl.Utils.Screen.NOW_PLAYING:
                case Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING:
                case Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY:
                case Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN:
                    return now_playing_return_to_search;
                default:
                    return false;
            }
        }

        private void render_search_screen (int x_offset) {
            var viewport = SDL.Video.Rect () { x = x_offset, y = 0, w = SCREEN_WIDTH, h = SCREEN_HEIGHT };
            renderer.set_viewport (viewport);

            renderer.set_draw_color (40, 40, 50, 255);
            renderer.fill_rect (null);

            // Input field (pill-shaped, full width)
            var input_rect = SDL.Video.Rect () { x = 15, y = 105, w = 690, h = 55 };
            renderer.set_draw_color (235, 230, 225, 255);
            Vinyl.Utils.Drawing.draw_rounded_rect_r (renderer, input_rect, (int) input_rect.h / 2);

            int text_left_pad = 22;
            int clear_icon_area = 45;
            int cursor_x = input_rect.x + text_left_pad;
            int cursor_h = 28;

            // Render search text inside input
            if (search_text.length > 0) {
                var ts = font_bold.render (search_text, {30, 30, 30, 255});
                if (ts != null) {
                    var tt = SDL.Video.Texture.create_from_surface (renderer, ts);
                    if (tt != null) {
                        int tw, th;
                        tt.query (null, null, out tw, out th);
                        cursor_h = th;
                        int max_tw = (int) input_rect.w - text_left_pad - clear_icon_area;
                        if (tw > max_tw) {
                            var src = SDL.Video.Rect () { x = tw - max_tw, y = 0, w = max_tw, h = th };
                            var dst = SDL.Video.Rect () {
                                x = input_rect.x + text_left_pad,
                                y = (int) (input_rect.y + (input_rect.h - th) / 2),
                                w = max_tw, h = th
                            };
                            renderer.copy (tt, src, dst);
                            cursor_x = input_rect.x + text_left_pad + max_tw;
                        } else {
                            renderer.copy (tt, null, {
                                input_rect.x + text_left_pad,
                                (int) (input_rect.y + (input_rect.h - th) / 2),
                                tw, th
                            });
                            cursor_x = input_rect.x + text_left_pad + tw;
                        }
                    }
                }

                // Clear-all icon inside input (right side, iPhone style)
                if (clear_all_icon != null) {
                    int icon_size = 22;
                    int icon_x = (int) input_rect.x + (int) input_rect.w - icon_size - 18;
                    int icon_y = (int) input_rect.y + ((int) input_rect.h - icon_size) / 2;
                    if (search_focus_zone == 1) {
                        renderer.set_draw_color (255, 156, 17, 255);
                        var bg_rect = SDL.Video.Rect () {
                            x = icon_x - 4, y = icon_y - 4,
                            w = icon_size + 8, h = icon_size + 8
                        };
                        Vinyl.Utils.Drawing.draw_rounded_rect_r (renderer, bg_rect, (icon_size + 8) / 2);
                    }
                    renderer.copy (clear_all_icon, null, {icon_x, icon_y, icon_size, icon_size});
                }
            }

            // Blinking cursor
            uint ticks = SDL.Timer.get_ticks ();
            if (ticks % 1000 < 500) {
                int cursor_y = (int) input_rect.y + ((int) input_rect.h - cursor_h) / 2;
                renderer.set_draw_color (30, 30, 30, 255);
                renderer.fill_rect ({cursor_x, cursor_y, 2, cursor_h});
            }

            // Separator line
            renderer.set_draw_color (60, 60, 70, 255);
            renderer.draw_line (0, 395, SCREEN_WIDTH, 395);

            // Search results
            if (search_track_list != null && search_track_list.get_total_items () > 0) {
                search_track_list.render (renderer, font, font_small);
            } else if (search_text.char_count () >= 3) {
                var ns = font.render ("No results", {160, 160, 160, 255});
                if (ns != null) {
                    var nt = SDL.Video.Texture.create_from_surface (renderer, ns);
                    if (nt != null) {
                        int nw, nh;
                        nt.query (null, null, out nw, out nh);
                        renderer.copy (nt, null, {(SCREEN_WIDTH - nw) / 2, 260, nw, nh});
                    }
                }
            }

            // On-screen keyboard
            if (search_keyboard != null) {
                search_keyboard.render (renderer, font);
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
                render_header_text_centered (Config.PROJECT_NAME, 25);
                exit_button.render (renderer);
                if (is_playing || is_radio_playing) {
                    now_playing_button.render (renderer);
                }
            } else if (
                current_screen == Vinyl.Utils.Screen.LIBRARY_MENU ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY_MENU ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_LIBRARY_MENU_TO_MAIN
            ) {
                render_header_text_centered ("My Music", 25);
                back_button.render (renderer);
                if (is_playing || is_radio_playing) {
                    now_playing_button.render (renderer);
                }
            } else if (
                current_screen == Vinyl.Utils.Screen.CATEGORY_LIST ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_CATEGORY_LIST ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_CATEGORY_LIST_TO_LIBRARY_MENU
            ) {
                string cat_title = library_category == "artists" ? "Artists" : "Albums";
                render_header_text_centered (cat_title, 25);
                back_button.render (renderer);
                if (is_playing || is_radio_playing) {
                    now_playing_button.render (renderer);
                }
            } else if (
                current_screen == Vinyl.Utils.Screen.LIBRARY ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_LIBRARY_TO_LIBRARY_MENU
            ) {
                if (is_category_browsing && category_list != null) {
                    string? sel = category_list.get_focused_item ();
                    if (sel != null) {
                        render_header_text_centered (sel, 25);
                    } else {
                        render_header_text_centered ("My Music", 25);
                    }
                } else {
                    string lib_title;
                    if (library_category == "favorites") {
                        lib_title = "Favorites";
                    } else {
                        lib_title = "All Songs";
                    }
                    render_header_text_centered (lib_title, 25);
                }
                back_button.render (renderer);
                sync_button.render (renderer);
                if (is_playing) {
                    now_playing_button.render (renderer);
                }
            } else if (
                current_screen == Vinyl.Utils.Screen.RADIO ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_RADIO ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_TO_MAIN
            ) {
                render_header_text_centered ("Radio", 25);
                back_button.render (renderer);
                if (is_playing || is_radio_playing) {
                    now_playing_button.render (renderer);
                }
            } else if (
                current_screen == Vinyl.Utils.Screen.SEARCH ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_SEARCH ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_SEARCH_TO_MAIN
            ) {
                render_header_text_centered ("Search", 25);
                back_button.render (renderer);
                if (is_playing || is_radio_playing) {
                    now_playing_button.render (renderer);
                }
            } else if (
                current_screen == Vinyl.Utils.Screen.NOW_PLAYING ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_SEARCH
            ) {
                if (now_playing_return_to_search && search_track_list != null) {
                    var text = "Now Playing • %d of %d".printf (
                        search_track_list.focused_index + 1, search_track_list.get_total_items ());
                    render_header_text_centered (text, 25);
                } else if (track_list != null) {
                    var text = "Now Playing • %d of %d".printf (
                        track_list.focused_index + 1, track_list.get_total_items ());
                    render_header_text_centered (text, 25);
                }
                back_button.render (renderer);
                playlist_button.render (renderer);
            } else if (
                current_screen == Vinyl.Utils.Screen.RADIO_NOW_PLAYING ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_RADIO ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_MAIN
            ) {
                if (radio_station_list != null) {
                    var text = "Now Playing • %d of %d".printf (
                        radio_station_list.focused_index + 1, radio_station_list.get_total_items ());
                    render_header_text_centered (text, 25);
                }
                back_button.render (renderer);
                playlist_button.render (renderer);
            }
        }

        private void handle_input_action (Vinyl.Utils.InputAction action) {
            if (action == Vinyl.Utils.InputAction.BACK &&
                (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY ||
                 current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN ||
                 current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_RADIO ||
                 current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_MAIN)) {
                return;
            }

            uint current_time = SDL.Timer.get_ticks ();

            if (current_screen == Vinyl.Utils.Screen.MAIN) {
                switch (action) {
                    case Vinyl.Utils.InputAction.LEFT:
                        if (current_time > last_joy_move + 200) {
                            if (main_toolbar_focused &&
                                (is_playing || is_radio_playing) &&
                                main_toolbar_index == 1) {
                                main_toolbar_index = 0;
                                last_joy_move = current_time;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.RIGHT:
                        if (current_time > last_joy_move + 200) {
                            if (main_toolbar_focused &&
                                (is_playing || is_radio_playing) &&
                                main_toolbar_index == 0) {
                                main_toolbar_index = 1;
                                last_joy_move = current_time;
                            }
                            if (!main_toolbar_focused &&
                                (is_playing || is_radio_playing) &&
                                focused_widget_index == focusable_widgets.size - 1) {
                                main_toolbar_focused = true;
                                main_toolbar_index = 1;
                                last_joy_move = current_time;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.UP:
                        if (current_time > last_joy_move + 200) {
                            if (main_toolbar_focused) {
                                break;
                            }
                            if ((is_playing || is_radio_playing) && focused_widget_index == 0) {
                                main_toolbar_focused = true;
                                main_toolbar_index = 1;
                                last_joy_move = current_time;
                                break;
                            }
                            focused_widget_index--;
                            if (focused_widget_index < 0) {
                                focused_widget_index = focusable_widgets.size - 1;
                            }
                            last_joy_move = current_time;
                        }
                        break;
                    case Vinyl.Utils.InputAction.DOWN:
                        if (current_time > last_joy_move + 200) {
                            if (main_toolbar_focused) {
                                main_toolbar_focused = false;
                                focused_widget_index = 0;
                                last_joy_move = current_time;
                                break;
                            }
                            focused_widget_index++;
                            if (focused_widget_index >= focusable_widgets.size) {
                                focused_widget_index = 0;
                            }
                            last_joy_move = current_time;
                        }
                        break;
                    case Vinyl.Utils.InputAction.CONFIRM:
                        if (main_toolbar_focused) {
                            if (main_toolbar_index == 0) {
                                quit = true;
                            } else if (main_toolbar_index == 1) {
                                if (is_radio_playing && radio_now_playing_widget != null) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
                                } else if (is_playing && player != null) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                                }
                            }
                            break;
                        }
                        var widget = focusable_widgets.get (focused_widget_index);
                        if (widget is Vinyl.Widgets.MenuButton) {
                            var button = (Vinyl.Widgets.MenuButton) widget;
                            if (button.id == "music") {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY_MENU;
                            } else if (button.id == "radio") {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO;
                            } else if (button.id == "search") {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_SEARCH;
                            }
                        } else if (widget is Vinyl.Widgets.ToolbarButton) {
                            var tb = (Vinyl.Widgets.ToolbarButton) widget;
                            if (tb == exit_button) {
                                quit = true;
                            }
                        }
                        break;
                    default:
                        break;
                }
            } else if (current_screen == Vinyl.Utils.Screen.LIBRARY_MENU) {
                bool any_playing = is_playing || is_radio_playing;
                switch (action) {
                    case Vinyl.Utils.InputAction.LEFT:
                        if (current_time > last_joy_move + 200) {
                            if (!library_menu_toolbar_focused) {
                                library_menu_toolbar_focused = true;
                                library_menu_header_focus = 0;
                                last_joy_move = current_time;
                            } else if (library_menu_toolbar_focused && any_playing &&
                                       library_menu_header_focus == 1) {
                                library_menu_header_focus = 0;
                                last_joy_move = current_time;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.RIGHT:
                        if (current_time > last_joy_move + 200) {
                            if (!library_menu_toolbar_focused) {
                                library_menu_toolbar_focused = true;
                                library_menu_header_focus = any_playing ? 1 : 0;
                                last_joy_move = current_time;
                            } else if (library_menu_toolbar_focused && any_playing &&
                                       library_menu_header_focus == 0) {
                                library_menu_header_focus = 1;
                                last_joy_move = current_time;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.UP:
                        if (current_time > last_joy_move + 200) {
                            if (library_menu_toolbar_focused) {
                                break;
                            }
                            if (library_menu_focused_index == 0) {
                                library_menu_toolbar_focused = true;
                                library_menu_header_focus = any_playing ? 1 : 0;
                                last_joy_move = current_time;
                                break;
                            }
                            library_menu_focused_index--;
                            last_joy_move = current_time;
                        }
                        break;
                    case Vinyl.Utils.InputAction.DOWN:
                        if (current_time > last_joy_move + 200) {
                            if (library_menu_toolbar_focused) {
                                library_menu_toolbar_focused = false;
                                library_menu_focused_index = 0;
                                last_joy_move = current_time;
                                break;
                            }
                            library_menu_focused_index++;
                            if (library_menu_focused_index >= library_menu_buttons.size) {
                                library_menu_focused_index = 0;
                            }
                            last_joy_move = current_time;
                        }
                        break;
                    case Vinyl.Utils.InputAction.CONFIRM:
                        if (library_menu_toolbar_focused) {
                            if (library_menu_header_focus == 0) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_LIBRARY_MENU_TO_MAIN;
                            } else if (library_menu_header_focus == 1 && any_playing) {
                                if (is_radio_playing && radio_now_playing_widget != null) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
                                } else if (is_playing && player != null) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                                }
                            }
                            break;
                        }
                        var selected_btn = library_menu_buttons.get (library_menu_focused_index);
                        activate_library_category (selected_btn.id);
                        break;
                    case Vinyl.Utils.InputAction.BACK:
                        if (!library_menu_toolbar_focused) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_LIBRARY_MENU_TO_MAIN;
                        }
                        break;
                    default:
                        break;
                }
            } else if (current_screen == Vinyl.Utils.Screen.CATEGORY_LIST) {
                bool any_playing_cat = is_playing || is_radio_playing;
                switch (action) {
                    case Vinyl.Utils.InputAction.LEFT:
                        if (current_time > last_joy_move + 200) {
                            if (is_category_list_focused) {
                                is_category_list_focused = false;
                                category_header_focus = 0;
                                last_joy_move = current_time;
                            } else if (any_playing_cat && category_header_focus == 1) {
                                category_header_focus = 0;
                                last_joy_move = current_time;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.RIGHT:
                        if (current_time > last_joy_move + 200) {
                            if (is_category_list_focused) {
                                is_category_list_focused = false;
                                category_header_focus = any_playing_cat ? 1 : 0;
                                last_joy_move = current_time;
                            } else if (any_playing_cat && category_header_focus == 0) {
                                category_header_focus = 1;
                                last_joy_move = current_time;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.UP:
                        if (current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (is_category_list_focused && category_list != null) {
                                if (category_list.focused_index == 0) {
                                    is_category_list_focused = false;
                                } else {
                                    category_list.scroll_up ();
                                }
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.DOWN:
                        if (current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (is_category_list_focused && category_list != null) {
                                category_list.scroll_down ();
                            } else {
                                is_category_list_focused = true;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.CONFIRM:
                        if (is_category_list_focused && category_list != null) {
                            select_category_item ();
                        } else if (category_header_focus == 0) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_CATEGORY_LIST_TO_LIBRARY_MENU;
                        } else if (any_playing_cat && category_header_focus == 1) {
                            if (is_radio_playing && radio_now_playing_widget != null) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
                            } else if (is_playing && player != null) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.BACK:
                        if (!is_category_list_focused) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_CATEGORY_LIST_TO_LIBRARY_MENU;
                        }
                        break;
                    default:
                        break;
                }
            } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                switch (action) {
                    case Vinyl.Utils.InputAction.LEFT:
                        if (current_time > last_joy_move + 200) {
                            if (is_track_list_focused) {
                                is_track_list_focused = false;
                                library_header_focus = 0;
                                last_joy_move = current_time;
                            } else if (library_header_focus > 0) {
                                library_header_focus--;
                                last_joy_move = current_time;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.RIGHT:
                        if (current_time > last_joy_move + 200) {
                            int max_focus = is_playing ? 2 : 1;
                            if (is_track_list_focused) {
                                is_track_list_focused = false;
                                library_header_focus = max_focus;
                                last_joy_move = current_time;
                            } else if (library_header_focus < max_focus) {
                                library_header_focus++;
                                last_joy_move = current_time;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.UP:
                        if (current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (is_track_list_focused && track_list != null) {
                                if (track_list.focused_index == 0) {
                                    is_track_list_focused = false;
                                } else {
                                    track_list.scroll_up ();
                                }
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.DOWN:
                        if (current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (is_track_list_focused && track_list != null) {
                                track_list.scroll_down ();
                            } else {
                                is_track_list_focused = true;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.CONFIRM:
                        if (is_track_list_focused && track_list != null) {
                            var track = track_list.get_focused_track ();
                            if (track != null) {
                                stop_radio ();
                                now_playing_return_to_search = false;
                                now_playing_widget = new Vinyl.Widgets.NowPlaying (
                                    renderer,
                                    track,
                                    0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90,
                                    track_list.focused_index, track_list.get_total_items ()
                                );
                                build_now_playing_focusable_widgets ();
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                                if (player != null) {
                                    player.stop ();
                                }
                                player = new Vinyl.Player (track_list.get_tracks (), track_list.focused_index);
                                player.state_changed.connect (on_player_state_changed);
                                player.play_pause ();
                                now_playing_widget.player_controls.update_volume (player.get_volume ());
                            }
                        } else if (library_header_focus == 1) {
                            trigger_sync_library ();
                        } else if (is_playing && library_header_focus == 2) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                        } else {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_LIBRARY_TO_LIBRARY_MENU;
                        }
                        break;
                    case Vinyl.Utils.InputAction.BACK:
                        if (!is_track_list_focused) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_LIBRARY_TO_LIBRARY_MENU;
                            library_header_focus = 0;
                        }
                        break;
                    default:
                        break;
                }
            } else if (current_screen == Vinyl.Utils.Screen.RADIO) {
                bool any_playing = is_playing || is_radio_playing;
                switch (action) {
                    case Vinyl.Utils.InputAction.LEFT:
                        if (current_time > last_joy_move + 200) {
                            if (is_radio_list_focused) {
                                is_radio_list_focused = false;
                                radio_header_focus = 0;
                                last_joy_move = current_time;
                            } else if (any_playing && radio_header_focus == 1) {
                                radio_header_focus = 0;
                                last_joy_move = current_time;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.RIGHT:
                        if (current_time > last_joy_move + 200) {
                            if (is_radio_list_focused) {
                                is_radio_list_focused = false;
                                radio_header_focus = any_playing ? 1 : 0;
                                last_joy_move = current_time;
                            } else if (any_playing && radio_header_focus == 0) {
                                radio_header_focus = 1;
                                last_joy_move = current_time;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.UP:
                        if (current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (is_radio_list_focused && radio_station_list != null) {
                                if (radio_station_list.focused_index == 0) {
                                    is_radio_list_focused = false;
                                } else {
                                    radio_station_list.scroll_up ();
                                }
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.DOWN:
                        if (current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (is_radio_list_focused && radio_station_list != null) {
                                radio_station_list.scroll_down ();
                            } else {
                                is_radio_list_focused = true;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.CONFIRM:
                        if (is_radio_list_focused && radio_station_list != null) {
                            var station = radio_station_list.get_focused_station ();
                            if (station != null && radio_player != null) {
                                start_radio (station);
                            }
                        } else if (radio_header_focus == 1) {
                            if (is_radio_playing && radio_now_playing_widget != null) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
                            } else if (is_playing) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                            }
                        } else {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_TO_MAIN;
                        }
                        break;
                    case Vinyl.Utils.InputAction.BACK:
                        if (!is_radio_list_focused) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_TO_MAIN;
                            radio_header_focus = 0;
                        }
                        break;
                    default:
                        break;
                }
            } else if (current_screen == Vinyl.Utils.Screen.SEARCH) {
                switch (action) {
                    case Vinyl.Utils.InputAction.LEFT:
                        if (current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (search_focus_zone == 2) {
                                search_focus_zone = 0;
                                search_header_focus = 0;
                            } else if (search_focus_zone == 0) {
                                bool any = is_playing || is_radio_playing;
                                if (any && search_header_focus == 1) {
                                    search_header_focus = 0;
                                }
                            } else if (search_focus_zone == 3 && search_keyboard != null) {
                                search_keyboard.move_left ();
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.RIGHT:
                        if (current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            bool any = is_playing || is_radio_playing;
                            if (search_focus_zone == 2) {
                                search_focus_zone = 0;
                                search_header_focus = any ? 1 : 0;
                            } else if (search_focus_zone == 0) {
                                if (any && search_header_focus == 0) {
                                    search_header_focus = 1;
                                }
                            } else if (search_focus_zone == 3 && search_keyboard != null) {
                                search_keyboard.move_right ();
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.UP:
                        if (current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (search_focus_zone == 3) {
                                if (search_keyboard == null || !search_keyboard.move_up ()) {
                                    if (search_track_list != null && search_track_list.get_total_items () > 0) {
                                        search_focus_zone = 2;
                                    } else if (search_text.length > 0) {
                                        search_focus_zone = 1;
                                    } else {
                                        search_focus_zone = 0;
                                        search_header_focus = 0;
                                    }
                                }
                            } else if (search_focus_zone == 2) {
                                if (search_track_list != null && search_track_list.focused_index == 0) {
                                    if (search_text.length > 0) {
                                        search_focus_zone = 1;
                                    } else {
                                        search_focus_zone = 0;
                                        search_header_focus = 0;
                                    }
                                } else if (search_track_list != null) {
                                    search_track_list.scroll_up ();
                                }
                            } else if (search_focus_zone == 1) {
                                search_focus_zone = 0;
                                search_header_focus = 0;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.DOWN:
                        if (current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (search_focus_zone == 0) {
                                if (search_text.length > 0) {
                                    search_focus_zone = 1;
                                } else if (search_track_list != null && search_track_list.get_total_items () > 0) {
                                    search_focus_zone = 2;
                                } else {
                                    search_focus_zone = 3;
                                }
                            } else if (search_focus_zone == 1) {
                                if (search_track_list != null && search_track_list.get_total_items () > 0) {
                                    search_focus_zone = 2;
                                } else {
                                    search_focus_zone = 3;
                                }
                            } else if (search_focus_zone == 2) {
                                if (search_track_list != null &&
                                    search_track_list.focused_index >= search_track_list.get_total_items () - 1) {
                                    search_focus_zone = 3;
                                } else if (search_track_list != null) {
                                    search_track_list.scroll_down ();
                                }
                            } else if (search_focus_zone == 3 && search_keyboard != null) {
                                search_keyboard.move_down ();
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.CONFIRM:
                        if (search_focus_zone == 0) {
                            if (search_header_focus == 0) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_SEARCH_TO_MAIN;
                            } else if (search_header_focus == 1 && (is_playing || is_radio_playing)) {
                                if (is_radio_playing && radio_now_playing_widget != null) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
                                } else if (is_playing) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                                }
                            }
                        } else if (search_focus_zone == 1) {
                            search_text = "";
                            update_search_results ();
                        } else if (search_focus_zone == 2) {
                            if (search_track_list != null) {
                                var track = search_track_list.get_focused_track ();
                                if (track != null) {
                                    play_search_result (track);
                                }
                            }
                        } else if (search_focus_zone == 3 && search_keyboard != null) {
                            var key = search_keyboard.get_focused_key ();
                            process_keyboard_key (key);
                        }
                        break;
                    case Vinyl.Utils.InputAction.BACK:
                        if (search_focus_zone == 0) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_SEARCH_TO_MAIN;
                        }
                        break;
                    default:
                        break;
                }
            } else if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                switch (action) {
                    case Vinyl.Utils.InputAction.LEFT:
                        if (now_playing_focusable_widgets != null &&
                            current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (now_playing_focused_widget_index == 0) {
                                now_playing_focused_widget_index = 2;
                            } else if (now_playing_focused_widget_index == 2) {
                                now_playing_focused_widget_index = 0;
                            } else if (now_playing_focused_widget_index >= 3) {
                                now_playing_focused_widget_index--;
                                if (now_playing_focused_widget_index < 3) {
                                    now_playing_focused_widget_index =
                                        now_playing_focusable_widgets.size - 1;
                                }
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.RIGHT:
                        if (now_playing_focusable_widgets != null &&
                            current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (now_playing_focused_widget_index == 0) {
                                now_playing_focused_widget_index = 2;
                            } else if (now_playing_focused_widget_index == 2) {
                                now_playing_focused_widget_index = 0;
                            } else if (now_playing_focused_widget_index >= 3) {
                                now_playing_focused_widget_index++;
                                if (now_playing_focused_widget_index >=
                                    now_playing_focusable_widgets.size) {
                                    now_playing_focused_widget_index = 3;
                                }
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.UP:
                        if (now_playing_focusable_widgets != null &&
                            current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (now_playing_focused_widget_index >= 3) {
                                now_playing_focused_widget_index = 1;
                            } else if (now_playing_focused_widget_index == 1) {
                                now_playing_focused_widget_index = 0;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.DOWN:
                        if (now_playing_focusable_widgets != null &&
                            current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (now_playing_focused_widget_index == 0 ||
                                now_playing_focused_widget_index == 2) {
                                now_playing_focused_widget_index = 1;
                            } else if (now_playing_focused_widget_index == 1) {
                                now_playing_focused_widget_index = 5;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.CONFIRM:
                        if (now_playing_focusable_widgets != null) {
                            var w = now_playing_focusable_widgets.get (now_playing_focused_widget_index);
                            if (w == back_button) {
                                if (now_playing_return_to_search) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_SEARCH;
                                } else {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY;
                                }
                            } else if (w == now_playing_widget.favorite_button) {
                                toggle_current_track_favorite ();
                            } else if (w == playlist_button) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN;
                            } else if (w == now_playing_widget.player_controls.prev_button) {
                                if (player != null) {
                                    player.play_previous ();
                                    now_playing_widget.update_track (player.get_current_track ());
                                    sync_track_list_focus_from_player ();
                                }
                            } else if (w == now_playing_widget.player_controls.rewind_button) {
                                var rb = now_playing_widget.player_controls.rewind_button;
                                if (player != null && rb != null && !rb.disabled) {
                                    now_playing_widget.seek (-0.05f, player);
                                    apply_seek_ui_sync ();
                                }
                            } else if (w == now_playing_widget.player_controls.play_pause_button) {
                                if (player != null) {
                                    player.play_pause ();
                                }
                            } else if (w == now_playing_widget.player_controls.forward_button) {
                                var fb = now_playing_widget.player_controls.forward_button;
                                if (player != null && fb != null && !fb.disabled) {
                                    now_playing_widget.seek (0.05f, player);
                                    apply_seek_ui_sync ();
                                }
                            } else if (w == now_playing_widget.player_controls.next_button) {
                                if (player != null) {
                                    player.play_next ();
                                    now_playing_widget.update_track (player.get_current_track ());
                                    sync_track_list_focus_from_player ();
                                }
                            } else if (w == now_playing_widget.player_controls.volume_down_button) {
                                if (player != null) {
                                    var volume = player.get_volume ();
                                    volume -= 0.1;
                                    if (volume < 0.0) volume = 0.0;
                                    player.set_volume (volume);
                                    now_playing_widget.player_controls.update_volume (volume);
                                }
                            } else if (w == now_playing_widget.player_controls.volume_up_button) {
                                if (player != null) {
                                    var volume = player.get_volume ();
                                    volume += 0.1;
                                    if (volume > 1.0) volume = 1.0;
                                    player.set_volume (volume);
                                    now_playing_widget.player_controls.update_volume (volume);
                                }
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.BACK:
                        if (now_playing_return_to_search) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_SEARCH;
                        } else {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY;
                        }
                        break;
                    default:
                        break;
                }
            } else if (current_screen == Vinyl.Utils.Screen.RADIO_NOW_PLAYING) {
                switch (action) {
                    case Vinyl.Utils.InputAction.LEFT:
                        if (radio_now_playing_focusable_widgets != null &&
                            current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (radio_now_playing_focused_widget_index <= 1) {
                                radio_now_playing_focused_widget_index =
                                    (radio_now_playing_focused_widget_index == 0) ? 1 : 0;
                            } else {
                                radio_now_playing_focused_widget_index--;
                                if (radio_now_playing_focused_widget_index < 2) {
                                    radio_now_playing_focused_widget_index =
                                        radio_now_playing_focusable_widgets.size - 1;
                                }
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.RIGHT:
                        if (radio_now_playing_focusable_widgets != null &&
                            current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (radio_now_playing_focused_widget_index <= 1) {
                                radio_now_playing_focused_widget_index =
                                    (radio_now_playing_focused_widget_index == 0) ? 1 : 0;
                            } else {
                                radio_now_playing_focused_widget_index++;
                                if (radio_now_playing_focused_widget_index >=
                                    radio_now_playing_focusable_widgets.size) {
                                    radio_now_playing_focused_widget_index = 2;
                                }
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.UP:
                        if (radio_now_playing_focusable_widgets != null &&
                            current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (radio_now_playing_focused_widget_index >= 2) {
                                radio_now_playing_focused_widget_index = 0;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.DOWN:
                        if (radio_now_playing_focusable_widgets != null &&
                            current_time > last_joy_move + 200) {
                            last_joy_move = current_time;
                            if (radio_now_playing_focused_widget_index <= 1) {
                                radio_now_playing_focused_widget_index = 2;
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.CONFIRM:
                        if (radio_now_playing_focusable_widgets != null) {
                            var w = radio_now_playing_focusable_widgets.get (
                                radio_now_playing_focused_widget_index);
                            if (w == back_button) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_RADIO;
                            } else if (w == playlist_button) {
                                current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_MAIN;
                            } else if (w == radio_now_playing_widget.player_controls.prev_button) {
                                radio_play_previous ();
                            } else if (w == radio_now_playing_widget.player_controls.play_pause_button) {
                                if (radio_player != null) {
                                    radio_player.play_pause ();
                                }
                            } else if (w == radio_now_playing_widget.player_controls.next_button) {
                                radio_play_next ();
                            } else if (w == radio_now_playing_widget.player_controls.volume_down_button) {
                                if (radio_player != null) {
                                    var volume = radio_player.get_volume ();
                                    volume -= 0.1;
                                    if (volume < 0.0) volume = 0.0;
                                    radio_player.set_volume (volume);
                                    radio_now_playing_widget.player_controls.update_volume (volume);
                                }
                            } else if (w == radio_now_playing_widget.player_controls.volume_up_button) {
                                if (radio_player != null) {
                                    var volume = radio_player.get_volume ();
                                    volume += 0.1;
                                    if (volume > 1.0) volume = 1.0;
                                    radio_player.set_volume (volume);
                                    radio_now_playing_widget.player_controls.update_volume (volume);
                                }
                            }
                        }
                        break;
                    case Vinyl.Utils.InputAction.BACK:
                        current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_NOW_PLAYING_TO_RADIO;
                        break;
                    default:
                        break;
                }
            }
        }

        private void update_focus () {
            if (current_screen == Vinyl.Utils.Screen.MAIN) {
                if (!is_playing && !is_radio_playing && (main_toolbar_focused || main_toolbar_index != 0)) {
                    main_toolbar_focused = false;
                    main_toolbar_index = 0;
                }
                if (main_toolbar_focused) {
                    foreach (var btn in main_menu_buttons) {
                        btn.focused = false;
                    }
                    if (exit_button != null) {
                        exit_button.focused = main_toolbar_index == 0;
                    }
                    if (now_playing_button != null) {
                        now_playing_button.focused = (is_playing || is_radio_playing) && main_toolbar_index == 1;
                    }
                } else {
                    for (var i = 0; i < focusable_widgets.size; i++) {
                        var widget = focusable_widgets.get (i);
                        bool is_focused = (i == focused_widget_index);

                        if (widget is Vinyl.Widgets.MenuButton) {
                            ((Vinyl.Widgets.MenuButton) widget).focused = is_focused;
                        } else if (widget is Vinyl.Widgets.ToolbarButton) {
                            ((Vinyl.Widgets.ToolbarButton) widget).focused = is_focused;
                        }
                    }
                    if (now_playing_button != null) {
                        now_playing_button.focused = false;
                    }
                }
                if (back_button != null) {
                    back_button.focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.LIBRARY_MENU) {
                foreach (var widget in focusable_widgets) {
                    if (widget is Vinyl.Widgets.MenuButton) {
                        ((Vinyl.Widgets.MenuButton) widget).focused = false;
                    } else if (widget is Vinyl.Widgets.ToolbarButton) {
                        ((Vinyl.Widgets.ToolbarButton) widget).focused = false;
                    }
                }

                bool any_playing = is_playing || is_radio_playing;
                if (!any_playing && library_menu_header_focus != 0) {
                    library_menu_header_focus = 0;
                }
                if (library_menu_toolbar_focused) {
                    foreach (var btn in library_menu_buttons) {
                        btn.focused = false;
                    }
                    if (back_button != null) {
                        back_button.focused = library_menu_header_focus == 0;
                    }
                    if (now_playing_button != null) {
                        now_playing_button.focused = any_playing && library_menu_header_focus == 1;
                    }
                } else {
                    for (var i = 0; i < library_menu_buttons.size; i++) {
                        library_menu_buttons.get (i).focused = (i == library_menu_focused_index);
                    }
                    if (back_button != null) {
                        back_button.focused = false;
                    }
                    if (now_playing_button != null) {
                        now_playing_button.focused = false;
                    }
                }
            } else if (current_screen == Vinyl.Utils.Screen.CATEGORY_LIST) {
                foreach (var widget in focusable_widgets) {
                    if (widget is Vinyl.Widgets.MenuButton) {
                        ((Vinyl.Widgets.MenuButton) widget).focused = false;
                    } else if (widget is Vinyl.Widgets.ToolbarButton) {
                        ((Vinyl.Widgets.ToolbarButton) widget).focused = false;
                    }
                }
                foreach (var btn in library_menu_buttons) {
                    btn.focused = false;
                }

                bool any_playing_cat = is_playing || is_radio_playing;
                if (!any_playing_cat && category_header_focus != 0) {
                    category_header_focus = 0;
                }
                if (back_button != null) {
                    back_button.focused = !is_category_list_focused && category_header_focus == 0;
                }
                if (now_playing_button != null) {
                    now_playing_button.focused = !is_category_list_focused &&
                        any_playing_cat && category_header_focus == 1;
                }
                if (category_list != null) {
                    category_list.is_focused = is_category_list_focused;
                }
            } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                foreach (var widget in focusable_widgets) {
                    if (widget is Vinyl.Widgets.MenuButton) {
                        ((Vinyl.Widgets.MenuButton) widget).focused = false;
                    } else if (widget is Vinyl.Widgets.ToolbarButton) {
                        ((Vinyl.Widgets.ToolbarButton) widget).focused = false;
                    }
                }
                foreach (var btn in library_menu_buttons) {
                    btn.focused = false;
                }

                if (!is_playing && library_header_focus == 2) {
                    library_header_focus = 1;
                }
                if (back_button != null) {
                    back_button.focused = !is_track_list_focused && library_header_focus == 0;
                }
                if (sync_button != null) {
                    sync_button.set_x (is_playing ? SCREEN_WIDTH - 190 : SCREEN_WIDTH - 100);
                    sync_button.focused = !is_track_list_focused && library_header_focus == 1;
                }
                if (now_playing_button != null) {
                    now_playing_button.focused = !is_track_list_focused && is_playing && library_header_focus == 2;
                }
                if (track_list != null) {
                    track_list.is_focused = is_track_list_focused;
                }
            } else if (current_screen == Vinyl.Utils.Screen.RADIO) {
                foreach (var widget in focusable_widgets) {
                    if (widget is Vinyl.Widgets.MenuButton) {
                        ((Vinyl.Widgets.MenuButton) widget).focused = false;
                    } else if (widget is Vinyl.Widgets.ToolbarButton) {
                        ((Vinyl.Widgets.ToolbarButton) widget).focused = false;
                    }
                }

                bool radio_or_music_playing = is_playing || is_radio_playing;
                if (!radio_or_music_playing && radio_header_focus != 0) {
                    radio_header_focus = 0;
                }
                if (back_button != null) {
                    back_button.focused = !is_radio_list_focused && radio_header_focus == 0;
                }
                if (now_playing_button != null) {
                    now_playing_button.focused = !is_radio_list_focused &&
                        radio_or_music_playing && radio_header_focus == 1;
                }
                if (radio_station_list != null) {
                    radio_station_list.is_focused = is_radio_list_focused;
                }
            } else if (current_screen == Vinyl.Utils.Screen.SEARCH) {
                foreach (var widget in focusable_widgets) {
                    if (widget is Vinyl.Widgets.MenuButton) {
                        ((Vinyl.Widgets.MenuButton) widget).focused = false;
                    } else if (widget is Vinyl.Widgets.ToolbarButton) {
                        ((Vinyl.Widgets.ToolbarButton) widget).focused = false;
                    }
                }

                bool any_playing = is_playing || is_radio_playing;
                if (!any_playing && search_header_focus != 0) {
                    search_header_focus = 0;
                }
                if (back_button != null) {
                    back_button.focused = search_focus_zone == 0 && search_header_focus == 0;
                }
                if (now_playing_button != null) {
                    now_playing_button.focused = search_focus_zone == 0 &&
                        any_playing && search_header_focus == 1;
                }
                if (search_track_list != null) {
                    search_track_list.is_focused = search_focus_zone == 2;
                }
                if (search_keyboard != null) {
                    search_keyboard.is_focused = search_focus_zone == 3;
                }
            } else if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                if (now_playing_button != null) {
                    now_playing_button.focused = false;
                }
                if (now_playing_focusable_widgets != null) {
                    for (var i = 0; i < now_playing_focusable_widgets.size; i++) {
                        var widget = now_playing_focusable_widgets.get (i);
                        bool is_focused = (i == now_playing_focused_widget_index);
                        if (widget is Vinyl.Widgets.IconButton) {
                            ((Vinyl.Widgets.IconButton) widget).focused = is_focused;
                        } else if (widget is Vinyl.Widgets.ToolbarButton) {
                            ((Vinyl.Widgets.ToolbarButton) widget).focused = is_focused;
                        }
                    }
                }
            } else if (current_screen == Vinyl.Utils.Screen.RADIO_NOW_PLAYING) {
                if (now_playing_button != null) {
                    now_playing_button.focused = false;
                }
                if (radio_now_playing_focusable_widgets != null) {
                    for (var i = 0; i < radio_now_playing_focusable_widgets.size; i++) {
                        var widget = radio_now_playing_focusable_widgets.get (i);
                        bool is_focused = (i == radio_now_playing_focused_widget_index);
                        if (widget is Vinyl.Widgets.IconButton) {
                            ((Vinyl.Widgets.IconButton) widget).focused = is_focused;
                        } else if (widget is Vinyl.Widgets.ToolbarButton) {
                            ((Vinyl.Widgets.ToolbarButton) widget).focused = is_focused;
                        }
                    }
                }
            }
        }

        private void start_radio (Vinyl.Radio.RadioStation station) {
            if (player != null) {
                player.stop ();
                is_playing = false;
            }
            radio_player.play_station (station);
            radio_station_list.active_station_code = station.country_code;

            radio_now_playing_widget = new Vinyl.Widgets.RadioNowPlaying (
                renderer,
                station,
                0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90,
                radio_station_list.focused_index, radio_station_list.get_total_items (),
                radio_player
            );
            radio_now_playing_widget.player_controls.update_volume (radio_player.get_volume ());
            build_radio_now_playing_focusable_widgets ();
            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO_NOW_PLAYING;
        }

        private void radio_play_next () {
            if (radio_station_list == null || radio_player == null) return;
            if (radio_station_list.focused_index < radio_station_list.get_total_items () - 1) {
                radio_station_list.scroll_down ();
                var station = radio_station_list.get_focused_station ();
                if (station != null) {
                    radio_player.play_station (station);
                    radio_station_list.active_station_code = station.country_code;
                    if (radio_now_playing_widget != null) {
                        radio_now_playing_widget.update_station (
                            station,
                            radio_station_list.focused_index,
                            radio_station_list.get_total_items ()
                        );
                        radio_now_playing_widget.player_controls.update_volume (radio_player.get_volume ());
                    }
                }
            }
        }

        private void radio_play_previous () {
            if (radio_station_list == null || radio_player == null) return;
            if (radio_station_list.focused_index > 0) {
                radio_station_list.scroll_up ();
                var station = radio_station_list.get_focused_station ();
                if (station != null) {
                    radio_player.play_station (station);
                    radio_station_list.active_station_code = station.country_code;
                    if (radio_now_playing_widget != null) {
                        radio_now_playing_widget.update_station (
                            station,
                            radio_station_list.focused_index,
                            radio_station_list.get_total_items ()
                        );
                        radio_now_playing_widget.player_controls.update_volume (radio_player.get_volume ());
                    }
                }
            }
        }

        private void stop_radio () {
            if (radio_player != null) {
                radio_player.stop ();
            }
            if (radio_station_list != null) {
                radio_station_list.active_station_code = null;
            }
            is_radio_playing = false;
            if (radio_now_playing_widget != null) {
                radio_now_playing_widget.disconnect_player ();
                radio_now_playing_widget = null;
            }
        }

        private void apply_seek_ui_sync () {
            if (player != null && now_playing_widget != null) {
                last_progress_update = SDL.Timer.get_ticks ();
                now_playing_widget.sync_ui_after_relative_seek (player);
            }
        }

        private void sync_track_list_focus_from_player () {
            if (now_playing_widget == null || player == null) {
                return;
            }
            int idx = player.get_current_track_index ();
            if (now_playing_return_to_search) {
                if (search_track_list != null) {
                    search_track_list.focused_index = idx;
                    now_playing_widget.player_controls.update_state (idx, search_track_list.get_total_items ());
                }
            } else {
                if (track_list != null) {
                    track_list.focused_index = idx;
                    now_playing_widget.player_controls.update_state (idx, track_list.get_total_items ());
                }
            }
        }

        private void build_now_playing_focusable_widgets () {
            var c = now_playing_widget.player_controls;
            now_playing_focusable_widgets = new Gee.ArrayList<Object> ();
            now_playing_focusable_widgets.add (back_button);               // 0
            now_playing_focusable_widgets.add (now_playing_widget.favorite_button); // 1
            now_playing_focusable_widgets.add (playlist_button);           // 2
            now_playing_focusable_widgets.add (c.prev_button);             // 3
            now_playing_focusable_widgets.add (c.rewind_button);           // 4
            now_playing_focusable_widgets.add (c.play_pause_button);       // 5
            now_playing_focusable_widgets.add (c.forward_button);          // 6
            now_playing_focusable_widgets.add (c.next_button);             // 7
            now_playing_focusable_widgets.add (c.volume_down_button);      // 8
            now_playing_focusable_widgets.add (c.volume_up_button);        // 9
            now_playing_focused_widget_index = 5;
        }

        /** Renders bold text centered in the header area between the side buttons, with ellipsis if needed. */
        private void render_header_text_centered (string text, int y) {
            int left_margin = 110;
            int right_margin = 110;
            int max_width = SCREEN_WIDTH - left_margin - right_margin;

            string display_text = text;
            var surface = font_bold.render (display_text, {255, 255, 255, 255});
            var texture = SDL.Video.Texture.create_from_surface (renderer, surface);
            int tw, th;
            texture.query (null, null, out tw, out th);

            if (tw > max_width) {
                string truncated = text;
                while (truncated.length > 1) {
                    truncated = truncated.substring (0, truncated.length - 1);
                    display_text = truncated + "…";
                    surface = font_bold.render (display_text, {255, 255, 255, 255});
                    texture = SDL.Video.Texture.create_from_surface (renderer, surface);
                    texture.query (null, null, out tw, out th);
                    if (tw <= max_width) {
                        break;
                    }
                }
            }

            int tx = (SCREEN_WIDTH - tw) / 2;
            renderer.copy (texture, null, {tx, y, tw, th});
        }

        private void on_player_state_changed (bool is_playing) {
            this.is_playing = is_playing;
        }

        private void on_radio_state_changed (bool playing) {
            this.is_radio_playing = playing;
            if (!playing && radio_station_list != null) {
                radio_station_list.active_station_code = null;
            }
        }

        private void trigger_sync_library () {
            if (is_syncing || music_scanner == null) return;
            is_syncing = true;
            music_scanner.sync_library.begin ((obj, res) => {
                var updated = music_scanner.sync_library.end (res);
                Idle.add (() => {
                    if (track_list != null && updated != null) {
                        track_list.reload_tracks (renderer, updated);
                        if (player != null) {
                            player.sync_playlist (track_list.get_tracks ());
                        }
                    }
                    is_syncing = false;
                    return false;
                });
            });
        }

        private void build_radio_now_playing_focusable_widgets () {
            var c = radio_now_playing_widget.player_controls;
            radio_now_playing_focusable_widgets = new Gee.ArrayList<Object> ();
            radio_now_playing_focusable_widgets.add (back_button);
            radio_now_playing_focusable_widgets.add (playlist_button);
            radio_now_playing_focusable_widgets.add (c.prev_button);
            radio_now_playing_focusable_widgets.add (c.rewind_button);
            radio_now_playing_focusable_widgets.add (c.play_pause_button);
            radio_now_playing_focusable_widgets.add (c.forward_button);
            radio_now_playing_focusable_widgets.add (c.next_button);
            radio_now_playing_focusable_widgets.add (c.volume_down_button);
            radio_now_playing_focusable_widgets.add (c.volume_up_button);
            radio_now_playing_focused_widget_index = 4;
        }

        private void update_search_results () {
            if (search_track_list == null || track_list == null) return;

            if (search_text.char_count () < 3) {
                search_track_list.reload_tracks (renderer, new Gee.ArrayList<Vinyl.Library.Track> ());
                return;
            }

            string query = search_text.down ();
            var all = track_list.get_tracks ();
            var results = new Gee.ArrayList<Vinyl.Library.Track> ();

            foreach (var track in all) {
                if (track.title.down ().contains (query) ||
                    track.artist.down ().contains (query) ||
                    track.album.down ().contains (query)) {
                    results.add (track);
                }
            }

            search_track_list.reload_tracks (renderer, results);
        }

        private void play_search_result (Vinyl.Library.Track track) {
            stop_radio ();
            now_playing_return_to_search = true;
            now_playing_widget = new Vinyl.Widgets.NowPlaying (
                renderer,
                track,
                0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90,
                search_track_list.focused_index, search_track_list.get_total_items ()
            );
            build_now_playing_focusable_widgets ();
            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
            if (player != null) {
                player.stop ();
            }
            player = new Vinyl.Player (search_track_list.get_tracks (), search_track_list.focused_index);
            player.state_changed.connect (on_player_state_changed);
            player.play_pause ();
            now_playing_widget.player_controls.update_volume (player.get_volume ());
        }

        private void process_keyboard_key (string key) {
            if (key == Vinyl.Widgets.OnScreenKeyboard.KEY_BACKSPACE) {
                if (search_text.length > 0) {
                    search_text = remove_last_char (search_text);
                }
            } else if (key == Vinyl.Widgets.OnScreenKeyboard.KEY_SPACE) {
                search_text += " ";
            } else {
                search_text += key;
            }
            update_search_results ();
        }

        private string remove_last_char (string s) {
            long count = s.char_count ();
            if (count <= 1) return "";
            return s.substring (0, s.index_of_nth_char (count - 1));
        }

        private void toggle_current_track_favorite () {
            if (now_playing_widget == null) return;
            var track = now_playing_widget.get_track ();
            track.favorite = !track.favorite;
            now_playing_widget.update_favorite_icon ();
            if (library_db != null && track.db_row_id >= 0) {
                library_db.toggle_favorite (track.db_row_id, track.favorite);
            }
        }

        private Gee.ArrayList<Vinyl.Library.Track> get_all_tracks () {
            if (library_db != null) {
                return library_db.load_tracks_for_ui ();
            }
            return new Gee.ArrayList<Vinyl.Library.Track> ();
        }

        private void activate_library_category (string category_id) {
            library_category = category_id;

            if (category_id == "all_songs") {
                is_category_browsing = false;
                var all = get_all_tracks ();
                if (track_list != null) {
                    track_list.reload_tracks (renderer, all);
                }
                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY;
            } else if (category_id == "favorites") {
                is_category_browsing = false;
                var all = get_all_tracks ();
                var favs = new Gee.ArrayList<Vinyl.Library.Track> ();
                foreach (var t in all) {
                    if (t.favorite) {
                        favs.add (t);
                    }
                }
                if (track_list != null) {
                    track_list.reload_tracks (renderer, favs);
                }
                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY;
            } else if (category_id == "artists") {
                is_category_browsing = true;
                var all = get_all_tracks ();
                var names = new Gee.TreeSet<string> ();
                foreach (var t in all) {
                    if (t.artist.length > 0) {
                        names.add (t.artist);
                    }
                }
                var sorted = new Gee.ArrayList<string> ();
                sorted.add_all (names);
                category_list = new Vinyl.Widgets.CategoryList (
                    renderer, Constants.ARTISTS_ICON_PATH, sorted,
                    0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90
                );
                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_CATEGORY_LIST;
            } else if (category_id == "albums") {
                is_category_browsing = true;
                var all = get_all_tracks ();
                var names = new Gee.TreeSet<string> ();
                foreach (var t in all) {
                    if (t.album.length > 0) {
                        names.add (t.album);
                    }
                }
                var sorted = new Gee.ArrayList<string> ();
                sorted.add_all (names);
                category_list = new Vinyl.Widgets.CategoryList (
                    renderer, Constants.ALBUMS_ICON_PATH, sorted,
                    0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90
                );
                current_screen = Vinyl.Utils.Screen.TRANSITION_TO_CATEGORY_LIST;
            }
        }

        private void select_category_item () {
            if (category_list == null) return;
            string? selected = category_list.get_focused_item ();
            if (selected == null) return;

            var all = get_all_tracks ();
            var filtered = new Gee.ArrayList<Vinyl.Library.Track> ();
            foreach (var t in all) {
                if (library_category == "artists" && t.artist == selected) {
                    filtered.add (t);
                } else if (library_category == "albums" && t.album == selected) {
                    filtered.add (t);
                }
            }
            if (track_list != null) {
                track_list.reload_tracks (renderer, filtered);
            }
            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY;
        }

        private void cleanup () {
            if (player != null) {
                player.stop ();
            }
            if (radio_player != null) {
                radio_player.stop ();
            }

            exit_button = null;
            back_button = null;
            sync_button = null;
            music_scanner = null;
            library_db = null;
            main_menu_buttons.clear ();
            main_menu_buttons = null;
            library_menu_buttons.clear ();
            library_menu_buttons = null;
            category_list = null;
            focusable_widgets.clear ();
            focusable_widgets = null;
            radio_station_list = null;
            radio_player = null;
            radio_now_playing_widget = null;
            search_keyboard = null;
            search_track_list = null;
            clear_all_icon = null;
            if (now_playing_focusable_widgets != null) {
                now_playing_focusable_widgets.clear ();
                now_playing_focusable_widgets = null;
            }
            if (radio_now_playing_focusable_widgets != null) {
                radio_now_playing_focusable_widgets.clear ();
                radio_now_playing_focusable_widgets = null;
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
