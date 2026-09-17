local ADDON_NAME = ...
local Addon = WordHunterWoW_Voice or {}
WordHunterWoW_Voice = Addon

-- The engine. It holds no audio: the clips live in the data addons, which are
-- separate downloads because the whole pack does not fit in one.
--
-- Nothing here builds an index of what exists. A clip is found by computing its
-- name (Naming.lua) and asking the client to play it; a clip that has not been
-- generated yet simply does not play. That is what lets the pack ship
-- incomplete and grow, instead of having to be finished before it is useful.

-- The folder this addon is loaded from, asked of the client rather than written
-- down. It used to be the literal "WordHunterWoW-Voice-DE", which is what the
-- CurseForge package is called and so was right for everyone who installed it
-- that way. A GitHub "Download ZIP" unpacks to WordHunterWoW-Voice-DE-main,
-- and then ADDON_LOADED never matched: no hooks, no play buttons, no settings
-- panel, and nothing anywhere to say why. The other two addons in this suite
-- take the name from the client already.
--
-- The written-down name stays as the fallback for the one case the client
-- cannot answer: a file run outside the addon loader, which is how the tests
-- run it.
local ENGINE = ADDON_NAME or "WordHunterWoW-Voice-DE"

-- QuestWordHunter, the addon this one hooks into when it is there. Named
-- because the load order is not something this addon can take on trust -- see
-- the ADDON_LOADED handler.
local BASE_ADDON = "WordHunterWoW"

-- Filled in by each data addon as it loads. A player who installed parts 1 and
-- 3 gets the quests those parts cover and silence for the rest, rather than an
-- error or a refusal to load.
WordHunterWoW_Voice_Parts = WordHunterWoW_Voice_Parts or {}

local playing

local function settings()
  WordHunterWoWVoiceDB = WordHunterWoWVoiceDB or {}
  local db = WordHunterWoWVoiceDB
  if db.enabled == nil then db.enabled = true end
  if db.words == nil then db.words = true end
  if db.channel == nil then db.channel = "Dialog" end
  return db
end

function Addon.GetEnabled() return settings().enabled and true or false end
function Addon.SetEnabled(value)
  settings().enabled = value and true or false
  if not settings().enabled then Addon.Stop() end
end

function Addon.GetWordsEnabled() return settings().words and true or false end
function Addon.SetWordsEnabled(value) settings().words = value and true or false end

-- How long to wait after the quest window opens before speaking.
--
-- Starting the instant the frame appears talks over the sound the client makes
-- opening it, and over the player still reading the title. A beat and a half is
-- long enough to settle and short enough not to feel broken.
local DEFAULT_DELAY = 1.5

function Addon.GetDelay()
  local value = tonumber(settings().delay)
  if value == nil then return DEFAULT_DELAY end
  return math.max(0, math.min(10, value))
end

function Addon.SetDelay(value)
  settings().delay = math.max(0, math.min(10, tonumber(value) or DEFAULT_DELAY))
end

-- Which sound pack holds a given clip.
--
-- One pack per expansion, because that is a unit a player recognises: someone
-- levelling through Classic installs Classic and carries nothing else, and
-- everything outside it is silent rather than broken. A quest pack declares the
-- range of quest ids it covers, so finding the owner is a comparison against at
-- most a dozen packs. The word pack declares only that it holds words -- a
-- word's clip is named by a hash and has no range to compare.
--
-- Which pack owns a clip is worked out fresh each time -- the list is a dozen
-- entries and caching it would buy nothing. What is cached is the two tables a
-- pack ships, the durations and the sentence grouping, because parsing those is
-- real work; ForgetParts throws that away, and is called whenever an addon
-- loads, since a pack that has just arrived brings tables the cache has never
-- seen. Each is parsed on its own, the first time something asks for a row of
-- it, so a pack opened only for its durations never parses the grouping.
local parsed = {}

function Addon.ForgetParts()
  parsed = {}
end

local function questOwner(questId)
  questId = tonumber(questId)
  if not questId then return nil end
  for folder, part in pairs(WordHunterWoW_Voice_Parts) do
    local range = part.quests
    if range and questId >= range[1] and questId <= range[2] then
      return folder
    end
  end
