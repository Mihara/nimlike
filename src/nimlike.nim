import std/os
import std/cgi
import std/parsecfg
import std/times
import std/uri

import strutils
import re
import tables

import elvis

import nimlikedb
import nimlikeutils
import emojihash

#[ Load config file and settle the data before we do anything.

If the environment variable NIMLIKE_CONFIG_FILE is set (gmid, for one, can do
that for you in server config, and others might have a similar feature -- or,
if they pass their own environment variables to their cgi children, you could
set it above them) it will be loaded from there, so there's no need to keep
potentially sensitive configuration files below server root. Otherwise,
nimlike.ini will be sought in the current directory. ]#

let cfg = loadConfig(os.getEnv("NIMLIKE_CONFIG_FILE", "nimlike.ini"))

let server_root = os.absolutePath(cfg.getSectionValue("nimlike", "server_root",
    os.getCurrentDir()), "/")
let datadir = os.absolutePath(cfg.getSectionValue("nimlike", "data"), "/")
let salt = cfg.getSectionValue("nimlike", "salt", "thisisabadsalt")
let allowed = cfg.getSectionValue("nimlike", "allow", r"\.gmi$")
let defaultNickname = cfg.getSectionValue("nimlike", "anonymous",
    "Incognito")

# Load the list of forbidden url regexps.
var forbiddenUrls: seq[string]
for url in cfg.getOrDefault("forbid").keys:
  forbiddenUrls.add(url)

let self = getScriptName()
let parts = getPathInfo().strip(chars = {'/'}, trailing = false).split('/', 1)

# If it didn't split properly, bail.
if len(parts) != 2:
  echo "59 Malformed URL. What exactly are you trying to do?...\r"
  quit(QuitFailure)

# If you're using pretty URLs, i.e. rely on index.gmi expansion of
# directories, -- not common in gemini space, but happens -- this should
# handle them, unless you're being exotic about it:
let targetFile = validateFile(
  if parts[1].endsWith("/"):
    parts[1] & "index.gmi"
  else:
    parts[1], server_root, allowed, forbiddenUrls)

# If we got pointed at an invalid target, bail.
if not ?targetFile:
  echo "59 No likes or comments allowed here.\r"
  quit(QuitFailure)

let targetUrl = parts[1].strip()
let command = parts[0]
var query = decodeUrl(getQueryString()).strip()

proc reShow() =
  ## Issue a redirect back to show comments for the same page.
  echo "31 $1/show/$2\r" % [self, targetUrl]
  quit(QuitSuccess)

# Now that all the prep work is done, we can actually process
# the command we got.

case command
of "show":

  # Borrow the page title from the file we were called for.
  let header = getFileHeader(targetFile)

  echo "20 text/gemini\r"

  #[ This, strictly speaking, needs a template engine, but the ones that don't
     introduce any overhead are just a bit too simple, while ones that are
     flexible enough are not worth it for just one template. ]#

  echo "# $1\n" % [header]

  # Comment count
  let likes = countLikes(datadir, targetUrl)
  if ?likes:
    echo "This post was ❤️ by $1 readers.\n" % [$likes]
  else:
    echo "No ❤️ so far. 😟\n"

  # And render the comments here.
  let comments = readComments(datadir, targetUrl)

  const commentSeparator = "────"
  if ?comments:
    echo "## Comments:\n"
    for c in comments:
      echo "$1 $2: $3 commented,\n" % [commentSeparator,
                                       c.date.format("yyyy-MM-dd"),  c.name]
      for line in c.text.split({'\n'}):
        if not line.startsWith("="):
          echo "> ", line
        else:
          echo line
      echo "\nID hash: ", emojihash(c.hash & salt)
    echo commentSeparator, "\n"

  echo "## Writing comments:"
  echo "* Leaving a like or comment records your IP address, for obvious ",
       "reasons. It's never shown to anyone."
  echo "* You need to present a client certificate to leave an actual comment."
  echo "* Newlines are allowed in comments, if your browser can send them. ",
       "Gemini links will work, if put on a separate line."
  echo "* You can state a nickname by starting your comment with ",
        "\"<nickname>:<space or newline>\""
  echo "* If you don't supply a nickname, it will be taken from your ",
       "certificate's UID or CN."
  echo "* If your certificate doesn't have any of those, you ",
      "will be called \"$1\".\n" % [defaultNickname]

  # I could make them only show to people who can use them,
  # but is it worth it?...

  echo "=> $1/like/$2 ❤️ Like this post" % [self, targetUrl]
  echo "=> $1/comment/$2 💬 Add a comment" % [self, targetUrl]
  echo "=> /$1 ↩ Go back\n" % [targetUrl]
  quit(QuitSuccess)

of "like":
  let remote = getRemoteAddr()
  # Check if the ip is not in the db already.
  try:
    if validLike(datadir, targetUrl, remote):
      if not saveLike(datadir, targetUrl, remote):
        dbFailure()
    else:
      # Else report an error...
      doFailure("You cannot give one post all the likes, sorry.")
  except IOError:
    readFailure()

  reshow()

of "comment":
  # Check if the user has a cert. If they don't, pop back an error.
  if os.getEnv("AUTH_TYPE") != "Certificate":
    echo "60 You must use a client certificate to leave a comment.\r"
    quit(QuitFailure)
  # But if they are in fact using one, see if they came with a query string.
  if not ?query:
    # If they didn't, call for input.
    echo "10 Please type your comment:\r"
    quit(QuitSuccess)

  # Parse our query string to ferret out a nickname:

  # If we don't find anything, we keep the default nickname.
  var nickname = defaultNickname

  # If they gave a nickname, remember it and excise it from the text.
  # Given nickname always overrides the one from the cert.
  let nickRe = re"^(.+):[ \n]"
  var matches: array[1, string]

  if query.contains(nickRe, matches):
    nickname = matches[0]
    query = query.replace(nickRe)
  else:
    #[ But if they didn't, fall back on the data from the certificate.

    TLS data are not part of the CGI standard, and Gemini standards don't
    specify any extensions. In Molly Brown, we can use TLS_CLIENT_SUBJECT,
    while in gmid the equivalent env var is called REMOTE_USER, which is,
    ironically, closer to the standard (which does specify it, just for http
    basic auth) than Molly Brown.

    We will need to parse the /CN= and /UID= out of them. ]#

    for envVar in ["TLS_CLIENT_SUBJECT", "REMOTE_USER"]:
      let certData = os.getEnv(envVar, "")
      if ?certData:
        var params = initTable[string, string]()
        # Parse the /-separated list of key-value pairs into a table.
        for element in certData.split('/'):
          if ?element:
            let kv = element.split('=')
            if len(kv) == 2:
              params[kv[0]] = kv[1]

        #[ Then pick one in order of preference.

        We prefer UID, then CN. We ignore email address, because we need the
        nickname to publish one, and publishing other people's email addresses
        is impolite. ]#

        for certVar in ["UID", "CN"]:
          if params.hasKey(certVar) and ?params[certVar]:
            nickname = params[certVar]
            break
        break

  # And save it!
  if not saveComment(datadir, targetUrl, Comment(
      name: nickname,
      hash: os.getEnv("TLS_CLIENT_HASH"),
      date: times.now(),
      ip: getRemoteAddr(),
      text: query)):
    dbFailure()

  reshow()

else:
  doFailure("Valid commands are 'show', 'like' and 'comment'.")
