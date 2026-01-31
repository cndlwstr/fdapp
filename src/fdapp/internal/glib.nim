import std/[dynlib, macros]

##[
  This module provides partial bindings for GLib.

  It is used internally for most of functionality of fdapp.
  You only need to import this module to call `iterate` manually when not importing the main fdapp module (see `test_icons.nim` for example).
]##


type
  GError* = ptr object
    domain*: cuint
    code*: cint
    message*: cstring

  GDBusNodeInfo* = ptr object
    refCount: cint
    path: cstring
    interfaces*: ptr UncheckedArray[pointer]
    nodes: ptr UncheckedArray[pointer]
    annotations: ptr UncheckedArray[pointer]

  # --- GObject ---
  GObject* = ptr object
  GObjectUnrefFunc = proc(obj: GObject) {.stdcall, gcsafe.}
  GObjectSignalConnectDataFunc = proc(obj: GObject, signal: cstring, handler: proc() {.cdecl.}, data, destroyData: pointer, connectFlags: cint): culong {.stdcall, gcsafe.}

  # --- GMainContext ---
  GMainContext* = ptr object
  GMainContextNewFunc = proc(): GMainContext {.stdcall, gcsafe.}
  GMainContextThreadDefaultFunc = proc(context: GMainContext) {.stdcall, gcsafe.}
  GMainContextIterationFunc = proc(context: GMainContext, mayBlock: cint): cint {.stdcall, gcsafe.}

  # --- GVariant ---
  GVariant* = ptr object
  GVariantType* = ptr object
  GVariantIter* = ptr object

  GVariantGetFunc = proc(value: GVariant, format: cstring) {.stdcall, gcsafe, varargs.}
  GVariantGetStringFunc = proc(value: GVariant, length: ptr csize_t): cstring {.stdcall, gcsafe.}
  GVariantLookupValueFunc = proc(dictionary: GVariant, key: cstring, expectedType: GVariantType): GVariant {.stdcall, gcsafe.}
  GVariantUnrefFunc = proc(value: GVariant) {.stdcall, gcsafe.}
  GVariantTypeNewFunc = proc(format: cstring): GVariantType {.stdcall, gcsafe.}
  GVariantIterInitFunc = proc(iter: GVariantIter, variant: GVariant): csize_t {.stdcall, gcsafe.}
  GVariantIterLoopFunc = proc(iter: GVariantIter, format: cstring): cint {.stdcall, gcsafe, varargs.}

  # --- GDBus ---
  GDBusConnection* = distinct GObject
  GDBusMethodInvocation* = distinct GObject
  GDBusCallback* = proc(connection: GDBusConnection, name: cstring, data: pointer) {.cdecl.}

  GDBusOwnNameFunc = proc(busType: cint, name: cstring, flags: cint, busAcquiredHandler, nameAcquiredHandler, nameLostHandler: GDBusCallback, data, dataFreeFunc: pointer): cuint {.stdcall, gcsafe.}
  GDBusInterfaceMethodCallFunc* = proc(connection: GDBusConnection, sender, objectPath, interfaceName, methodName: cstring, parameters: GVariant, invocation: GDBusMethodInvocation, data: pointer) {.cdecl.}
  GDBusInterfaceGetPropertyFunc* = proc(connection: GDBusConnection, sender, objectPath, interfaceName, propertyName: cstring, error: ptr GError, data: pointer): pointer {.cdecl.}
  GDBusInterfaceSetPropertyFunc* = proc(connection: GDBusConnection, sender, objectPath, interfaceName, propertyName: cstring, value: pointer, error: ptr GError, data: pointer): cint {.cdecl.}

  GDBusInterfaceVTable* = object
    methodCall*: GDBusInterfaceMethodCallFunc
    getProperty*: GDBusInterfaceGetPropertyFunc
    setProperty*: GDBusInterfaceSetPropertyFunc

  GDBusConnectionRegisterObjectFunc = proc(connection: GDBusConnection, objectPath: cstring, interfaceInfo: pointer, vtable: ptr GDBusInterfaceVTable, data, dataFreeFunc: pointer, error: ptr GError): cuint {.stdcall, gcsafe.}
  GDBusNodeInfoNewForXmlFunc = proc(xml: cstring, error: ptr GError): GDBusNodeInfo {.stdcall, gcsafe.}
  GDBusMethodInvocationReturnValueFunc = proc(invocation: GDBusMethodInvocation, parameters: GVariant) {.stdcall, gcsafe.}

  # --- GSettings ---
  GSettings* = distinct GObject
  GSettingsNewFunc = proc(schema: cstring): GSettings {.stdcall, gcsafe.}
  GSettingsGetStringFunc = proc(settings: GSettings, key: cstring): cstring {.stdcall, gcsafe.}


