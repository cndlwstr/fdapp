import unittest
import std/[os, osproc]
import fdapp


const APP_ID = "io.github.cndlwstr.test"
var activated = 0

test "validate app id":
  try:
    discard fdappInit("somethingThatIs.NotReverseDNS")
    check false
  except AssertionDefect:
    check true


let app = fdappInit(APP_ID)
app.onActivate:
  inc activated


test "activation fallback":
  app.open(@["file://" & getHomeDir() & "/.nimble"])
  check activated == 1


test "single-instance app test":
  app.activate()
  # activated == 2 at this point

  let p = startProcess(getAppFilename())

  while p.running:
    fdappIterate()

  check p.waitForExit() == 0
  check activated == 3
