local Addon = WordHunterWoW_Voice or {}
WordHunterWoW_Voice = Addon

-- The frame that shows who is talking.
--
-- Sound with nothing on screen is confusing: a voice starts, and the player has
-- no way to tell which quest it belongs to, whether it is this addon at all, or
-- how to make it stop. So while a passage is being read there is a portrait, the
-- quest's name, which sentence of how many is being spoken, and one transport
-- button in the corner -- pause while it is speaking, play when it is not.
--
-- This wore a close cross in the corner at first, which reads as "hide this
-- window" and so was never pressed to stop a voice -- and there was no way at
-- all to hear a passage a second time, which is the thing somebody learning the
-- language wants most. A pair of media-transport icons answers both without
-- putting a word of German on the frame.
--
-- It appears only while something is being read and takes no clicks otherwise,
-- so it costs a player who never notices it nothing.

-- What this window follows, and why it is a scale rather than a font size.
--
-- It followed nothing at all: a player who set the quest panel to 200% got
-- 24pt words with a fixed 300x96 talker beside them, which is one of the
-- windows the "every window a different size" complaint was pointing at.
--
-- It cannot be answered with a font size. Both strings here are SetWordWrap
-- (false) inside a frame pinned at 300 wide, with 194px of that left for the
-- quest name -- less than a real German quest name needs at 12pt already. A
-- bigger font in the same box truncates more, not less. SetScale grows the box
-- and the letters together, which is the only move that makes this frame
-- readable rather than shorter.
--
-- And no new setting: the voice side stores no size key of its own, so it
-- borrows the base addon's quest-panel text size -- the setting for the words
-- this window is captioning. With the base absent there is nothing to ask and
-- it stays at 1, the same shape the theming and the padding here already take.
local function textScale()
  local base = WordHunterWoW_Addon
  local value = base and base.GetTextScale and base.GetTextScale()
  if type(value) ~= "number" or value <= 0 then return 1 end
  return value
end

local WIDTH, HEIGHT = 300, 96
local PORTRAIT = 58
local BUTTON = 24

local frame, model, portrait, title, subtitle, play, pause, restart

-- Which of the two transport buttons is on screen. Never both: the icon showing
-- is the thing a click will do, which is the whole reason a media player draws
-- it this way.
local speaking = false

local function db()
  WordHunterWoWVoiceDB = WordHunterWoWVoiceDB or {}
  return WordHunterWoWVoiceDB
end

function Addon.GetTalkerEnabled()
  local value = db().talker
  if value == nil then return true end
  return value and true or false
end

function Addon.SetTalkerEnabled(value)
  db().talker = value and true or false
  if not db().talker then Addon.HideTalker() end
end

-- Where it sits. Dragged by the player and remembered; the default is above the
-- action bars rather than centred, because the middle of the screen is where
-- everything else in this game already is.
local function place(self)
  local held = db().talkerPoint
  self:ClearAllPoints()
  if held then
    self:SetPoint(held[1], UIParent, held[2], held[3], held[4])
  else
    self:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 210)
  end
end

-- How far in from the edge the contents have to start.
--
-- The skins do not agree on how much of the frame their border art eats. The
-- built-in backdrop below keeps to four pixels, but QuestWordHunter's parchment
-- skin reaches a dozen in and paints its reading surface inside that -- so a
-- portrait anchored eight pixels from the edge, which is right for every other
-- skin, sat half on the border. Read off the chosen skin rather than listed per
-- skin here, so one added to the base addon later is handled without a change.
local CONTENT_PAD = 8

local function padding()
  local base = WordHunterWoW_Addon
  local style = base and base.BACKGROUNDS and base.GetBackgroundStyle
    and base.BACKGROUNDS[base.GetBackgroundStyle()]
  local insets = style and style.insets
  if not insets then return CONTENT_PAD end
  local deepest = math.max(insets.left or 0, insets.top or 0,
    insets.right or 0, insets.bottom or 0)
  return math.max(CONTENT_PAD, deepest + 4)
end

local function layout()
  if not frame then return end
  local pad = padding()
  -- The button sits two pixels closer to the corner than the portrait does to
  -- the side, which is where it has always been and reads as tucked in rather
  -- than floating.
  local corner = pad - 2
  model:ClearAllPoints()
  model:SetPoint("LEFT", pad, 0)
  portrait:ClearAllPoints()
  portrait:SetPoint("LEFT", pad, 0)
  for _, text in ipairs({ title, subtitle }) do
    -- Stopping exactly where the button starts. The two are never allowed to
    -- overlap, because a truncated quest name is tidy and a quest name printed
    -- through a button is not.
    text:SetPoint("RIGHT", frame, "RIGHT", -(corner + BUTTON * 2 + 2), 0)
  end
  -- Play and pause share a corner because only one of them is ever up. Restart
  -- is a third thing and is always up, so it sits beside them rather than on
  -- top of them -- and to their left, so the corner keeps holding whichever of
  -- the pair is showing and nothing moves as they swap.
  for _, button in ipairs({ play, pause }) do
    button:ClearAllPoints()
    button:SetPoint("TOPRIGHT", -corner, -corner)
  end
  if restart then
    restart:ClearAllPoints()
    restart:SetPoint("TOPRIGHT", -(corner + BUTTON + 2), -corner)
  end
