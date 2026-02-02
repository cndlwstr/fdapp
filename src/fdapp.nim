import std/[cmdline, sequtils, strformat, strutils]
import fdapp/[icons, internal/glib {.all.}]
export icons

##[
  Main fdapp module provides a way to create an application that runs a DBus service under a well-known name.

  Use `fdappInit`_ to initialize. By default, 3 interfaces are provided on DBus:

    * `org.freedesktop.Application`

      Allows the user's desktop environment to launch your application using DBus, optionally sending arguments. See the spec `here <https://specifications.freedesktop.org/desktop-entry/latest/dbus.html>`_.

    * `com.canonical.Unity.LauncherEntry`

      Allows to modify your app's taskbar icon by showing a counter or a progress bar, or setting the icon into urgent state (quicklists are not supported by fdapp). You should never expect these modifications to be shown since not all desktop environments and taskbars support Unity Launcher API. See the spec `here <https://wiki.ubuntu.com/Unity/LauncherAPI>`_.

      For testing purposes or when building for environments where desktop file name doesn't match app ID (for example, in Snap packages), define `UnityDesktopFile` to be the filename (just name, not path) of your desktop file.

    * a custom interface that provides `CommandLine` method

      The interface will have the name matching your app ID. The purpose of `CommandLine` method is to pass command-line arguments that are not file paths or URIs. This is a non-standard addition that will not be used by desktop environments, but may be useful if you want your app to parse custom command-line arguments.

  Each interface can be disabled, but not both `org.freedesktop.Application` and the custom interface at the same time.

  Running a DBus service under a well-known name means that your application will become single-instance. But this doesn't mean it has to be a single-window app, see `SDL2 example <https://github.com/cndlwstr/fdapp/blob/main/examples/fdapp_sdl2.nim>`_ to get the idea of how a multi-window app can be implemented.

  In case when your application fails to own a name after start (because there's already an instance running), it will call a method on the running instance:

    * if there is no arguments passed, `Activate` will be called or, if `org.freedesktop.Application` interface is disabled, `CommandLine` will be called;
    * if there are some arguments passed, the app will check if all of them are URIs or file paths:
        * if yes, `Open` will be called or, if `org.freedesktop.Application` interface is disabled, `CommandLine` will be called.
        * if no, `CommandLine` will be called or, if the custom interface is disabled, `Activate` will be called (without passing arguments).

  For the functionality of this module to work, you must call `fdappIterate`_ in your application's loop.
]##

type
  DBusInterface* = enum
    ## Represents a DBus interface
    orgFreedesktopApplication, ## `org.freedesktop.Application`
    comCanonicalUnity, ## `com.canonical.Unity.LauncherEntry`
    commandLine ## an interface with application ID as the name that provides `CommandLine` method

  DBusInterfaces* = set[DBusInterface]

  FreedesktopAppObj = object
    appId: string
    busId: cuint
    busConnection: GDBusConnection
    interfaces: DBusInterfaces

    # org.freedesktop.Application
    activateCallback: proc(startupId: string, activationToken: string)
    openCallback: proc(startupId: string, activationToken: string, uris: seq[string])
    activateActionCallback: proc(startupId: string, activationToken: string, actionName: string)

    # com.canonical.Unity.LauncherEntry
    appUri: string
    unityObjectPath: string
    unityParams: tuple[count: int64, progress: float64, urgent, countVisible, progressVisible: bool]

    # Custom interface
    commandLineCallback: proc(args: seq[string])

  FreedesktopApp* = ref FreedesktopAppObj
    ## Represents an application

  UnityParam = enum
    count, progress, urgent, countVisible = "count-visible", progressVisible = "progress-visible"


var dbusInfo: GDBusNodeInfo


proc `=destroy`(app: var FreedesktopAppObj) =
  if app.busId > 0: gbusUnownName(app.busId)
  dbusInfo.unref()


const
  SessionBus = 2
  DoNotQueue = 4
  FreedesktopAppXml = staticRead("fdapp/internal/dbus/org.freedesktop.Application.xml")
  UnityLauncherXml = staticRead("fdapp/internal/dbus/com.canonical.Unity.LauncherEntry.xml")
  CommandLineXml = staticRead("fdapp/internal/dbus/custom.xml")


