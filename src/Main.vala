/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2016 Juan Pablo Lozano <libredeb@gmail.com>
 */

using Gst;

public int main (string[] args) {
    Gst.init (ref args);
    var app = new Vinyl.Application ();
    return app.run (args);
}
