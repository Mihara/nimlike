import os
import std/sha1
import strutils
import jstin
import json
import times

type
  Comment* = object
    name*: string
    hash*: string
    text*: string
    ip*: string
    date*: DateTime

proc fromJson(x: var DateTime, n: JsonNode) =
  x = n.getStr().parse("yyyy-MM-dd'T'HH:mm:sszzz")

proc toJson(x: DateTime): JsonNode =
  newJString(x.format("yyyy-MM-dd'T'HH:mm:sszzz"))

## To prevent filenames-too-long and other such problems,
## we hash the URLs to make database filenames.

func hashFilename(slug: string): string =
  toLower($secureHash(slug))

func commentsFilename(slug: string): string =
  hashFilename(slug) & ".jsonl"

func likesFilename(slug: string): string =
  hashFilename(slug) & ".txt"

## The format of the comment database is jsonl: Json objects, one per line.
## File locking can be safely skipped on POSIX: Writes shorter than PIPE_BUF
## are supposed to be atomic, the value of PIPE_BUF is at least 4kb,
## and the maximum length of an URL in Gemini is 1024 bytes.

proc saveComment*(directory, target: string, data: Comment) =
  try:
    let f = open(directory / commentsFilename(target), fmAppend)
    f.writeLine(toJson(data))
    f.flushFile()
    f.close()
  except IOError:
    echo "42 Could not write to comments database.\r"
    quit(QuitFailure)

proc readComments*(directory, target: string): seq[Comment] =
  let fn = directory / commentsFilename(target)
  if not os.fileExists(fn):
    return
  try:
    for line in readFile(fn).split({'\n'}):
      try:
        result.add(fromJson[Comment](parseJson(line)))
      except JsonParsingError:
        continue
  except IOError:
    echo "42 Could not read comments database.\r"
    quit(QuitFailure)

## Likes 'database' is just a text file with one IP address per line.
## If you're editing them manually, make sure there is a newline at the end,
## or the count will be off by one.

proc saveLike*(directory, target: string, ip: string) =
  try:
    let f = open(directory / likesFilename(target), fmAppend)
    f.writeLine(ip)
    f.flushFile()
    f.close()
  except IOError:
    echo "42 Could not write to likes database.\r"
    quit(QuitFailure)

proc validLike*(directory, target: string, ip: string): bool =
  # If we don't have a db for it, all likes are valid.
  result = true
  let fn = directory / likesFilename(target)
  if not os.fileExists(fn):
    return
  try:
    for thatIP in readFile(fn).split({'\n'}):
      if thatIP == ip:
        result = false
        break
  except IOError:
    echo "42 Could not read likes database.\r"
    quit(QuitFailure)

proc countLikes*(directory, target: string): int =
  let fn = directory / likesFilename(target)
  if not os.fileExists(fn):
    return
  # There will always be an extra newline at the end of file.
  try:
    result = readFile(fn).countLines() - 1
  except IOError:
    echo "42 Could not read likes database.\r"
    quit(QuitFailure)
  # but just in case, we turn a negative into a 0.
  if result < 0:
    result = 0
