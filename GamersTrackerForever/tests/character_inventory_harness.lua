-- Lua 5.1 fixture tests for Task 3 character and inventory contracts.
local root = "."
local files = {
  root .. "/Constants.lua",
  root .. "/ApiCompat.lua",
  root .. "/Repository.lua",
  root .. "/ApiCompatInventory.lua",
  root .. "/InventoryScanner.lua",
  root .. "/CharacterService.lua",
}
for _, file in ipairs(files) do
  local chunk, err = loadfile(file)
  assert(chunk, err)
  chunk()
end

local clock = 1000
local bankOpen = false
local namespaced = {
  [0] = { [1] = { itemID = 100, stackCount = 4 }, [2] = { itemID = 200, stackCount = 2 } },
  [1] = { [1] = { itemID = 100, stackCount = 6 } },
  [-1] = { [1] = { itemID = 300, stackCount = 9 } },
  [5] = {}, [6] = {}, [7] = {}, [8] = {}, [9] = {}, [10] = {}, [11] = {},
}
local env = {
  WOW_PROJECT_ID = 2,
  WOW_PROJECT_CLASSIC_ERA = 2,
  NUM_BAG_SLOTS = 1,
  NUM_BANKBAGSLOTS = 7,
  C_Container = {},
  C_Timer = {},
}
function env.GetBuildInfo() return "1.15.9", "63830", "test", 11509 end
function env.UnitFullName() return "Ana", "Realm A" end
function env.UnitGUID() return "Player-1-0001" end
function env.UnitClass() return "Warrior", "WARRIOR", 1 end
function env.UnitFactionGroup() return "Alliance" end
function env.UnitLevel() return 42 end
function env.GetRealmName() return "Realm A" end
function env.IsBagOpen(id) return id == -1 and bankOpen end
function env.C_Container.GetContainerNumSlots(id)
  local bag = namespaced[id] or {}
  local max = 0
  for slot in pairs(bag) do if slot > max then max = slot end end
  return max
