AltCraftTracker = AltCraftTracker or {}

local ACT = AltCraftTracker
local MinimapButton = {}
MinimapButton.__index = MinimapButton
ACT.MinimapButton = MinimapButton

local function enabled(self)
  if type(self.isEnabled) == "function" then local ok, value = pcall(self.isEnabled); if ok then return value ~= false end end
  local db = self.repository and self.repository.db
  local setting = db and db.settings and db.settings.minimapButton
  return setting ~= false
end

function MinimapButton:Create(options)
  options = type(options) == "table" and options or {}
  local repository = options.repository
  local settings = repository and repository.db and repository.db.settings or {}
  return setmetatable({ env = options.env or _G, repository = repository, onClick = options.onClick,
    isEnabled = options.isEnabled, setEnabled = options.setEnabled,
    angle = tonumber(options.angle) or tonumber(settings.minimapAngle) or 0 }, MinimapButton)
end

function MinimapButton:Initialize(options)
  options = type(options) == "table" and options or {}
  for _, key in ipairs({ "repository", "onClick", "isEnabled", "setEnabled" }) do if options[key] ~= nil then self[key] = options[key] end end
  if options.angle ~= nil then self.angle = tonumber(options.angle) or self.angle end
  if self.initialized then self:Refresh() return self end
  if not enabled(self) or type(CreateFrame) ~= "function" or not Minimap then return self end
  local button = CreateFrame("Button", "AltCraftTrackerMinimapButton", Minimap)
  button:SetSize(32, 32); button:SetFrameStrata("MEDIUM"); button:SetFrameLevel(8)
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local icon = button:CreateTexture(nil, "BACKGROUND"); icon:SetTexture("Interface\\Icons\\INV_Misc_EngGizmos_19"); icon:SetSize(20, 20); icon:SetPoint("CENTER")
  button:SetScript("OnClick", function() if type(self.onClick) == "function" then self.onClick() elseif ACT.UI and type(ACT.UI.Toggle) == "function" then ACT.UI:Toggle() end end)
  button:SetScript("OnEnter", function() if GameTooltip and GameTooltip.SetOwner then GameTooltip:SetOwner(button, "ANCHOR_LEFT"); GameTooltip:AddLine("AltCraft Tracker"); GameTooltip:AddLine("Click to open"); GameTooltip:Show() end end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnDragStart", function() self.dragging = true end)
  button:SetScript("OnDragStop", function() self.dragging = false end)
  button:SetScript("OnUpdate", function(_, elapsed)
    if not self.dragging or not GetCursorPosition or not Minimap.GetCenter then return end
    local scale = Minimap:GetEffectiveScale() or 1; local x, y = GetCursorPosition(); local cx, cy = Minimap:GetCenter()
    if cx and cy then
      self.angle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
      local db = self.repository and self.repository.db
      if db and db.settings then db.settings.minimapAngle = self.angle end
      self:Refresh()
    end
  end)
  self.button = button; self.initialized = true; self:Refresh()
  return self
end

function MinimapButton:IsEnabled()
  return enabled(self)
end

function MinimapButton:SetEnabled(value)
  value = value == true
  if type(self.setEnabled) == "function" then
    local ok, result = pcall(self.setEnabled, value)
    if not ok or result == false then return false end
  else
    local db = self.repository and self.repository.db
    if db and db.settings then db.settings.minimapButton = value else return false end
  end
  if value and not self.button then
    -- The button is intentionally not created while disabled. Re-enable it
    -- immediately when the user changes the setting via slash command.
    self.initialized = false
    self:Initialize()
  else
    self:Refresh()
  end
  return true
end

function MinimapButton:ToggleEnabled()
  return self:SetEnabled(not enabled(self))
end

function MinimapButton:Refresh()
  if not self.button then return end
  if not enabled(self) then self.button:Hide(); return end
  self.button:Show()
  local radius = 80; local radians = math.rad(self.angle or 0)
  self.button:ClearAllPoints(); self.button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

return MinimapButton
