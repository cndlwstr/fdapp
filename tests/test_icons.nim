import unittest
import std/[strformat, strutils]
import fdapp/[icons]


test "icon theme":
  let systemTheme = getSystemIconTheme()
  if systemTheme != nil:
    echo fmt"Your system icon theme is: {systemTheme.id} ({systemTheme.name})"
    echo "Installed icon themes: ", getIconThemesList().join(", ")

  let adw = findIconTheme("Adwaita") # Adwaita is installed by default on many distros
  check adw != nil
  check adw.id == "Adwaita"
  check adw.name == "Adwaita"
  check adw.comment == "The Only One"
  check adw.inherits.contains findIconTheme("hicolor")

  check lookupIcon("package-x-generic-symbolic", theme = adw).path == "/usr/share/icons/Adwaita/symbolic/mimetypes/package-x-generic-symbolic.svg"
  check lookupIcon("package-x-generic-symbolic", theme = findIconTheme("hicolor")) == nil
  check lookupIcon("blah-blah") == nil
  check lookupIcon("folder", theme = adw, size = 512).size == 128 # Adwaita doesn't have 512px icons
