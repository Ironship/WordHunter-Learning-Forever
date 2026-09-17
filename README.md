# WordHunter Learning for World of Warcraft: Forever

The WordHunter addons -- quest words you can click and learn, the English text
of the quest beside the German one, a German dictionary, and a German voice
reading the quest giver's lines -- packaged for the **World of Warcraft:
Forever** beta client. Six addons, taken unchanged from their own repositories
and given the manifest this client asks for.

This is a beta build for a beta client. It was made on 2026-09-17, the day the
beta opened, and has not yet been seen running in the game: the client had
never been launched when it was built. What rests on evidence and what rests
on nothing yet is set out below.

## Installing

Every addon goes into the beta client's addon folder:

    C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\

Either unpack the six zips from the Releases page there, or copy the six
addon folders out of a checkout of this repository -- a checkout is
installable as it stands. GitHub's *Download ZIP* unpacks everything into a
folder called `WordHunter-Learning-Forever-main`; copy the six folders out of
it, not the folder itself.

| folder | version | what it does | needs |
|---|---|---|---|
| `WordHunterWoW` | 1.19.4 | the base addon: clickable quest words, your word list, the quest panel | -- |
| `WordHunterWoW-ENPanel` | 1.6.3 | the English text of the quest, Classic data | works alone |
| `WordHunterWoW-Dictionary-DE` | 1.5.0 | German-English dictionary, 73,863 entries | base |
| `WordHunterWoW-Voice-DE` | 1.1.1 | the voiceover engine | works alone |
| `WordHunterWoW-Voice-DE-Classic` | 1.0.2 | German quest audio, quest ids 1-9665, 25,234 clips | engine |
| `WordHunterWoW-Voice-DE-Words` | 1.0.6 | German audio for single dictionary words, 104,274 clips | engine, base |

The two sound packs are 1.4 GB between them. Everything else is 17 MB.

The game reads addon manifests once, at start-up. After copying files while
the game runs, quit and start it again; `/reload` is not enough.

## What the Forever client is, as far as addons are concerned

Battle.net installs it as product `wow_classic_beta` into `_classic_beta_`,
beside `_retail_` and `_classic_era_`. The build is **1.60.1.69893** and
Blizzard's codename for it is **Camelot**: the executable carries
`Blizzard.Telemetry.Wow_Camelot` and a `DefaultForeverBindings.wtf`.

Three facts decide the package:

- The loader wants **`<Addon>_Camelot.toc`**, the way Classic Era wants
  `_Vanilla` and Retail `_Mainline`. Deadly Boss Mods ships six such
  manifests, and its own detection reads
  `private.isForever = private.wowTOC == 16001`.
- The interface number is **16001** -- 1.60.1 written the way every manifest
  writes a version, and the number DBM's Camelot manifests carry.
- The API is the **Classic Era surface**, so each package is the Classic Era
  variant of the addon (the `_Vanilla` manifest's file list) under the new
  number. ENPanel therefore ships its Classic quest data, not the Retail set.

Each addon carries the Camelot manifest and a plain `<Addon>.toc` with the
same content. The plain one is the loader's fallback should it not know the
suffix; it costs 500 bytes and means the addon cannot simply vanish from the
list. The `_Vanilla` manifest is deliberately **not** shipped: if the Forever
loader did read it, its 11509 would mark the addon out of date.

## Not verified in game

Launch the beta, open the AddOns list at the character screen, and check that
all six appear and none is marked out of date. If they are marked out of date
the number is wrong; if they are missing altogether the suffix is wrong and
the fallback manifest did not catch it. Either is worth an issue here.

Known limits that the packages inherit rather than introduce:

- ENPanel knows the 4,244 Classic Era quests. Quests Forever adds -- its new
  dungeons, Hall of Thanes and the rest -- show no English text until the
  Classic data is rebuilt against Forever.
- The Classic sound pack was read from Retail's German text, and where the
  Era wording differs the Retail telling is what plays; the pack's own README
  says so. Forever presumably runs Era's wording.
- `WordHunterWoW-ENPanel-Items`, the English item names, is not here. It would
  build the same way: add it to `ADDONS` in the script.

## How it was built

`build_forever.py` takes, for each addon, the files git tracks in its
repository minus what its `.pkgmeta` ignores -- the same set CurseForge's
packager builds from a tag -- then drops the Retail and Era manifests, drops
any Lua the Era manifest never loads (ENPanel's Retail quest text), and writes
the two manifests above. It refuses to build if a manifest names a file that is
not tracked. Every zip is reopened after writing and its members compared, by
name and size, against what went in; a written tree is compared the same way.
`BUILD-INFO.txt` names the commit each addon was built from and the sha256 of
each zip.

The script expects the six addon repositories as siblings of this one:

    python build_forever.py --out .          # the six folders here, and the zips
    python build_forever.py --install        # straight into the beta client

Built from: [WordHunterWoW](https://github.com/Ironship/WordHunterWoW),
[WordHunterWoW-ENPanel](https://github.com/Ironship/WordHunterWoW-ENPanel),
[WordHunterWoW-Dictionary-DE](https://github.com/Ironship/WordHunterWoW-Dictionary-DE),
[WordHunterWoW-Voice-DE](https://github.com/Ironship/WordHunterWoW-Voice-DE),
[WordHunterWoW-Voice-DE-Classic](https://github.com/Ironship/WordHunterWoW-Voice-DE-Classic),
[WordHunterWoW-Voice-DE-Words](https://github.com/Ironship/WordHunterWoW-Voice-DE-Words).

## Licences

Each addon folder carries its own `LICENSE` and, where it ships third-party
data, a `NOTICE`; those are the terms, unchanged from the source repositories.
The English panel, the dictionary and the voiceover are GPL v3. The audio is
CC BY-NC 4.0: it is given away and may not be sold.

## The step after this one

Once the client is seen loading them, the durable fix is a
`<Addon>_Camelot.toc` in each of the six repositories, so that CurseForge
builds Forever files from every tag instead of this repository building them
by hand.