proc dbusMethodCallCallback(connection: GDBusConnection, sender, objectPath, interfaceName, methodName: cstring, parameters: GVariant, invocation: GDBusMethodInvocation, data: pointer) {.cdecl.} =
  let app = cast[FreedesktopApp](data)

  proc getPlatformData(dict: GVariant): (string, string) =
    let t = newGVariantType("s")
    defer: t.free()

    let startupIdVariant = dict.lookupValue("desktop-startup-id", t)
    if cast[pointer](startupIdVariant) != nil:
      result[0] = $startupIdVariant.getString(nil)
      startupIdVariant.unref()

    let activationTokenVariant = dict.lookupValue("activation-token", t)
    if cast[pointer](activationTokenVariant) != nil:
      result[1] = $activationTokenVariant.getString(nil)
      activationTokenVariant.unref()

  if interfaceName == "org.freedesktop.Application":
    case methodName:
    of "Activate":
      if app.activateCallback != nil:
        let platformDict = parameters.getChildValue(0)
        let (startupId, activationToken) = getPlatformData(platformDict)
        platformDict.unref()

        app.activateCallback(startupId, activationToken)
    of "Open":
      if app.openCallback != nil:
        let
          urisArray = parameters.getChildValue(0)
          iter = newGVariantIter(urisArray)
        var
          item: cstring
          uris = newSeq[string]()
        while iter.loop("s", item.addr) > 0:
          uris.add($item)
        iter.free()

        let platformDict = parameters.getChildValue(1)
        let (startupId, activationToken) = getPlatformData(platformDict)
        platformDict.unref()

        app.openCallback(startupId, activationToken, uris)
    of "ActivateAction":
      if app.activateActionCallback != nil:
        let actionName = $(parameters.getChildValue(0).getString(nil))
        let platformDict = parameters.getChildValue(2)
        let (startupId, activationToken) = getPlatformData(platformDict)
        platformDict.unref()

        app.activateActionCallback(startupId, activationToken, actionName)
    else: discard
    invocation.returnValue(nil)
    return
  elif interfaceName == "com.canonical.Unity.LauncherEntry" and methodName == "Query":
    let t = newGVariantType("a{sv}")
    defer: t.free()
    let builder = newGVariantBuilder(t)
    defer: builder.unref()
    builder.add("{sv}", "count", newGVariant("x", app.unityParams.count.culong))
    builder.add("{sv}", "progress", newGVariant("d", app.unityParams.progress.cdouble))
    builder.add("{sv}", "urgent", newGVariant("b", if app.unityParams.urgent: 1 else: 0))
    builder.add("{sv}", "count-visible", newGVariant("b", if app.unityParams.countVisible: 1 else: 0))
    builder.add("{sv}", "progress-visible", newGVariant("b", if app.unityParams.progressVisible: 1 else: 0))
    invocation.returnValue(newGVariant("(sa{sv})", app.appUri.cstring, builder))
    return
  elif interfaceName == app.appId.cstring and methodName == "CommandLine":
    let
      argsArray = parameters.getChildValue(0)
      iter = newGVariantIter(argsArray)
    var
      item: cstring
      args = newSeq[string]()
    while iter.loop("s", item.addr) > 0:
      args.add($item)
    iter.free()
    app.commandLineCallback(args)
    invocation.returnValue(nil)
    return


const dbusVTable = GDBusInterfaceVTable(methodCall: dbusMethodCallCallback, getProperty: nil, setProperty: nil)


proc busAcquiredCallback(connection: GDBusConnection, name: cstring, data: pointer) {.cdecl.} =
  let app = cast[FreedesktopApp](data)
  app.busConnection = connection

  if orgFreedesktopApplication in app.interfaces:
    let freedesktopObjectPath = ("/" & app.appId.replace('-', '_').replace('.', '/')).cstring
    let freedesktopId = connection.registerObject(freedesktopObjectPath, dbusInfo.interfaces[0], dbusVTable.addr, data, nil, nil)
    doAssert freedesktopId > 0, fmt"Failed to register DBus object for path {$freedesktopObjectPath} and interface org.freedesktop.Application"

  if comCanonicalUnity in app.interfaces:
    proc djb2(s: string): uint64 =
      var hash: uint64 = 5381
      for c in s:
        hash = (hash shl 5) + hash + uint64(c)
      return hash

    app.unityObjectPath = "/com/canonical/unity/launcherentry/" & $app.appUri.djb2()
    let unityId = connection.registerObject(app.unityObjectPath.cstring, dbusInfo.interfaces[1], dbusVTable.addr, data, nil, nil)
    doAssert unityId > 0, "Failed to register DBus object for path" & app.unityObjectPath

  if commandLine in app.interfaces:
    let cmdLineObjectPath = ("/" & app.appId.replace('-', '_').replace('.', '/')).cstring
    let cmdLineId = connection.registerObject(cmdLineObjectPath, dbusInfo.interfaces[2], dbusVTable.addr, data, nil, nil)
    doAssert cmdLineId > 0, fmt"Failed to register DBus object for path {$cmdLineObjectPath} and interface {app.appId}"


