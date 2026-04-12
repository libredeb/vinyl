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
        private bool quit = false;

        private SDLTTF.Font? font;
        private SDLTTF.Font? font_bold;
        private SDLTTF.Font? font_small;

        private Vinyl.Utils.Screen current_screen = Vinyl.Utils.Screen.MAIN;
        private float screen_offset_x = 0;

        private Vinyl.Widgets.ToolbarButton? exit_button;
        private Vinyl.Widgets.ToolbarButton? back_button;
        private Vinyl.Widgets.ToolbarButton? playlist_button;
        private Vinyl.Widgets.ToolbarButton? now_playing_button;

        private Gee.ArrayList<Vinyl.Widgets.MenuButton> main_menu_buttons;
        private Gee.ArrayList<Object> focusable_widgets;
        private int focused_widget_index = 0;
        private SDL.Input.GameController? controller;
        private uint last_joy_move = 0; // For joystick move delay
        private bool is_track_list_focused = false;
        /** 0 = back, 1 = now_playing toolbar (only when is_playing). */
        private int library_header_focus = 0;
        /** Main screen: focus on header toolbar (exit vs now playing) instead of menu body. */
        private bool main_toolbar_focused = false;
        /** 0 = exit, 1 = now_playing (only when is_playing). */
        private int main_toolbar_index = 0;
        private Vinyl.Player? player = null;
        private uint last_progress_update = 0;
        private bool is_playing = false;

        private Vinyl.Widgets.TrackList? track_list;
        private Vinyl.Widgets.NowPlaying? now_playing_widget;
        private Gee.ArrayList<Object>? now_playing_focusable_widgets;
        private int now_playing_focused_widget_index = 0;

        private Vinyl.Widgets.RadioStationList? radio_station_list;
        private Vinyl.Radio.RadioPlayer? radio_player;
        private bool is_radio_list_focused = false;
        /** 0 = back, 1 = now_playing toolbar (only when music is_playing). */
        private int radio_header_focus = 0;

        public int run (string[] args) {
            if (!this.init ()) {
                return 1;
            }

            if (!this.load_media ()) {
                return 1;
            }

            var library_db = new Vinyl.Library.LibraryDatabase ();
            if (!library_db.open ()) {
                warning ("Library database could not be opened; continuing with an empty library.");
            }

            var tracks = library_db.load_tracks_for_ui ();
            track_list = new Vinyl.Widgets.TrackList (
                renderer,
                tracks,
                0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90
            );

            var stations = Vinyl.Radio.RadioStation.load_stations ();
            radio_station_list = new Vinyl.Widgets.RadioStationList (
                renderer,
                stations,
                0, 90, SCREEN_WIDTH, SCREEN_HEIGHT - 90
            );
            radio_player = new Vinyl.Radio.RadioPlayer ();

            var music_scanner = new Vinyl.Library.MusicScanner (library_db);
            music_scanner.sync_library.begin ((obj, res) => {
                var updated = music_scanner.sync_library.end (res);
                Idle.add (() => {
                    if (track_list != null && updated != null) {
                        track_list.reload_tracks (renderer, updated);
                        if (player != null) {
                            player.sync_playlist (track_list.get_tracks ());
                        }
                    }
                    return false;
                });
            });

            while (!this.quit) {
                if (player != null) {
                    player.handle_messages ();
                }
                if (radio_player != null) {
                    radio_player.handle_messages ();
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

                    if (current_screen == Vinyl.Utils.Screen.MAIN) {
                        if (exit_button.is_clicked (mouse_x, mouse_y)) {
                            quit = true;
                        }

                        for (var i = 0; i < main_menu_buttons.size; i++) {
                            var button = main_menu_buttons.get (i);
                            if (button.is_clicked (mouse_x, mouse_y)) {
                                focused_widget_index = focusable_widgets.index_of (button);

                                if (button.id == "music") {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY;
                                } else if (button.id == "radio") {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO;
                                }
                            }
                        }

                        if (now_playing_button.is_clicked (mouse_x, mouse_y) &&
                            player != null && player.is_playing ()) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_MAIN;
                        }
                        Vinyl.Library.Track? track = null;
                        if (track_list != null && track_list.is_clicked (mouse_x, mouse_y, out track)) {
                            if (track != null) {
                                stop_radio ();
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

                        if (now_playing_button.is_clicked (mouse_x, mouse_y) && is_playing) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                        if (back_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY;
                        } else if (playlist_button.is_clicked (mouse_x, mouse_y)) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN;
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
                        if (radio_station_list != null && radio_station_list.is_clicked (mouse_x, mouse_y, out clicked_station)) {
                            if (clicked_station != null && radio_player != null) {
                                start_radio (clicked_station);
                            }
                        }
                        if (now_playing_button.is_clicked (mouse_x, mouse_y) && is_playing) {
                            current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                        }
                    }
                } else if (e.type == SDL.EventType.MOUSEWHEEL) {
                    if (current_screen == Vinyl.Utils.Screen.LIBRARY && track_list != null) {
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
                    }
                } else if (e.type == SDL.EventType.CONTROLLERBUTTONDOWN) {
                    if (e.cbutton.button == SDL.Input.GameController.Button.B &&
                        (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY ||
                         current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN)) {
                        /* Drop extra B presses while the Now Playing exit animation runs. */
                    } else if (current_screen == Vinyl.Utils.Screen.MAIN) {
                        uint current_time = SDL.Timer.get_ticks ();
                        switch (e.cbutton.button) {
                            case SDL.Input.GameController.Button.DPAD_LEFT:
                                if (current_time > last_joy_move + 200) {
                                    if (main_toolbar_focused && is_playing && main_toolbar_index == 1) {
                                        main_toolbar_index = 0;
                                        last_joy_move = current_time;
                                    }
                                }
                                break;
                            case SDL.Input.GameController.Button.DPAD_RIGHT:
                                if (current_time > last_joy_move + 200) {
                                    if (main_toolbar_focused && is_playing && main_toolbar_index == 0) {
                                        main_toolbar_index = 1;
                                        last_joy_move = current_time;
                                    }
                                }
                                break;
                            case SDL.Input.GameController.Button.DPAD_UP:
                                if (current_time > last_joy_move + 200) {
                                    if (main_toolbar_focused) {
                                        break;
                                    }
                                    if (is_playing && focused_widget_index == 0) {
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
                            case SDL.Input.GameController.Button.DPAD_DOWN:
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
                            case SDL.Input.GameController.Button.A:
                                if (main_toolbar_focused) {
                                    if (main_toolbar_index == 0) {
                                        quit = true;
                                    } else if (is_playing && main_toolbar_index == 1 && player != null) {
                                        current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                                    }
                                    break;
                                }
                                var widget = focusable_widgets.get (focused_widget_index);
                                if (widget is Vinyl.Widgets.MenuButton) {
                                    var button = (Vinyl.Widgets.MenuButton) widget;
                                    if (button.id == "music") {
                                        current_screen = Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY;
                                    } else if (button.id == "radio") {
                                        current_screen = Vinyl.Utils.Screen.TRANSITION_TO_RADIO;
                                    }
                                } else if (widget is Vinyl.Widgets.ToolbarButton) {
                                    var tb = (Vinyl.Widgets.ToolbarButton) widget;
                                    if (tb == exit_button) {
                                        quit = true;
                                    }
                                }
                                break;
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                        uint lib_time = SDL.Timer.get_ticks ();
                        switch (e.cbutton.button) {
                            case SDL.Input.GameController.Button.DPAD_LEFT:
                                if (lib_time > last_joy_move + 200) {
                                    if (!is_track_list_focused && is_playing && library_header_focus == 1) {
                                        library_header_focus = 0;
                                        last_joy_move = lib_time;
                                    }
                                }
                                break;
                            case SDL.Input.GameController.Button.DPAD_RIGHT:
                                if (lib_time > last_joy_move + 200) {
                                    if (!is_track_list_focused && is_playing && library_header_focus == 0) {
                                        library_header_focus = 1;
                                        last_joy_move = lib_time;
                                    }
                                }
                                break;
                            case SDL.Input.GameController.Button.DPAD_UP:
                                if (lib_time > last_joy_move + 200) {
                                    last_joy_move = lib_time;
                                    if (is_track_list_focused && track_list != null) {
                                        if (track_list.focused_index == 0) {
                                            is_track_list_focused = false;
                                        } else {
                                            track_list.scroll_up ();
                                        }
                                    }
                                }
                                break;
                            case SDL.Input.GameController.Button.DPAD_DOWN:
                                if (lib_time > last_joy_move + 200) {
                                    last_joy_move = lib_time;
                                    if (is_track_list_focused && track_list != null) {
                                        track_list.scroll_down ();
                                    } else {
                                        is_track_list_focused = true;
                                    }
                                }
                                break;
                            case SDL.Input.GameController.Button.A:
                                if (is_track_list_focused && track_list != null) {
                                    var track = track_list.get_focused_track ();
                                    if (track != null) {
                                        stop_radio ();
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
                                } else if (is_playing && library_header_focus == 1) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                                } else {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_MAIN;
                                }
                                break;
                            case SDL.Input.GameController.Button.B:
                                if (!is_track_list_focused) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_MAIN;
                                    library_header_focus = 0;
                                }
                                break;
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.RADIO) {
                        uint radio_time = SDL.Timer.get_ticks ();
                        switch (e.cbutton.button) {
                            case SDL.Input.GameController.Button.DPAD_LEFT:
                                if (radio_time > last_joy_move + 200) {
                                    if (!is_radio_list_focused && is_playing && radio_header_focus == 1) {
                                        radio_header_focus = 0;
                                        last_joy_move = radio_time;
                                    }
                                }
                                break;
                            case SDL.Input.GameController.Button.DPAD_RIGHT:
                                if (radio_time > last_joy_move + 200) {
                                    if (!is_radio_list_focused && is_playing && radio_header_focus == 0) {
                                        radio_header_focus = 1;
                                        last_joy_move = radio_time;
                                    }
                                }
                                break;
                            case SDL.Input.GameController.Button.DPAD_UP:
                                if (radio_time > last_joy_move + 200) {
                                    last_joy_move = radio_time;
                                    if (is_radio_list_focused && radio_station_list != null) {
                                        if (radio_station_list.focused_index == 0) {
                                            is_radio_list_focused = false;
                                        } else {
                                            radio_station_list.scroll_up ();
                                        }
                                    }
                                }
                                break;
                            case SDL.Input.GameController.Button.DPAD_DOWN:
                                if (radio_time > last_joy_move + 200) {
                                    last_joy_move = radio_time;
                                    if (is_radio_list_focused && radio_station_list != null) {
                                        radio_station_list.scroll_down ();
                                    } else {
                                        is_radio_list_focused = true;
                                    }
                                }
                                break;
                            case SDL.Input.GameController.Button.A:
                                if (is_radio_list_focused && radio_station_list != null) {
                                    var station = radio_station_list.get_focused_station ();
                                    if (station != null && radio_player != null) {
                                        start_radio (station);
                                    }
                                } else if (is_playing && radio_header_focus == 1) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING;
                                } else {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_TO_MAIN;
                                }
                                break;
                            case SDL.Input.GameController.Button.B:
                                if (!is_radio_list_focused) {
                                    current_screen = Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_TO_MAIN;
                                    radio_header_focus = 0;
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
                                    } else if (widget == now_playing_widget.player_controls.prev_button) {
                                        if (player != null) {
                                            player.play_previous ();
                                            now_playing_widget.update_track (player.get_current_track ());
                                            sync_track_list_focus_from_player ();
                                        }
                                    } else if (widget == now_playing_widget.player_controls.rewind_button) {
                                        var rb = now_playing_widget.player_controls.rewind_button;
                                        if (player != null && rb != null && !rb.disabled) {
                                            now_playing_widget.seek (-0.05f, player);
                                            apply_seek_ui_sync ();
                                        }
                                    } else if (widget == now_playing_widget.player_controls.play_pause_button) {
                                        if (player != null) {
                                            player.play_pause ();
                                        }
                                    } else if (widget == now_playing_widget.player_controls.forward_button) {
                                        var fb = now_playing_widget.player_controls.forward_button;
                                        if (player != null && fb != null && !fb.disabled) {
                                            now_playing_widget.seek (0.05f, player);
                                            apply_seek_ui_sync ();
                                        }
                                    } else if (widget == now_playing_widget.player_controls.next_button) {
                                        if (player != null) {
                                            player.play_next ();
                                            now_playing_widget.update_track (player.get_current_track ());
                                            sync_track_list_focus_from_player ();
                                        }
                                    } else if (widget == now_playing_widget.player_controls.volume_down_button) {
                                        if (player != null) {
                                            var volume = player.get_volume ();
                                            volume -= 0.1;
                                            if (volume < 0.0) volume = 0.0;
                                            player.set_volume (volume);
                                            now_playing_widget.player_controls.update_volume (volume);
                                        }
                                    } else if (widget == now_playing_widget.player_controls.volume_up_button) {
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
                        }
                    }
                } else if (e.type == SDL.EventType.CONTROLLERAXISMOTION) {
                    uint current_time = SDL.Timer.get_ticks ();
                    if (current_screen == Vinyl.Utils.Screen.MAIN) {
                        if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTY) {
                            if (e.caxis.value < -8000) { // Up
                                if (current_time > last_joy_move + 200) {
                                    if (!main_toolbar_focused && is_playing && focused_widget_index == 0) {
                                        main_toolbar_focused = true;
                                        main_toolbar_index = 1;
                                        last_joy_move = current_time;
                                    } else if (!main_toolbar_focused) {
                                        focused_widget_index--;
                                        if (focused_widget_index < 0) {
                                            focused_widget_index = focusable_widgets.size - 1;
                                        }
                                        last_joy_move = current_time;
                                    }
                                }
                            } else if (e.caxis.value > 8000) { // Down
                                if (current_time > last_joy_move + 200) {
                                    if (main_toolbar_focused) {
                                        main_toolbar_focused = false;
                                        focused_widget_index = 0;
                                        last_joy_move = current_time;
                                    } else {
                                        focused_widget_index++;
                                        if (focused_widget_index >= focusable_widgets.size) {
                                            focused_widget_index = 0;
                                        }
                                        last_joy_move = current_time;
                                    }
                                }
                            }
                        } else if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTX) {
                            if (current_time > last_joy_move + 200) {
                                if (main_toolbar_focused && is_playing) {
                                    if (e.caxis.value < -8000) {
                                        main_toolbar_index = 0;
                                        last_joy_move = current_time;
                                    } else if (e.caxis.value > 8000) {
                                        main_toolbar_index = 1;
                                        last_joy_move = current_time;
                                    }
                                } else if (
                                    !main_toolbar_focused && is_playing &&
                                    focused_widget_index == focusable_widgets.size - 1) {
                                    if (e.caxis.value > 8000) {
                                        main_toolbar_focused = true;
                                        main_toolbar_index = 1;
                                        last_joy_move = current_time;
                                    }
                                }
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                        if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTY) {
                            if (e.caxis.value < -8000) { // Up
                                if (current_time > last_joy_move + 200) {
                                    if (is_track_list_focused && track_list != null) {
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
                                    if (is_track_list_focused && track_list != null) {
                                        track_list.scroll_down ();
                                    } else {
                                        is_track_list_focused = true;
                                    }
                                    last_joy_move = current_time;
                                }
                            }
                        } else if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTX) {
                            if (current_time > last_joy_move + 200) {
                                if (!is_track_list_focused && is_playing) {
                                    if (e.caxis.value < -8000) {
                                        library_header_focus = 0;
                                        last_joy_move = current_time;
                                    } else if (e.caxis.value > 8000) {
                                        library_header_focus = 1;
                                        last_joy_move = current_time;
                                    }
                                }
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.RADIO) {
                        if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTY) {
                            if (e.caxis.value < -8000) {
                                if (current_time > last_joy_move + 200) {
                                    if (is_radio_list_focused && radio_station_list != null) {
                                        if (radio_station_list.focused_index == 0) {
                                            is_radio_list_focused = false;
                                        } else {
                                            radio_station_list.scroll_up ();
                                        }
                                    }
                                    last_joy_move = current_time;
                                }
                            } else if (e.caxis.value > 8000) {
                                if (current_time > last_joy_move + 200) {
                                    if (is_radio_list_focused && radio_station_list != null) {
                                        radio_station_list.scroll_down ();
                                    } else {
                                        is_radio_list_focused = true;
                                    }
                                    last_joy_move = current_time;
                                }
                            }
                        } else if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTX) {
                            if (current_time > last_joy_move + 200) {
                                if (!is_radio_list_focused && is_playing) {
                                    if (e.caxis.value < -8000) {
                                        radio_header_focus = 0;
                                        last_joy_move = current_time;
                                    } else if (e.caxis.value > 8000) {
                                        radio_header_focus = 1;
                                        last_joy_move = current_time;
                                    }
                                }
                            }
                        }
                    } else if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                        if (now_playing_focusable_widgets != null) {
                            if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTX) {
                                if (current_time > last_joy_move + 200) {
                                    last_joy_move = current_time;
                                    if (now_playing_focused_widget_index <= 1) { // Top bar
                                        now_playing_focused_widget_index =
                                            (now_playing_focused_widget_index == 0) ? 1 : 0;
                                    } else { // Player controls
                                        if (e.caxis.value < -8000) { // Left
                                            now_playing_focused_widget_index--;
                                            if (now_playing_focused_widget_index < 2) {
                                                now_playing_focused_widget_index =
                                                    now_playing_focusable_widgets.size - 1;
                                            }
                                        } else if (e.caxis.value > 8000) { // Right
                                            now_playing_focused_widget_index++;
                                            if (now_playing_focused_widget_index >=
                                                now_playing_focusable_widgets.size) {
                                                now_playing_focused_widget_index = 2;
                                            }
                                        }
                                    }
                                }
                            } else if (e.caxis.axis == SDL.Input.GameController.Axis.LEFTY) {
                                if (current_time > last_joy_move + 200) {
                                    last_joy_move = current_time;
                                    if (e.caxis.value < -8000) { // Up
                                        if (now_playing_focused_widget_index >= 2) {
                                            now_playing_focused_widget_index = 0;
                                        }
                                    } else if (e.caxis.value > 8000) { // Down
                                        if (now_playing_focused_widget_index <= 1) {
                                            now_playing_focused_widget_index = 2;
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
                    is_track_list_focused = false;
                    library_header_focus = 0;
                    main_toolbar_focused = false;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_TO_MAIN) {
                screen_offset_x += TRANSITION_SPEED / 60.0f; // Move to the right
                if (screen_offset_x >= 0) {
                    screen_offset_x = 0;
                    current_screen = Vinyl.Utils.Screen.MAIN;
                    main_toolbar_focused = false;
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
                    is_track_list_focused = false;
                    library_header_focus = is_playing ? 1 : 0;
                }
            } else if (current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_MAIN) {
                screen_offset_x += TRANSITION_SPEED / 60.0f; // Move to the right
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
            }
            update_focus ();

            if (current_screen == Vinyl.Utils.Screen.NOW_PLAYING) {
                if (player != null && now_playing_widget != null) {
                    // Update play/pause icon
                    if (player.is_playing ()) {
                        now_playing_widget.player_controls.play_pause_button.set_texture (
                            renderer, Constants.PAUSE_TB_ICON_PATH);
                    } else {
                        now_playing_widget.player_controls.play_pause_button.set_texture (
                            renderer, Constants.PLAY_TB_ICON_PATH);
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

            if (current_screen == Vinyl.Utils.Screen.RADIO ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_RADIO ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_TO_MAIN) {
                render_radio_screen ((int)screen_offset_x + SCREEN_WIDTH);
            } else {
                render_library_screen ((int)screen_offset_x + SCREEN_WIDTH);
                render_now_playing_screen ((int)screen_offset_x + SCREEN_WIDTH * 2);
            }

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

        private void render_radio_screen (int x_offset) {
            var viewport = SDL.Video.Rect () { x = x_offset, y = 0, w = SCREEN_WIDTH, h = SCREEN_HEIGHT };
            renderer.set_viewport (viewport);

            renderer.set_draw_color (40, 40, 50, 255);
            renderer.fill_rect (null);

            if (radio_station_list != null) {
                radio_station_list.render (renderer, font, font_small);
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
                render_text (Config.PROJECT_NAME, (SCREEN_WIDTH / 2) - 50, 25, true);
                exit_button.render (renderer);
                if (is_playing) {
                    now_playing_button.render (renderer);
                }
            } else if (
                current_screen == Vinyl.Utils.Screen.LIBRARY ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_LIBRARY
            ) {
                render_text ("My Music", (SCREEN_WIDTH / 2) - 80, 25, true);
                back_button.render (renderer);
                if (is_playing) {
                    now_playing_button.render (renderer);
                }
            } else if (
                current_screen == Vinyl.Utils.Screen.RADIO ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_RADIO ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_RADIO_TO_MAIN
            ) {
                render_text ("Radio", (SCREEN_WIDTH / 2) - 50, 25, true);
                back_button.render (renderer);
                if (is_playing) {
                    now_playing_button.render (renderer);
                }
            } else if (
                current_screen == Vinyl.Utils.Screen.NOW_PLAYING ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_TO_NOW_PLAYING ||
                current_screen == Vinyl.Utils.Screen.TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY
            ) {
                if (track_list != null) {
                    var text = "Now Playing • %d of %d".printf (
                        track_list.focused_index + 1, track_list.get_total_items ());
                    render_text (text, (SCREEN_WIDTH / 2) - 150, 25, true);
                }
                back_button.render (renderer);
                playlist_button.render (renderer);
            }
        }

        private void update_focus () {
            if (current_screen == Vinyl.Utils.Screen.MAIN) {
                if (!is_playing && (main_toolbar_focused || main_toolbar_index != 0)) {
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
                        now_playing_button.focused = is_playing && main_toolbar_index == 1;
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
            } else if (current_screen == Vinyl.Utils.Screen.LIBRARY) {
                // Unfocus all main screen widgets
                foreach (var widget in focusable_widgets) {
                    if (widget is Vinyl.Widgets.MenuButton) {
                        ((Vinyl.Widgets.MenuButton) widget).focused = false;
                    } else if (widget is Vinyl.Widgets.ToolbarButton) {
                        ((Vinyl.Widgets.ToolbarButton) widget).focused = false;
                    }
                }

                if (!is_playing && library_header_focus != 0) {
                    library_header_focus = 0;
                }
                if (back_button != null) {
                    back_button.focused = !is_track_list_focused && library_header_focus == 0;
                }
                if (now_playing_button != null) {
                    now_playing_button.focused = !is_track_list_focused && is_playing && library_header_focus == 1;
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

                if (!is_playing && radio_header_focus != 0) {
                    radio_header_focus = 0;
                }
                if (back_button != null) {
                    back_button.focused = !is_radio_list_focused && radio_header_focus == 0;
                }
                if (now_playing_button != null) {
                    now_playing_button.focused = !is_radio_list_focused && is_playing && radio_header_focus == 1;
                }
                if (radio_station_list != null) {
                    radio_station_list.is_focused = is_radio_list_focused;
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
            }
        }

        private void start_radio (Vinyl.Radio.RadioStation station) {
            if (player != null) {
                player.stop ();
            }
            radio_player.play_station (station);
            radio_station_list.active_station_code = station.country_code;
        }

        private void stop_radio () {
            if (radio_player != null) {
                radio_player.stop ();
            }
            if (radio_station_list != null) {
                radio_station_list.active_station_code = null;
            }
        }

        private void apply_seek_ui_sync () {
            if (player != null && now_playing_widget != null) {
                last_progress_update = SDL.Timer.get_ticks ();
                now_playing_widget.sync_ui_after_relative_seek (player);
            }
        }

        private void sync_track_list_focus_from_player () {
            if (track_list == null || now_playing_widget == null || player == null) {
                return;
            }
            int idx = player.get_current_track_index ();
            track_list.focused_index = idx;
            now_playing_widget.player_controls.update_state (idx, track_list.get_total_items ());
        }

        private void build_now_playing_focusable_widgets () {
            var c = now_playing_widget.player_controls;
            now_playing_focusable_widgets = new Gee.ArrayList<Object> ();
            now_playing_focusable_widgets.add (back_button);
            now_playing_focusable_widgets.add (playlist_button);
            now_playing_focusable_widgets.add (c.prev_button);
            now_playing_focusable_widgets.add (c.rewind_button);
            now_playing_focusable_widgets.add (c.play_pause_button);
            now_playing_focusable_widgets.add (c.forward_button);
            now_playing_focusable_widgets.add (c.next_button);
            now_playing_focusable_widgets.add (c.volume_down_button);
            now_playing_focusable_widgets.add (c.volume_up_button);
            now_playing_focused_widget_index = 4; // Focus play button
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

        private void on_player_state_changed (bool is_playing) {
            this.is_playing = is_playing;
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
            main_menu_buttons.clear ();
            main_menu_buttons = null;
            focusable_widgets.clear ();
            focusable_widgets = null;
            radio_station_list = null;
            radio_player = null;
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
