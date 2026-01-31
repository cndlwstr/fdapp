import unittest
import std/osproc
import fdapp


const APP_ID = "io.github.cndlwstr.test"


test "validate app id":
  try:
    let app = fdappInit("somethingThatIsNotReverseDNS")
    check false
  except AssertionDefect:
    check true


test "dbus activation":
  let app = fdappInit(APP_ID)
  var activated = false

  app.onActivate:
    check startupId == "ID"
    check activationToken == "TOKEN"
    activated = true

  let p = startProcess("/usr/bin/gdbus", args = ["call", "-e", "-d", APP_ID, "-o", "/", "-m", "org.freedesktop.Application.Activate", "-t", "1", "{\"desktop-startup-id\": <\"ID\">, \"activation-token\": <\"TOKEN\">}"])
  defer: p.close()

  while p.running:
    fdappIterate()

  check p.peekExitCode() == 0
  check activated
