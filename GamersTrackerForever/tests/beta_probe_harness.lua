-- Read-only probe fixture.  It verifies the probe can inspect both legacy and
-- C_Container-shaped APIs without opening the bank or retaining item names.
local calls = { bank = 0, item = 0, modernLine = 0, modernLists = 0, legacyRecipes = 0 }

function GetBuildInfo() return "1.60.1", "69913", "fixture", 16001 end
WOW_PROJECT_ID = 1
WOW_PROJECT_FLAVOR = "test"
function UnitFullName() return "BetaTester", "Forever Realm" end
function UnitGUID() return "Player-99-0001" end
function UnitFactionGroup() return "Horde" end
function UnitLevel() return 60 end
function GetRealmName() return "Forever Realm" end
function GetProfessions() return 4, nil, 8 end
function GetProfessionInfo(index) return index == 4 and "Alchemy" or "Fishing", 1, 100, 300 end
function GetNumSkillLines() return 2 end
function GetSkillLineInfo(index) return index == 1 and "Alchemy" or "Fishing", false, true, 100, 300 end
function GetTradeSkillLine() calls.legacyRecipes = calls.legacyRecipes + 1; return "Alchemy", 100, 300 end
function GetNumTradeSkills() calls.legacyRecipes = calls.legacyRecipes + 1; return 1 end
function GetTradeSkillInfo() calls.legacyRecipes = calls.legacyRecipes + 1; return "Elixir", "optimal", 1, false end
function GetTradeSkillRecipeLink() return "|Htrade:171:0|h[Recipe]|h" end
function GetTradeSkillItemLink() return "|Hitem:42:0|h[Item Name]|h" end
function GetTradeSkillIcon() return 1 end
function GetTradeSkillNumMade() return 1, 1 end
function GetTradeSkillNumReagents() return 1 end
function GetTradeSkillReagentInfo() return "Copper", 1, 2, 0 end
function GetTradeSkillReagentItemLink() return "|Hitem:43:0|h[Copper]|h" end
function IsBagOpen(id) calls.bank = calls.bank + 1; if id == -1 then return false end return nil end
TradeSkillFrame = {
  shown = false,
  IsShown = function(self) return self.shown end,
}
C_TradeSkillUI = {
  IsTradeSkillReady = function() return true end,
  GetTradeSkillLineInfo = function()
    calls.modernLine = calls.modernLine + 1
    return { skillLineID = 171, recipeCount = 2 }
  end,
  GetRecipesForSkillLine = function()
    calls.modernLists = calls.modernLists + 1
    return { 9001, 9002 }
  end,
  GetFilteredRecipeIDs = function()
    calls.modernLists = calls.modernLists + 1
    return { 9001 }
  end,
  -- Availability is reported, but the probe must not invoke detail methods:
  -- their return values could contain recipe/item names and reagent data.
  GetRecipeInfo = function() error("detail API must not be called by probe") end,
}
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
GamersTrackerForeverDB = { products = { classic_era = {}, forever_beta = {} } }

local files = { "Constants.lua", "ApiCompat.lua", "ApiCompatInventory.lua", "ApiCompatProfessions.lua", "ApiCompatForever.lua", "BetaProbe.lua" }
for _, file in ipairs(files) do
  local chunk, err = loadfile(file)
  assert(chunk, err)
  chunk()
end

local api, product = GamersTrackerForever.ApiCompat.Detect(_G)
assert(product == "forever_beta")
assert(api:IsSupported())
assert(api:GetProduct() == "forever_beta")
assert(api:GetCurrentContext().key == "Player-99-0001")
assert(api:GetCurrentContext().level == 60)
assert(api:GetCapabilities()[GamersTrackerForever.CAPABILITY.BAG_INVENTORY_SCAN])
assert(api:GetCapabilities()[GamersTrackerForever.CAPABILITY.PROFESSION_ENUMERATION])
assert(not api:GetCapabilities()[GamersTrackerForever.CAPABILITY.LEARNED_RECIPE_SCAN])
local professionInfo = GetProfessionInfo
GetProfessionInfo = function(index)
  if index == 4 then return "Alchemy", 1, nil, nil end
  return professionInfo(index)
end
local incompleteRanks = api:GetProfessionEntries()
assert(incompleteRanks == nil, "missing beta ranks must not become a zero snapshot")
GetProfessionInfo = professionInfo
local probe = GamersTrackerForever.BetaProbe:Create(_G, api)
assert(calls.bank == 0 and calls.item == 0, "probe must be inert until run")
local result = probe:Run()
assert(result.client.interface == 16001 and result.client.flavor == "test")
assert(result.character.guid == "Player-99-0001" and result.character.level == 60)
assert(result.professions.enumeration.slots == 2 and result.professions.enumeration.infoResults == 2)
assert(result.tradeSkills.count == 1 and result.tradeSkills.readableRows == 1)
assert(result.tradeSkills.modern.namespacePresent == true)
assert(result.tradeSkills.modern.window == "closed")
assert(result.tradeSkills.modern.attempted == false and result.tradeSkills.modern.calls == 0)
assert(calls.modernLine == 0 and calls.modernLists == 0, "closed profession window must not enumerate modern recipes")
assert(result.bags.source == "C_Container" and result.bags.itemSlots == 1 and result.bags.itemCount == 7)
assert(result.bank.slotProbePerformed == false and result.bank.accessible == false)
assert(calls.bank == 1 and calls.item > 0)
assert(result.savedVariables.activePartitionPresent == true)
local lines = probe:FormatLines(result)
local output = table.concat(lines, "\n")
assert(not output:match("Copper") and not output:match("Item Name") and not output:match("secret"))

