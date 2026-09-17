local addonName = ...

local frame
local hideWatched = {}
local db
-- Which passage the NPC is showing. The base addon works this out too, and its
-- answer is preferred when it is installed, but this addon has to stand on its
-- own: without it there is nothing to ask.
local lastPassage = "offer"
local lastPlainBody
local lastCaveat
local lastQuestId
local displayedPassage

local function layoutContent()
  if not frame then return end
  local w = frame:GetWidth()
  frame.content:SetWidth(math.max(200, w - 52))
  if frame:IsShown() then
    frame.content:SetHeight(math.max(1, frame.text:GetStringHeight() + 12))
    frame.scroll:UpdateScrollChildRect()
  end
end

-- Not the compatibility layer from the base addon: this addon stands on its own
-- and must not depend on it. All that is needed here is which family of client
-- this is, and that is one global.
local function isClassicClient()
  return type(WOW_PROJECT_ID) == "number" and type(WOW_PROJECT_MAINLINE) == "number"
     and WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE
end

local function applyTheme(target)
  local Addon = WordHunterWoW_Addon
  if Addon and Addon.ApplyBackground then
    Addon.ApplyBackground(target)
  elseif isClassicClient() then
    -- Classic's own frames are all this tooltip skin, and the panel should look
    -- like it belongs beside them. The base addon defaults to the same thing
    -- there, so a player with both installed sees one style, not two.
    target:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
      tile = true, tileSize = 16, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    target:SetBackdropColor(0.04, 0.06, 0.10, 1)
    target:SetBackdropBorderColor(0.22, 0.24, 0.34, 0.95)
  else
    target:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    target:SetBackdropColor(0.08, 0.09, 0.13, 1)
    target:SetBackdropBorderColor(0.22, 0.24, 0.34, 0.95)
  end
end

local function expandTokens(text)
  text = tostring(text or "")
  return (text:gsub("{name}", "<name>"):gsub("{class}", "<class>")
    :gsub("{race}", "<race>"):gsub("{sex}", "<sex>"))
end

local function questText(questId, passage)
  local entry = WordHunterWoW_QuestEN and WordHunterWoW_QuestEN[tonumber(questId)]
  if not entry then return nil end
  local title = expandTokens(entry.title or "")
  local description = expandTokens(entry.description or "")
  local objectives = expandTokens(entry.objectives or "")
  -- The player is reading the progress or hand-in line, and this record has the
  -- English for it. Show that, not the opening text: they are different
  -- passages, and until now the panel could only apologise for the difference.
  if passage == "progress" and (entry.progress or "") ~= "" then
    return title, expandTokens(entry.progress), true, true
  end
  -- "reward" is what both this addon and the base call the hand-in frame.
  if passage == "reward" and (entry.completion or "") ~= "" then
    return title, expandTokens(entry.completion), true, true
  end
  local body = description
  if objectives ~= "" then body = body .. (body ~= "" and "\n\n" or "") .. objectives end
  -- Whether this record has the quest's opening text at all. Retail records
  -- always do; Classic records never do, because the source has none.
  return title, body, description ~= "", false
end

-- A Blizzard global can be missing entirely on one game and be something other
-- than a frame on another, so nothing here indexes one without checking.
local function isShown(frame)
  return (type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown()) and true or false
end

local function questFrameOpen()
  return isShown(QuestFrame)
end

local function questLogOpen()
  -- Classic's quest log is a window of its own. Retail's lives inside the world
  -- map, which is why Retail needs both halves checked.
  if isShown(QuestLogFrame) then return true end
  local details = QuestMapFrame and QuestMapFrame.DetailsFrame
  if isShown(details) then return true end
  return isShown(WorldMapFrame) and isShown(QuestMapFrame)
end

-- Classic has no C_QuestLog.GetSelectedQuest. Its quest log knows which row is
-- selected, and GetQuestLogTitle returns the quest id somewhere among its
-- results -- the position has moved between builds, so rather than counting
-- commas, take the number that maps back to the row we started from.
local function classicSelectedQuestId()
  if type(GetQuestLogSelection) ~= "function" or type(GetQuestLogTitle) ~= "function" then return nil end
  if type(GetQuestLogIndexByID) ~= "function" then return nil end
  local index = GetQuestLogSelection()
  if not index or index <= 0 then return nil end
  local function pick(...)
    for i = 1, select("#", ...) do
      local value = select(i, ...)
      if type(value) == "number" and value > 0 and GetQuestLogIndexByID(value) == index then
        return value
      end
    end
    return nil
  end
  return pick(GetQuestLogTitle(index))
