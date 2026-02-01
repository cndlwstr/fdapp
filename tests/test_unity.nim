import unittest
import std/[importutils, os, osproc, random, streams, strutils]
import fdapp

privateAccess(FreedesktopApp)
randomize()


test "unity launcher":
  let app = fdappInit("io.github.cndlwstr.test")
  var progress = 0.0

  proc update() =
    sleep(500)
    app.setTaskbarProgress(progress)
    app.setTaskbarCount(rand(100))
    progress += 0.20

  app.onActivate:
    app.setTaskbarProgressVisible(true)
    app.setTaskbarCountVisible(true)

    while true:
      fdappIterate()
      update()
      if progress > 1.0:
        break

  echo "Starting Unity Launcher test for " & app.appUri
  echo "Use -d:UnityDesktopFile=... to change desktop file name"

  app.activate()

  sleep(500)
  app.setTaskbarProgressVisible(false)
  app.setTaskbarUrgent(true)
  sleep(500)

  let p = startProcess("/usr/bin/gdbus", args = ["call", "-e", "-d", app.appId, "-o", app.unityObjectPath, "-m", "com.canonical.Unity.LauncherEntry.Query"])
  while p.running:
    fdappIterate()
  check p.outputStream.readAll().contains("'progress': <1.0>, 'urgent': <true>, 'count-visible': <true>, 'progress-visible': <false>")

  app.resetTaskbar()