proc nameLostCallback(connection: GDBusConnection, name: cstring, data: pointer) {.cdecl.} =
  let app = cast[FreedesktopApp](data)
  let objectPath = ("/" & app.appId.replace('-', '_').replace('.', '/')).cstring
  var error: GError
  var ret: GVariant

  var args: seq[string]
  when declared(commandLineParams):
    args = commandLineParams()

  if args.len > 0:
    let t = newGVariantType("as")
    defer: t.free()
    let builder = newGVariantBuilder(t)
    defer: builder.unref()
    for arg in args:
      builder.add("s", arg.cstring)

    let argsAreUris = args.filter(proc (arg: string): bool = arg.contains("://")).len == args.len
    let argsArePaths = args.filter(proc (arg: string): bool = arg.startsWith('/')).len == args.len
    if (argsAreUris or argsArePaths) and (orgFreedesktopApplication in app.interfaces):
      ret = connection.call(app.appId.cstring, objectPath, "org.freedesktop.Application", "Open", newGVariant("(asa{sv})", builder, nil), nil, 0, -1, nil, error.addr)
    elif commandLine in app.interfaces:
      ret = connection.call(app.appId.cstring, objectPath, app.appId.cstring, "CommandLine", newGVariant("(as)", builder), nil, 0, -1, nil, error.addr)
    else:
      ret = connection.call(app.appId.cstring, objectPath, "org.freedesktop.Application", "Activate", newGVariant("(a{sv})", nil), nil, 0, -1, nil, error.addr)
  else:
    if orgFreedesktopApplication in app.interfaces:
      ret = connection.call(app.appId.cstring, objectPath, "org.freedesktop.Application", "Activate", newGVariant("(a{sv})", nil), nil, 0, -1, nil, error.addr)
    else:
      ret = connection.call(app.appId.cstring, objectPath, app.appId.cstring, "CommandLine", newGVariant("(as)", nil), nil, 0, -1, nil, error.addr)

  if ret != nil:
    ret.unref()
    quit 0
  else:
    let msg = $error.message
    error.free()
    quit msg, 1


const UnityDesktopFile {.strdefine.} = ""


proc fdappInit*(id: static string, interfaces: static DBusInterfaces = {orgFreedesktopApplication, comCanonicalUnity, commandLine}): FreedesktopApp =
  ## Initialize fdapp.
  ##
  ## `id` must be a valid application id in reverse-DNS notation (for example, "io.github.cndlwstr.fdapp"). This id will be used as a well-known name on DBus to be owned and as a filename of the application's desktop file for Unity Launcher API (unless `UnityDesktopFile` is defined).
  ##
  ## `interfaces` is a set of interfaces to provide on DBus. All interfaces are enabled by default. The set must contain at least either `orgFreedesktopApplication <#DBusInterface>`_ or `commandLine <#DBusInterface>`_.

  static:
    doAssert id.len > 0, "Application ID can't be empty"
    doAssert id.count('.') >= 2, "Application ID must be in reverse-DNS format"
    doAssert (orgFreedesktopApplication in interfaces) or (commandLine in interfaces), "Cannot run single-instance app without either org.freedesktop.Application or custom command-line interface"

  result = new FreedesktopApp
  result.appId = id

  if UnityDesktopFile.len > 0:
    let desktopFile = if UnityDesktopFile.endsWith(".desktop"): UnityDesktopFile else: UnityDesktopFile & ".desktop"
    result.appUri = fmt"application://{desktopFile}"
  else:
    result.appUri = fmt"application://{id}.desktop"

  result.interfaces = interfaces
  let dbusXml = ("<node>" & FreedesktopAppXml & UnityLauncherXml & CommandLineXml.format(id) & "</node>").cstring

  withGlibContext:
    var err: GError
    dbusInfo = newGDBusNodeInfoForXml(dbusXml, err.addr)
    doAssert err == nil, $err.message

    result.busId = gbusOwnName(SESSION_BUS, id.cstring, DO_NOT_QUEUE, busAcquiredCallback, nil, nameLostCallback, result[].addr, nil)