end

local function currentQuestId()
  if questFrameOpen() then
    local id = GetQuestID and GetQuestID()
    if id and id > 0 then return id end
  end
  local id = QuestMapFrame_GetDetailQuestID and QuestMapFrame_GetDetailQuestID()
  if id and id > 0 then return id end
  id = C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
  if id and id > 0 then return id end
  id = classicSelectedQuestId()
  if id and id > 0 then return id end
  id = GetQuestID and GetQuestID()
  if id and id > 0 then return id end
  return nil
end

local function hideIfOrphaned()
  if not frame or not frame:IsShown() then return end
  if not questFrameOpen() and not questLogOpen() then
    frame:Hide()
  end
end

local function watchHide(target)
  if not target or hideWatched[target] then return end
  hideWatched[target] = true
  target:HookScript("OnHide", function()
    C_Timer.After(0, hideIfOrphaned)
  end)
end

-- The panel sits beside whichever window it is translating, and those two are
-- nowhere near each other: an NPC's dialogue opens small and to the left, the
-- map fills most of the screen. A single remembered position cannot serve both
-- -- put it where it belongs next to the dialogue and it lands over the middle
-- of the map -- so each window keeps its own.
local function currentHost()
  if isShown(QuestFrame) then return "quest", QuestFrame end
  -- Classic's quest log window stands in for Retail's map here. It is the same
  -- situation from the panel's point of view -- the player is reading the log
  -- rather than talking to an NPC -- so it shares the remembered position and
  -- an upgrading player keeps the one they already set.
  if isShown(QuestLogFrame) then return "map", QuestLogFrame end
  if isShown(WorldMapFrame) then return "map", WorldMapFrame end
  return nil, nil
end

local context = "quest"

local function savedPositions()
  if not db then return nil end
  db.pos = db.pos or {}
  -- Earlier versions kept one position for both. Seed both contexts with it so
  -- an upgrade does not throw away where the player had put the panel.
  if db.point and db.x and db.y then
    local old = { point = db.point, relativePoint = db.relativePoint, x = db.x, y = db.y }
    db.pos.quest = db.pos.quest or old
    db.pos.map = db.pos.map or old
    db.point, db.relativePoint, db.x, db.y = nil, nil, nil, nil
  end
  return db.pos
end

local function savePosition()
  if not frame then return end
  local positions = savedPositions()
  if not positions then return end
  local x, y = frame:GetLeft(), frame:GetTop()
  if type(x) ~= "number" or type(y) ~= "number" then return end
  -- Pin it to the screen rather than to the window it was sitting beside. Once
  -- it has been moved by hand it should stay put instead of following that
  -- window around, and the stored numbers have to still mean the same thing.
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  positions[context] = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = x, y = y }
end