end

local function wordOwner()
  for folder, part in pairs(WordHunterWoW_Voice_Parts) do
    if part.words then return folder end
  end
end

local function fullPath(relative, folder)
  if not folder or not relative then return nil end
  return "Interface\\AddOns\\" .. folder .. "\\" .. relative
end

-- Bumped whenever anything cancels the reading. A passage is several clips
-- played one after another on timers, and a timer that fires after the player
-- has closed the window must do nothing -- so each scheduled step remembers the
-- number it was booked under and gives up if it no longer matches.
local chain = 0

-- What is being read, and how far in, so it can be resumed or read again. Kept
-- after the passage finishes: the moment somebody wants it repeated is the
-- moment it stopped. `sentence` is nil once the passage has run out, which is
-- what tells the play button to start again rather than carry on.
--
-- Declared up here with `chain` rather than beside the functions that write it,
-- because Stop -- which sits above those -- has to be able to throw it away.
local current
local paused

local function silence()
  if playing then
    StopSound(playing)
    playing = nil
  end
end

-- Stop and forget. This is the quest window closing, or the addon being
-- switched off: there is no passage on screen any more, so there is nothing
-- left to resume or repeat and the frame goes with it. Pause is the one that
-- remembers.
function Addon.Stop()
  chain = chain + 1
  silence()
  current, paused = nil, false
  if Addon.HideTalker then Addon.HideTalker() end
end

local function play(path)
  if not path then return false end
  silence()
  -- PlaySoundFile answers false when the file is not there, which is the normal
  -- case for a clip nobody has generated yet. Not an error, and not worth a
  -- message: the player asked for a voice, not for a report on coverage.
  local willPlay, handle = PlaySoundFile(path, settings().channel)
  if willPlay then playing = handle end
  return willPlay and true or false
end

-- A pause between two sentences of the same passage, so a paragraph does not
-- arrive as one breathless run. The same quarter second the generator leaves
-- between the pieces of a sentence too long to speak in one go.
local SENTENCE_GAP = 0.25

-- How long each sentence of a passage runs, in hundredths of a second.
--
-- The pack ships this as one long string rather than a Lua table: a table of
-- thirty thousand passages is thirty thousand constants in the compiled file,
-- and a chunk may hold 262,143. One string is one constant however big it gets.
-- It is parsed the first time a quest in that pack is opened and kept after,
-- until ForgetParts throws the parse away.

