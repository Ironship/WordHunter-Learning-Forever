local UI = {}
WordHunterWoW_Addon.GamePadUI = UI

local windows = setmetatable({}, { __mode = "k" })
local registered = setmetatable({}, { __mode = "k" })
local buttonFrames = setmetatable({}, { __mode = "k" })
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function visible(frame)
  return frame and (frame.IsVisible and frame:IsVisible() or not frame.IsVisible and frame:IsShown())
end

function UI.ConsolePortActive()
  return ConsolePort and type(ConsolePort.IsCursorActive) == "function" and ConsolePort:IsCursorActive()
end

function UI.Register(frame)
  windows[frame] = true
  if not inCombat() and not registered[frame] and ConsolePort
      and type(ConsolePort.AddInterfaceCursorFrame) == "function" then
    registered[frame] = ConsolePort:AddInterfaceCursorFrame(frame) or nil
  end
end

function UI.EnableButtons(frame)
  buttonFrames[frame] = true
  if not inCombat() and type(frame.EnableGamePadButton) == "function" then
    frame:EnableGamePadButton(true)
    frame:SetPropagateKeyboardInput(true)
  end
end

function UI.Key(key)
  if ConsolePort and type(ConsolePort.GetFormattedButtonCombination) == "function" then
    local glyph = ConsolePort:GetFormattedButtonCombination(key, "")
    if glyph then return glyph end
  end
  return GetBindingText and GetBindingText(key, 1) or _G["KEY_" .. key] or key
end

function UI.Hint()
  if UI.ConsolePortActive() then return "ConsolePort: D-pad: select · use the cursor's button hints" end
  return UI.Key("PADDUP") .. "/" .. UI.Key("PADDDOWN") .. ": select  ·  "
    .. UI.Key("PADDLEFT") .. "/" .. UI.Key("PADDRIGHT") .. ": move / adjust  ·  "
    .. UI.Key("PAD1") .. ": activate  ·  " .. UI.Key("PAD2") .. ": back"
end

local selected, selectionHost, mark
local function script(node, name, ...)
  local handler = node and node:GetScript(name)
  if handler then handler(node, ...) end
end

function UI.Clear()
  if selected then
    script(selected, "OnLeave")
    if selected:IsObjectType("EditBox") == true and selected:HasFocus() then selected:ClearFocus() end
  end
  selected, selectionHost = nil, nil
  if mark then mark:Hide() end
end

local function reveal(node, host)
  local scroll = node:GetParent()
  while scroll and scroll ~= host do
    if scroll:IsObjectType("ScrollFrame") then
      local top, bottom, high, low = node:GetTop(), node:GetBottom(), scroll:GetTop(), scroll:GetBottom()
      if top and bottom and high and low then
        local offset = scroll:GetVerticalScroll()
        local scale = node:GetEffectiveScale() / scroll:GetEffectiveScale()
        if top * scale > high then offset = offset - (top * scale - high) - 4
        elseif bottom * scale < low then offset = offset + (low - bottom * scale) + 4 end
        scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(), offset)))
      end
      return
    end
    scroll = scroll:GetParent()
  end
end

local function focus(host, node)
  UI.Clear()
  selected, selectionHost = node, host
  if not mark then
    mark = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    mark:EnableMouse(false)
    mark:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    mark:SetBackdropBorderColor(1, .82, 0, 1)
  end
  mark:SetParent(node)
  mark:ClearAllPoints()
  mark:SetPoint("TOPLEFT", node, "TOPLEFT", -2, 2)
  mark:SetPoint("BOTTOMRIGHT", node, "BOTTOMRIGHT", 2, -2)
  mark:SetFrameLevel(node:GetFrameLevel() + 5)
  mark:Show()
  reveal(node, host)
  script(node, "OnEnter")
end