local function anchorFrame()
  if not frame then return end
  local key, host = currentHost()
  context = key or context
  local positions = savedPositions()
  local saved = positions and positions[context]
  frame:ClearAllPoints()
  if saved then
    frame:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x, saved.y)
  elseif host then
    frame:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function ensureFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", "WordHunterWoWENPanelFrame", UIParent, "BackdropTemplate")
  frame:SetSize(420, 480)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)
  -- A frame with no anchor point has no position, and the game draws nothing --
  -- Show() succeeds and the panel is simply not on screen anywhere. Every child
  -- below is anchored; the window itself never was, so it has never actually
  -- been visible on its own.
  anchorFrame()
  applyTheme(frame)
  if WordHunterWoW_Addon then
    WordHunterWoW_Addon.enPanel = frame
    -- Published as soon as the frame exists. The base addon's size slider looks
    -- this up when it moves, and the frame is only built on the first quest --
    -- so a player who opened the settings first found the slider did nothing.
    if WordHunterWoW_Addon.ApplyWindowScale then
      WordHunterWoW_Addon.ApplyWindowScale("enPanelTextScale")
    end
  end
  if WordHunterWoW_Addon and WordHunterWoW_Addon.MakeResizable then
    WordHunterWoW_Addon.MakeResizable(frame, "enPanel", 280, 220, 700, 800)
  else
    frame:SetResizable(true)
    if frame.SetResizeBounds then
      frame:SetResizeBounds(280, 220, 700, 800)
    else
      -- Classic has no SetResizeBounds; it is the one call that replaced these
      -- two. Guarding it without a fallback leaves the window with no limits at
      -- all there, so it can be dragged down to nothing or out past the screen
      -- with no way back. The base addon learned this and fixed it in
      -- Core.lua; this branch -- the standalone one, which is the whole point
      -- of shipping a Vanilla manifest -- never got the same treatment.
      if frame.SetMinResize then frame:SetMinResize(280, 220) end
      if frame.SetMaxResize then frame:SetMaxResize(700, 800) end
    end
    local handle = CreateFrame("Button", nil, frame)
    handle:SetSize(16, 16)
    handle:SetPoint("BOTTOMRIGHT", -4, 4)
    handle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    handle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    handle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    handle:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    handle:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    frame.resizeHandle = handle
  end
  if db and db.w and db.h then frame:SetSize(db.w, db.h) end
  frame:HookScript("OnSizeChanged", function(self)
    if db then
      db.w, db.h = self:GetWidth(), self:GetHeight()
    end
    layoutContent()
  end)
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", 16, -14)
  frame.title:SetPoint("TOPRIGHT", -40, -14)
  frame.title:SetJustifyH("LEFT")
  frame.title:SetMaxLines(1)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  frame.scroll:SetPoint("TOPLEFT", 16, -44)
  frame.scroll:SetPoint("BOTTOMRIGHT", -34, 16)
  frame.content = CreateFrame("Frame", nil, frame.scroll)
  frame.content:SetSize(368, 1)
  frame.scroll:SetScrollChild(frame.content)
  frame.text = frame.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.text:SetPoint("TOPLEFT", 0, 0)
  frame.text:SetPoint("TOPRIGHT", 0, 0)
  frame.text:SetJustifyH("LEFT")
  frame.text:SetJustifyV("TOP")
  frame.text:SetWordWrap(true)

  -- Size. The whole window is scaled rather than its font strings one by one:
  -- SetScale takes the title, the text and the scroll bar with it, and nothing
  -- has to know which fields exist.
  --
  -- The base addon keeps every size in one settings page, so this reads its
  -- value when it is there. That is a plain read of a global the other addon
  -- happens to have saved -- no dependency, no load order -- and this addon
  -- still works on its own with its own remembered size.
  function frame.ApplyTextScale()
    local scale
    local base = _G.WordHunterWoWDB
    if type(base) == "table" and type(base.settings) == "table" then
      local v = base.settings.enPanelTextScale
      if type(v) == "number" and v >= 0.8 and v <= 2.0 then scale = v end
    end
    if not scale and type(db) == "table" then
      local v = db.scale
      if type(v) == "number" and v >= 0.8 and v <= 2.0 then scale = v end
    end
    if frame.SetScale then frame:SetScale(scale or 1.0) end
  end
  frame.ApplyTextScale()
  frame:Hide()
  return frame
end

-- New and older base addons can both host this panel; standalone uses the
-- same readable palette without adding a dependency or changing load order.
local function colorHex(key, fallback)
  local Addon = WordHunterWoW_Addon
  if Addon and Addon.COLORS and Addon.COLORS.text and Addon.ColorHex then
    return Addon.ColorHex(key)
  end
  return fallback
end

-- The same arrangement for the words the panel says in its own voice. The base
-- addon keeps every such string in one table so a translator has one place to
-- work through, and a player who has both addons should read one set of words
-- rather than two; standalone -- the ordinary case -- falls back to the English
-- written here, which is why each caller passes its own fallback rather than
-- leaving the panel with a blank line where a sentence should be.
local function label(key, fallback)
  local Addon = WordHunterWoW_Addon
  local labels = Addon and Addon.LABELS
  local value = labels and labels[key]
  return type(value) == "string" and value or fallback
end

local function wrapSentence(body, sentenceIndex, word, occurrence)
  local Addon = WordHunterWoW_Addon
  if not body or not Addon or not Addon.SplitSentences then return body end
  local sentences, spans = Addon.SplitSentences(body)
  local span = spans and spans[sentenceIndex]
  if not span then return body end
  local sentence = sentences[sentenceIndex]
  local match = word and Addon.MatchEnglishTokenIndexes
    and Addon.MatchEnglishTokenIndexes(sentence, word, occurrence) or {}
  local n = 0
  local sentenceColor = colorHex("enHighlight", "|cffcce8ff")
  local wordColor = colorHex("enWordHighlight", "|cffffa89c")
  -- Keep original whitespace and locate by byte span, including when another
  -- paragraph contains exactly the same English sentence.
  local colored = sentence:gsub("%S+", function(token)
    n = n + 1
    return (match[n] and wordColor or sentenceColor) .. token .. "|r"
  end)
  return body:sub(1, span.start - 1) .. colored .. body:sub(span.finish + 1)
