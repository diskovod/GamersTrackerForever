GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local Commands = {}
Commands.__index = Commands
GTF.Commands = Commands

function Commands:Create(env)
  return setmetatable({ env = env or _G }, Commands)
end

function Commands:Print(message)
  local frame = self.env.DEFAULT_CHAT_FRAME
  if frame and type(frame.AddMessage) == "function" then
    frame:AddMessage("|cff33ff99GamersTrackerForever|r " .. tostring(message))
  end
end

function Commands:Status()
  for _, line in ipairs(GTF:GetStatusLines()) do
    self:Print(line)
  end
end

function Commands:Handle(message)
  local command = tostring(message or ""):lower():match("^%s*(.-)%s*$")
  if command == "" or command == "toggle" or command == "open" then
    if GTF.UI and type(GTF.UI.Toggle) == "function" then GTF.UI:Toggle() end
    return
  end
  if command == "status" then
    self:Status()
    return
  end
  local minimap = command:match("^minimap%s*(.*)$")
  if minimap then
    minimap = minimap:match("^%s*(.-)%s*$")
    local button = GTF.MinimapButton
    if not button or type(button.SetEnabled) ~= "function" then
      self:Print("minimap button is unavailable")
      return
    end
    if minimap == "on" then button:SetEnabled(true)
    elseif minimap == "off" then button:SetEnabled(false)
    elseif minimap == "" or minimap == "toggle" then button:ToggleEnabled()
    else self:Print("usage: /gtf minimap on|off|toggle (alias: /act)"); return end
    self:Print("minimap button " .. (button:IsEnabled() and "enabled" or "disabled"))
    return
  end
  self:Print("usage: /gtf [status|toggle|minimap on|off|toggle] (alias: /act)")
end

function Commands:Initialize()
  self.env.SLASH_GAMERSTRACKERFOREVER1 = "/gtf"
  self.env.SLASH_GAMERSTRACKERFOREVER2 = "/act"
  self.env.SlashCmdList = self.env.SlashCmdList or {}
  self.env.SlashCmdList.GAMERSTRACKERFOREVER = function(message)
    self:Handle(message)
  end
end
