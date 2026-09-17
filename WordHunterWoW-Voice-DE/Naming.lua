local Addon = WordHunterWoW_Voice or {}
WordHunterWoW_Voice = Addon

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

function Addon.WordPath(key)
  local hash = Addon.WordHash(key)
  return "sounds\\w\\" .. hash:sub(1, 2) .. "\\" .. hash .. ".ogg"
end

-- The three passages an NPC says out loud. Objectives and the title are read
-- off the screen by the player, not spoken by anyone.
Addon.SPOKEN_FIELDS = { description = "o", progress = "p", completion = "c" }

-- One clip per sentence, numbered from one in reading order. The addon lights up
-- the sentence it is reading, and a clip that held a whole passage could not be
-- pointed at any single line.
function Addon.QuestPath(questId, field, sentence)
  local letter = Addon.SPOKEN_FIELDS[field]
  questId, sentence = tonumber(questId), tonumber(sentence)
  if not letter or not questId or not sentence then return nil end
  return string.format("sounds\\q\\%02d\\%d_%s%d.ogg",
    questId % 100, questId, letter, sentence)
end