let gioHandle = loadLibPattern("libgio-2.0.so(|.0)")
assert gioHandle != nil

let
  # --- GObject ---
  unrefObject* = cast[GObjectUnrefFunc](gioHandle.symAddr("g_object_unref"))
  connect* = cast[GObjectSignalConnectDataFunc](gioHandle.symAddr("g_signal_connect_data"))

  # --- GMainContext ---
  newGMainContext = cast[GMainContextNewFunc](gioHandle.symAddr("g_main_context_new"))
  pushThreadDefault = cast[GMainContextThreadDefaultFunc](gioHandle.symAddr("g_main_context_push_thread_default"))
  popThreadDefault = cast[GMainContextThreadDefaultFunc](gioHandle.symAddr("g_main_context_pop_thread_default"))
  iteration = cast[GMainContextIterationFunc](gioHandle.symAddr("g_main_context_iteration"))
  glibContext* = newGMainContext()
    ## Separate `GMainContext` to be used by the library.
    ## If your application uses GLib, you should not worry that fdapp will mess with your app's context, because it uses its own.

  # --- GVariant ---
  get* = cast[GVariantGetFunc](gioHandle.symAddr("g_variant_get"))
  lookupValue* = cast[GVariantLookupValueFunc](gioHandle.symAddr("g_variant_lookup_value"))
  getString* = cast[GVariantGetStringFunc](gioHandle.symAddr("g_variant_get_string"))
  unrefVariant* = cast[GVariantUnrefFunc](gioHandle.symAddr("g_variant_unref"))
  newGVariantType* = cast[GVariantTypeNewFunc](gioHandle.symAddr("g_variant_type_new"))
  init* = cast[GVariantIterInitFunc](gioHandle.symAddr("g_variant_iter_init"))
  loop* = cast[GVariantIterLoopFunc](gioHandle.symAddr("g_variant_iter_loop"))

  # --- GDBus ---
  newGDBusNodeInfoForXml* = cast[GDBusNodeInfoNewForXmlFunc](gioHandle.symAddr("g_dbus_node_info_new_for_xml"))
  gbusOwnName* = cast[GDBusOwnNameFunc](gioHandle.symAddr("g_bus_own_name"))
  registerObject* = cast[GDBusConnectionRegisterObjectFunc](gioHandle.symAddr("g_dbus_connection_register_object"))
  returnValue* = cast[GDBusMethodInvocationReturnValueFunc](gioHandle.symAddr("g_dbus_method_invocation_return_value"))

  # --- GSettings ---
  newGSettings* = cast[GSettingsNewFunc](gioHandle.symAddr("g_settings_new"))
  gsettingsGetString* = cast[GSettingsGetStringFunc](gioHandle.symAddr("g_settings_get_string"))


proc withGlibContextImpl(actions: NimNode): NimNode =
  result = newStmtList()
  result.add newCall(bindSym"pushThreadDefault", bindSym"glibContext")
  result.add actions
  result.add newCall(bindSym"popThreadDefault", bindSym"glibContext")


macro withGlibContext*(actions: untyped) =
  ## Sets fdapp's Glib context to be the current one, then executes `actions` and switches back current context.

  withGlibContextImpl(actions)


proc iterate*(context: GMainContext) =
  ## Non-blocking iteration of `context`

  discard context.iteration(0)
