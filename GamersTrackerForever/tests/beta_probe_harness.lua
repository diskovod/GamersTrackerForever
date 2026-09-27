-- Read-only probe fixture.  It verifies the probe can inspect both legacy and
-- C_Container-shaped APIs without opening the bank or retaining item names.
local calls = { bank = 0, item = 0 }

function GetBuildInfo() return "1.60.1", "70001", "fixture", 120001 end
-- Forever beta may reuse the Classic project id; the build-family gate must
-- select the Forever adapter, never the Classic one.
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
GamersTrackerForeverDB = { products = { forever = { characters = {} }, classic_era = {} } }

local files = { "Constants.lua", "ApiCompat.lua", "ApiCompatInventory.lua", "ApiCompatProfessions.lua", "BetaProbe.lua" }
for _, file in ipairs(files) do
  local chunk, err = loadfile(file)
  assert(chunk, err)
  chunk()
end

local api, product = GamersTrackerForever.ApiCompat.Detect(_G)
assert(product == "forever" and api:IsSupported())
local context = api:GetCurrentContext()
assert(context.identity.displayName == "BetaTester-Forever Realm" and context.identity.realm == nil)
assert(context.transferGroup == "forever|unknown|normal|horde", context.transferGroup)
assert(context.key == "Player-99-0001")
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

-- Forever bootstrap constructs the scanner graph in its own partition.
local bootFiles = { "Constants.lua", "ApiCompat.lua", "ApiCompatInventory.lua", "ApiCompatProfessions.lua",
  "BetaProbe.lua", "EventDispatcher.lua", "Repository.lua", "CharacterService.lua", "InventoryScanner.lua",
  "ProfessionScanner.lua", "CraftabilityService.lua", "RecipeCatalog.lua", "ViewModels.lua", "SlashCommands.lua",
  "Bootstrap.lua" }
local function boot()
  GamersTrackerForever = nil
  for _, file in ipairs(bootFiles) do
    local chunk, err = loadfile(file)
    assert(chunk, err)
    chunk()
  end
  assert(GamersTrackerForever:Initialize())
  return GamersTrackerForever
end
local GTF = boot()
assert(GTF.product == "forever")
assert(not GTF.Repository:IsReadOnly())
assert(GTF.Characters ~= nil and GTF.Professions ~= nil)
assert(GTF.Repository:GetCharacter("forever", "must-save", true) ~= nil)

-- Unknown client families still fail closed: no scanners, read-only partition.
function GetBuildInfo() return "2.5.4", "70001", "fixture", 20504 end
WOW_PROJECT_ID = 5
GamersTrackerForeverDB = { products = { ["unsupported:5"] = { characters = {} } } }
GTF = boot()
assert(GTF.product == "unsupported:5" and not GTF.Api:IsSupported())
assert(GTF.Inventory == nil and GTF.Characters == nil)
assert(GTF.Repository:IsReadOnly())
assert(GTF.Repository:GetCharacter("unsupported:5", "must-not-save", true) == nil)
assert(GTF.Repository:GetProduct("unsupported:5", false).characters["must-not-save"] == nil)
print("GamersTrackerForever beta probe harness: PASS")
