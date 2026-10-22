local ADDON_NAME = ... or "WordHunterWoW-Voice-DE"
local Addon = WordHunterWoW_Voice or {}
WordHunterWoW_Voice = Addon

-- Every sound pack carries a copy of the engine -- these five files and the two
-- stand-in clips -- so that any one pack is a complete download and there is no
-- separate engine to install first. The client loads addons in the order of
-- their folder names, so the first pack it reaches runs its copy and writes its
-- folder here; the copies in every pack after it read the name, see it is not
-- theirs, and stop at their first lines -- each of the five files carries the
-- same two. One engine runs, whichever pack it came from, and finds every
-- pack's clips the way it always has: by the folder each pack names in Part.lua.
--
-- A stand-alone engine from before the packs carried one -- the old
-- WordHunterWoW-Voice-DE folder, if it was never removed -- loads ahead of any
-- pack by the same alphabetical rule and defines its functions without ever
-- naming a host. ForgetParts is one of them, and its presence means an engine
-- is already running, so the copies yield to that one too rather than run a
-- second engine over it.
--
-- The version is written down here rather than read from a manifest because a
-- pack's manifest carries the pack's version, which moves when clips are
-- re-read and the engine has not changed. Each copy files its own before it
-- yields, so the running engine can say when a pack carries a newer one than
-- the copy that got to run -- Settings.lua's page and /whwv both do.
local ENGINE_VERSION = "2.0.6"
Addon.copies = Addon.copies or {}
Addon.copies[ADDON_NAME] = ENGINE_VERSION
if Addon.host == nil and Addon.ForgetParts == nil then Addon.host = ADDON_NAME end
if Addon.host ~= ADDON_NAME then return end

-- Where a clip lives. The same arithmetic as Tools/naming.py, and
-- tests/naming.test.lua holds the two to the same answers.
--
-- No bit library. WoW ships one, but FNV-1a only ever exclusive-ors a single
-- byte into the hash, so only the low eight bits can change -- and eight bits
-- can be done with arithmetic that runs anywhere, including the plain
-- interpreter the tests use.

local MASK32 = 4294967296
local PRIME = 16777619
local OFFSET = 2166136261

local function xor8(a, b)
  local result, place = 0, 1
  for _ = 1, 8 do
    local x, y = a % 2, b % 2
    if x ~= y then result = result + place end
    a, b, place = (a - x) / 2, (b - y) / 2, place * 2
  end
  return result
end

-- a * b modulo 2^32, without ever forming a number Lua cannot hold exactly.
-- Splitting b into two 16-bit halves keeps every partial product under 2^48;
-- the doubles Lua 5.1 counts with are exact to 2^53.
local function mul32(a, b)
  local low = b % 65536
  local high = (b - low) / 65536
  return ((a * high) % 65536 * 65536 + a * low) % MASK32
end

local function fnv1a32(text, seed)
  local hash = seed or OFFSET
  for i = 1, #text do
    local byte = text:byte(i)
    local tail = hash % 256
    hash = mul32(hash - tail + xor8(tail, byte), PRIME)
  end
  return hash
end

-- Sixty-four bits, as two passes with different seeds. One pass is not enough:
-- over a hundred thousand words a 32-bit hash collides more likely than not,
-- and a collision plays a different word out loud.
function Addon.WordHash(key)
  local first = fnv1a32(key)
  local second = fnv1a32("\1" .. key)
  return string.format("%08x%08x", first, second)
end

-- What a pack's clips are encoded as.
--
-- Vorbis until 2026-09-20, and still Vorbis for every pack that says nothing:
-- the extension used to be written into these two functions, and a pack built
-- before this one does not know the question was ever asked.
--
-- The packs that go to CurseForge are MP3 now. Three approved projects hold
-- about 3,500 MB between them and the quest audio is 5,246 MB; measured on
-- real clips, 24 kbps MP3 is the first setting that fits and no Vorbis setting
-- does. A pack declares `ext = "mp3"` in its Part.lua and the engine asks the
-- client for the name that pack actually shipped.
local function extension(ext)
  return ext == "mp3" and "mp3" or "ogg"
end

function Addon.WordPath(key, ext)
  local hash = Addon.WordHash(key)
  return "sounds\\w\\" .. hash:sub(1, 2) .. "\\" .. hash .. "." .. extension(ext)
end

-- The three passages an NPC says out loud. Objectives and the title are read
-- off the screen by the player, not spoken by anyone.
Addon.SPOKEN_FIELDS = { description = "o", progress = "p", completion = "c" }

-- One clip per sentence, numbered from one in reading order. The addon lights up
-- the sentence it is reading, and a clip that held a whole passage could not be
-- pointed at any single line.
function Addon.QuestPath(questId, field, sentence, ext)
  local letter = Addon.SPOKEN_FIELDS[field]
  questId, sentence = tonumber(questId), tonumber(sentence)
  if not letter or not questId or not sentence then return nil end
  return string.format("sounds\\q\\%02d\\%d_%s%d.%s",
    questId % 100, questId, letter, sentence, extension(ext))
end

-- The running engine's version: the one the host pack filed at its first line.
function Addon.EngineVersion()
  return Addon.copies and Addon.host and Addon.copies[Addon.host] or nil
end

-- "2.0.1" against "2.0.0", part by part, so that "2.10.0" is newer than "2.9.0".
local function newer(a, b)
  local pa, pb = {}, {}
  for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x > y end
  end
  return false
end

-- The packs whose copy of the engine is newer than the one that got to run, as
-- { folder = ..., version = ... }, so the settings page and /whwv can name the
-- pack to update: the client runs the first copy it loads, not the newest, and
-- after updating one pack of several the new version can be on disk and not
-- running, with nothing else anywhere to say so.
function Addon.NewerCopies()
  local found = {}
  local running = Addon.EngineVersion()
  if not running then return found end
  for folder, version in pairs(Addon.copies) do
    if folder ~= Addon.host and newer(version, running) then
      found[#found + 1] = { folder = folder, version = version }
    end
  end
  table.sort(found, function(a, b) return a.folder < b.folder end)
  return found
end
