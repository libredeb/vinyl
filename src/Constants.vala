/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2016 Juan Pablo Lozano <libredeb@gmail.com>
 */

//Here are declared the constants
namespace Constants {
    public const string VINYL_DATADIR = Config.PACKAGE_SHAREDIR + "/" + Config.PROJECT_NAME;
    public const string BACK_ICON_PATH = VINYL_DATADIR + "/gfx/back_icon.png";
    public const string EXIT_ICON_PATH = VINYL_DATADIR + "/gfx/exit_icon.png";
    public const string LIBRARY_ICON_PATH = VINYL_DATADIR + "/gfx/library_icon.png";
    public const string RADIO_ICON_PATH = VINYL_DATADIR + "/gfx/radio_icon.png";
    public const string SEARCH_ICON_PATH = VINYL_DATADIR + "/gfx/search_icon.png";
    public const string ARROW_RIGHT_ICON_PATH = VINYL_DATADIR + "/gfx/arrow_right.png";
    public const string BACK_TB_ICON_PATH = VINYL_DATADIR + "/gfx/back_tb.png";
    public const string EXIT_TB_ICON_PATH = VINYL_DATADIR + "/gfx/exit_tb.png";
    public const string PLAYLIST_TB_ICON_PATH = VINYL_DATADIR + "/gfx/playlist_tb.png";
    public const string TOOLBAR_BUTTON_BG_PATH = VINYL_DATADIR + "/gfx/toolbar_button_bg.png";
    public const string TOOLBAR_BUTTON_BG_PRESS_PATH = VINYL_DATADIR + "/gfx/toolbar_button_bg_press.png";
    public const string DEFAULT_COVER_ICON_PATH = VINYL_DATADIR + "/gfx/default_cover.png";
    public const string FONT_PATH = VINYL_DATADIR + "/fonts/FreeSans.ttf";
    public const string FONT_BOLD_PATH = VINYL_DATADIR + "/fonts/FreeSansBold.ttf";
    public const string[] SUPPORTED_FORMATS = {
        ".mp3", ".flac", ".ogg", ".wav"
    };
}
