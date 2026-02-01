##[
  This module provides utilities to get info about system icons.

  Use `lookupIcon proc`_ to get full path of a requested icon.

  `findIconTheme proc`_, `getSystemIconTheme proc`_, `getIconThemesList proc`_ provide info about icon themes.

  `onIconThemeChanged template`_ allows to watch when the system icon theme gets changed.

  Take note that this module doesn't fully implement `the spec <
  https://specifications.freedesktop.org/icon-theme/latest/>`_. While `icon lookup <#lookupIcon>`_ should work as expected, some icon themes data is not taken into account and not provided.
]##

import std/[algorithm, os, sequtils, sets, strformat, strutils, tables]
import internal/gsettings {.all.}
from internal/glib import glibContext, iterate
export glibContext, iterate
## .. importdoc:: internal/glib.nim, ../fdapp.nim


type
  IconType* = enum
    threshold, fixed, scalable

  IconThemeSubdir* = object
    path*: string
    size*: uint
    scale*: uint = 1
    icType*: IconType = threshold

  IconTheme* = ref object
    id*: string
    paths*: seq[string]
    name*: string
    localizedName*: Table[string, string]
    comment*: string
    localizedComment*: Table[string, string]
    directories*: seq[IconThemeSubdir]
    inherits*: seq[IconTheme]

  IconFormat* = enum
    xpm, png, svg

  Icon* = ref object
    path*: string
    size*: uint
    format*: IconFormat


let interfaceSettings = newSettings("org.gnome.desktop.interface")

var themesCache: Table[string, IconTheme]


proc addDirIfExists(dir: string, s: var seq[string]) =
  if dirExists(dir): s.add dir


let themesDirs = block:
  var t = newSeq[string]()

  let home = getEnv("HOME")
  addDirIfExists fmt"{home}/.icons", t

  let xdgDataDirs = getEnv("XDG_DATA_DIRS")
  if xdgDataDirs.len > 0:
    for dir in xdgDataDirs.split(':'):
      addDirIfExists dir, t
  else:
    addDirIfExists fmt"{home}/.local/share/icons", t
    addDirIfExists "/usr/local/share/icons", t
    t.add "/usr/share/icons" # de-facto standard dir, expected to exist

  addDirIfExists fmt"{home}/.local/share/pixmaps", t
  addDirIfExists "/usr/share/pixmaps", t
  t


proc cmpSubdirs(a, b: IconThemeSubdir): int =
  return cmp(a.size * a.scale, b.size * b.scale)


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
  var subdir: IconThemeSubdir
  for line in f.lines:
    if line.startsWith('[') and line != "[Icon Theme]":
      if subdir.path.len > 0: result.directories.add subdir
      subdir = IconThemeSubdir(path: line[1..^2])
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
      elif key == "Inherits":
        for id in value.split(','):
          let inhTheme = findIconTheme(id)
          if inhTheme != nil: result.inherits.add inhTheme
      elif key == "Size":
        try: subdir.size = value.parseUint
        except: discard
      elif key == "Scale":
        try: subdir.scale = value.parseUint
        except: discard
      elif key == "Type":
        try: subdir.icType = parseEnum[IconType](value.toLower)
        except: subdir.icType = threshold
  result.directories.add subdir
  result.directories.sort(cmpSubdirs)

  themesCache[id] = result


proc getSystemIconTheme*(): IconTheme =
  ## Gets current system icon theme (or `nil` if failed to detect)

  let id = interfaceSettings.get("icon-theme")
  if id.len == 0:
    return nil
  return findIconTheme(id)


proc getIconThemesList*(): seq[string] =
  ## Gets list of all installed icon themes.
  ##
  ## You can use retrieved ids to pass into `findIconTheme proc`_.

  var themes: HashSet[string]
  for dir in themesDirs:
    for entry in walkDir(dir):
      if entry.kind == pcDir and fileExists(fmt"{entry.path}/index.theme"):
        themes.incl entry.path.splitFile().name
  return toSeq(themes).sorted


proc lookupIcon*(name: string, theme: IconTheme = getSystemIconTheme(),
                 icTypes: set[IconType] = {threshold, fixed, scalable},
                 size: uint = 0, scale: uint = 1,
                 formats: set[IconFormat] = {png, svg}): Icon =
  ## Gets an icon. If an icon isn't found, `nil` is returned.
  ##
  ## `name` must be just an icon name, without extension.
  ##
  ## If an icon exists, but not in requested size, an icon of smaller size will be returned, or, if that doesn't exist either, an icon of bigger size.

  if theme == nil:
    return nil

  result = new Icon

  for root in theme.paths:
    for dir in theme.directories:
      for format in formats:
        let path = fmt"{root}/{dir.path}/{name}.{format}"
        if fileExists(path):
          if dir.size == size:
            result.path = path
            result.size = dir.size
            result.format = format
            return
          elif dir.size > size and result.path.len > 0:
            return
          else:
            result.path = path
            result.size = dir.size
            result.format = format

  if result.path.len > 0:
    return result

  if theme.inherits.len > 0:
    for inhTheme in theme.inherits:
      let inhIcon = lookupIcon(name, inhTheme, icTypes, size, scale, formats)
      if inhIcon != nil: return inhIcon

  return nil


template onIconThemeChanged*(actions: untyped) =
  ## Allows to watch for when the system icon theme gets changed.
  ##
  ## For this functionality to work, it is required to iterate GLib context. When not using main fdapp module to call `fdappIterate proc`_, call `iterate proc`_ with `glib: glibContext <internal/glib.html#glibContext>`_ (both exported by this module) in your app's loop (see `test_icons.nim <https://github.com/cndlwstr/fdapp/blob/main/tests/test_icons.nim>`_ for example).

  interfaceSettings.onChanged("icon-theme"): actions
