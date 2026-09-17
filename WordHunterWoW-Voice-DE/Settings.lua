local Addon = WordHunterWoW_Voice or {}
WordHunterWoW_Voice = Addon

-- The options panel, in the game's own AddOns list.
--
-- Everything here is already reachable through /whwv, and the slash command
-- stays. But a player who installs a voice pack and hears nothing looks in
-- Options first, and finding nothing there reads as "it does not work" rather
-- than "it is switched off" -- so the panel exists mostly to be found.
--
-- It also answers the question the slash command cannot: which packs are
-- actually installed. That is the single most common way this addon appears
-- broken, because a quest outside every installed pack is silent by design and
-- looks exactly like a fault.

local PANEL_NAME = "QuestWordHunter Voice"

-- The page follows the base addon's quest panel text size, the same setting the
-- talker window borrows and for the same reason: the voice side stores no size
-- key of its own, and this page is read beside the windows that setting governs.
-- With the base absent there is nothing to ask and the page stays as it was
-- drawn, which is the shape the theming here already takes.
local function pageScale()
  local base = WordHunterWoW_Addon
  local value = base and base.GetTextScale and base.GetTextScale()
  if type(value) ~= "number" or value <= 0 then return 1 end
  return value
end

-- Sizes a string by the job it does rather than by the font object it was built
-- from -- the object still supplies the family and, with it, the colour, which
-- is the trap in any size work here: a Blizzard font object carries a colour as
-- well as a size, so a string re-pointed at another object to fix its size comes
-- back gold where it was white.
local function roleFont(fs, role, scale)
  local base = WordHunterWoW_Addon
  if base and base.ApplyFontRole then base.ApplyFontRole(fs, role, scale) end
end

