local addonName = ...

local function importDictionary()
  local addon = WordHunterWoW_Addon
  if not addon or not addon.RegisterDictionaryProvider or type(WordHunterWoW_Dictionary_DE) ~= "table" then return end
  addon.RegisterDictionaryProvider("deDE", addonName, WordHunterWoW_Dictionary_DE)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, loaded)
  if loaded == addonName then importDictionary() end
end)

-- WordHunterWoW is a required dependency, so its provider API is already available.
-- Register immediately as well as on ADDON_LOADED to avoid load-order edge cases.
importDictionary()
