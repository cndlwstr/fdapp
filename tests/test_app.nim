import unittest
import fdapp


const APP_ID = "io.github.cndlwstr.test"


test "validate app id":
  try:
    discard fdappInit("somethingThatIs.NotReverseDNS")
    check false
  except AssertionDefect:
    check true


test "activation fallback":
  let app = fdappInit(APP_ID)
  var activated = false

  app.onActivate:
    activated = true

  app.open(@["file:///home/user/.nimble"])
  check activated
