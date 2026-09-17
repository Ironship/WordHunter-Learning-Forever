# QuestWordHunter — German Voiceover: Classic

The German a quest giver says out loud, for Classic: quest ids **1–9,665**.

**25,234 clips, 35.1 hours.** Both are counted from this pack's own duration
table in `Part.lua` — the table the engine plays from — so they are what the
pack can actually be asked for, not what happens to sit on disk.

One clip per sentence, across the three passages an NPC speaks: the offer, the
progress line and the hand-in. Quest titles and objectives are not here. Nobody
says them out loud; they are read off the screen.

The boundary is a quest id range because ids were handed out roughly in the
order the content was written. It is approximate at the edges — a quest added to
an old zone years later keeps a new id — and harmlessly so: a quest outside the
range is silent for anyone who holds only this pack, which is what already
happens for a clip nobody has generated yet.

## On Classic Era the words can differ

The clips were read from Retail quest text. On Classic Era the same quest id
does not always mean the same words: roughly one in five shared ids has a
different German title (`Garrick Padfoot` vs `Garrick Schleichfuß`,
`Blackrock` vs `Schwarzfelsklan`), and some ids are entirely different quests
on the two games. Offer, progress and hand-in lines come from the same source,
so where the text diverged you will hear the Retail telling. This note stands
until the clips are re-read from Classic text.

## It does nothing on its own

Everything that decides when to play a clip is in the engine addon,
[QuestWordHunter — German Voiceover](https://github.com/Ironship/WordHunterWoW-Voice-DE).
It is a hard dependency: without it the client will not load this pack at all.

## The audio is in this repository

`sounds/` is committed, and `.gitignore` says why. It is 648 MB here, out of
about 6.1 gigabytes across the twelve packs. So a checkout of this repository is
installable by itself: copy the folder into `Interface/AddOns` and it plays.

`Tools/build_pack.py` in the engine repository assembles the same thing, and is
the quicker route when the clips have just been regenerated:

```
python Tools/build_pack.py --only Classic --out "…/Interface/AddOns"
```

## Where a clip lives

`sounds\q\<id mod 100>\<id>_<o|p|c><sentence>.ogg` — `o` is the offer, `p`
the progress line, `c` the hand-in, and sentences are numbered from one. The
engine computes that name and asks the client for it, so there is no index that
can fall out of step with the files. The two-digit folder is there only so that
nothing has to open a directory of tens of thousands of clips.

Retail 12.1 (interface 120100) and Classic Era (11509) — one manifest each.
GPL v3, see `LICENSE`. The audio carries CC BY-NC 4.0, which `NOTICE` sets out:
this is given away and may not be sold.
