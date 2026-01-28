import unittest
import std/[strformat, strutils]
import fdapp/[icontheme]


test "icon theme":
  let adw = findIconTheme("Adwaita")
  check adw != nil
  check adw.id == "Adwaita"
  check adw.name == "Adwaita"
  check adw.comment == "The Only One"
  check adw.inherits.contains findIconTheme("hicolor")
  let systemTheme = getSystemIconTheme()
  echo fmt"Your system icon theme is: {systemTheme.id} ({systemTheme.name})"
  echo "Installed icon themes: ", getIconThemesList().join(", ")
