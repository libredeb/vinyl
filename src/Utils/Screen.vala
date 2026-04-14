/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2016 Juan Pablo Lozano <libredeb@gmail.com>
 */
namespace Vinyl.Utils {
    public enum Screen {
        MAIN,
        LIBRARY,
        NOW_PLAYING,
        RADIO,
        TRANSITION_TO_LIBRARY,
        TRANSITION_TO_MAIN,
        TRANSITION_TO_NOW_PLAYING,
        TRANSITION_FROM_NOW_PLAYING_TO_LIBRARY,
        TRANSITION_FROM_NOW_PLAYING_TO_MAIN,
        TRANSITION_TO_RADIO,
        TRANSITION_FROM_RADIO_TO_MAIN,
        RADIO_NOW_PLAYING,
        TRANSITION_TO_RADIO_NOW_PLAYING,
        TRANSITION_FROM_RADIO_NOW_PLAYING_TO_RADIO,
        TRANSITION_FROM_RADIO_NOW_PLAYING_TO_MAIN
    }
}
