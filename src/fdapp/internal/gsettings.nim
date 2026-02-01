##[
    This module provides access to GSettings.

    It is used internally by `fdapp/icons <../icons.html>`_.
]##

import glib {.all.}

{.push hint[XDeclaredButNotUsed]: off.}


proc newSettings(schema: string): GSettings =
  withGlibContext:
    result = newGSettings(schema)


proc get(settings: GSettings, key: string): string =
  withGlibContext:
    result = $settings.getString(key)


template onChanged(settings: GSettings, key: string, actions: untyped) =
  withGlibContext:
    discard settings.getString(key) # GLib will only emit signal if the key was read at least once
    let connection = glib.connect(cast[GObject](settings), "changed::icon-theme", proc() {.cdecl.} = actions, nil, nil, 0)
    doAssert connection > 0

{.pop.}