end

-- Wear whatever QuestWordHunter is wearing, when it is installed.
--
-- The base addon paints its own windows through ApplyBackground, which knows
-- the skin the player picked, the opacity slider, and the opaque surface it
-- lays under text so letters stay legible on the parchment one. Calling it is
-- the whole of the integration. Copying a palette over here instead would go
-- stale the first time the base addon gained a fifth skin -- which is how this
-- frame came to stop matching the rest in the first place.
--
-- The base addon is optional and the .toc says so, so with it absent this does
-- nothing at all and the dialog backdrop build() set is what stays.
local function applyTheme()
  local base = WordHunterWoW_Addon
  if not frame or not base or not base.ApplyBackground then return end
  base.ApplyBackground(frame)
  -- Its text colours too. ApplyBackground puts every skin's text on the same
  -- near-black reading surface, chosen for the base addon's near-white letters;
  -- the game's gold GameFontNormal was picked against a parchment box.
  local colors = base.COLORS
  if colors and colors.text then
    title:SetTextColor(colors.text[1], colors.text[2], colors.text[3])
  end
  if colors and colors.muted then
    subtitle:SetTextColor(colors.muted[1], colors.muted[2], colors.muted[3])
  end
  layout()
end

-- Repaint when the player changes the skin or moves the opacity slider.
--
-- The base addon fans that out to its own windows from a list it holds itself,
-- and there is no slot in it for a frame belonging to another addon. So the
-- fan-out is wrapped rather than joined -- the same trick Voice.lua plays on
-- openEditor, and for the same reason: this addon can then sit beside any
-- version of the base one without the two having to agree on anything.
local themeHooked

local function followTheme()
  local base = WordHunterWoW_Addon
  if themeHooked or not base or not base.RefreshAllBackdrops then return end
  themeHooked = true
  local previous = base.RefreshAllBackdrops
  base.RefreshAllBackdrops = function(...)
    previous(...)
    applyTheme()
  end
  -- Caught up once here as well, since the base addon may have loaded after
  -- this frame was built and the skin need never change again.
  applyTheme()
end

local function build()
  if frame then return frame end
  frame = CreateFrame("Frame", "WordHunterWoWVoiceTalker", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetScale(textScale())
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relative, x, y = self:GetPoint()
    db().talkerPoint = { point, relative, x, y }
  end)
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end
  place(frame)

  -- A living portrait where the client can give one, a flat one where it cannot.
  -- SetUnit only works while the unit is there to look at, which for a quest
  -- giver is exactly as long as the window is open -- so the flat texture is
  -- taken at the same moment and kept as the fallback.
  model = CreateFrame("PlayerModel", nil, frame)
  model:SetSize(PORTRAIT, PORTRAIT)

  portrait = frame:CreateTexture(nil, "ARTWORK")
  portrait:SetSize(PORTRAIT, PORTRAIT)
  portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  portrait:Hide()

  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", model, "TOPRIGHT", 10, -4)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)

  subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetWordWrap(false)

  -- The transport pair, with the words in the tooltip. An icon is read at a
  -- glance where a label has to be read; these sit on a frame that appears
  -- while a voice is talking, and nobody wants to read at that moment. Both are
  -- anchored to the same corner, because only one of them is ever on screen.
  local function transport(tip, action)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(BUTTON, BUTTON)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", action)
    button:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(tip)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return button
  end

  -- The spellbook's page-turn arrow. There is no play glyph in the client, and
  -- this is one of the few right-pointing arrows that is genuinely everywhere:
  -- it has been in Interface\Buttons since 1.12 and Retail's own
  -- SharedUIPanelTemplates still draws its increment buttons from it. A button
  -- whose texture is missing is an invisible button, so the artwork mattered
  -- more here than the exact shape.
  play = transport("Vorlesen fortsetzen", function()
    if Addon.Resume then Addon.Resume() end
  end)
  local arrow = play:CreateTexture(nil, "ARTWORK")
  arrow:SetAllPoints()
  arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")

  -- Read it again from the top. Addon.Replay already existed for the slash
  -- command; what it never had was a way to reach it while listening, which is
  -- exactly when a learner wants it -- half a passage understood is the normal
  -- outcome of a first hearing, and reopening the quest to get it back is a
  -- worse answer than a button that is already on screen.
  --
  -- The dressing room's rotate-left arrow, which is a curved one. Two icons
  -- were tried before it and both said the wrong thing: TimeManager's
  -- ResetButton is a filled dot in a frame and reads as a lamp, and the
  -- spellbook's previous-page arrow is a straight triangle that reads as
  -- "back one", not "from the top".
  --
  -- Curved is what makes it mean repeat rather than reverse, and this one is
  -- safe to reach for: the character and dressing-room frames have turned their
  -- models with it since vanilla, so it is on every client this addon loads on.
  -- A prettier icon that is missing on one of them is an invisible button.
  restart = transport("Von vorne vorlesen", function()
    if Addon.Replay then Addon.Replay() end
  end)
  local again = restart:CreateTexture(nil, "ARTWORK")
  again:SetAllPoints()
  again:SetTexture("Interface\\Buttons\\UI-RotationLeft-Button-Up")

  -- Pause is drawn rather than loaded, because no pause texture ships with
  -- every client. WHITE8X8 is a plain white square the client will stretch to
  -- any size -- it is what the base addon's own hairline borders are made of --
  -- so two bars of it stay crisp at any scale, where a bitmap icon squeezed
  -- into 24 pixels does not.
  --
  -- Gold, not white: the arrow above is the game's gold, and a white pause
  -- beside a gold play reads as two buttons borrowed from two different addons.
  pause = transport("Vorlesen pausieren", function()
    if Addon.Pause then Addon.Pause() end
  end)
  for _, offset in ipairs({ -4, 4 }) do
    local bar = pause:CreateTexture(nil, "ARTWORK")
    bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetVertexColor(1, 0.82, 0)
    bar:SetSize(5, 14)
    bar:SetPoint("CENTER", pause, "CENTER", offset, 0)
  end

  layout()
  Addon.SetTalkerSpeaking(speaking)
  applyTheme()

  frame:Hide()
  Addon.talkerFrame = frame
  return frame
