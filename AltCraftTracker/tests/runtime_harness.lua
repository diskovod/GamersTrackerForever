-- Minimal Lua 5.1/WoW-style smoke harness for Task 1.
-- Run with a Lua 5.1-compatible interpreter from the addon directory.

local messages = {}
local registeredEvents = {}
local frames = {}

function GetBuildInfo()
  return "1.15.9", "63830", "test", 11509
end
WOW_PROJECT_ID = 2
WOW_PROJECT_CLASSIC_ERA = 2
function UnitFullName() return "Ana", "Test Realm" end
function UnitGUID() return "Player-1-0001" end
function UnitClass() return "Warrior", 1 end
function UnitFactionGroup() return "Alliance" end
function UnitLevel() return 42 end
function GetRealmName() return "Test Realm" end
function UnitName() return "Ana", "Test Realm" end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }
SlashCmdList = {}
function CreateFrame()
  local frame = {}
  frames[#frames + 1] = frame
  function frame:RegisterEvent(event) registeredEvents[event] = true end
  function frame:SetScript(kind, callback) frame[kind] = callback end
  return frame
end

local root = "."
local files = {
  root .. "/Constants.lua",
  root .. "/ApiCompat.lua",
  root .. "/EventDispatcher.lua",
  root .. "/SlashCommands.lua",
  root .. "/Repository.lua",
  root .. "/Bootstrap.lua",
}
for _, file in ipairs(files) do
  local chunk, err = loadfile(file)
  assert(chunk, err)
  chunk()
end

assert(AltCraftTracker:Initialize())
assert(AltCraftTracker.product == "classic_era")
assert(AltCraftTracker.Api:GetCurrentContext().key == "Player-1-0001")
assert(AltCraftTracker.Api:GetTransferGroup() == "classic_era|test-realm|alliance")
assert(registeredEvents.PLAYER_LOGIN and registeredEvents.PLAYER_LOGOUT)
assert(SlashCmdList.ALTCRAFTTRACKER)
local firstSubscriber, secondSubscriber = false, false
AltCraftTracker.Dispatcher:On("HARNESS_EVENT", function(value)
  assert(value == "payload")
  error("expected harness failure")
end)
AltCraftTracker.Dispatcher:On("HARNESS_EVENT", function(value)
  assert(value == "payload")
  secondSubscriber = true
end)
AltCraftTracker.Dispatcher:On("HARNESS_EVENT", function()
  firstSubscriber = true
end)
AltCraftTracker.Dispatcher:Dispatch("HARNESS_EVENT", "payload")
assert(firstSubscriber and secondSubscriber)
assert(AltCraftTracker.Runtime.lastError:match("expected harness failure"))
for _, frame in ipairs(frames) do
  if frame.OnEvent then
    frame.OnEvent(frame, "PLAYER_LOGIN")
  end
end
assert(AltCraftTracker.Runtime.context.level == 42)
for _, frame in ipairs(frames) do
  if frame.OnEvent then
    frame.OnEvent(frame, "PLAYER_LEVEL_UP", 43)
  end
end
assert(AltCraftTracker.Runtime.context.level == 43)
AltCraftTrackerDB = {
  products = {
    classic_era = {
      recipes = { copper = {} },
      characters = {
        tracked = { tracked = true },
        untracked = { tracked = false },
        legacy = {},
      },
    },
  },
}
local trackedCount, recipeCount = AltCraftTracker:GetDatabaseCounts()
assert(trackedCount == 1 and recipeCount == 1)
SlashCmdList.ALTCRAFTTRACKER("status")
assert(#messages > 0)
assert(messages[1]:match("version 0.1.0"))
local foundUnsupported = false
for _, message in ipairs(messages) do
  if message:match("unsupported capabilities") then
    foundUnsupported = true
  end
end
assert(foundUnsupported)
print("AltCraft Tracker Task 1 runtime harness: PASS")