-- The noise a tick box makes. The template plays it from its own OnClick, and
-- the OnClick below replaces that script rather than hooking it -- it has to,
-- since the template's handler also files the value away in the options system
-- this page does not use -- so the sound has to be made here. Without it these
-- four boxes were the only silent ones in the whole options window, which reads
-- as a click that did not register.
local function clickSound(ticked)
  if not PlaySound then return end
  local kit = SOUNDKIT
  local sound = kit and (ticked and kit.IG_MAINMENU_OPTION_CHECKBOX_ON
    or kit.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  -- A client old enough to predate the SOUNDKIT table takes the name instead,
  -- and a client with neither gets silence rather than an error: this addon
  -- runs on more than one of them and none of these globals is promised.
  if sound == nil then
    sound = ticked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff"
  end
  PlaySound(sound)
end

local function makeCheck(parent, label, tooltip, get, set)
  local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  check.Text:SetText(label)
  -- Shown from here rather than left to the template. check.tooltipText and
  -- check.tooltipRequirement were the old way of telling the options UI what to
  -- say, and InterfaceOptionsCheckButton_OnEnter was the one thing that read
  -- them. That function is gone, and on Classic Era the template is an empty
  -- alias in DeprecatedTemplates.xml whose ancestors script no OnEnter at all,
  -- so both fields were written and never looked at again -- four sentences
  -- explaining what each switch does, reaching nobody.
  check:SetScript("OnEnter", function(self)
    if not GameTooltip or not GameTooltip.SetOwner then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(label, 1, 1, 1)
    -- Wrapped: these run past a line, and a tooltip does not wrap by itself.
    GameTooltip:AddLine(tooltip, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  check:SetScript("OnLeave", function()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
  end)
  check:SetScript("OnClick", function(self)
    local ticked = self:GetChecked() and true or false
    clickSound(ticked)
    set(ticked)
  end)
  check.refresh = function() check:SetChecked(get()) end
  return check
end

-- What the player has installed, in the order the packs were released, so the
-- list reads the way the download page does.
local ORDER = {
  "Classic", "BurningCrusade", "Wrath", "Cataclysm", "Pandaria", "Draenor",
  "Legion", "Azeroth", "Shadowlands", "Dragonflight", "WarWithin", "Words",
}

function Addon.InstalledPacks()
  local held, quests, words = {}, 0, false
  for folder, part in pairs(WordHunterWoW_Voice_Parts or {}) do
    local name = folder:match("^WordHunterWoW%-Voice%-DE%-(.+)$") or folder
    held[name] = true
    if part.words then words = true else quests = quests + 1 end
  end
  local named = {}
  for _, name in ipairs(ORDER) do
    if held[name] then
      named[#named + 1] = name
      held[name] = nil
    end
  end
  -- Anything with a name this addon does not know about still gets listed;
  -- silently dropping it would hide exactly the case worth seeing.
  for name in pairs(held) do named[#named + 1] = name end
  return named, quests, words
end

function Addon.CreateSettingsPanel()
  if Addon.settingsPanel then return Addon.settingsPanel end
  local panel = CreateFrame("Frame")
  panel.name = PANEL_NAME

  -- Where everything on the page sits at 100%, kept rather than applied once,
  -- so a size chosen later can put the whole page down again.
  --
  -- The page cannot answer a size setting by scaling itself. It is parented into
  -- Blizzard's options canvas, so it already carries that canvas's effective
  -- scale and SetScale here would multiply with it rather than replace it -- the
  -- same reason QuestWordHunter's own options page sizes its contents. So this
  -- file's own strings take a font role, and Blizzard's composites -- the tick
  -- boxes and the slider, drawn from art and children this file does not own --
  -- are scaled one at a time, which is safe where scaling the page is not
  -- because their parent is this panel and this panel is never scaled.
  --
  -- `opts`: role, the font role one of this file's strings is drawn at; own, a
  -- composite that carries its own scale; w, its width at 100%.
  local rows = {}
  panel.rows = rows
  local function place(frame, anchor, x, y, opts)
    opts = opts or {}
    opts.frame, opts.anchor, opts.x, opts.y = frame, anchor, x, y
    rows[#rows + 1] = opts
    return frame
  end

  local function layout()
    local scale = pageScale()
    for _, row in ipairs(rows) do
      local frame = row.frame
      frame:ClearAllPoints()
      if row.own then
        frame:SetScale(scale)
        -- Handed over as they are: the offsets of a scaled frame are read in
        -- that frame's own units, so the frame supplies the multiplication. Do
        -- it here as well and the gap is scaled twice, which at 100% looks
        -- exactly the same as doing it right.
        frame:SetPoint("TOPLEFT", row.anchor or panel, row.anchor and "BOTTOMLEFT" or "TOPLEFT",
          row.x, row.y)
        if row.w then frame:SetWidth(row.w / scale) end
      else
        roleFont(frame, row.role, scale)
        -- An unscaled string reads its offsets in the panel's units, so the gap
        -- above it has to be multiplied here or the letters grow while the line
        -- above them stays where it was.
        frame:SetPoint("TOPLEFT", row.anchor or panel, row.anchor and "BOTTOMLEFT" or "TOPLEFT",
          row.x, row.y * scale)
        -- Horizontal insets are left alone. The canvas is as wide as it is and
        -- no size setting may widen it, so the page grows downwards only.
        if row.wide then frame:SetPoint("RIGHT", panel, "RIGHT", -16, 0) end
      end
    end
  end
  panel.layout = layout

  local title = place(panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"),
    nil, 16, -16, { role = "heading" })
  title:SetText(PANEL_NAME)
  panel.title = title

  local blurb = place(panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
    title, 0, -8, { role = "meta", wide = true })
  blurb:SetJustifyH("LEFT")
  blurb:SetText("Liest deutschen Questtext vor. Die Audiodateien liegen in "
    .. "separaten Paketen; ein Quest ohne Aufnahme bleibt still.")

  local quests = place(makeCheck(panel, "Questtext vorlesen",
    "Liest Beschreibung, Zwischenstand und Abgabe, Satz für Satz.",
    Addon.GetEnabled, Addon.SetEnabled), blurb, 0, -16, { own = true })

  local words = place(makeCheck(panel, "Einzelne Wörter vorlesen",
    "Spricht ein Wort aus, wenn es angeklickt wird. Braucht das Wörterpaket.",
    Addon.GetWordsEnabled, Addon.SetWordsEnabled), quests, 0, -8, { own = true })

  local talker = place(makeCheck(panel, "Sprecherfenster anzeigen",
    "Zeigt während des Vorlesens, zu welchem Quest die Stimme gehört, "
    .. "mit einer Schaltfläche zum Abbrechen. Verschiebbar.",
    Addon.GetTalkerEnabled, Addon.SetTalkerEnabled), words, 0, -8, { own = true })

  local demo = place(makeCheck(panel, "Platzhalter abspielen",
    "Spielt einen Hinweis ab, wenn für den Quest noch keine Aufnahme existiert. "
    .. "Zum Prüfen, ob überhaupt Ton ankommt.",
    Addon.GetDemo, Addon.SetDemo), talker, 0, -8, { own = true })

  -- How long the voice waits before starting. A slider rather than a switch
  -- because the right value depends on how fast the player reads, and the
  -- default is a compromise nobody asked for.
  local delay = place(CreateFrame("Slider", "WordHunterWoWVoiceDelaySlider", panel,
    "OptionsSliderTemplate"), demo, 6, -32, { own = true, w = 220 })
  delay:SetMinMaxValues(0, 5)
  delay:SetValueStep(0.25)
  if delay.SetObeyStepOnDrag then delay:SetObeyStepOnDrag(true) end
  if delay.Low then delay.Low:SetText("sofort") end
  if delay.High then delay.High:SetText("5 s") end
  delay:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value * 4 + 0.5) / 4
    Addon.SetDelay(value)
    if self.Text then
      self.Text:SetText(value == 0 and "Verzögerung: sofort"
        or string.format("Verzögerung: %.2f s", value))
    end
  end)
  delay.refresh = function()
    delay:SetValue(Addon.GetDelay())
    if delay.Text then
      local value = Addon.GetDelay()
      delay.Text:SetText(value == 0 and "Verzögerung: sofort"
        or string.format("Verzögerung: %.2f s", value))
    end
  end

  local installed = place(panel:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
    delay, -6, -28, { role = "body" })
  installed:SetText("Installierte Pakete")

  local list = place(panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
    installed, 0, -6, { role = "meta", wide = true })
  list:SetJustifyH("LEFT")

  panel.refresh = function()
    quests.refresh()
    words.refresh()
    talker.refresh()
    demo.refresh()
    delay.refresh()
    local named, questPacks, hasWords = Addon.InstalledPacks()
    if #named == 0 then
      list:SetText("|cffff8080Keine|r. Ohne ein Paket bleibt jeder Quest still.")
    else
      local tail = hasWords and "" or "  |cffc0c0c0(kein Wörterpaket)|r"
      list:SetText(table.concat(named, ", ") .. tail)
    end
    -- Words cannot be spoken without the pack that holds them, and a switch
    -- that does nothing is worse than one that says why.
    if hasWords then words:Enable() else words:Disable() end
    if questPacks == 0 then quests:Disable() else quests:Enable() end
    -- Last. The size lives in the base addon and can be changed with this page
    -- closed, and Blizzard's own route in -- Esc, Options, AddOns -- touches
    -- none of these controls, so opening the page is where it has to catch up.
    layout()
  end

  -- Laid out once at whatever size is already stored, rather than at 100% and
  -- corrected on the first show.
  layout()

  panel:SetScript("OnShow", function(self) self.refresh() end)

  if Settings and Settings.RegisterAddOnCategory then
    -- Kept here, on this addon's own table, and not written onto the category.
    --
    -- What stood in its place was `category.ID = panel.name`, from the idiom
    -- that went round when this API arrived, and it broke the thing it was
    -- there to help: the client sets that field to a number as it builds the
    -- category, GetID hands that number back, and OpenToCategory wants the
    -- number -- so the name put there is what OpenSettings passed instead, and
    -- /whwv config opened nothing. The quieter half is that the table came out
    -- of Blizzard's own code, and writing into one of those taints it, which
    -- then travels to everything this addon does next.
    --
    -- Nothing in this addon or in QuestWordHunter ever looks the category up by
    -- name, so the name only ever fed the fallback at the bottom of this file.
    -- It can feed it from this side, where nothing is anyone else's.
    Addon.settingsCategoryName = panel.name
    if Settings.RegisterCanvasLayoutCategory then
      local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
      Settings.RegisterAddOnCategory(category)
      Addon.settingsCategory = category
    else
      local category = Settings.RegisterVerticalLayoutCategory(panel.name)
      Settings.RegisterAddOnCategory(category)
      Addon.settingsCategory = category
    end
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end

  Addon.settingsPanel = panel
  return panel
end

function Addon.OpenSettings()
  local panel = Addon.CreateSettingsPanel()
  if panel.refresh then panel.refresh() end
  if Settings and Settings.OpenToCategory and Addon.settingsCategory then
    -- GetID first, because that is the number the client filled in and the
    -- number OpenToCategory documents. The two behind it are for a category
    -- object that answers neither: its own ID field, and failing that the name
    -- the page was registered under, which is what the old call took.
    local category = Addon.settingsCategory
    local id = category.GetID and category:GetID() or category.ID
      or Addon.settingsCategoryName
    if id then Settings.OpenToCategory(id) end
  elseif InterfaceOptionsFrame_OpenToCategory then
    -- Called twice on the old client: the first call only opens the frame.
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end
