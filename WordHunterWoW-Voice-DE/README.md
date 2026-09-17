# QuestWordHunter — German Voiceover

Quest text you can read is already here. This is the part you can listen to: the
German a quest giver hands you, spoken, and any single word out loud when you
click it.

**Status: spoken.** All of it — every quest passage in every expansion, and
every word in the German dictionary. 341,538 clips in twelve packs.

## Why it has to be pre-generated

The WoW client cannot synthesise speech. There is no API for it and no way to
reach one from an addon. Everything the pack says has to be generated in
advance, encoded as Ogg Vorbis, and shipped as files the client plays with
`PlaySoundFile`.

That decides the shape of the project. It is not an addon with a tool beside it;
it is a generation pipeline whose output happens to be an addon.

## How big it is

Measured, not estimated, against the German corpus in
`WordHunterWoW-Dictionary-DE`:

| | clips | audio |
|---|---:|---:|
| quest passages — offer, progress, hand-in | 237,264 | 281.3 h |
| dictionary words | 104,274 | 28.8 h |
| **total** | **341,538** | **310.1 h** |

Objectives and quest titles are not in it. Nobody says them out loud — they are
read off the screen.

The clip count is sentences, not passages: there are 71,775 passages, and each
is cut into one clip per sentence so a reading can be followed, paused and
resumed a sentence at a time.

Both hour figures are measured rather than projected, which they did not use to
be. The quest hours are the sum of every value in the eleven packs' own duration
tables; the word hours are read off the clips themselves. The table used to say
368 h and 397 h, extrapolated from the 107,489 clips that existed at the time at
5.59 s each — the finished corpus averages 4.27 s, and carrying the early mean
across the rest is where the extra 87 hours came from. It also said no word had
been spoken yet, which stopped being true the day the word pack was committed.

At the pace an RTX 4090 runs the reader, that is days of generation, not weeks,
and it only has to happen once. Afterwards each run does the new quests and
whatever text Blizzard rewrote.

## Choosing the reader

Four readers were measured on the same fifty real passages, with the same
reference recording, and the output transcribed back with Whisper and compared
to the text it was given. That number is what a listener hears as a fault: a
reader that stutters gains a word, one that gives up loses several.

| reader | word error | insertions | word for word |
|---|---|---|---|
| Chatterbox Multilingual 0.1.7 | 23.5% | 16.2% | 24 of 50 |
| Chatterbox Multilingual V3 | 11.6% | 2.2% | 23 of 50 |
| Qwen3-TTS 1.7B | 9.2% | 4.1% | 36 of 50 |
| Voxtral 4B | — | — | chosen on listening |

*Insertions* is where the fault this project kept hitting lands: a reader given
a single word says it and then carries on inventing sentences, because nothing
in a one-word prompt tells it to stop. The dictionary is 104,274 single words,
so that column decides more than the first one does.

Two things came out of the measuring that were not about the models at all.
The references were being destroyed before the reader ever saw them — a
`silenceremove` filter set to remove pauses was also removing the quiet parts of
words, so "ich habe sie bei einem Absturz verloren" reached the reader as
"...bei einem Absturz". Repairing that halved Chatterbox's rambling on its own.
And a reference cut off mid-sentence made Qwen finish the sentence before
starting the one it was asked for, which looked exactly like a model defect and
was not.

**Voxtral 4B** (Mistral, March 2026) is what ships. It is twice the size of the
next largest, German is one of nine languages rather than one of twenty-five,
and it was chosen by ear against the others on the same lines.

Its licence is **CC-BY-NC-4.0**, inherited from the voice datasets it was
trained on. That is a deliberate choice and not an oversight: this addon is
given away, which is what non-commercial means, and the alternative was to ship
a reader that says the wrong word once in every nine.

The trade it forces is voice cloning. Mistral removed the audio encoder from the
open weights, so the reader cannot be given a voice — it has twenty-one of its
own, of which `de_male` and `de_female` are native German. The upload endpoint
accepts a recording and stores it, but computes no embedding for it
(`embedding_dim: null`), and speech generation then does not know the voice.

