import unittest
import std/[os, osproc]
import fdapp


const APP_ID = "io.github.cndlwstr.test"
const OBJ_PATH = "/io/github/cndlwstr/test"

let app = fdappInit(APP_ID)

var
  activated = false
  opened = false
  actionActivated = false

app.onActivate:
  check startupId == "ID"
  check activationToken == "TOKEN"
  activated = true

app.onOpen:
  check startupId == "ID"
  check activationToken == "TOKEN"
  check uris[0] == "file:///home/user/Pictures/funny_cat.jpg"
  check uris[1] == "https://nim-lang.org/"
  opened = true

app.onAction:
  check startupId == "ID"
  check activationToken == "TOKEN"
  check actionName == "test"
  actionActivated = true


test "dbus activation":
  let p = startProcess("/usr/bin/gdbus", args = ["call", "-e", "-d", APP_ID, "-o", OBJ_PATH, "-m", "org.freedesktop.Application.Activate", "-t", "1", "{\"desktop-startup-id\": <\"ID\">, \"activation-token\": <\"TOKEN\">}"])
  defer: p.close()

  while p.running:
    fdappIterate()

  check p.peekExitCode() == 0
  check activated


test "dbus opening":
  let p = startProcess("/usr/bin/gdbus", args = ["call", "-e", "-d", APP_ID, "-o", OBJ_PATH, "-m", "org.freedesktop.Application.Open", "-t", "1", "[\"file:///home/user/Pictures/funny_cat.jpg\", \"https://nim-lang.org/\"]", "{\"desktop-startup-id\": <\"ID\">, \"activation-token\": <\"TOKEN\">}"])
  defer: p.close()

  while p.running:
    fdappIterate()

  check p.peekExitCode() == 0
  check opened


test "dbus action":
  let p = startProcess("/usr/bin/gdbus", args = ["call", "-e", "-d", APP_ID, "-o", OBJ_PATH, "-m", "org.freedesktop.Application.ActivateAction", "-t", "1", "test", "[]", "{\"desktop-startup-id\": <\"ID\">, \"activation-token\": <\"TOKEN\">}"])
  defer: p.close()

  while p.running:
    fdappIterate()

  check p.peekExitCode() == 0
  check actionActivated


app.onActivate:
  activated = true

test "single-instance app test":
  activated = false
  let p = startProcess(getAppFilename())

  while not activated:
    fdappIterate()

  check p.waitForExit() == 0
