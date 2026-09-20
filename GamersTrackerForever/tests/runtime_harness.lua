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
  root .. "/BetaProbe.lua",
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

assert(GamersTrackerForever:Initialize())
assert(GamersTrackerForever.product == "classic_era")
assert(GamersTrackerForever.Api:GetCurrentContext().key == "Player-1-0001")
assert(GamersTrackerForever.Api:GetTransferGroup() == "classic_era|test-realm|alliance")
assert(registeredEvents.PLAYER_LOGIN and registeredEvents.PLAYER_LOGOUT)
assert(SlashCmdList.GAMERSTRACKERFOREVER)
assert(SLASH_GAMERSTRACKERFOREVER1 == "/gtf" and SLASH_GAMERSTRACKERFOREVER2 == "/act")
local firstSubscriber, secondSubscriber = false, false
GamersTrackerForever.Dispatcher:On("HARNESS_EVENT", function(value)
  assert(value == "payload")
  error("expected harness failure")
end)
GamersTrackerForever.Dispatcher:On("HARNESS_EVENT", function(value)
  assert(value == "payload")
  secondSubscriber = true
end)
GamersTrackerForever.Dispatcher:On("HARNESS_EVENT", function()
  firstSubscriber = true
end)
GamersTrackerForever.Dispatcher:Dispatch("HARNESS_EVENT", "payload")
assert(firstSubscriber and secondSubscriber)
assert(GamersTrackerForever.Runtime.lastError:match("expected harness failure"))
for _, frame in ipairs(frames) do
  if frame.OnEvent then
    frame.OnEvent(frame, "PLAYER_LOGIN")
  end
end
assert(GamersTrackerForever.Runtime.context.level == 42)
for _, frame in ipairs(frames) do
  if frame.OnEvent then
    frame.OnEvent(frame, "PLAYER_LEVEL_UP", 43)
  end
end
assert(GamersTrackerForever.Runtime.context.level == 43)
GamersTrackerForeverDB = {
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
local trackedCount, recipeCount = GamersTrackerForever:GetDatabaseCounts()
assert(trackedCount == 1 and recipeCount == 1)
SlashCmdList.GAMERSTRACKERFOREVER("status")
assert(#messages > 0)
SlashCmdList.GAMERSTRACKERFOREVER("probe")
assert(GamersTrackerForever.BetaProbe and GamersTrackerForever.BetaProbe.lastResult)
assert(messages[1]:match("version 0.2.0"))
local foundUnsupported = false
for _, message in ipairs(messages) do
  if message:match("unsupported capabilities") then
    foundUnsupported = true
  end
end
assert(foundUnsupported)
print("GamersTrackerForever Task 1 runtime harness: PASS")