end

-- Which of the two the frame is showing. The engine calls this rather than the
-- frame asking the engine, so the frame stays something that can be checked
-- without a client and the engine stays the only thing that knows whether a
-- voice is running.
function Addon.SetTalkerSpeaking(value)
  speaking = value and true or false
  if not play or not pause then return end
  if speaking then
    pause:Show()
    play:Hide()
  else
    play:Show()
    pause:Hide()
  end
end

Addon.BuildTalker = build

-- Shown when a passage starts. `speaker` is the unit token to portray, if the
-- client still has one; `name` is what to write.
function Addon.ShowTalker(name, speaker, line)
  if not Addon.GetTalkerEnabled() then return end
  build()
  -- Tried on every passage rather than once at load: the base addon is optional
  -- and nothing here controls when it turns up, and after the first success
  -- this costs two comparisons.
  followTheme()
  Addon.SetTalkerSpeaking(true)
  title:SetText(name or "")
  subtitle:SetText(line or "")
  local shown = false
  if speaker and UnitExists and UnitExists(speaker) then
    if model.SetUnit then
      model:SetUnit(speaker)
      model:Show()
      portrait:Hide()
      shown = true
    end
  end
  if not shown then
    -- No unit to model: the quest giver's own portrait if the client will give
    -- one, and the icon a quest giver wears on the minimap if it will not.
    portrait:Show()
    model:Hide()
    if speaker and SetPortraitTexture and UnitExists and UnitExists(speaker) then
      SetPortraitTexture(portrait, speaker)
    else
      portrait:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    end
  end
  -- Caught up here as well as at build time: the talker is built once and the
  -- slider can move at any point after that, and this window only ever appears
  -- at the start of a passage, so there is no cheaper moment to ask.
  frame:SetScale(textScale())
  frame:Show()
end

function Addon.HideTalker()
  if frame then frame:Hide() end
end

-- Stop speaking, but leave the frame up so the passage can be heard again.
-- Hiding it the moment the voice ends puts the play button out of reach at
-- exactly the moment somebody wants it.
function Addon.RestTalker()
  if not frame or not frame:IsShown() then return end
  Addon.SetTalkerSpeaking(false)
  if subtitle then subtitle:SetText("fertig vorgelesen") end
end

-- What the frame says. Kept apart from the frame so it can be checked without
-- a client: the second line counts sentences, and off-by-one there is the kind
-- of thing nobody notices until it says "Satz 4 von 3".
function Addon.TalkerLine(index, total)
  index, total = tonumber(index) or 1, tonumber(total)
  if not total or total <= 1 then return "" end
  if index > total then index = total end
  return string.format("Satz %d von %d", index, total)
end
