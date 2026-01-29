import std/[dynlib]

## This module provides bindings for GSettings from libgio.
## It is used in `icons` module to get system icon theme.


type
  GSettingsPtr = pointer
  GSettings = object
    handle: GSettingsPtr

  GSettingsNewFunc = proc(schema: cstring): GSettingsPtr {.gcsafe, stdcall.}
  GSettingsGetStringFunc = proc(settings: GSettingsPtr, key: cstring): cstring {.gcsafe, stdcall.}
  GObjectUnrefFunc = proc(obj: GSettingsPtr) {.gcsafe, stdcall.}


let
  gioHandle = loadLibPattern("libgio-2.0.so(|.0)")
  gsettingsNew = cast[GSettingsNewFunc](gioHandle.symAddr("g_settings_new"))
  gsettingsGetString = cast[GSettingsGetStringFunc](gioHandle.symAddr("g_settings_get_string"))
  gobjectUnref = cast[GObjectUnrefFunc](gioHandle.symAddr("g_object_unref"))


proc newSettings*(schema: string): GSettings =
  if gioHandle != nil:
    result.handle = gsettingsNew(schema.cstring)


proc getString*(settings: GSettings, key: string): string =
  if gioHandle != nil:
    return $gsettingsGetString(settings.handle, key.cstring)


proc `=destroy`(settings: var GSettings) =
  if gioHandle != nil:
    try: gobjectUnref(settings.handle) except: discard
