import os
import strutils
import re

proc validateFile*(filename, server_root, allowed: string,
                   forbiddenUrls: seq[string]): string =
  ## Find the file the URL points to and see if we're
  ## allowed to comment on it.

  # First we normalize the path to prevent directory traversal attacks.
  let fn = filename.strip()
  let thatFile = os.normalizedPath(os.joinPath(server_root, fn))

  #[ Our prospective file must
  * be under server root,
  * exist,
  * match the regexp given in 'allowed' config variable,
  * not be present in the list of forbidden urls. ]#

  if thatFile.startsWith(server_root):
    # Does the file exist and match the allow regexp ?
    if not os.fileExists(thatFile) or not fn.contains(re(allowed)):
      return
    # Does it match any of the forbid regexps?
    for url in forbiddenUrls:
      if fn.contains(re(url)):
        return

    result = thatFile

proc getFileHeader*(filename: string): string =
  ## Read through the filename to produce a header for the page.
  ## The first level-1 header line is returned.
  ## If nothing is found, you just get the bare filename with
  ## no path for a title.

  result = os.lastPathPart(filename)

  #[ Just to save us some effort -- if it's not a .gmi or .gemini file that you
  for some reason are allowing to comment on, skip parsing it. I have not yet
  seen any other file extensions used for gemtext in the wild. ]#

  if not result.endsWith(".gmi") and not result.endsWith(".gemini"):
    return

  let targetFile = open(filename)
  try:
    var line = ""
    while true:
      line = readLine(targetFile)
      if line.startsWith("# "):
        result = line[2..^1].strip()
        break
  except EOFError:
    discard
  except IOError:
    discard
  finally:
    targetFile.close()

proc dbFailure*() =
  echo "42 Could not save data for some reason.\r"
  quit(QuitFailure)

proc readFailure*() =
  echo "42 Could not read data for some reason.\r"
  quit(QuitFailure)

proc doFailure*(msg: string) =
  echo "50 ", msg, "\r"
  quit(QuitFailure)

func booleanCfg*(s: string): bool =
  if s.strip().toLower() in ["true", "1", "on", "yes"]:
    result = true

func intCfg*(s: string): int =
  try:
    result = parseInt(s)
  except:
    discard
