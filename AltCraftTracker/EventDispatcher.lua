AltCraftTracker = AltCraftTracker or {}

local ACT = AltCraftTracker
local Dispatcher = {}
Dispatcher.__index = Dispatcher
ACT.EventDispatcher = Dispatcher

function Dispatcher:Create(env)
  local dispatcher = setmetatable({ env = env or _G, handlers = {}, lastEvents = {}, frame = nil }, Dispatcher)
  return dispatcher
end

function Dispatcher:On(event, handler)
  if type(handler) ~= "function" then
    return false
  end
  self.handlers[event] = self.handlers[event] or {}
  self.handlers[event][#self.handlers[event] + 1] = handler
  return true
end

function Dispatcher:Dispatch(event, ...)
  self.lastEvents[event] = ACT.Now()
  local handlers = self.handlers[event]
  if handlers then
    for _, handler in ipairs(handlers) do
      local ok, err = pcall(handler, ...)
      if not ok and ACT.SetError then
        ACT:SetError(err)
      end
    end
  end
end

function Dispatcher:Initialize()
  if self.frame then
    return self
  end
  local createFrame = self.env.CreateFrame
  if type(createFrame) ~= "function" then
    return self
  end
  self.frame = createFrame("Frame", "AltCraftTrackerEventFrame")
  for _, event in ipairs(ACT.EVENTS) do
    if self.frame.RegisterEvent then
      self.frame:RegisterEvent(event)
    end
  end
  if self.frame.SetScript then
    self.frame:SetScript("OnEvent", function(_, event, ...)
      self:Dispatch(event, ...)
    end)
  end
  return self
end