`voices/` is what is left of that attempt, and it is not shipped or tracked —
only its README is. What sits there is the game's own flirt and joke lines,
pulled from the client to cut references from, back when the plan was a voice
per race. This file used to describe them as contributors' recordings, which was
never what they were; `.gitignore` has always kept the whole folder out, and
says plainly that game recordings must never be published.

`de_male` and `de_female` are the two in use, the reader's two native German
presets. Every clip is brought to −18 LUFS on the way out, so the pack is even
whoever is speaking and a quest giver is not inaudible under the game.

The man was `neutral_male` for the first 68,795 clips, picked off a single
sample that sounded better. That sample did not show what a quest chain did:
`neutral_male` is the model's general-purpose voice, not a German one, and it
reads German with an audible English accent. The thirteen decibels between it
and `de_male` were the tell and were read as a loudness quirk to be normalised
away -- two voices built for different languages will not agree on level. All of
those clips were spoken again.

### Running it

vLLM has no Windows build and the weights ship in Mistral's own format, so the
reader runs under WSL:

```bash
VLLM_USE_FLASHINFER_SAMPLER=0 \
  vllm serve mistralai/Voxtral-4B-TTS-2603 --omni --port 8000
```

`VLLM_USE_FLASHINFER_SAMPLER=0` is not optional. vLLM otherwise picks
flashinfer for sampling and compiles that kernel on first use, which needs a
CUDA toolkit; WSL carries the driver and no compiler, so the engine dies after
the model has already loaded.

## The pipeline

```
Tools/plan_lines.py       what still has to be spoken, and what has to be spoken again
Tools/generate_voxtral.py speak it, resumably, in batches of sixteen
Tools/build_pack.py       assemble the clips into installable sound packs
Tools/pack_release.py     zip them for CurseForge, and prove each zip opens
```

Nothing in it is a one-shot. `plan_lines.py` compares the corpus against what is
on disk and reports three numbers — generated, missing, stale — where *stale*
means the German text changed under a clip that already exists.
`generate_voxtral.py` does exactly that list. Run both again after a patch and only the difference is
spoken.

```bash
python Tools/plan_lines.py --write
python Tools/generate_voxtral.py --limit 64      # listen to a pilot first
python Tools/generate_voxtral.py                 # then the rest
python Tools/build_pack.py --only Classic        # one pack, as soon as it is done
python Tools/build_pack.py --out "…/Interface/AddOns"   # straight into the client
python Tools/pack_release.py                     # the upload archives, all thirteen
python Tools/pack_release.py --check             # open the ones already built
```

`pack_release.py` exists because the archives used to be zipped by hand, and on
2026-09-14 one of them was wrong: the Words archive had a valid header, 643 MB
of content and no end-of-central-directory record at all, so nothing could open
it. A directory listing could not tell — it looked like a slightly smaller file,
which reads as "compressed well" rather than as "stopped early". The real
archive is 828 MB. So the tool reopens every archive it writes and compares it
against what went in, and writes to a `.partial` name until that passes. What
goes in is what git tracks minus what `.pkgmeta` ignores, which is the same
answer CurseForge's own packager would reach from the same tag.

The order is the order the packs are released in: Classic first, then each
expansion, and the dictionary's hundred thousand words last. Left in plan order
Classic would only be finished once most of the corpus was, and there would be
nothing to give anyone for a day.

Measured at 230 to 300 clips a minute on a 4090 — the whole corpus in a bit
over a day, Classic in ninety minutes. The figure holds with the game running,
but only because the reader is told to cap its cache: left to size itself it
takes all but 700 MB of the card, and Windows then evicts it to host memory the
moment WoW starts. Nothing reports that. The reader answers every request and
the rate falls to a seventh. Batching is what buys that: sixteen clips per
request rather than one. Larger batches are worse, not better, because every
clip in a batch waits for the longest one in it and the card runs out of memory
around forty-eight.

