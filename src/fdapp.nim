import std/[strformat, strutils]
import fdapp/[icons, internal/glib]
export icons


type
  FreedesktopAppObj = object
    id: string
    activateCallback: proc(startupId: string, activationToken: string)
    openCallback: proc(startupId: string, activationToken: string)
    activateActionCallback: proc(startupId: string, activationToken: string)

  FreedesktopApp = ref FreedesktopAppObj


const
  SESSION_BUS = 2
  DO_NOT_QUEUE = 4
  FREEDESKTOP_APP_XML = """
<interface name='org.freedesktop.Application'>
  <method name='Activate'>
    <arg type='a{sv}' name='platform_data' direction='in'/>
  </method>
  <method name='Open'>
    <arg type='as' name='uris' direction='in'/>
    <arg type='a{sv}' name='platform_data' direction='in'/>
  </method>
  <method name='ActivateAction'>
    <arg type='s' name='action_name' direction='in'/>
    <arg type='av' name='parameter' direction='in'/>
    <arg type='a{sv}' name='platform_data' direction='in'/>
  </method>
</interface>
"""


var
  dbusInfo: GDBusNodeInfo


proc dbusMethodCallCallback(connection: GDBusConnection, sender, objectPath, interfaceName, methodName: cstring, parameters: GVariant, invocation: GDBusMethodInvocation, data: pointer) {.cdecl.} =
  let app = cast[FreedesktopApp](data)

  proc getPlatformData(dict: GVariant): (string, string) =
    var startupIdVariant = dict.lookupValue("desktop-startup-id", newGVariantType("s"))
    if cast[pointer](startupIdVariant) != nil:
      result[0] = $startupIdVariant.getString(nil)
      startupIdVariant.unrefVariant()

    var activationTokenVariant = dict.lookupValue("activation-token", newGVariantType("s"))
    if cast[pointer](activationTokenVariant) != nil:
      result[1] = $activationTokenVariant.getString(nil)
      activationTokenVariant.unrefVariant()

  if interfaceName == "org.freedesktop.Application":
    case methodName:
    of "Activate":
      if app.activateCallback != nil:
        var platformDict: ptr GVariant
        parameters.get("(a{sv})", platformDict.addr)
        let (startupId, activationToken) = getPlatformData(platformDict[])
        platformDict[].unrefVariant()

        app.activateCallback(startupId, activationToken)
    else: discard

  invocation.returnValue(nil)

const dbusVTable = GDBusInterfaceVTable(methodCall: dbusMethodCallCallback, getProperty: nil, setProperty: nil)


proc busAcquiredCallback(connection: GDBusConnection, name: cstring, data: pointer) {.cdecl.} =
  let id = connection.registerObject("/", dbusInfo.interfaces[0], dbusVTable.addr, data, nil, nil)
  assert id > 0, "Failed to acquire session bus"


proc fdappInit*(id: string): FreedesktopApp =
  assert id.len > 0, "Application ID can't be empty"
  assert id.count('.') >= 2, "Application ID must be in reverse-DNS format"

  result = new FreedesktopApp
  result.id = id

  var dbusXml = fmt"<node>{FREEDESKTOP_APP_XML}</node>".cstring
  withGlibContext:
    var err: GError
    dbusInfo = newGDBusNodeInfoForXml(dbusXml, addr(err))
    assert err == nil, $err.message

    discard gbusOwnName(SESSION_BUS, id.cstring, DO_NOT_QUEUE, busAcquiredCallback, nil, nil, addr(result[]), nil)


template onActivate*(app: FreedesktopApp, actions: untyped) =
  let activateCallback = proc(startupId {.inject.}, activationToken {.inject.}: string) = actions
  app.activateCallback = activateCallback


proc fdappIterate*() =
  ## Non-blocking iteration of fdapp's context.
  ##
  ## You must call this in your app's event loop.

  glibContext.iterate()
