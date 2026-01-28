import std/[algorithm, os, sequtils, sets, strformat, strutils, tables]
import gsettings

##[
  This module provides `IconTheme` object that contains some data
  about a system icon theme.

  Use `findIconTheme(id: string)` to get `IconTheme`.

  Take note that this module doesn't fully implement the spec.
]##


type IconTheme = ref object
  id*: string
  paths*: seq[string]
  name*: string
  localizedName*: Table[string, string]
  comment*: string
  localizedComment*: Table[string, string]
  directories*: seq[string]
  inherits*: seq[IconTheme]


var themesCache: Table[string, IconTheme]


proc addDirIfExists(dir: string, s: var seq[string]) =
  if dirExists(dir): s.add dir


let themesDirs = block:
  var t = newSeq[string]()

  let home = getEnv("HOME")
  addDirIfExists home & "/.icons", t

  if getEnv("XDG_DATA_DIRS").len > 0:
    for dir in getEnv("XDG_DATA_DIRS").split(':'):
      addDirIfExists dir, t
  else:
    addDirIfExists home & "/.local/share/icons", t
    addDirIfExists "/usr/local/share/icons", t
    t.add "/usr/share/icons" # de-facto standard dir, expected to exist

  addDirIfExists home & "/.local/share/pixmaps", t
  addDirIfExists "/usr/share/pixmaps", t
  t


proc findIconTheme*(id: string): IconTheme =
  ## Finds a theme by `id`, which is a "system" name (directory name),
  ## not a user-readable name (e.g. "breeze", not "Breeze").

  if themesCache.hasKey(id):
    return themesCache[id]

  result = new IconTheme

  var configPath: string
  for dir in themesDirs:
    let themeDir = fmt"{dir}/{id}"
    addDirIfExists themeDir, result.paths
    let cfg = fmt"{themeDir}/index.theme"
    if configPath.len == 0 and fileExists(cfg):
      configPath = cfg

  if configPath.len == 0:
    return nil

  result.id = id

  var f: File
  if not open(f, configPath):
    raise newException(Exception, fmt"{id} icon theme was not found")

  # std/parsecfg doesn't support keys with `[]` (e.g `Name[ru]`), we have to parse manually
  for line in f.lines:
    if line.startsWith('[') and line != "[Icon Theme]":
      break
    elif line.contains('='):
      let kv = line.split('=')
      let key = kv[0].strip
      let value = kv[1].strip
      if key == "Name":
        result.name = value
      elif key.startsWith("Name["):
        result.localizedName[key[5..^2]] = value
      elif key == "Comment":
        result.comment = value
      elif key.startsWith("Comment["):
        result.localizedComment[key[8..^2]] = value
      elif key == "Directories":
        result.directories.add value.split(',').filter(
          proc (d: string): bool = return not d.contains('@'))
      elif key == "Inherits":
        for id in value.split(','):
          let inhTheme = findIconTheme(id)
          if inhTheme != nil: result.inherits.add inhTheme

  themesCache[id] = result


proc getSystemIconTheme*(): IconTheme =
  ## Gets current system icon theme (or `nil` if failed to detect)

  let settings = newSettings("org.gnome.desktop.interface")
  let id = $settings.getString("icon-theme")
  if id.len == 0:
    return nil
  return findIconTheme(id)


proc getIconThemesList*(): seq[string] =
  ## Gets list of all installed icon themes.
  ##
  ## You can use retrieved ids to pass into `findIconTheme`.

  var themes: HashSet[string]
  for dir in themesDirs:
    for entry in walkDir(dir):
      if entry.kind == pcDir and fileExists(fmt"{entry.path}/index.theme"):
        themes.incl entry.path.splitFile().name
  return toSeq(themes).sorted
