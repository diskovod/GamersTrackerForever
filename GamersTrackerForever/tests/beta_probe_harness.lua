-- Read-only probe fixture.  It verifies the probe can inspect both legacy and
-- C_Container-shaped APIs without opening the bank or retaining item names.
local calls = { bank = 0, item = 0 }

function GetBuildInfo() return "1.60.1", "70001", "fixture", 120001 end
-- Forever beta may reuse the Classic project id; the build-family gate must
-- still refuse to select the Classic adapter.
WOW_PROJECT_ID = 2
WOW_PROJECT_FOREVER = 2
WOW_PROJECT_CLASSIC_ERA = 2
WOW_PROJECT_FLAVOR = "wow_classic_beta"
function UnitFullName() return "BetaTester", "Forever Realm" end
function UnitGUID() return "Player-99-0001" end
function UnitFactionGroup() return "Horde" end
function UnitLevel() return 60 end
function GetRealmName() return "Forever Realm" end
function GetProfessions() return 4, nil, 8 end
function GetProfessionInfo(index) return index == 4 and "Alchemy" or "Fishing", 1, 100, 300 end
function GetNumSkillLines() return 2 end
function GetSkillLineInfo(index) return index == 1 and "Alchemy" or "Fishing", false, true, 100, 300 end
function GetTradeSkillLine() return "Alchemy", 100, 300 end
function GetNumTradeSkills() return 1 end
function GetTradeSkillInfo() return "Elixir", "optimal", 1, false end
function GetTradeSkillRecipeLink() return "|Htrade:171:0|h[Recipe]|h" end
function GetTradeSkillItemLink() return "|Hitem:42:0|h[Item Name]|h" end
function GetTradeSkillIcon() return 1 end
function GetTradeSkillNumMade() return 1, 1 end
function GetTradeSkillNumReagents() return 1 end
function GetTradeSkillReagentInfo() return "Copper", 1, 2, 0 end
function GetTradeSkillReagentItemLink() return "|Hitem:43:0|h[Copper]|h" end
function IsBagOpen(id) calls.bank = calls.bank + 1; if id == -1 then return false end return nil end
NUM_BAG_SLOTS = 1
NUM_BANKBAGSLOTS = 7
C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and 2 or 1 end,
  GetContainerItemInfo = function(bag, slot)
    calls.item = calls.item + 1
    if bag == 0 and slot == 1 then return { itemID = 42, stackCount = 7, hyperlink = "|Hitem:42|h[secret]|h" } end
    return nil
  end,
}
GamersTrackerForeverDB = { products = { ["unsupported:2"] = { characters = {} }, classic_era = {} } }

local files = { "Constants.lua", "ApiCompat.lua", "ApiCompatInventory.lua", "ApiCompatProfessions.lua", "BetaProbe.lua" }
for _, file in ipairs(files) do
  local chunk, err = loadfile(file)
  assert(chunk, err)
  chunk()
end

local api, product = GamersTrackerForever.ApiCompat.Detect(_G)
assert(product == "unsupported:2")
assert(not api:IsSupported())
local probe = GamersTrackerForever.BetaProbe:Create(_G, api)
assert(calls.bank == 0 and calls.item == 0, "probe must be inert until run")
local result = probe:Run()
assert(result.client.interface == 120001 and result.client.flavor == "wow_classic_beta")
assert(result.client.constants.WOW_PROJECT_FOREVER == 2)
assert(result.character.guid == "Player-99-0001" and result.character.level == 60)
assert(result.professions.enumeration.slots == 2 and result.professions.enumeration.infoResults == 2)
assert(result.tradeSkills.count == 1 and result.tradeSkills.readableRows == 1)
assert(result.bags.source == "C_Container" and result.bags.itemSlots == 1 and result.bags.itemCount == 7)
assert(result.bank.slotProbePerformed == false and result.bank.accessible == false)
assert(calls.bank == 1 and calls.item > 0)
assert(result.savedVariables.activePartitionPresent == true)
local lines = probe:FormatLines(result)
local output = table.concat(lines, "\n")
assert(not output:match("Copper") and not output:match("Item Name") and not output:match("secret"))

-- Bootstrap must fail closed as well as detection: no Classic services are
-- constructed and the unsupported partition cannot be created by a writer.
for _, file in ipairs({ "EventDispatcher.lua", "SlashCommands.lua", "Repository.lua", "Bootstrap.lua" }) do
  local chunk, err = loadfile(file)
  assert(chunk, err)
  chunk()
end
assert(GamersTrackerForever:Initialize())
assert(GamersTrackerForever.product == "unsupported:2")
assert(GamersTrackerForever.Inventory == nil and GamersTrackerForever.Characters == nil)
assert(GamersTrackerForever.Repository:IsReadOnly())
assert(GamersTrackerForever.Repository:GetProduct("unsupported:2", true) ~= nil)
assert(GamersTrackerForever.Repository:GetCharacter("unsupported:2", "must-not-save", true) == nil)
assert(GamersTrackerForever.Repository:GetProduct("unsupported:2", false).characters["must-not-save"] == nil)
print("GamersTrackerForever beta probe harness: PASS")
