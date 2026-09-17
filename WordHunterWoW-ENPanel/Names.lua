local addonName = ...

-- Blizzard's tooltips speak whatever language the client is set to. Someone
-- playing in German sees "Feuerball" and has no way to find out that the guides
-- and the group they are in call it Fireball. This appends the English name to
-- the tooltip that is already on screen, rather than opening a second window,
-- so it reads the way the rest of the tooltip does.
--
-- Spell and creature names ship with the panel; there are few enough of them to
-- be free. Items are 168k entries and 90% of the payload, so they live in an
-- optional addon that registers itself here when installed.

WordHunterWoW_ENNames_Spell = WordHunterWoW_ENNames_Spell or {}
WordHunterWoW_ENNames_NPC = WordHunterWoW_ENNames_NPC or {}
WordHunterWoW_ENDesc_Spell = WordHunterWoW_ENDesc_Spell or {}

local ENPanelNames = {}
_G.WordHunterWoW_ENPanelNames = ENPanelNames

local KINDS = { item = true, spell = true, npc = true }
local tables = {
  spell = WordHunterWoW_ENNames_Spell,
  npc = WordHunterWoW_ENNames_NPC,
}
-- What the thing actually does, in English. A name on its own tells you what to
-- search for; the description tells you what you are looking at. Creatures have
-- none -- the game has no text for them either.
local descriptions = {
  spell = WordHunterWoW_ENDesc_Spell,
}

-- Optional name packs call this. Kept deliberately small: a pack is a kind and
-- a table of id -> English name, nothing more.
function ENPanelNames.Register(kind, entries, texts)
  if not KINDS[kind] or type(entries) ~= "table" then return false end
  tables[kind] = entries
  if type(texts) == "table" then descriptions[kind] = texts end
  return true
end

function ENPanelNames.Get(kind, id)
  local source = tables[kind]
  if not source or not id then return nil end
  return source[tonumber(id)]
end

function ENPanelNames.GetDescription(kind, id)
  local source = descriptions[kind]
  if not source or not id then return nil end
  local text = source[tonumber(id)]
  if text == nil or text == "" then return nil end
  return text
end

function ENPanelNames.Counts()
  local out = {}
  for kind, source in pairs(tables) do
    local n = 0
    for _ in pairs(source) do n = n + 1 end
    out[kind] = n
  end
  return out
end

local function enabled()
  local db = WordHunterWoWENPanelDB
  if not db or db.showNames == nil then return true end
  return db.showNames and true or false
end
ENPanelNames.Enabled = enabled

function ENPanelNames.SetEnabled(value)
  WordHunterWoWENPanelDB = WordHunterWoWENPanelDB or {}
  WordHunterWoWENPanelDB.showNames = not not value
end

-- The client's own language. When someone plays in English there is nothing to
-- add, so the whole feature stays out of the way.
local function clientIsEnglish()
  local locale = GetLocale and GetLocale() or "enUS"
  return locale == "enUS" or locale == "enGB"
end

local LABEL = "English"

-- Retail hands back "secret" values from its own frames -- a tooltip's text, a
-- unit's guid. Reading or comparing one raises an error and taints this addon's
-- execution, after which nothing it does works at all. Everything that comes out
-- of the game goes through here first.
local function usable(value)
  if value == nil then return false end
  if canaccessvalue and not canaccessvalue(value) then return false end
  if issecretvalue and issecretvalue(value) then return false end
  return true
end
ENPanelNames.Usable = usable

-- Adding a line and calling Show() can put the tooltip back through the very
-- hook that got us here on the older script-based path, and a tooltip that
-- appends to itself grows without end. One flag stops that for good.
local appending = false

