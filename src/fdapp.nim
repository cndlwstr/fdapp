import std/[strformat, strutils]
import fdapp/[icons, internal/glib]
export icons


type
  UnityParam = enum
    count, progress, urgent, countVisible = "count-visible", progressVisible = "progress-visible"

  FreedesktopAppObj = object
    appId: string
    busId: cuint
    busConnection: GDBusConnection

    # org.freedesktop.Application
    activateCallback: proc(startupId: string, activationToken: string)
    openCallback: proc(startupId: string, activationToken: string, uris: seq[string])
    activateActionCallback: proc(startupId: string, activationToken: string, actionName: string)

    # com.canonical.Unity.LauncherEntry
    appUri: string
    unityObjectPath: string
    unityParams: tuple[count: int64, progress: float64, urgent, countVisible, progressVisible: bool]

  FreedesktopApp* = ref FreedesktopAppObj


var dbusInfo: GDBusNodeInfo


proc `=destroy`(app: var FreedesktopAppObj) =
  if app.busId > 0: gbusUnownName(app.busId)
  dbusInfo.unref()


const
  SESSION_BUS = 2
  DO_NOT_QUEUE = 4
  FREEDESKTOP_APP_XML = staticRead("fdapp/internal/dbus/org.freedesktop.Application.xml")
  UNITY_LAUNCHER_XML = staticRead("fdapp/internal/dbus/com.canonical.Unity.LauncherEntry.xml")


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

  invocation.returnValue(nil)


const dbusVTable = GDBusInterfaceVTable(methodCall: dbusMethodCallCallback, getProperty: nil, setProperty: nil)


proc busAcquiredCallback(connection: GDBusConnection, name: cstring, data: pointer) {.cdecl.} =
  let app = cast[FreedesktopApp](data)
  app.busConnection = connection

  let freedesktopObjectPath = ("/" & app.appId.replace('-', '_').replace('.', '/')).cstring
  let freedesktopId = connection.registerObject(freedesktopObjectPath, dbusInfo.interfaces[0], dbusVTable.addr, data, nil, nil)
  doAssert freedesktopId > 0, "Failed to register DBus object for path " & $freedesktopObjectPath

  proc djb2(s: string): uint64 =
    var hash: uint64 = 5381
    for c in s:
      hash = (hash shl 5) + hash + uint64(c)
    return hash

  app.unityObjectPath = "/com/canonical/unity/launcherentry/" & $app.appUri.djb2()
  let unityId = connection.registerObject(app.unityObjectPath.cstring, dbusInfo.interfaces[1], dbusVTable.addr, data, nil, nil)
  doAssert unityId > 0, "Failed to register DBus object for path" & app.unityObjectPath


proc nameLostCallback(connection: GDBusConnection, name: cstring, data: pointer) {.cdecl.} =
  let app = cast[FreedesktopApp](data)
  let objectPath = ("/" & app.appId.replace('-', '_').replace('.', '/')).cstring
  var error: GError
  var ret: GVariant

  ret = connection.call(app.appId.cstring, objectPath, "org.freedesktop.Application", "Activate", newGVariant("(a{sv})", nil), nil, 0, -1, nil, error.addr)

  if ret != nil:
    ret.unref()
    quit 0
  else:
    let msg = $error.message
    error.free()
    quit msg, 1


const UnityDesktopFile {.strdefine.} = ""


proc fdappInit*(id: string): FreedesktopApp =
  doAssert id.len > 0, "Application ID can't be empty"
  doAssert id.count('.') >= 2, "Application ID must be in reverse-DNS format"

  result = new FreedesktopApp
  result.appId = id

  when defined(UnityDesktopFile):
    let desktopFile = if UnityDesktopFile.endsWith(".desktop"): UnityDesktopFile else: UnityDesktopFile & ".desktop"
    result.appUri = fmt"application://{desktopFile}"
  else:
    result.appUri = fmt"application://{id}.desktop"

  var dbusXml = fmt"<node>{FREEDESKTOP_APP_XML}{UNITY_LAUNCHER_XML}</node>".cstring
  withGlibContext:
    var err: GError
    dbusInfo = newGDBusNodeInfoForXml(dbusXml, err.addr)
    doAssert err == nil, $err.message

    result.busId = gbusOwnName(SESSION_BUS, id.cstring, DO_NOT_QUEUE, busAcquiredCallback, nil, nameLostCallback, result[].addr, nil)


proc fdappIterate*() =
  ## Non-blocking iteration of fdapp's context.
  ##
  ## You must call this in your app's event loop.

  glibContext.iterate()


proc ensureActivation(app: FreedesktopApp) =
  doAssert app.activateCallback != nil, "Attempt to activate application without activate callback set"
  while cast[pointer](app.busConnection) == nil:
    fdappIterate() # waiting for dbus connection


proc activate*(app: FreedesktopApp) =
  app.ensureActivation()
  app.activateCallback("", "")


proc open*(app: FreedesktopApp, uris: seq[string]) =
  app.ensureActivation()
  app.openCallback("", "", uris)


proc activateAction*(app: FreedesktopApp, actionName: string) =
  app.ensureActivation()
  app.activateActionCallback("", "", actionName)


template onActivate*(app: FreedesktopApp, actions: untyped) =
  let activateCallback = proc(startupId {.inject.}, activationToken {.inject.}: string) = actions
  app.activateCallback = activateCallback
  if app.openCallback == nil:
    app.openCallback = proc(startupId {.inject.}, activationToken {.inject.}: string, _: seq[string]) = activateCallback(startupId, activationToken)
  if app.activateActionCallback == nil:
    app.activateActionCallback = proc(startupId {.inject.}, activationToken {.inject.}: string, _: string) = activateCallback(startupId, activationToken)


template onOpen*(app: FreedesktopApp, actions: untyped) =
  let openCallback = proc(startupId {.inject.}, activationToken {.inject.}: string, uris {.inject.}: seq[string]) = actions
  app.openCallback = openCallback


template onAction*(app: FreedesktopApp, actions: untyped) =
  let activateActionCallback = proc(startupId {.inject.}, activationToken {.inject.}, actionName {.inject.}: string) = actions
  app.activateActionCallback = activateActionCallback


proc emitUnityUpdate(app: FreedesktopApp, param: UnityParam) =
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
  app.unityParams.count = value
  app.emitUnityUpdate(count)


proc setTaskbarProgress*(app: FreedesktopApp, value: float64) =
  assert value >= 0.0 and value <= 1.0
  app.unityParams.progress = value
  app.emitUnityUpdate(progress)


proc setTaskbarUrgent*(app: FreedesktopApp, value: bool) =
  app.unityParams.urgent = value
  app.emitUnityUpdate(urgent)


proc setTaskbarCountVisible*(app: FreedesktopApp, value: bool) =
  app.unityParams.countVisible = value
  app.emitUnityUpdate(countVisible)


proc setTaskbarProgressVisible*(app: FreedesktopApp, value: bool) =
  app.unityParams.progressVisible = value
  app.emitUnityUpdate(progressVisible)


proc resetTaskbar*(app: FreedesktopApp) =
  app.setTaskbarCount(0)
  app.setTaskbarProgress(0.0)
  app.setTaskbarUrgent(false)
  app.setTaskbarCountVisible(false)
  app.setTaskbarProgressVisible(false)