end

local function paintEnglishBody(target, highlightSentence, word, occurrence)
  local f = target or frame
  if not f or not f.text then return end
  local body = lastPlainBody or ""
  if highlightSentence then body = wrapSentence(body, highlightSentence, word, occurrence) end
  if lastCaveat then
    body = body .. (body ~= "" and "\n\n" or "")
      .. colorHex("caveat", "|cffc2ccdb") .. lastCaveat .. "|r"
  end
  f.text:SetTextColor(0.93, 0.94, 0.96)
  f.text:SetText(body ~= "" and body or "English text is not available for this quest.")
  layoutContent()
end

local function showQuest(questId)
  local Addon = WordHunterWoW_Addon
  if Addon and Addon.GetIntegratedLayout and Addon.GetIntegratedLayout() then
    if frame then frame:Hide() end
    return
  end
  questId = questId or currentQuestId()
  if not questId or questId == 0 then return end
  local lastQuest = Addon and Addon.lastQuest
  local passage = (lastQuest and lastQuest.passage) or lastPassage
  local title, body, hasOpeningText, matchesPassage = questText(questId, passage)
  -- Blizzard's quest API publishes only the opening text and objectives, so for
  -- a long time that was all this panel had. Where the English for the progress
  -- or hand-in line is now known, matchesPassage is true and the panel shows the
  -- passage the player is actually reading. Where it is not, say so rather than
  -- passing off the opening text as a translation of something else.
  local caveat
  -- A record that is a title and nothing else: no opening text, no objective,
  -- no progress or hand-in line. 9,770 of the 49,041 shipped Retail records are
  -- exactly that, and 132 of those carry a title that admits it -- <UNUSED 1>,
  -- DEPRECATED. The other nine and a half thousand read as real quests, which
  -- is why this needs an answer of its own. Both branches below would name a
  -- passage that does not exist, and the objective one in particular left the
  -- reader looking down an empty panel for a line that was never there. Tested
  -- first, because whether there is anything at all to show settles the
  -- question before which passage was asked for can matter.
  --
  -- An empty string, not nil: nil is a quest this addon has no record of, and
  -- paintEnglishBody already has its own sentence for that.
  if body == "" then
    caveat = label("enNoText", "[No English text exists for this quest beyond its title.]")
  elseif body and passage and passage ~= "offer" and not matchesPassage then
    -- Addon is nil whenever the base addon is absent or switched off, which is
    -- the normal case now that this works on its own. Until lastPassage existed
    -- this branch could only be reached when the base had supplied the passage,
    -- so it was safe by accident; it is not any more.
    --
    -- Classic records have no opening text, so this branch used to claim it was
    -- showing the opening while actually showing the objective.
    if hasOpeningText == false then
      caveat = label("enNoOffer", "[No English opening text exists for this quest. Showing its objective.]")
    else
      caveat = label("enOfferOnly",
        "[Blizzard publishes no English text for this part of a quest. Showing the quest's opening text instead.]")
    end
  elseif body and hasOpeningText == false then
    -- A Classic record has the title and the objective and nothing else. Left
    -- unexplained, a one-line objective under a paragraph of German reads as if
    -- the translation had been cut short.
    caveat = label("enNoOffer", "[No English opening text exists for this quest. Showing its objective.]")
  end
  lastPlainBody = body
  lastCaveat = caveat
  lastQuestId, displayedPassage = tonumber(questId), passage
  local f = ensureFrame()
  applyTheme(f)
  -- Size before position. SetScale reinterprets the anchor offsets, so scaling
  -- after anchoring moved the window away from where it was just placed.
  if f.ApplyTextScale then f.ApplyTextScale() end
  anchorFrame()
  f.title:SetText(title or ("English quest #" .. questId))
  paintEnglishBody(f, nil)
  f:Show()
  f:Raise()
end

-- Hooking a name that does not exist is an error, and half of these names are
-- absent on any given game, so each one is checked before it is hooked and
-- hooked only once -- hooksecurefunc cannot be undone, and a second hook would
-- show the quest twice.
local hookedNames = {}
local function hookOnce(name, handler)
  if hookedNames[name] or type(_G[name]) ~= "function" then return false end
  hookedNames[name] = true
  hooksecurefunc(name, handler)
  return true
end