-- Opening the already-existing profession frame enables only the bounded
-- aggregate probes.  No recipe-detail function is called.
TradeSkillFrame.shown = true
local openResult = probe:Run()
assert(openResult.tradeSkills.modern.window == "open")
assert(openResult.tradeSkills.modern.attempted == true)
assert(openResult.tradeSkills.modern.lineInfo.ok == true)
assert(openResult.tradeSkills.modern.lineInfo.firstIsTable == true)
assert(openResult.tradeSkills.modern.recipeLists.getRecipesForSkillLine.firstCount == 2)
assert(openResult.tradeSkills.modern.recipeLists.getFilteredRecipeIDs.firstCount == 1)
assert(calls.modernLine == 1 and calls.modernLists == 2)
local openOutput = table.concat(probe:FormatLines(openResult), "\n")
assert(not openOutput:match("9001") and not openOutput:match("skillLineID"))

-- Bootstrap enables rank-only profession persistence, while recipe services
-- remain disabled. Trade-skill events must never invoke legacy recipe APIs.
for _, file in ipairs({ "EventDispatcher.lua", "SlashCommands.lua", "Repository.lua", "InventoryScanner.lua", "CharacterService.lua", "ProfessionScanner.lua", "ViewModels.lua", "UI.lua", "Bootstrap.lua" }) do
  local chunk, err = loadfile(file)
  assert(chunk, err)
  chunk()
end
assert(GamersTrackerForever:Initialize())
assert(GamersTrackerForever.product == "forever_beta")
assert(GamersTrackerForever.Inventory ~= nil and GamersTrackerForever.Characters ~= nil)
assert(GamersTrackerForever.Professions ~= nil and GamersTrackerForever.Professions.rankOnly)
assert(GamersTrackerForever.Catalog == nil)
assert(not GamersTrackerForever.Repository:IsReadOnly())
assert(GamersTrackerForever.Repository:GetProduct("forever_beta", true) ~= nil)
assert(GamersTrackerForever.Repository:GetCharacter("forever_beta", "must-save", true) ~= nil)
assert(GamersTrackerForever.Repository:GetProduct("classic_era", false).characters["must-save"] == nil)
local bagResult = GamersTrackerForever.Inventory:ScanBags(1234)
assert(bagResult.success and bagResult.bags[42] == 7)
local betaCharacter = GamersTrackerForever.Repository:GetCharacter("forever_beta", "Player-99-0001", false)
assert(betaCharacter and betaCharacter.inventory.bags[42] == 7)
calls.legacyRecipes = 0
GamersTrackerForever.Dispatcher:Dispatch("PLAYER_LOGIN")
betaCharacter = GamersTrackerForever.Repository:GetCharacter("forever_beta", "Player-99-0001", false)
local alchemy = betaCharacter and betaCharacter.professions["profession:alchemy"]
local fishing = betaCharacter and betaCharacter.professions["profession:fishing"]
assert(alchemy and alchemy.name == "Alchemy" and alchemy.rank == 100 and alchemy.maxRank == 300,
  "beta profession rank snapshot must persist")
assert(fishing and fishing.name == "Fishing" and fishing.rank == 100 and fishing.maxRank == 300,
  "sparse profession slots must persist")
GamersTrackerForever.Dispatcher:Dispatch("TRADE_SKILL_SHOW")
GamersTrackerForever.Dispatcher:Dispatch("TRADE_SKILL_UPDATE")
GamersTrackerForever.Dispatcher:Dispatch("TRADE_SKILL_CLOSE")
assert(calls.legacyRecipes == 0, "rank-only beta must never invoke legacy recipe APIs")
assert(api:GetCapabilities()[GamersTrackerForever.CAPABILITY.BANK_INVENTORY_SCAN] == false)
local bankCommits = 0
local commitBankSnapshot = GamersTrackerForever.Repository.CommitBankSnapshot
GamersTrackerForever.Repository.CommitBankSnapshot = function(...)
  bankCommits = bankCommits + 1
  return commitBankSnapshot(...)
end
GamersTrackerForever.Dispatcher:Dispatch("BANKFRAME_OPENED")
assert(GamersTrackerForever.Inventory.bankOpen == false)
assert(GamersTrackerForever.Inventory.pendingBank == false)
assert(bankCommits == 0, "unsupported beta bank event must not commit a bank snapshot")
assert(next(betaCharacter.inventory.bank) == nil, "unsupported beta bank event must not persist bank data")
assert(GamersTrackerForever.Inventory:ScanBank(1234).success == false)
assert(bankCommits == 0, "direct beta bank scan must not commit a bank snapshot")
print("GamersTrackerForever beta probe harness: PASS")
