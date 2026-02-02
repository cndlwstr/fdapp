import unittest
import std/[os, osproc]
import fdapp


let app = fdappInit("io.github.cndlwstr.test")
var activated = 0
app.onActivate:
  inc activated


test "activation fallback":
  app.open(@["file://" & getHomeDir() & "/.nimble"])
  check activated == 1


test "single-instance app test":
  app.activate()
  # activated == 2 at this point

  let p = startProcess(getAppFilename())
  defer: p.close()

  while p.running:
    fdappIterate()

  check p.waitForExit() == 0
  check activated == 3