-- Both of the tables a pack ships -- the durations and the grouping -- are the
-- same shape: one line per passage, "<quest> <letter> <n,n,n>". They are parsed
-- by one function rather than two because a second copy of this loop is a
-- second chance to disagree about the format, and the two tables are written by
-- one line of build_pack.py each.
local function parseTable(blob)
  local held = {}
  for quest, kind, list in blob:gmatch("(%d+) (%a) ([%d,]+)") do
    local numbers = {}
    for value in list:gmatch("(%d+)") do
      numbers[#numbers + 1] = tonumber(value)
    end
    quest = tonumber(quest)
    held[quest] = held[quest] or {}
    held[quest][kind] = numbers
  end
  return held
end

-- One passage's row out of one of those tables, parsing the whole table the
-- first time anything asks for a row of it.
local function tableFor(folder, which, questId, field)
  local part = folder and WordHunterWoW_Voice_Parts[folder]
  if not part or not part[which] then return nil end
  local held = parsed[folder] or {}
  parsed[folder] = held
  if not held[which] then held[which] = parseTable(part[which]) end
  -- Both tables are filed under the letter the clip's name uses, not the
  -- field's own name: "description" is stored as "o", the same translation
  -- Naming.lua makes when it builds the path.
  local letter = Addon.SPOKEN_FIELDS and Addon.SPOKEN_FIELDS[field]
  local quest = held[which][tonumber(questId)]
  return letter and quest and quest[letter]
end

local function lengthsFor(folder, questId, field)
  return tableFor(folder, "lengths", questId, field)
end

-- Which sentence each clip of this passage begins at, as the generator recorded
-- it. Nil for a pack built before the grouping was shipped, and also nil for a
-- passage the pack deliberately left out of the table -- see ClipSpans, where
-- the two are told apart.
local function startsFor(folder, questId, field)
  return tableFor(folder, "starts", questId, field)
end

-- Exposed so the tests can reach it, and so a pack can be checked in game.
Addon.LengthsFor = lengthsFor
-- PlayButtons.lua needs to know whether a quest is covered before it draws
-- anything, since a button that plays nothing is worse than no button.
Addon.QuestOwner = questOwner

-- The three passages an NPC says out loud, and the event that shows each.
local PASSAGE_EVENT = {
  QUEST_DETAIL = "description",
  QUEST_PROGRESS = "progress",
  QUEST_COMPLETE = "completion",
}

-- Stand-in clips, played when the real one has not been generated yet. The pack
-- takes weeks to speak in full, and waiting for it to answer the only questions
-- that matter -- does a voice reading over a quest window help or annoy, is it
-- too loud, does it stop when it should -- would be weeks wasted.
--
-- Off unless asked for. A player wants the quest they opened, not a sample of
-- somebody else's; this is for judging the behaviour before the content exists.
function Addon.GetDemo() return settings().demo and true or false end
function Addon.SetDemo(value)
  settings().demo = value and true or false
  if not settings().demo then Addon.Stop() end
end

-- Which stand-in to use. UnitSex answers 2 for male and 3 for female, and it
-- answers for NPCs, which is the one piece of the casting the client knows by
-- itself -- so the stand-in is at least the right sex.
--
-- In demo/, not sounds/: .pkgmeta keeps sounds/ out of the built addon, since
-- that is where hundreds of thousands of generated clips land. A stand-in put
-- there would exist here and ship nowhere.
--
-- The clip says what it is -- that this quest has no audio yet -- rather than
-- reading another quest's words in its place.
local function placeholder()
  local sex = UnitSex and UnitSex("npc")
  local name = sex == 3 and "female" or "male"
  return "Interface\\AddOns\\" .. ENGINE .. "\\demo\\" .. name .. ".ogg"
end

-- Which sentences of a passage each clip covers.
--
-- A clip is not always one sentence. Tools/speech.py joins sentences shorter
-- than thirty characters to a neighbour, because the reader stumbles on a
-- two-word clip and there are tens of thousands of them; so clip three may be
-- sentences four and five. Anything that wants to follow the reading -- the
-- English panel highlighting along -- needs the group, not the clip number.
--
-- Shipped in the pack, not worked out here. It was worked out here at first,
-- on the reasoning that the same text and the same sentence splitter are
-- already on both sides -- and the text is not the same text. Tools/speech.py
-- groups the words the narrator was given, where the vocative and its comma
-- have been struck out because there is no name to record: "Das sind
-- schwierige Zeiten, {name}." is spoken as "Das sind schwierige Zeiten.", 27
-- characters, under the thirty-character minimum, and so joined to the sentence
-- after it. The client renders the same line with a player's name in it, 36
-- characters, and this code left it standing on its own. One clip in the pack,
-- two spans here, and from there every button in the passage was one sentence
-- early and the last paragraph had none at all.
--
-- Making the derivation cleverer would only have narrowed that: the two sides
-- are grouping different strings, so any rule that measures the string can be
-- made to disagree. The sentence *numbers* are the one thing that does not move
-- -- filling a token in changes a sentence's length, never how many sentences
-- came before it -- so that is what the pack carries.
--
-- The grouping below is kept because six pack repositories were published
-- without the table and must keep working. It is the degraded path, not the
-- normal one: it is right whenever the passage carries no substitution, which
-- is most of them, and wrong in the way described above when it does.
local MIN_CHARS = 30
local MAX_CHARS = 420

local function hasLetter(text)
  return text:find("%a") ~= nil or text:find("[\128-\255]") ~= nil
end

-- Characters, not bytes. The thresholds above are the generator's, and Python
-- counts characters; "#" in Lua counts bytes, and German is full of two-byte
-- ones. "Zäh, erfinderisch, schnell..." is 28 characters and 30 bytes, so
-- comparing bytes closed a clip the generator kept open -- which the crosscheck
-- caught as forty-one passages grouped differently.
--
-- A UTF-8 sequence is one lead byte followed by continuation bytes in
-- 0x80..0xBF, so counting everything that is not a continuation byte counts
-- characters.
local function charCount(text)
  local n = 0
  for i = 1, #text do
    local byte = text:byte(i)
    if byte < 128 or byte >= 192 then n = n + 1 end
  end
  return n
end

-- The sentences of one paragraph, grouped exactly as Tools/speech.py groups
-- them. `before` is how many sentences of the passage came earlier, so the
-- numbers recorded are the passage's own and not the paragraph's.
-- Strip the edges the way Python does, which includes the no-break space.
-- Quest text carries them ("the fee of two gold pieces.\194\160Once this fee"),
-- Python counts one as whitespace and drops it, and Lua's "%s" is ASCII only --
-- so without this a sentence is one character longer here than there, and a
-- passage sitting on the thirty-character threshold groups differently.
-- Looped, because the two kinds alternate: quest text has a no-break space
-- followed by an ordinary one, and a single pass of each leaves the other
-- behind. A Lua character class cannot hold a two-byte character, so they are
-- stripped in turn until nothing more comes off.
local function trimSpace(text)
  local previous
  repeat
    previous = text
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("^\194\160", ""):gsub("\194\160$", "")
  until text == previous
  return text
end

local function groupParagraph(sentences, before, out)
  local group, first = {}, nil
  local function joined() return table.concat(group, " ") end
  for i, sentence in ipairs(sentences) do
    sentence = trimSpace(sentence)
    local candidate = #group > 0 and (joined() .. " " .. sentence) or sentence
    if #group > 0 and charCount(candidate) > MAX_CHARS then
      -- The new sentence would overflow, so the group closes without it and the
      -- sentence starts the next one.
      out[#out + 1] = { text = joined(), first = before + first, last = before + i - 1 }
      group, first = { sentence }, i
    else
      if #group == 0 then first = i end
      group[#group + 1] = sentence
    end
    if charCount(joined()) >= MIN_CHARS then
      out[#out + 1] = { text = joined(), first = before + first, last = before + i }
      group, first = {}, nil
    end
  end
  if #group > 0 then
    -- Whatever is left is below the minimum: it joins the clip before it rather
    -- than becoming a clip the reader would choke on. That clip may belong to
    -- the paragraph before, which is what the Python does too.
    local tail = joined()
    local previous = out[#out]
    local last = before + first + #group - 1
    if previous and charCount(previous.text) + 1 + charCount(tail) <= MAX_CHARS then
      previous.text = previous.text .. " " .. tail
      previous.last = last
    else
      out[#out + 1] = { text = tail, first = before + first, last = last }
    end
  end
end

-- Every sentence of the passage, paragraph by paragraph, so that a sentence
-- number means the same thing here as it does in the pack: counted across the
-- whole passage and not restarted at each paragraph.
local function sentenceCount(base, text)
  local total = 0
  for _, paragraph in ipairs(base.SplitParagraphs(text or "")) do
    total = total + #base.SplitSentences(paragraph)
  end
  return total
end

-- The grouping the pack recorded, turned into spans against this text.
--
-- Only the first sentence of each clip is shipped. The last is the sentence
-- before the next clip begins, and for the final clip it is the last sentence
-- there is -- so the pack carries one number per clip instead of two, on a
-- table that already runs to hundreds of kilobytes. The one place that costs
-- anything is a passage where the generator threw a clip away for holding no
-- letter: the sentences it covered are handed to the clip before it here rather
-- than to nothing. Nothing plays them either way, and no caller reads `last`
-- except the test that prints it.
--
-- A quest rewritten longer or shorter since the pack was built lands here with
-- numbers that overrun the text. Nothing is clamped away: a span past the end
-- finds no token to sit against and PlayButtons draws no button for it, which
-- is what should happen for a clip whose sentence is no longer on screen.
local function spansFromStarts(firsts, total)
  local out = {}
  for index, first in ipairs(firsts) do
    local following = firsts[index + 1]
    local last = following and (following - 1) or total
    if last < first then last = first end
    out[index] = { first = first, last = last }
  end
  return out
end

-- For a whole passage: one entry per clip, in the order they are spoken, each
-- saying which sentences of the passage it holds.
--
-- `questId` and `field` say which passage this is, so the pack's own grouping
-- can be looked up. Left out -- as the older tests and any caller that only has
-- text do -- the grouping is derived instead, which is the degraded path.
function Addon.ClipSpans(text, questId, field)
  local base = WordHunterWoW_Addon
  if not base or not base.SplitSentences or not base.SplitParagraphs then return nil end

  local folder = questId and questOwner(questId)
  local part = folder and WordHunterWoW_Voice_Parts[folder]
  if part and part.starts then
    -- A pack that ships the table but names no row for this passage is saying
    -- the grouping is the plain one: clip n is sentence n. That is 58% of the
    -- German corpus, and writing all of it out would have nearly doubled a
    -- string the pack already carries for no information at all. Absence is
    -- only readable as "plain" because `part.starts` existing is what says the
    -- pack is of the new kind at all; an old pack has no field here and never
    -- reaches this branch.
    local firsts = startsFor(folder, questId, field)
    local total = sentenceCount(base, text)
    if not firsts then
      -- How many clips there are is the one thing that must not be counted off
      -- the text on screen, and it does not have to be: the pack already ships
      -- a duration per clip, so the row length is the clip count. Counting the
      -- client's sentences instead put the bug back for exactly the passages
      -- this branch covers -- a passage read as "1,2,3,4" by the generator but
      -- split into five sentences by the client came out with five clips again.
      local lengths = lengthsFor(folder, questId, field)
      local count = lengths and #lengths or total
      firsts = {}
      for i = 1, count do firsts[i] = i end
    end
    return spansFromStarts(firsts, total)
  end

  local grouped, seen = {}, 0
  for _, paragraph in ipairs(base.SplitParagraphs(text or "")) do
    local sentences = base.SplitSentences(paragraph)
    groupParagraph(sentences, seen, grouped)
    seen = seen + #sentences
  end
  -- A clip with no letter in it is not speech and was never generated, so it
  -- must not take a clip number here either.
  local out = {}
  for _, clip in ipairs(grouped) do
    if hasLetter(clip.text) then
      out[#out + 1] = { first = clip.first, last = clip.last }
    end
  end
  return out
end

-- Wait, then do the thing -- unless the reading was cancelled meanwhile.
local function after(seconds, action)
  if C_Timer and C_Timer.After then
    C_Timer.After(seconds, action)
    return
  end
  -- No C_Timer on the oldest clients this addon claims to support. A frame that
  -- counts down on OnUpdate does the same job with no dependency.
  --
  -- A frame per wait, not one shared frame. Two waits overlap in the ordinary
  -- case -- the delay before a passage starts and the gap between its
  -- sentences -- and a shared frame would have the second silently cancel the
  -- first. They are short-lived and there is at most a handful.
  local waiter = CreateFrame("Frame")
  local due = seconds
  waiter:SetScript("OnUpdate", function(self, elapsed)
    due = due - elapsed
    if due <= 0 then
      self:SetScript("OnUpdate", nil)
      self:Hide()
      action()
    end
  end)
end

-- Tell the English panel which sentence is being spoken, so the translation
-- follows the reading. Optional in both directions: the panel need not be
-- installed, and the panel does not need this addon.
--
-- The spans are worked out once per passage and kept, because a passage is read
-- clip by clip and recomputing the grouping for each one would be the same
-- answer four times over.
-- Keyed by the passage as well as the text, because the grouping now comes out
-- of the pack and two passages of the same quest are two different rows there.
local spansFor, spansText, spansKey
local function highlight(index, questId, field)
  local base = WordHunterWoW_Addon
  local quest = base and base.lastQuest
  if not quest or not quest.text or not base.HighlightEnglishForWord then return end
  local key = tostring(questId) .. "\1" .. tostring(field)
  if spansText ~= quest.text or spansKey ~= key then
    spansFor, spansText, spansKey =
      Addon.ClipSpans(quest.text, questId, field), quest.text, key
  end
  local span = spansFor and spansFor[index]
  if not span then return end
  -- HighlightEnglishForWord, not OnHighlightEnglishForWord. The second is the
  -- notification the base addon sends out after it has painted its own English
  -- column; calling it directly told the separate English window and left that
  -- column dark, which is the arrangement most people read in. The painting
  -- function ends by sending the same notification, so the window still hears
  -- about the sentence, once.
  --
  -- No word: the panel is being told a sentence, not a click. sentenceOnly so
  -- it lights the sentence rather than a word inside it.
  base.HighlightEnglishForWord(nil, span.first, nil, true)
end

-- Play one sentence and book the next, so a passage is read through rather than
-- cut off after its first line. A pack that ships no durations plays only the
-- sentence asked for, which is what the engine did before they existed.
-- Who is speaking and what it is called, for the frame that shows it. Taken
-- from the client when the window is still open, and from the base addon when
-- it is not -- a passage that starts after a delay may outlive the unit.
local function speakerName()
  if GetTitleText then
    local text = GetTitleText()
    if text and text ~= "" then return text end
  end
  local base = WordHunterWoW_Addon
  local quest = base and base.lastQuest
  return quest and quest.title or ""
end

local function readFrom(questId, field, index, folder, only)
  local relative = Addon.QuestPath(questId, field, index)
  if not relative or not play(fullPath(relative, folder)) then return false end
  highlight(index, questId, field)
  -- Recorded per sentence, not once when the passage starts. The sentence
  -- somebody pauses on is the one they were listening to, and resuming from the
  -- opening line of a five-sentence quest is not pausing, it is starting over.
  current = { questId = questId, field = field, sentence = index }
  paused = false
  local lengths = lengthsFor(folder, questId, field)
  if Addon.ShowTalker then
    Addon.ShowTalker(speakerName(), "npc",
      Addon.TalkerLine(index, lengths and #lengths or nil))
  end
  local thisOne = lengths and lengths[index]
  if thisOne then
    local mine = chain
    if lengths[index + 1] and not only then
      after(thisOne / 100 + SENTENCE_GAP, function()
        if chain == mine then readFrom(questId, field, index + 1, folder) end
      end)
    else
      -- The last sentence. The frame stays, saying it has finished rather than
      -- claiming to still be reading: the moment somebody wants to hear a
      -- passage again is the moment it stops, and hiding the frame then puts
      -- the button for it out of reach. It goes when the quest window does.
      after(thisOne / 100, function()
        if chain ~= mine then return end
        -- Nothing left to carry on from, so the play button reads the passage
        -- from the top instead of repeating its closing line.
        if current then current.sentence = nil end
        if Addon.RestTalker then Addon.RestTalker() end
      end)
    end
  end
  return true
end

-- `sentence` starts the reading part-way in, which the tests use and both the
-- replay and the resume buttons do; left out, the passage is read from the
-- beginning.
--- `only` reads the one clip and stops there instead of carrying on into the
--- rest of the passage. That is what the button beside a paragraph means: it is
--- offered per paragraph, so pressing it to hear one line and being read the
--- remaining four is not a shortcut, it is the wrong thing happening. Reading
--- the whole passage is what the quest window already does by itself, and what
--- the talker's own play button goes back to.
function Addon.PlayQuest(questId, field, sentence, only)
  if not Addon.GetEnabled() then return false end
  Addon.Stop()
  local folder = questOwner(tonumber(questId))
  if readFrom(questId, field, sentence or 1, folder, only) then return true end
  if Addon.GetDemo() then return play(placeholder()) end
  return false
end

-- Pause, at sentence granularity and no finer.
--
-- PlaySoundFile hands back a handle and nothing else: there is no call that
-- asks the client how far into a clip it has got, and StopSound cannot be
-- undone -- a stopped clip can only be started again from its beginning. So
-- this stops the voice and remembers which sentence it was on, and the play
-- button starts that sentence over. At worst half a sentence is heard twice,
-- which is roughly what somebody who paused mid-thought wanted anyway.
--
-- Pretending otherwise would mean resuming at the top of the passage and
-- calling it a pause, which is the sort of thing that gets noticed once.
function Addon.Pause()
  if not current or not current.sentence then return false end
  chain = chain + 1
  silence()
  paused = true
  -- The frame stays up, still showing which sentence it stopped on -- that is
  -- both the confirmation that it paused and where it will pick up. Hiding it
  -- would take the button that resumes away with it.
  if Addon.SetTalkerSpeaking then Addon.SetTalkerSpeaking(false) end
  return true
end

function Addon.IsPaused()
  return paused and true or false
end

-- Carry on from the sentence Pause remembered. With nothing paused -- a passage
-- that ran to its end, or one stopped and forgotten -- this reads from the
-- first sentence, which is what a play button means on something that is not
-- part-way through.
function Addon.Resume()
  if not current then return false end
  local sentence = paused and current.sentence
  paused = false
  if not sentence then return Addon.Replay() end
  return Addon.PlayQuest(current.questId, current.field, sentence)
end

-- Read the passage again from its first sentence.
function Addon.Replay()
  if not current then return false end
  return Addon.PlayQuest(current.questId, current.field, 1)
end

function Addon.CanReplay()
  return current ~= nil
end

function Addon.PlayWord(word)
  if not Addon.GetEnabled() or not Addon.GetWordsEnabled() then return false end
  local key = Addon.WordKey(word)
  if key == "" then return false end
  return play(fullPath(Addon.WordPath(key), wordOwner()))
end

-- The key a clip was filed under. The dictionary casefolds and turns the eszett
-- into ss; the generator hashed that same key, so the same rule has to run here
-- or every word with an eszett in it goes looking in the wrong place.
function Addon.WordKey(word)
  word = tostring(word or "")
  local base = WordHunterWoW_Addon
  if base and base.wordKey then return base.wordKey(word) end
  -- Standing alone, without the base addon: good enough for ASCII, and the
  -- words that need more than this are exactly the ones the base addon is
  -- installed to look up anyway.
  -- Lua's lower() is byte-wise ASCII, so Ä, Ö and Ü pass through it unchanged
  -- while the pack files them folded. German capitalises every noun, so what
  -- that silently lost was not an edge case but every noun beginning with an
  -- umlaut -- Öl, Über, Äpfel. The comment that used to sit here said the words
  -- needing more than this were the ones the base addon is installed for, which
  -- was a rationalisation and wrong: they are ordinary vocabulary.
  local folded = word:gsub("ẞ", "ss"):gsub("ß", "ss")
  folded = folded:gsub("Ä", "ä"):gsub("Ö", "ö"):gsub("Ü", "ü")
  return (folded:lower())
end

local frame = CreateFrame("Frame")
for event in pairs(PASSAGE_EVENT) do frame:RegisterEvent(event) end
frame:RegisterEvent("QUEST_FINISHED")
frame:RegisterEvent("ADDON_LOADED")
-- GOSSIP_CLOSED is deliberately not here.
--
-- Taking a quest from a gossip window fires QUEST_DETAIL and then
-- GOSSIP_CLOSED, one after the other. Treating the second as "the window shut,
-- stop reading" cancelled the passage that the first had just started -- and
-- once the start was put behind a delay, the cancel always landed first, so
-- nothing was ever spoken for any quest taken from a gossip menu. Which is
-- nearly all of them.
--
-- Nothing is lost by dropping it: this addon never reads gossip text, so a
-- gossip window closing has no audio of its own to stop.
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    -- A data addon may load after this one. Its declaration is only visible
    -- once it has, so the map is dropped and rebuilt on the next lookup.
    Addon.ForgetParts()
    if arg1 == ENGINE then
      Addon.HookBaseAddon()
      if Addon.HookQuestPanel then Addon.HookQuestPanel() end
      -- Registered at load, not on first use: a panel that only appears once
      -- the player has found the slash command is a panel nobody finds.
      if Addon.CreateSettingsPanel then Addon.CreateSettingsPanel() end
    elseif arg1 == BASE_ADDON then
      -- The base addon arriving after this one. OptionalDeps asks for the other
      -- order and usually gets it, but it is a request about addons that are
      -- both enabled when the list is built and nothing more. Land on the other
      -- side of it -- and a load this addon does not control can -- and the two
      -- calls above found no base addon, installed nothing, and were never
      -- tried again: clicking a word says nothing and no play button appears
      -- beside a paragraph, with nothing anywhere to say why. Both hooks refuse
      -- a second run, so covering it costs this branch.
      --
      -- WordHunterWoW-ENPanel answers the same event for the same reason.
      Addon.HookBaseAddon()
      if Addon.HookQuestPanel then Addon.HookQuestPanel() end
    end
    return
  end
  local field = PASSAGE_EVENT[event]
  if field then
    local questId = GetQuestID and GetQuestID() or 0
    -- The whole passage, after a beat: the first sentence when the delay is up,
    -- the rest on timers taken from the durations the pack ships.
    --
    -- Stop() runs first so that opening a second quest window during the wait
    -- cancels the first one's pending start, rather than both of them speaking.
    if questId and questId > 0 then
      Addon.Stop()
      local mine = chain
      local wait = Addon.GetDelay()
      if wait > 0 then
        after(wait, function()
          if chain == mine then Addon.PlayQuest(questId, field) end
        end)
      else
        Addon.PlayQuest(questId, field)
      end
    end
  elseif event == "QUEST_FINISHED" then
    -- Closing the quest window stops the voice. Reading on while the frame is
    -- gone is the single most irritating thing a pack like this can do.
    --
    -- Named, not a catch-all. This used to stop on any event that was not a
    -- passage, which meant that adding an event to the list above -- as
    -- GOSSIP_CLOSED once was -- silently turned it into a stop button. That is
    -- how every quest taken from a gossip menu came to be read for nought:
    -- QUEST_DETAIL started the passage and GOSSIP_CLOSED, arriving immediately
    -- after, cancelled it.
    Addon.Stop()
  end
end)

-- There is no settings panel yet, and there does not need to be one before the
-- pack has anything to say. A slash command is enough to answer the questions
-- this build exists to answer.
local function say(text)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff59aefaQuestWordHunter Voice:|r " .. text)
  end
end

local function status()
  return string.format("quests %s, words %s, stand-ins %s",
    Addon.GetEnabled() and "on" or "off",
    Addon.GetWordsEnabled() and "on" or "off",
    Addon.GetDemo() and "on" or "off")
end

SLASH_WHWVOICE1 = "/whwvoice"
SLASH_WHWVOICE2 = "/whwv"
SlashCmdList = SlashCmdList or {}
SlashCmdList["WHWVOICE"] = function(input)
  local command = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if command == "on" or command == "off" then
    Addon.SetEnabled(command == "on")
  elseif command == "words" then
    Addon.SetWordsEnabled(not Addon.GetWordsEnabled())
  elseif command == "demo" then
    Addon.SetDemo(not Addon.GetDemo())
    if Addon.GetDemo() then
      say("stand-ins on: every quest will say something, but only the ones "
        .. "already generated say their own words.")
    end
  elseif command == "stop" then
    Addon.Stop()
  elseif command == "config" or command == "options" then
    if Addon.OpenSettings then Addon.OpenSettings() end
    return
  else
    say(status())
    say("/whwv on | off | words | demo | stop | config")
    return
  end
  say(status())
end

-- Clicking a word in QuestWordHunter should say it. Done by wrapping the base
-- addon's own editor rather than asking it for a hook, so this addon can be
-- installed beside any version of it without the two having to agree on
-- anything.
function Addon.HookBaseAddon()
  local base = WordHunterWoW_Addon
  if not base or not base.openEditor or Addon.hooked then return end
  Addon.hooked = true
  local openEditor = base.openEditor
  base.openEditor = function(word, ...)
    Addon.PlayWord(word)
    return openEditor(word, ...)
  end
end