proc fdappIterate*() =
  ## Non-blocking iteration of fdapp's context.
  ##
  ## You must call this in your app's loop.
  ##
  ## This is a shortcut for `glibContext.iterate <fdapp/internal/glib.html#glibContext>`_.

  glibContext.iterate()


proc ensureActivation(app: FreedesktopApp) =
  doAssert app.activateCallback != nil, "Attempt to activate application without activate callback set"
  while cast[pointer](app.busConnection) == nil:
    fdappIterate() # waiting for dbus connection


proc activate*(app: FreedesktopApp) =
  ## Calls `onActivate=`_ callback.

  app.ensureActivation()
  app.activateCallback("", "")


proc open*(app: FreedesktopApp, uris: seq[string]) =
  ## Calls `onOpen=`_ callback.

  app.ensureActivation()
  app.openCallback("", "", uris)


proc activateAction*(app: FreedesktopApp, actionName: string) =
  ## Calls `onAction=`_ callback.

  app.ensureActivation()
  app.activateActionCallback("", "", actionName)


proc commandLine*(app: FreedesktopApp, args: seq[string]) =
  ## Calls `onCommandLine=`_ callback.

  doAssert app.commandLineCallback != nil, "Attempt to send command-line arguments without command-line callback set"
  app.commandLineCallback(args)


proc `onActivate=`*(app: FreedesktopApp, callback: proc(startupId, activationToken: string)) =
  ## Sets a callback for Activate method on `org.freedesktop.Application` interface.
  ##
  ## See `the spec <https://specifications.freedesktop.org/desktop-entry/latest/dbus.html>`_ for details on `startupId` and `activationToken`.
  ##
  ## If callbacks for other DBus methods are not set, calling these methods will fall back to using this `callback`.

  app.activateCallback = callback
  if app.openCallback == nil:
    app.openCallback = proc(startupId, activationToken: string, _: seq[string]) = callback(startupId, activationToken)
  if app.activateActionCallback == nil:
    app.activateActionCallback = proc(startupId, activationToken: string, _: string) = callback(startupId, activationToken)
  if app.commandLineCallback == nil:
    app.commandLineCallback = proc(_: seq[string]) = callback("", "")


template onActivate*(app: FreedesktopApp, actions: untyped) =
  ## Sets a callback for Activate method on `org.freedesktop.Application` interface.
  ##
  ## This is a shortcut for `onActivate=`_. Parameters `startupId` and `activationToken` are injected.

  app.onActivate = proc(startupId {.inject.}, activationToken {.inject.}: string) = actions


proc `onOpen=`*(app: FreedesktopApp, callback: proc(startupId, activationToken: string, uris: seq[string])) =
  ## Sets a callback for Open method on `org.freedesktop.Application` interface.
  ##
  ## See `the spec <https://specifications.freedesktop.org/desktop-entry/latest/dbus.html>`_ for details on `startupId` and `activationToken`.
  ##
  ## `uris` is a sequence of URIs to open. Take note that local files may either be passed in a form of `file://...` URIs or as file paths when `%u` or `%U` field is used in your application's desktop file (see details `here <https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html>`_).

  app.openCallback = callback


template onOpen*(app: FreedesktopApp, actions: untyped) =
  ## Sets a callback for Open method on `org.freedesktop.Application` interface.
  ##
  ## This is a shortcut for `onOpen=`_. Parameters `startupId`, `activationToken` and `uris` are injected.

  app.onOpen = proc(startupId {.inject.}, activationToken {.inject.}: string, uris {.inject.}: seq[string]) = actions


proc `onAction=`*(app: FreedesktopApp, callback: proc(startupId, activationToken, actionName: string)) =
  ## Sets a callback for ActivateAction method on `org.freedesktop.Application` interface.
  ##
  ## See `the spec <https://specifications.freedesktop.org/desktop-entry/latest/dbus.html>`_ for details on `startupId` and `activationToken`.
  ##
  ## `actionName` is the name of the action.
  ##
  ## While the interface method includes argument `parameter` with type `av`, it's unclear from the spec what it is used for. Current fdapp implementation completely ignores it and doesn't pass to the callback. Please open an issue if you know why and how this should be changed.

  app.activateActionCallback = callback


template onAction*(app: FreedesktopApp, actions: untyped) =
  ## Sets a callback for ActivateAction method on `org.freedesktop.Application` interface.
  ##
  ## This is a shortcut for `onAction=`_. Parameters `startupId`, `activationToken` and `actionName` are injected.

  app.onAction = proc(startupId {.inject.}, activationToken {.inject.}, actionName {.inject.}: string) = actions