local function appendName(tooltip, kind, id)
  if appending then return end
  if not enabled() or clientIsEnglish() then return end
  local english = ENPanelNames.Get(kind, id)
  if not english or english == "" then return end
  -- Adding the line when the tooltip already shows that exact text would just
  -- repeat the title back at the player. The title is a secret value on some
  -- tooltips, and then there is no way to tell -- so assume it does not match.
  local first = _G[tooltip:GetName() .. "TextLeft1"]
  local current = first and first.GetText and first:GetText()
  local repeated = usable(current) and current == english
  local description = ENPanelNames.GetDescription(kind, id)
  if repeated and not description then return end
  -- The latch is released whatever happens below. Without that, one error in a
  -- single tooltip left it stuck on and every later tooltip in the session
  -- silently skipped its English line.
  appending = true
  pcall(function()
    -- A blank line first. Without it the English runs straight on from the German
    -- and the tooltip reads as one confused paragraph in two languages.
    tooltip:AddLine(" ")
    if not repeated then
      tooltip:AddDoubleLine(LABEL, english, 0.55, 0.62, 0.78, 1.00, 0.82, 0.30)
    end
    if type(description) == "string" then
      -- Wrapped, and in the gold the game uses for an ability's effect text, so
      -- it reads as the English half of what is already above it rather than as
      -- a separate addon shouting.
      tooltip:AddLine(description, 1.00, 0.82, 0.30, true)
    end
    tooltip:Show()
  end)
  appending = false
end
ENPanelNames.AppendName = appendName

local function npcIdFromGuid(guid)
  if type(guid) ~= "string" then return nil end
  -- Creature-0-4379-0-27-448-000082EF89 : the unit id is the sixth field.
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id)
end
ENPanelNames.NpcIdFromGuid = npcIdFromGuid

-- Classic has no TooltipDataProcessor: a tooltip announces what it is showing
-- through its own scripts, and what it is showing has to be read back off it
-- rather than handed over. Retail keeps the path above -- this is only reached
-- when the newer API is genuinely absent, so a client that has both is
-- unaffected.
local function hookTooltipsClassic()
  local tooltips = { GameTooltip, ItemRefTooltip }
  local hookedAny = false
  for _, tooltip in ipairs(tooltips) do
    if type(tooltip) == "table" and type(tooltip.HookScript) == "function" then
      hookedAny = true
      tooltip:HookScript("OnTooltipSetItem", function(self)
        local _, link = self:GetItem()
        if not usable(link) or type(link) ~= "string" then return end
        local id = tonumber(link:match("item:(%d+)"))
        if id then appendName(self, "item", id) end
      end)
      tooltip:HookScript("OnTooltipSetSpell", function(self)
        -- Classic returns name, rank, id. Retail's script path (if it ever
        -- lands here) returns name, id. Take the last number.
        local a, b, c = self:GetSpell()
        local id = type(c) == "number" and c or b
        if usable(id) and type(id) == "number" then appendName(self, "spell", id) end
      end)
      tooltip:HookScript("OnTooltipSetUnit", function(self)
        local _, unit = self:GetUnit()
        if not usable(unit) then return end
        local guid = UnitGUID and UnitGUID(unit or "mouseover")
        if usable(guid) then appendName(self, "npc", npcIdFromGuid(guid)) end
      end)
    end
  end
  return hookedAny
end

local function hookTooltips()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(tooltip, data)
      if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
      if not data or not usable(data.type) then return end
      -- Truthiness on a secret id raises and taints the addon. Ask first.
      if data.type == Enum.TooltipDataType.Item then
        if usable(data.id) then appendName(tooltip, "item", data.id) end
      elseif data.type == Enum.TooltipDataType.Spell then
        if usable(data.id) then appendName(tooltip, "spell", data.id) end
      elseif data.type == Enum.TooltipDataType.Unit then
        -- data.id is a unit token here, not a creature id; the guid carries it.
        -- Both the token and the guid can be secret.
        if not usable(data.id) then return end
        local guid = UnitGUID and UnitGUID(data.id)
        if usable(guid) then
          appendName(tooltip, "npc", npcIdFromGuid(guid))
        end
      end
    end)
    return true
  end
  return hookTooltipsClassic()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, loaded)
  if loaded ~= addonName then return end
  WordHunterWoWENPanelDB = WordHunterWoWENPanelDB or {}
  hookTooltips()
end)
