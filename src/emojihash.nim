import marshal
import std/sha1

## During compile time, we load our emoji alphabet.
proc loadAlphabet(): seq[cstring] =
  let emojiList = staticRead"alphabet.json"
  return to[seq[cstring]](emojiList)

const alphabet = loadAlphabet()

proc emojiHash*(s: string): string =
  ## This takes a string, produces a sha1 hash of that string
  ## (a salt is added before this gets called) and then tries
  ## to express it as a sequence of emoji.

  #[ Eventually I got fed up trying to do arbitrary length integers
  and bit-shifting, and opted for something easier.

  We have 20 bytes in sha1, so we can have 5 chunks of 4 bytes.  Just convert
  each chunk into a float between 0 and 1, mapping 0 to 0 and 1 to max 4 byte
  unsigned int.  Then map those over the list of emoji we have selected for
  this.

  Is this a correct baseN implementation? Very much no. Will it work and give
  unambiguous results? Yes. I had to jump hoops to get it to work on 32 bit
  systems, though. Which, unfortunately, your typical Raspberry is. ]#

  var thatHash = newSha1State()
  thatHash.update(s)
  let rawHash = thatHash.finalize()

  const maxCell = float(0xffffffff)

  for chunk in 0..4:
    var chunkSum: uint64
    for cell in 0..3:
      chunkSum += uint(rawHash[chunk*4+cell]) shl (cell*8)
    result &= alphabet[int((float(chunkSum) / maxCell) *
    (len(alphabet) - 1))]

when isMainModule:
  echo emojihash("This is a string.")
  doAssert emojihash("This is a string.") == "🐯🐏🙇🌕🎙"
