-- Task 7 integration fixture for Lua 5.1-compatible runtimes.
-- This intentionally uses no WoW frame implementation: it exercises the
-- complete data/event graph and leaves UI construction to the in-client list.

local calls = { bags = 0, bank = 0 }
local messages = {}

function time() return 1000 end
function GetBuildInfo() return "1.15.9", "63830", "fixture", 11509 end
WOW_PROJECT_ID, WOW_PROJECT_CLASSIC_ERA = 2, 2
function UnitFullName() return "Ana", "Test Realm" end
function UnitName() return "Ana", "Test Realm" end
function UnitGUID() return "Player-1-0001" end
function UnitClass() return "Mage", "MAGE", 8 end
function UnitFactionGroup() return "Alliance" end
function UnitLevel() return 42 end
function GetRealmName() return "Test Realm" end

function GetProfessions() return 1, nil, nil, nil, nil, nil end
function GetProfessionInfo() return "Alchemy", 136240, 225, 300, 1, 0, 171 end
function GetTradeSkillLine() return "Alchemy", 225, 300, 1, 0, 171 end
function GetNumTradeSkills() return 1 end
function GetTradeSkillInfo() return "Minor Healing Potion", "optimal", 1, true end
function GetTradeSkillRecipeLink() return "|cffffffff|Htrade:1:0:0:0|h[Minor Healing Potion]|h|r" end
function GetTradeSkillItemLink() return "|cffffffff|Hitem:118:0:0:0|h[Minor Healing Potion]|h|r" end
function GetTradeSkillIcon() return 136240 end
function GetTradeSkillNumMade() return 1, 1 end
function GetTradeSkillReagentInfo() return "Peacebloom", "|cffffffff|Hitem:2447:0:0:0|h[Peacebloom]|h|r", 2, 2 end
function GetTradeSkillReagentItemLink() return "|cffffffff|Hitem:2447:0:0:0|h[Peacebloom]|h|r" end
function GetTradeSkillNumReagents() return 1 end

function GetContainerNumSlots(containerID)
  if containerID == -1 then calls.bank = calls.bank + 1; return 1 end
  calls.bags = calls.bags + 1; return 1
end
function GetContainerItemInfo(containerID)
  if containerID == -1 then return "icon", 2, false, 1, false, false, "|cffffffff|Hitem:2447:0:0:0|h[Peacebloom]|h|r" end
  return "icon", 4, false, 1, false, false, "|cffffffff|Hitem:2447:0:0:0|h[Peacebloom]|h|r"
end
NUM_BAG_SLOTS, NUM_BANKBAGSLOTS = 0, 0
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList = {}

local files = {
  "Constants.lua", "ApiCompat.lua", "ApiCompatInventory.lua", "ApiCompatProfessions.lua",
  "EventDispatcher.lua", "Repository.lua", "CharacterService.lua", "InventoryScanner.lua",
  "ProfessionScanner.lua", "CraftabilityService.lua", "RecipeCatalog.lua", "ViewModels.lua",
  "UI.lua", "MinimapButton.lua", "SlashCommands.lua", "Bootstrap.lua",
}
for _, file in ipairs(files) do local chunk, err = loadfile(file); assert(chunk, err); chunk() end

assert(AltCraftTracker:Initialize())
assert(AltCraftTracker.Api and AltCraftTracker.Repository and AltCraftTracker.Characters)
assert(AltCraftTracker.Professions and AltCraftTracker.Inventory and AltCraftTracker.Catalog)
assert(AltCraftTracker.Repository.db.settings.minimapButton == true)
assert(AltCraftTracker.Repository.db.settings.uiGeometry.width == 610)

AltCraftTracker.Dispatcher:Dispatch("PLAYER_LOGIN")
local firstBagCalls = calls.bags
AltCraftTracker.Dispatcher:Dispatch("PLAYER_ENTERING_WORLD")
assert(calls.bags == firstBagCalls, "login/entering-world duplicated destructive bag scan")
local character = AltCraftTracker.Repository:GetCharacter("classic_era", "Player-1-0001", false)
assert(character and character.level == 42 and character.inventory.bags[2447] == 4)
assert(character.professions["profession:171"].rank == 225)

AltCraftTracker.Dispatcher:Dispatch("BANKFRAME_OPENED")
AltCraftTracker.Dispatcher:Dispatch("BANKFRAME_CLOSED")
assert(character.inventory.bank[2447] == 2 and character.inventory.bankScannedAt == 1000)
AltCraftTracker.Dispatcher:Dispatch("PLAYER_LOGOUT")
assert(character.inventory.bank[2447] == 2, "logout erased last-known bank data")

SlashCmdList.ALTCRAFTTRACKER("minimap off")
assert(AltCraftTracker.Repository.db.settings.minimapButton == false)
SlashCmdList.ALTCRAFTTRACKER("minimap on")
assert(AltCraftTracker.Repository.db.settings.minimapButton == true)
SlashCmdList.ALTCRAFTTRACKER("status")
assert(#messages > 0)

local future = { schemaVersion = 99, settings = { minimapButton = false }, products = {} }
local futureRepo = AltCraftTracker.Repository:Create({})
futureRepo:Initialize(future)
assert(futureRepo:IsReadOnly() and future.schemaVersion == 99, "future schema was downgraded")

local geometryRoot = { schemaVersion = 1, settings = {
  minimapButton = false, minimapAngle = 135,
  uiGeometry = { point = "TOPLEFT", relative = "TOPLEFT", x = 17, y = -23, width = 700, height = 500 },
}, products = {} }
local geometryRepo = AltCraftTracker.Repository:Create({})
geometryRepo:Initialize(geometryRoot)
assert(geometryRepo.db.settings.minimapButton == false and geometryRepo.db.settings.minimapAngle == 135)
assert(geometryRepo.db.settings.uiGeometry.point == "TOPLEFT" and geometryRepo.db.settings.uiGeometry.width == 700)
local reloadedRepo = AltCraftTracker.Repository:Create({})
reloadedRepo:Initialize(geometryRepo.db)
assert(reloadedRepo.db.settings.uiGeometry.height == 500, "UI geometry was lost during normalization/reload")

print("AltCraft Tracker Task 7 integration harness: PASS")