`ffmpeg` must be on PATH. `pip install -r Tools/requirements.txt` for the rest.

## How a clip is found

The addon does not ship an index. It computes the name of the clip it wants and
asks for it; if that file has not been generated, nothing plays and nothing
breaks.

- a quest passage is `sounds/q/<id mod 100>/<id>_<o|p|c><clip>.ogg`, numbered
  from 1 — one clip per sentence except where two short ones were read together,
  which is what the next section is about
- a word is `sounds/w/<first two hex digits>/<64-bit FNV-1a of the key>.ogg`,
  because German keys carry umlauts and the eszett and a WoW client does not
  reliably find a file whose path has those in it

The hash is computed in `Tools/naming.py` and in `Naming.lua`, and the two
implementations are held to the same frozen vectors by `tests/naming.test.lua`.
A drift between them would not be an error — it would be silence on every word
in the pack, which is why it is a test.

Across all 104,274 words in the shipped dictionary, no two share a clip.

## Which sentences a clip covers

A clip is not always one sentence. `Tools/speech.py` joins a sentence shorter
than thirty characters to its neighbour, because the reader stumbles on a
two-word clip, so clip 2 of a passage may be its sentences 3 and 4. The addon
needs that mapping to light the right English line and to put a play button
beside the right paragraph.

The pack ships it. `Part.lua` carries a `starts` table beside `lengths`, one
line per passage, holding the first sentence of each clip:

    8473 o 1,3,4,5

The engine used to work this out for itself instead, on the reasoning that both
sides hold the same text and the same sentence splitter. They do not hold the
same text. The generator groups what the narrator was given, with the vocative
struck out because there is no player name to record: "Das sind schwierige
Zeiten, {name}." is spoken as "Das sind schwierige Zeiten." — 27 characters,
under the minimum, so it was joined to the sentence after it. The client draws
the same line with a name in it, 36 characters, and the addon left it standing
alone. One clip in the pack, two spans in the addon, and from there every play
button in quest 8473 sat one paragraph too high and the last paragraph had none.
Measured over the corpus with the tokens filled in, 2,285 of 71,775 passages
came out with a different number of clips.

Sentence *numbers* are what survives the difference: filling a token in changes
how long a sentence is, never how many sentences come before it. So the pack
carries numbers rather than lengths, and the whole class goes with it rather
than the one instance.

Only the first sentence of each clip is written, and only where the grouping is
not simply one clip per sentence — 42% of passages, 450 KB against the 1.5 MB
the durations already take. The last sentence of a clip is the one before the
next clip starts; a passage with no line is read one clip per sentence, and how
many clips that is comes from the duration row, never from counting the
sentences on screen.

A pack built before this table existed has no `starts` at all, and the engine
falls back to working the grouping out as it used to. Those keep playing, wrong
in the way described above for the passages that carry a substitution and right
for the rest. Rebuilding a pack fixes it.

`tests/spans.test.lua` pins quest 8473 itself, text and pack written out, so the
case somebody photographed fails loudly on a bare checkout.
`Tools/crosscheck_grouping.py` and `tests/grouping.test.lua` hold the addon to
the generator's answer across four thousand passages, on text with the
substitutions filled in. They did not before: the checker ran `speech.clean()` over the text and handed the result to
both sides, so the transformation under suspicion had already been applied to
the input and the two agreed across 13,177 clips while the real case diverged.

## Packaging

One engine addon, several sound packs. The German VoiceOver for Classic is split
into four parts and that covers Classic alone; this covers Retail.

Each pack declares the range of quest ids it covers, so the engine knows where
to look without a manifest of 341,538 filenames. Install some of the parts and
you get what those parts cover — the rest is silent rather than broken.

### The quest audio is read from Retail's German, on every client

Worth knowing before installing on Classic Era. `Tools/plan_lines.py` builds the
plan from Retail records only, and the quest packs ship a Classic Era manifest,
so on Era a clip is found and played for a quest whose on-screen German may not
be the German that was read.