proc `onCommandLine=`*(app: FreedesktopApp, callback: proc(args: seq[string])) =
  ## Sets a callback for CommandLine method on the custom interface.
  ##
  ## `args` is a sequence of command-line arguments.

  app.commandLineCallback = callback


template onCommandLine*(app: FreedesktopApp, actions: untyped) =
  ## Sets a callback for CommandLine method on the custom interface.
  ##
  ## This is a shortcut for `onCommandLine=`_. Parameter `args` is injected.

  app.commandLineCallback = proc(args {.inject.}: seq[string]) = actions


proc emitUnityUpdate(app: FreedesktopApp, param: UnityParam) =
  if not (comCanonicalUnity in app.interfaces):
    return

  let t = newGVariantType("a{sv}")
  defer: t.free()
  let builder = newGVariantBuilder(t)
  defer: builder.unref()
  let name = ($param).cstring

  case param
  of count:
    builder.add("{sv}", name, newGVariant("x", app.unityParams.count.culong))
  of progress:
    builder.add("{sv}", name, newGVariant("d", app.unityParams.progress.cdouble))
  of urgent:
    builder.add("{sv}", name, newGVariant("b", if app.unityParams.urgent: 1 else: 0))
  of countVisible:
    builder.add("{sv}", name, newGVariant("b", if app.unityParams.countVisible: 1 else: 0))
  of progressVisible:
    builder.add("{sv}", name, newGVariant("b", if app.unityParams.progressVisible: 1 else: 0))

  let params = newGVariant("(sa{sv})", app.appUri.cstring, builder)
  discard app.busConnection.emitSignal(nil, app.unityObjectPath.cstring, "com.canonical.Unity.LauncherEntry", "Update", params, nil)


proc setTaskbarCount*(app: FreedesktopApp, value: int64) =
  ## Sets `value` for counter in taskbar icon using Unity Launcher API.
  ##
  ## Do not forget to call `setTaskbarCountVisible`_ to enable showing counter in taskbar.
  ##
  ## When `comCanonicalUnity <#DBusInterface>`_ is not enabled in `fdappInit`_, this has no effect.

  app.unityParams.count = value
  app.emitUnityUpdate(count)


proc setTaskbarProgress*(app: FreedesktopApp, value: float64) =
  ## Sets `value` for progress bar in taskbar icon using Unity Launcher API.
  ##
  ## `value` must be in range `0.0..1.0`.
  ##
  ## Do not forget to call `setTaskbarProgressVisible`_ to enable showing progress bar in taskbar.
  ##
  ## When `comCanonicalUnity <#DBusInterface>`_ is not enabled in `fdappInit`_, this has no effect.

  assert value >= 0.0 and value <= 1.0
  app.unityParams.progress = value
  app.emitUnityUpdate(progress)


proc setTaskbarUrgent*(app: FreedesktopApp, value: bool) =
  ## Sets whether urgent state in taskbar icon should be enabled using Unity Launcher API.
  ##
  ## When `comCanonicalUnity <#DBusInterface>`_ is not enabled in `fdappInit`_, this has no effect.

  app.unityParams.urgent = value
  app.emitUnityUpdate(urgent)


proc setTaskbarCountVisible*(app: FreedesktopApp, value: bool) =
  ## Sets visibility of counter in taskbar icon using Unity Launcher API.
  ##
  ## When `comCanonicalUnity <#DBusInterface>`_ is not enabled in `fdappInit`_, this has no effect.

  app.unityParams.countVisible = value
  app.emitUnityUpdate(countVisible)


proc setTaskbarProgressVisible*(app: FreedesktopApp, value: bool) =
  ## Sets visibility of progress bar in taskbar icon using Unity Launcher API.
  ##
  ## When `comCanonicalUnity <#DBusInterface>`_ is not enabled in `fdappInit`_, this has no effect.

  app.unityParams.progressVisible = value
  app.emitUnityUpdate(progressVisible)


proc resetTaskbar*(app: FreedesktopApp) =
  ## Resets taskbar icon state using Unity Launcher API.
  ##
  ## If your application uses other methods to modify taskbar icon, it's suggested to call this before your application quits as it is not guaranteed that the user's taskbar will reset the icon automatically.

  app.setTaskbarCount(0)
  app.setTaskbarProgress(0.0)
  app.setTaskbarUrgent(false)
  app.setTaskbarCountVisible(false)
  app.setTaskbarProgressVisible(false)

