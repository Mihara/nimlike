# Nimlike

A CGI-based likes and comments system for the [Gemini](https://gemini.circumlunar.space/) protocol, inspired by [gemlikes](https://github.com/makeworld-the-better-one/gemlikes/).

This is *slightly* less of a toy project than gemlikes claims to be, meaning that it still probably won't stand up to any true loads and has obvious shortcomings, but all of the things that I didn't like about gemlikes were rectified. Namely:

* There's only one executable, and you can name it whatever you like.
* No temporary files are created during operation.
* Page titles on comment pages are read from actual pages, and filenames are used only if the actual pages don't have a level 1 header.
* Comments can contain newlines and links.
* What passes for a database is more resilient to user input.
* Comments require a client certificate to enter, likes do not.
* Comments handle nicknames more gracefully.
* When a nickname isn't given, a nickname for comment author is extracted from their certificate itself, if possible.
* Identifying markers of comment authors -- that is, client certificate hashes -- are further hashed with a salt, and rendered as a string of emoji, preventing impersonation of people who wrote comments previously.
* You don't have to keep the configuration file inside gemini server root, so nobody can read your salt or learn things about your directory structure from it.

You might not care about these, it is a matter of taste. But if you do, I hope this comes in useful.

## Installation

Nimlike is, as the name implies, written in [Nim](https://nim-lang.org/), which is my current language of choice for jobs like these. Currently there are no released static binaries -- they're very much possible, but I don't feel it's ready to be used by people who are just looking for a quick solution, just yet. At the time of writing it's about a day old.

You will have to compile it from source by getting Nim installed and building it yourself:

``` shell
nimble build -d:release
```

This results in a single `nimlike` binary which goes into your server's cgi-bin location and can be named whatever you like.

⚠️ Despite that it can be renamed, the rest of this documentation will assume that it is named `nimlike` and lives in `/cgi-bin/nimlike` somewhere in the root of your Gemini server.

## Other requirements

* Your Gemini server must support CGI. Obviously. Not all of them do.
* It must correctly follow the [CGI standard](https://datatracker.ietf.org/doc/html/rfc3875). In particular, it must handle [PATH_INFO](https://datatracker.ietf.org/doc/html/rfc3875#section-4.1.5) and [SCRIPT_NAME](https://datatracker.ietf.org/doc/html/rfc3875#section-4.1.13) variables properly.
* While there's no gemini standard for gemini-specific variables -- some things in the CGI standard obviously don't apply, while there's some debate on where the things specific to Gemini, like client certificate information, should go -- `AUTH_INFO` must contain the string `Certificate` if the user is presenting a client certificate, and either `TLS_CLIENT_SUBJECT` or `REMOTE_USER` must contain a certificate identification string -- the one that looks like `/CN=foo/emailAddress=....`. `TLS_CLIENT_HASH` must contain the certificate hash.

To my knowledge, [Molly Brown](https://tildegit.org/solderpunk/molly-brown) and [gmid](https://github.com/omar-polo/gmid) both qualify, but there's a lot of gemini servers out there and I don't know if yours does. The only one actually tested with so far is gmid. If a given popular server does something else with this information, I could see about adapting nimlike to handle it as well, but no promises. As long as it passes on everything required, it can be done.

The other assumptions are:

* Every file you might want to comment on is accessible under server root, at a path that will be present in its actual URL. I.e. that there is a one-to-one URL/filename correspondence, at least for files that need access to the comment system.
* All of the file names for such files will match one (configurable) regular expression.
* If you're using pretty URLs -- that is, do things like pointing an url at `/my-cool-post/` while the actual file the post is in is `/my-cool-post/index.gmi` -- that the default file to be served is indeed named `index.gmi`. It should work even in that situation, but `index.gmi` is currently hard-coded.

Failure to observe these assumptions will only mean that for files that don't fit them, nimlike will show an error 59 instead of a comment page, so depending on how your site is organized, they may be a deal-breaker or completely irrelevant.

## Abuse resistance

There is currently very little of that, but client certificates should at least discourage casual spamming a little. A post can only be liked by a given IP address once, but that's about it.

I am of a mind that, barring the actual security holes, reacting to people actually engaging in abuse, rather than preventively trying to block legitimate things they *might* try to do too much, makes more sense for a hobby tool like that.

That said, it is very much recommended to disallow access to `nimlike` in your `robots.txt`:

```
User-agent: *
Disallow: /cgi-bin/nimlike/
```

There are bots which ignore this, and there's no POST in Gemini, so there's nothing the bots *usually* won't do, and we can't do anything about that. A bot coming over and accidentally liking all of your posts out of the blue is still just as much a problem as it was.

## Example comment page

Here's an example of what a comment page looks like:

``` markdown
# My Cool Post

This post was ❤️ by 1 readers.

## Comments:

──── 2022-02-19: r2aze commented,

> I have written a most marvelous proof, which this margin is too narrow to contain.
=> https://google.com See google

ID hash: ❤️🖥🦀💕
────

## Writing comments:
* Leaving a like or comment records your IP address, for obvious reasons. It's never shown to anyone.
* You need to present a client certificate to leave an actual comment.
* Newlines are allowed in comments, if your browser can send them. Gemini links will work, if put on a separate line.
* You can state a nickname by starting your comment with "<nickname>:<space or newline>"
* If you don't supply a nickname, it will be taken from your certificate's UID or CN.
* If your certificate doesn't have any of those, you will be called "Anonymous".

=> /cgi-bin/nimlike/like/archive/my-cool-post.gmi ❤️ Like this post
=> /cgi-bin/nimlike/comment/archive/my-cool-post.gmi 💬 Add a comment
=> /archive/my-cool-post.gmi ↩ Go back

```

This also neatly illustrates some of the distinctive capabilities of nimlike.

## Usage

Assuming a file *located at* `/foo/bar/my-cool-post.gmi` (rather than named `my-cool-post.gmi` which is what would be relevant to gemlikes) needs comments and likes, put a link in it:

```
=> /cgi-bin/nimlike/show/foo/bar/my-cool-post.gmi View comments and likes
```

To be more precise, the requisite URL is `<path to nimlike executable>/show/<full path to target page sans the opening slash>`.

## Internals

Database, or what passes for it, is stored in [jsonl](https://jsonlines.org/) files -- that is, blocks of compressed JSON separated by newlines. Similarly, records of likes are one-IP-address-per-line text files with a trailing newline. There hardly is a need for a true database in this application -- my comment system for my html blog, which shares a lot of design ideas with nimlike, doesn't have one either. The big difference is that there, frontend reads the jsonl files directly and takes care of rendering, so less sensitive information is stored. There's no frontend in Gemini space, so nimlike takes care of it by itself.

Each URL's "database" is a single file. The names of the files are sha1 hashes of their URL, so it's irrelevant what you get up to in your URLs or how long they are. If you need to move a post to a new URL, you will have to figure out the new hash (just leave a like and see which file got created) and rename the files.

This allows you to keep the database in a git repository, as well as do mass edits on it with existing command-line tools and things like [jq](https://stedolan.github.io/jq/).

At the moment, if you don't like the particular rendering of the comment page, you still need to edit the source code, but if there's enough demand for it, I might adopt a templating language for the purpose.

## Configuration

On startup, nimlike looks for a configuration file. If the environment variable `NIMLIKE_CONFIG_FILE` is set to a file name, (absolute path please) configuration will be loaded from there. Gmid, for one, allows you to set CGI environment variables in server config, and others might have a similar feature -- or, if they pass their own environment variables to their cgi children, you could set it above them.

Otherwise, the file named `nimlike.ini` will be sought in the current directory, wherever that is. I'll just quote it here for ease of reading:

``` ini
;; Nimlike config

[nimlike]

;; Where the server root is. Needs an absolute path.
server_root=/home/mihara/Projects/blog/gemini/

;; Where we keep our "database", which is a directory that must be writable by
;; the server and/or its cgi children, somewhere outside server root.
;; It will not be created automatically.
;;
;; Comments will be in *.jsonl
;; Likes will be in *.txt
;;
data=/home/mihara/Projects/blog/gemini-nimlike/

;; Regexp to tell commentable files from non-commentable in a generic way. If
;; it matches the filename, comment is allowed, unless it also matches any of
;; the forbid regexps below.
;;
;; Needs to be written with r"" like that to work, that's Nim syntax.
;; The syntax for the regular expression itself is standard PCRE.
allow = r"\.gmi$"

;; Salt for the emoji hash function.
salt = "moderatelywickedwitchoftheeast"

;; The name for commenters for whom a nickname cannot be determined.
anonymous = Anonymous

;; You can uncomment this to disable like functionality while leaving in the
;; comments.
;disable_likes = true

[forbid]
;; A list, one per line, of URL regexps, leading slash excluded, on which comments
;; and likes are forbidden.
;; I use it to exclude pages like tag and post lists.
r"^archive.gmi"
r"^tags.gmi"
r"^index.gmi"
r"^categories/.*"
r"^tags/.*"
```

I believe the above comments are sufficient to explain what does what. You can also check out the extensively commented source code.

## License

This program is licensed under the MIT license, the full text of which you can find in the [LICENSE](LICENSE) file.