local function hookQuestUi()
  hookOnce("QuestInfo_ShowDescriptionText", function()
    C_Timer.After(0, function() showQuest() end)
  end)
  -- Reading a quest in the log always shows its offer text, whatever the last
  -- NPC conversation happened to be.
  hookOnce("QuestMapFrame_ShowQuestDetails", function()
    C_Timer.After(0, function()
      local questId = QuestMapFrame_GetDetailQuestID and QuestMapFrame_GetDetailQuestID()
      if not questId or questId == 0 then
        questId = C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
      end
      lastPassage = "offer"
      showQuest(questId)
    end)
  end)
  local function fromClassicLog()
    C_Timer.After(0, function()
      lastPassage = "offer"
      showQuest(classicSelectedQuestId())
    end)
  end
  hookOnce("QuestLog_SetSelection", fromClassicLog)
  hookOnce("QuestLog_UpdateQuestDetails", fromClassicLog)
  watchHide(QuestFrame)
  watchHide(WorldMapFrame)
  watchHide(QuestMapFrame)
  watchHide(QuestLogFrame)
  if QuestMapFrame and QuestMapFrame.DetailsFrame then watchHide(QuestMapFrame.DetailsFrame) end
end

-- Wire up the two-way integration with the base addon, if it is there. Safe to
-- call more than once and safe to call when the base is absent.
local function hookBaseAddon()
  local Addon = WordHunterWoW_Addon
  if not Addon then return end
  if frame then
    Addon.enPanel = frame
    if Addon.ApplyWindowScale then Addon.ApplyWindowScale("enPanelTextScale") end
  end
  Addon.OnIntegratedLayoutChanged = function(integrated)
    if integrated then
      if frame then frame:Hide() end
    else
      showQuest()
    end
  end
  Addon.OnHighlightEnglishForWord = function(word, quest, deSentenceIndex, wordOccurrence, sentenceOnly)
    if not frame or not frame:IsShown() then return end
    if Addon.GetIntegratedLayout and Addon.GetIntegratedLayout() then return end
    if not Addon.MatchEnglishSentence or not lastPlainBody then return end
    local index
    -- A word, or a sentence number on its own. The second is how the German
    -- voiceover asks: it knows which sentence it is speaking and nobody has
    -- clicked anything, so the English side follows along as the quest is read
    -- aloud. Everything else about the check is unchanged -- the quest shown
    -- still has to be the quest asked about.
    if (word or deSentenceIndex) and quest and not lastCaveat
      and tonumber(quest.id) == lastQuestId
      and (quest.passage or "offer") == (displayedPassage or "offer") then
      index = Addon.MatchEnglishSentence(quest.text, lastPlainBody, word, deSentenceIndex)
    end
    paintEnglishBody(frame, index, not sentenceOnly and word or nil, wordOccurrence)
  end
  if Addon.ApplyIntegratedLayout then Addon.ApplyIntegratedLayout() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_PROGRESS")
events:RegisterEvent("QUEST_COMPLETE")
events:RegisterEvent("QUEST_FINISHED")
events:SetScript("OnEvent", function(_, event, loaded)
  if event == "ADDON_LOADED" then
    if loaded == addonName then
      WordHunterWoWENPanelDB = WordHunterWoWENPanelDB or {}
      db = WordHunterWoWENPanelDB
      hookQuestUi()
      hookBaseAddon()
    elseif loaded == "WordHunterWoW" then
      -- The base addon may load after this one. Declaring it as an optional
      -- dependency would fix the order, but it also makes WoW file this addon
      -- under it in the AddOns list as though it were a component of it, which
      -- it is not. Reacting to the load instead costs one branch and leaves
      -- this addon standing on its own in the list.
      hookBaseAddon()
    elseif loaded == "Blizzard_WorldMap" or loaded == "Blizzard_UIPanels_Game" then
      hookQuestUi()
    end
  elseif event == "QUEST_FINISHED" then
    lastPassage = "offer"
    if frame then frame:Hide() end
  else
    -- QUEST_DETAIL is the offer, QUEST_PROGRESS the "are you done yet" line,
    -- QUEST_COMPLETE the hand-in. Only the first has English text behind it.
    if event == "QUEST_PROGRESS" then
      lastPassage = "progress"
    elseif event == "QUEST_COMPLETE" then
      lastPassage = "reward"
    else
      lastPassage = "offer"
    end
    hookQuestUi()
    C_Timer.After(0, function() showQuest() end)
  end
end)
