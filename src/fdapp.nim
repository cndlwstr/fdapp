import std/[strformat, strutils]
import fdapp/[icons, internal/glib]
export icons


type
  FreedesktopAppObj = object
    appId: string
    busId: cuint
    activateCallback: proc(startupId: string, activationToken: string)
    openCallback: proc(startupId: string, activationToken: string, uris: seq[string])
    activateActionCallback: proc(startupId: string, activationToken: string, actionName: string)

  FreedesktopApp* = ref FreedesktopAppObj


var dbusInfo: GDBusNodeInfo


proc `=destroy`(app: var FreedesktopAppObj) =
  if app.busId > 0: gbusUnownName(app.busId)
  dbusInfo.unref()


const
  SESSION_BUS = 2
  DO_NOT_QUEUE = 4
  FREEDESKTOP_APP_XML = staticRead("fdapp/internal/dbus/org.freedesktop.Application.xml")


proc dbusMethodCallCallback(connection: GDBusConnection, sender, objectPath, interfaceName, methodName: cstring, parameters: GVariant, invocation: GDBusMethodInvocation, data: pointer) {.cdecl.} =
  let app = cast[FreedesktopApp](data)

  proc getPlatformData(dict: GVariant): (string, string) =
    let startupIdVariant = dict.lookupValue("desktop-startup-id", newGVariantType("s"))
    if cast[pointer](startupIdVariant) != nil:
      result[0] = $startupIdVariant.getString(nil)
      startupIdVariant.unref()

    let activationTokenVariant = dict.lookupValue("activation-token", newGVariantType("s"))
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


const dbusVTable = GDBusInterfaceVTable(methodCall: dbusMethodCallCallback, getProperty: nil, setProperty: nil)


proc busAcquiredCallback(connection: GDBusConnection, name: cstring, data: pointer) {.cdecl.} =
  let app = cast[FreedesktopApp](data)
  let objectPath = ("/" & app.appId.replace('-', '_').replace('.', '/')).cstring
  let id = connection.registerObject(objectPath, dbusInfo.interfaces[0], dbusVTable.addr, data, nil, nil)

  doAssert id > 0, "Failed to register DBus object"
  app.busId = id


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


proc fdappInit*(id: string): FreedesktopApp =
  doAssert id.len > 0, "Application ID can't be empty"
  doAssert id.count('.') >= 2, "Application ID must be in reverse-DNS format"

  result = new FreedesktopApp
  result.appId = id

  var dbusXml = fmt"<node>{FREEDESKTOP_APP_XML}</node>".cstring
  withGlibContext:
    var err: GError
    dbusInfo = newGDBusNodeInfoForXml(dbusXml, err.addr)
    doAssert err == nil, $err.message

    discard gbusOwnName(SESSION_BUS, id.cstring, DO_NOT_QUEUE, busAcquiredCallback, nil, nameLostCallback, result[].addr, nil)


proc activate*(app: FreedesktopApp) =
  doAssert app.activateCallback != nil, "Attempt to activate application without activate callback set"
  app.activateCallback("", "")


proc open*(app: FreedesktopApp, uris: seq[string]) =
  doAssert app.activateCallback != nil, "Attempt to activate application without activate callback set"
  app.openCallback("", "", uris)


proc activateAction*(app: FreedesktopApp, actionName: string) =
  doAssert app.activateCallback != nil, "Attempt to activate application without activate callback set"
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


proc fdappIterate*() =
  ## Non-blocking iteration of fdapp's context.
  ##
  ## You must call this in your app's event loop.

  glibContext.iterate()
