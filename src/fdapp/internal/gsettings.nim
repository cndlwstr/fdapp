##[
    This module provides access to GSettings.

    While you can use this module for your own purposes, take note it only supports working with string type values, because fdapp only needs that internally.
]##

import glib


proc newSettings*(schema: string): GSettings =
  withGlibContext:
    result = newGSettings(schema.cstring)


proc getString*(settings: GSettings, key: string): string =
  withGlibContext:
    result = $gsettingsGetString(settings, key.cstring)


template onChanged*(settings: GSettings, key: string, actions: untyped) =
  withGlibContext:
    discard settings.getString(key) # GLib will only emit signal if the key was read at least once
    let connection = glib.connect(cast[GObject](settings), "changed::icon-theme", proc() {.cdecl.} = actions, nil, nil, 0)
    assert connection > 0