It is the same quest and the same id — the divergence is in the wording.
Cataclysm rewrote quests that Era still runs as they were, and Blizzard later
translated proper nouns that Era's deDE leaves in English: Padfoot became
Schleichfuß, Blackrock became Schwarzfelsklan, Scrimshank became Kieselschliff.
Measured across the 4,231 quests held in both, 696 titles differ — 16.5%. Body
text is likely worse, since it carries more names, but that cannot be measured
yet: the Classic harvest captured titles and objectives only, and the spoken
fields were never collected.

Which is also why this is not fixed rather than merely described. Generating
Classic audio needs Classic quest text, and that has to be harvested from a
Classic client first. Until then the packs are useful on Era with the words
sometimes wrong, which is a better trade than refusing to load. The dictionary
word pack is unaffected — a German word is the same word on either client.

Every pack is a git repository of its own, beside this one — twelve of them,
`WordHunterWoW-Voice-DE-Classic` through `-Words`. A pack repository holds
everything the addon is made of, audio included: both manifests, the licence,
the notice, `sounds/`, and `Part.lua`, which `build_pack.py` generates because
it is derived from the clips. A checkout is installable as it stands.

The audio is committed rather than fetched from somewhere, because CurseForge
packages a tagged commit — a pack repository without its clips would publish an
addon that installs, loads, and is silent, which is worse than one that fails.
Git saves 9% on ogg and nothing at all between two renderings of the same
sentence, so a re-read of the corpus adds its full size to history again; the
answer to that is to squash when it happens, and it has been done once already,
which took Cataclysm from 1,352 MB back to 736.

That is why `build_pack.py` writes to two places. `--repos` is where those
repositories live and gets the generated manifest; `--out` is where a playable
pack is assembled, the repository's files plus the clips, and is what the client
loads. Making the repository itself the assembled pack was the alternative, and
it would put a second seven gigabytes on a disk the generator is already writing
to in order to version a file that is 200 KB.

## Races

The intent is a voice per race rather than one narrator. More voices cost
nothing to generate: a quest is spoken once, in one voice.

What is missing is which race gives which quest. Blizzard's API does not publish
it — the quest endpoint has no quest giver, and the creature endpoint answers
404 for the ids tried. Other packs take it from a third-party content dump; this
project does not use one and will not start.

The client knows at the moment the window opens, and this project already fills
exactly that kind of gap by collecting from the client. See `voices/README.md`.

So: a narrator first, because it needs nothing that does not exist; the map
collected while people play; race voices for what the map covers, growing with
it.

## Layout

```
Naming.lua        where a clip lives — the addon's half
Voice.lua         playback, quest hooks, the word hook
Talker.lua        the window that shows who is speaking, and the transport
PlayButtons.lua   a play button beside each paragraph, drawn into the base panel
Settings.lua      the options page, and what it says when no pack is installed
Tools/naming.py   where a clip lives — the generator's half
Tools/speech.py   quest markup out, speakable German in
Tools/plan_lines.py, generate_voxtral.py, build_pack.py
Tools/check_install.lua  asks the engine itself where every clip should be
tests/            nine files; run each with `lua` or `python`
```

## On its own, or alongside the word hunter

This addon does not need [QuestWordHunter](https://github.com/Ironship/WordHunterWoW).
Install it with a sound pack and nothing else, open a quest, and it reads: it
watches the quest events itself rather than waiting to be told, and the window
that shows who is speaking — with its stop and pause — is its own. So is the
options page.

What QuestWordHunter adds is a surface rather than a capability. Its quest panel
is where the play button beside each paragraph is drawn, and where the English
sentence lights up in step with the reading. Neither can exist without a panel
to draw into, so without it they are simply absent, and the reading is unchanged.

Clicking a single word to hear it is the one thing that does want the base
addon, because clicking a word is something its panel offers.

Retail 12.1 and Classic Era. GPL v3 — see `LICENSE`.
