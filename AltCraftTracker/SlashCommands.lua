AltCraftTracker = AltCraftTracker or {}

local ACT = AltCraftTracker
local Commands = {}
Commands.__index = Commands
ACT.Commands = Commands

function Commands:Create(env)
  return setmetatable({ env = env or _G }, Commands)
end

function Commands:Print(message)
  local frame = self.env.DEFAULT_CHAT_FRAME
  if frame and type(frame.AddMessage) == "function" then
    frame:AddMessage("|cff33ff99AltCraft Tracker|r " .. tostring(message))
  end
end

function Commands:Status()
  for _, line in ipairs(ACT:GetStatusLines()) do
    self:Print(line)
  end
end

function Commands:Handle(message)
  local command = tostring(message or ""):lower():match("^%s*(.-)%s*$")
  if command == "" or command == "toggle" or command == "open" then
    if ACT.UI and type(ACT.UI.Toggle) == "function" then ACT.UI:Toggle() end
    return
  end
  if command == "status" then
    self:Status()
    return
  end
  local minimap = command:match("^minimap%s*(.*)$")
  if minimap then
    minimap = minimap:match("^%s*(.-)%s*$")
    local button = ACT.MinimapButton
    if not button or type(button.SetEnabled) ~= "function" then
      self:Print("minimap button is unavailable")
      return
    end
    if minimap == "on" then button:SetEnabled(true)
    elseif minimap == "off" then button:SetEnabled(false)
    elseif minimap == "" or minimap == "toggle" then button:ToggleEnabled()
    else self:Print("usage: /act minimap on|off|toggle"); return end
    self:Print("minimap button " .. (button:IsEnabled() and "enabled" or "disabled"))
    return
  end
  self:Print("usage: /act [status|toggle|minimap on|off|toggle]")
end

function Commands:Initialize()
  self.env.SLASH_ALTCRAFTTRACKER1 = "/act"
  self.env.SlashCmdList = self.env.SlashCmdList or {}
  self.env.SlashCmdList.ALTCRAFTTRACKER = function(message)
    self:Handle(message)
  end
end
