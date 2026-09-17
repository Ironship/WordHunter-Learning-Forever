# QuestWordHunter — German Voiceover: Words

Single German words, spoken. This is the pack the engine reaches for when you
click a word, rather than when you open a quest.

**104,274 clips, 28.8 hours.** One for every entry in the dictionary. It was
last in the generation order, behind the eleven expansions of quest text, and
`Part.lua` — the file that tells the engine a word pack is installed at all —
was under version control from the start, so the pack had somewhere to land.

Every clip has been listened to by a speech recogniser and checked against the
word it was asked for, and 4,619 of them were respoken until the recogniser
could hear the word in the replacement. The fault being repaired: the reader,
given three characters and nothing else to align on, would sometimes invent
several seconds of confident German around the word.

Unlike a quest pack this one declares no range. A word's clip is named by a hash
and there is nothing to compare, so the engine simply takes the one word pack it
finds.

## It does nothing on its own, and it needs two addons rather than one

Everything that decides when to play a clip is in the engine addon,
[QuestWordHunter — German Voiceover](https://github.com/Ironship/WordHunterWoW-Voice-DE).

It also needs [QuestWordHunter](https://github.com/Ironship/WordHunterWoW)
itself, which the quest packs do not. A quest pack plays when a quest window
opens, and the engine watches for that on its own. A word plays when somebody
clicks one, and clicking a word is something only QuestWordHunter's panel
offers — so without it these clips are 104,274 files nothing can reach.

Both are hard dependencies: without either, the client will not load this pack
at all.

## The audio is in this repository

`sounds/` is committed, and `.gitignore` says why. It is 804 MB here, out of
about 6.1 gigabytes across the twelve packs. So a checkout of this repository is
installable by itself: copy the folder into `Interface/AddOns` and it plays.

`Tools/build_pack.py` in the engine repository assembles the same thing, and is
the quicker route when the clips have just been regenerated:

```
python Tools/build_pack.py --only Words --out "…/Interface/AddOns"
```

## Where a clip lives

`sounds\w\<first two hex digits>\<64-bit FNV-1a of the key>.ogg`. The name is
a hash rather than the word because German keys carry umlauts and the eszett,
and a WoW client does not reliably open a file whose path has those in it. The
same hash is computed in `Tools/naming.py` and in `Naming.lua` in the engine
repository, and `tests/naming.test.lua` holds the two to the same answers.

Retail 12.1 (interface 120100) and Classic Era (11509) — one manifest each.
GPL v3, see `LICENSE`. The audio carries CC BY-NC 4.0, which `NOTICE` sets out:
this is given away and may not be sold.
