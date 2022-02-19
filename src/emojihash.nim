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

  We have 20 bytes in sha1, so we can have 4 chunks of 5 bytes.  Just convert
  each chunk into a float between 0 and 1, mapping 0 to 0 and 1 to max 5 byte
  unsigned int.  Then map those over the list of emoji we have selected for
  this.

  Is this a correct baseN implementation? Not really. Will it work and give
  unambiguous results? Yes. ]#

  var thatHash = newSha1State()
  thatHash.update(s)
  let rawHash = thatHash.finalize()

  # This is kinda bullshit if you ask me: I can't *just* toFloat an int64.
  const maxCell = toFloat(int(0xffffffffff))

  for chunk in 0..3:
    var chunkSum = 0
    for cell in 0..4:
      chunkSum += int(rawHash[chunk*5+cell]) shl (cell*8)
    result &= alphabet[int((toFloat(chunkSum) / maxCell) *
    (len(alphabet) - 1))]
