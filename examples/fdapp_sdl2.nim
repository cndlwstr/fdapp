#[
  fdapp + sdl2 multi-window example.

  Based on bare-bones sdl2 example from nim sdl2 repo.
  You can use the following command to call Activate method that will create a new window:

    $ gdbus call -e -d io.github.cndlwstr.fdapp_sdl2 -o /io/github/cndlwstr/fdapp_sdl2 -m org.freedesktop.Application.Activate "{}"

  As `onOpen` template isn't used, a call to Open method on dbus will trigger `onActivate` as well:

    $ gdbus call -e -d io.github.cndlwstr.fdapp_sdl2 -o /io/github/cndlwstr/fdapp_sdl2 -m org.freedesktop.Application.Open "[]" "{}"

  And the same works with ActivateAction method.
]#

import fdapp, sdl2

discard sdl2.init(INIT_EVERYTHING)
let app = fdappInit("io.github.cndlwstr.fdapp_sdl2", {orgFreedesktopApplication}) # disabling dbus interfaces that we don't need

var
  windows: seq[tuple[handle: WindowPtr, render: RendererPtr]]
  evt = sdl2.defaultEvent
  runApp = true


app.onActivate = proc(startupId, activationToken: string) =
  # Or simply `app.onActivate:`, parameters will be injected.
  # The same works for other dbus methods' callbacks.

  # Creating a new window
  var
    window = createWindow(("SDL Window " & $(windows.len + 1)).cstring, 100, 100, 640, 480, SDL_WINDOW_SHOWN)
    render = createRenderer(window, -1, Renderer_Accelerated or Renderer_PresentVsync or Renderer_TargetTexture)
  windows.add (window, render)


app.activate() # Let's make our first window by triggering `onActivate` manually

# Main loop
while runApp:
  fdappIterate()

  while pollEvent(evt):
    if evt.kind == QuitEvent:
      runApp = false
      break
    if evt.kind == WindowEvent:
      var windowEvent = cast[WindowEventPtr](addr(evt))
      var i = 0
      while i < windows.len:
        let (window, render) = windows[i]
        if window.getID() != windowEvent.windowID:
          inc i
          continue
        if windowEvent.event == WindowEvent_Close:
          destroy render
          destroy window
          windows.del i
          continue
        inc i

  for (_, render) in windows:
    render.setDrawColor 55,55,55,255
    render.clear
    render.present

  if windows.len == 0:
    # No windows left, time to quit
    runApp = false