end
function env.C_Container.GetContainerItemInfo(id, slot) return (namespaced[id] or {})[slot] end
local timerQueue = {}
function env.C_Timer.After(_, callback) timerQueue[#timerQueue + 1] = callback end

local api = GamersTrackerForever.ApiCompat.CreateClassic(env)
local repository = GamersTrackerForever.Repository:Create({})
repository:Initialize(nil, api)
local scanner = GamersTrackerForever.InventoryScanner:Create(env, api, repository, { clock = function() return clock end })

local service = GamersTrackerForever.CharacterService:Create(env, api, repository, scanner, { clock = function() return clock end })
local login = service:OnLogin()
assert(login.success and login.context.level == 42)
local character = repository:GetCharacter("classic_era", "Player-1-0001")
assert(character and character.level == 42 and character.lastSeenAt == 1000)
assert(character.inventory.bags[100] == 10 and character.inventory.bags[200] == 2)

bankOpen = true
api:SetBankAccessible(true)
local bank = scanner:ScanBank(1001)
assert(bank.success and character.inventory.bank[300] == 9 and character.inventory.bankScannedAt == 1001)
bankOpen = false
api:SetBankAccessible(false)
local inaccessible = scanner:ScanBank(1002)
assert(not inaccessible.success and inaccessible.accessible == false)
assert(character.inventory.bank[300] == 9 and character.inventory.bankScannedAt == 1001)

-- Two noisy bag events collapse into one scheduled scan.
scanner:HandleEvent("BAG_UPDATE")
scanner:HandleEvent("BAG_UPDATE_DELAYED")
assert(scanner.pendingBags == true and #timerQueue == 1)
namespaced[0][1].stackCount = 7
for _, callback in ipairs(timerQueue) do callback() end
timerQueue = {}
assert(character.inventory.bags[100] == 13)

-- Level-up stores the event's new level, rather than rereading a stale UnitLevel.
local level = service:HandleEvent("PLAYER_LEVEL_UP", 43)
assert(level.success and character.level == 43)

-- A reconciliation has a stable public interface and refreshes last-seen/bags.
clock = 1600
local reconcile = service:Reconcile()
assert(reconcile.success and character.level == 42) -- fixture UnitLevel remains 42
assert(character.lastSeenAt == 1600 and character.inventory.bagsScannedAt == 1600)

-- Closing an accessible bank may refresh it, but closing never erases it.
bankOpen = true
api:SetBankAccessible(true)
service:HandleEvent("BANKFRAME_OPENED")
scanner:FlushPending(1700)
bankOpen = false
service:HandleEvent("BANKFRAME_CLOSED")
assert(character.inventory.bank[300] == 9)

-- Legacy API normalization uses GetContainerItemID/link when no C_Container exists.
local legacyEnv = {
  NUM_BAG_SLOTS = 0,
  NUM_BANKBAGSLOTS = 0,
  GetContainerNumSlots = function(id) return id == 0 and 1 or 0 end,
  GetContainerItemInfo = function(id, slot)
    if id == 0 and slot == 1 then return "icon", 5, false, 1, false, false, "|cff|Hitem:400:0|h[Legacy]|h|r" end
  end,
  GetContainerItemID = function(id, slot) if id == 0 and slot == 1 then return 400 end end,
}
local legacyApi = GamersTrackerForever.ApiCompat.CreateClassic(legacyEnv)
local legacyScanner = GamersTrackerForever.InventoryScanner:Create(legacyEnv, legacyApi, nil)
local legacyTotals = legacyScanner:ScanContainers({ 0 })
assert(legacyTotals[400] == 5)

-- SoD can report zero container slots briefly while the character enters the
-- world. That is an unavailable snapshot, not proof that every bag is empty.
-- A failed early scan must preserve the last valid inventory for the retry.
local lateReady = false
local lateEnv = {
  NUM_BAG_SLOTS = 4,
  C_Timer = {},
  C_Container = {
    GetContainerNumSlots = function(id) return lateReady and (id == 0 and 1 or 0) or 0 end,
    GetContainerItemInfo = function(id, slot) return lateReady and id == 0 and slot == 1 and { itemID = 6948, stackCount = 2 } or nil end,
  },
}
local lateTimerQueue = {}
function lateEnv.C_Timer.After(_, callback) lateTimerQueue[#lateTimerQueue + 1] = callback end
local lateApi = GamersTrackerForever.ApiCompat.CreateClassic(lateEnv)
local lateRepository = GamersTrackerForever.Repository:Create({})
lateRepository:Initialize(nil, lateApi)
lateRepository:UpsertCharacter("classic_era", "late-player", {
  tracked = true,
  inventory = { bags = { [6948] = 1 }, bagsScannedAt = 900 },
})
local lateScanner = GamersTrackerForever.InventoryScanner:Create(lateEnv, lateApi, lateRepository, {
  productKey = "classic_era", characterKey = "late-player", clock = function() return 1000 end,
})
local lateResult = lateScanner:OnLogin()
assert(lateResult.success == false, "zero readable bag slots must not be committed as an empty inventory")
local lateCharacter = lateRepository:GetCharacter("classic_era", "late-player")
assert(lateCharacter.inventory.bags[6948] == 1 and lateCharacter.inventory.bagsScannedAt == 900,
  "an unavailable early bag scan must preserve the previous snapshot")
assert(#lateTimerQueue == 1, "early login should schedule one bounded retry")
-- PLAYER_LOGIN and PLAYER_ENTERING_WORLD can both fire before that callback.
-- The second event must invalidate the first timer and arm a fresh retry;
-- executing the stale callback must not clear the newer timer's state.
local secondLogin = lateScanner:OnLogin()
assert(secondLogin.success == false, "the repeated early login remains unavailable")
assert(#lateTimerQueue == 2, "a repeated login should arm a fresh retry timer")
assert(lateScanner.loginRetryScheduled == true)
lateReady = true
local staleRetry = table.remove(lateTimerQueue, 1); staleRetry()
assert(lateCharacter.inventory.bags[6948] == 1 and lateScanner.loginRetryScheduled == true,
  "a stale retry callback must not clear the active retry state")
local retry = table.remove(lateTimerQueue, 1); retry()
assert(lateCharacter.inventory.bags[6948] == 2 and lateCharacter.inventory.bagsScannedAt == 1000,
  "a later readable scan should commit the recovered bag contents")
assert(lateScanner.loginRetryScheduled == false and lateScanner.loginRetryAttempts == 0)

print("GamersTrackerForever Task 3 character/inventory harness: PASS")