local function candidates(host)
  local out = {}
  local function visit(frame)
    if not visible(frame) then return end
    local enabled = not frame.IsEnabled or frame:IsEnabled()
    local row = rawget(frame, "settingsRow")
    if type(row) == "table" and row.dimmed then enabled = false end
    local slider = frame:IsObjectType("Slider") and frame:GetOrientation() == "HORIZONTAL"
    local interactive = frame:IsObjectType("Button") == true or frame:IsObjectType("EditBox") == true or slider == true
    if enabled and interactive and frame:GetWidth() > 0 and frame:GetHeight() > 0
        and not (frame.IsProtected and frame:IsProtected()) then
      out[#out + 1] = frame
    end
    if type(frame.GetChildren) == "function" then
      for _, child in ipairs({ frame:GetChildren() }) do visit(child) end
    end
  end
  visit(host)
  table.sort(out, function(a, b)
    local ax, ay = a:GetCenter(); local bx, by = b:GetCenter()
    if not ay or not by then return false end
    local rowA, rowB = math.floor(ay / 6), math.floor(by / 6)
    if rowA ~= rowB then return rowA > rowB end
    return (ax or 0) < (bx or 0)
  end)
  return out
end

function UI.Navigate(host, key)
  if inCombat() or UI.ConsolePortActive() then return false end
  local direction = ({ PADDUP = -1, PADDDOWN = 1, PADDLEFT = -1, PADDRIGHT = 1 })[key]
  if not direction and key ~= "PAD1" then return false end
  local nodes, index = candidates(host)
  if #nodes == 0 then return false end
  for i, node in ipairs(nodes) do if node == selected and selectionHost == host then index = i end end
  if not index then
    if nodes[1] then focus(host, nodes[1]) end
    return true
  end
  local node = nodes[index]
  if direction then
    if node:IsObjectType("Slider") and (key == "PADDLEFT" or key == "PADDRIGHT") then
      local low, high = node:GetMinMaxValues()
      local step = node:GetValueStep()
      if not step or step <= 0 then step = (high - low) / 100 end
      node:SetValue(math.max(low, math.min(high, node:GetValue() + direction * step)))
    else
      focus(host, nodes[math.max(1, math.min(#nodes, index + direction))])
    end
  elseif node:IsObjectType("EditBox") then
    if node:HasFocus() then node:ClearFocus() else node:SetFocus() end
  elseif node:IsObjectType("Slider") then
    return true
  else
    -- Click preserves the client's CheckButton toggle and OnClick hooks.
    if node.Click then node:Click("LeftButton") else script(node, "OnClick", "LeftButton") end
    if not visible(node) then UI.Clear() end
  end
  return true
end

function UI.Attach(frame, handler)
  UI.Register(frame)
  if not frame.EnableGamePadButton then return end
  UI.EnableButtons(frame)
  frame:SetScript("OnGamePadButtonDown", function(self, key)
    if inCombat() then return end
    local handled = not UI.ConsolePortActive() and handler(self, key)
    self:SetPropagateKeyboardInput(not handled)
  end)
  frame:HookScript("OnHide", UI.Clear)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_REGEN_ENABLED" }) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function()
  for frame in pairs(windows) do UI.Register(frame) end
  for frame in pairs(buttonFrames) do UI.EnableButtons(frame) end
end)


local Addon = WordHunterWoW_Addon
function Addon.AttachGamePad(frame)
  Addon.GamePadUI.Attach(frame, function(self, key)
    for _, name in ipairs({ 'confirmDialog', 'copyDialog', 'editor', 'listFrame', 'statsFrame', 'panel' }) do
      local open = Addon[name]
      if open and open:IsShown() then
        if key == 'PAD2' then open:Hide(); return true end
        return Addon.GamePadUI.Navigate(open, key)
      end
    end
    if self == Addon.questLogButton then
      if key == 'PAD3' then Addon.ToggleQuestFromLog(); return true end
      return false
    end
    if key == 'PAD2' then self:Hide(); return true end
    return Addon.GamePadUI.Navigate(self, key)
  end)
  if frame:IsObjectType('Button') then return end
  local hint = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
  hint:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 12, 2)
  hint:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -12, 2)
  hint:SetJustifyH('LEFT')
  frame:HookScript('OnShow', function()
    local enabled = (C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled())
      or (GetCVarBool and GetCVarBool('GamePadEnable'))
    hint:SetText(enabled and Addon.GamePadUI.Hint() or '')
  end)
end
