-- Read-only runtime compatibility probe for the World of Warcraft Forever
-- beta.  This module intentionally does not select a Forever adapter or make
-- any claim that a beta build is supported.  It is inert until /gtf probe is
-- used and contains no file, network, protected-action, or item-name access.

GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local Probe = {}
Probe.__index = Probe
GTF.BetaProbe = Probe

local function hasFunction(value, name)
  return type(value) == "table" and type(value[name]) == "function"
end

local function invoke(fn, ...)
  if type(fn) ~= "function" then
    return false, {}
  end
  local values = { pcall(fn, ...) }
  local ok = table.remove(values, 1)
  return ok == true, values
end

local function call(env, name, ...)
  return invoke(env and env[name], ...)
end

local function bool(value)
  return value == true
end

local function stringValue(value)
  if value == nil then return "" end
  return tostring(value)
end

local function numberValue(value)
  return tonumber(value)
end

local function present(value)
  return value ~= nil and value ~= ""
end

local function functionMap(env, names, owner)
  local result = {}
  for _, name in ipairs(names) do
    result[name] = owner and hasFunction(owner, name) or hasFunction(env, name)
  end
  return result
end

local function countTrue(map)
  local count = 0
  for _, value in pairs(map or {}) do
    if value then count = count + 1 end
  end
  return count
end

local function sortedKeys(value)
  local result = {}
  if type(value) ~= "table" then return result end
  for key in pairs(value) do
    result[#result + 1] = tostring(key)
  end
  table.sort(result)
  return result
end

function Probe:Create(env, api, repository)
  return setmetatable({ env = env or _G, api = api, repository = repository, lastResult = nil }, Probe)
end

function Probe:Initialize(api, repository)
  if api then self.api = api end
  if repository then self.repository = repository end
  return self
end

function Probe:ReadClient()
  local env = self.env
  local result = {
    getBuildInfo = type(env.GetBuildInfo) == "function",
    version = "",
    build = "",
    date = "",
    interface = 0,
    projectID = env.WOW_PROJECT_ID,
    flavor = env.WOW_PROJECT_FLAVOR or env.WOW_PROJECT_NAME or env.WOW_PROJECT,
  }
  local ok, values = call(env, "GetBuildInfo")
  if ok then
    result.version = stringValue(values[1])
    result.build = stringValue(values[2])
    result.date = stringValue(values[3])
    result.interface = numberValue(values[4]) or 0
  end
  if not present(result.flavor) and type(env.GetCVar) == "function" then
    -- The cvar is only a best-effort flavor hint.  It is never required for
    -- product selection and is not persisted.
    local cvarOK, cvarValues = call(env, "GetCVar", "portal")
    if cvarOK and present(cvarValues[1]) then result.flavor = cvarValues[1] end
  end
  result.flavor = stringValue(result.flavor)
  local constants = {}
  -- Only scalar WOW_PROJECT_* globals are retained.  This gives a useful
  -- view of the product constants without retaining arbitrary client tables.
  for key, value in pairs(env) do
    if type(key) == "string" and key:match("^WOW_PROJECT_")
      and (type(value) == "string" or type(value) == "number" or type(value) == "boolean") then
      constants[key] = value
    end
  end
  result.constants = constants
  result.constantCount = countTrue((function()
    local marker = {}
    for key in pairs(constants) do marker[key] = true end
    return marker
  end)())
  return result
end

function Probe:ReadCharacter()
  local env = self.env
  local result = {
    functions = functionMap(env, { "UnitFullName", "UnitName", "UnitGUID", "GetRealmName", "UnitFactionGroup", "UnitLevel" }),
    displayName = "",
    realm = "",
    guid = "",
    faction = "",
    level = 0,
  }
  local ok, values = call(env, "UnitFullName", "player")
  if not ok then ok, values = call(env, "UnitName", "player") end
  if ok then
    result.displayName = stringValue(values[1])
    result.realm = stringValue(values[2])
  end
  if not present(result.realm) then
    local realmOK, realmValues = call(env, "GetRealmName")
    if realmOK then result.realm = stringValue(realmValues[1]) end
  end
  local guidOK, guidValues = call(env, "UnitGUID", "player")
  if guidOK then result.guid = stringValue(guidValues[1]) end
  local factionOK, factionValues = call(env, "UnitFactionGroup", "player")
  if factionOK then result.faction = stringValue(factionValues[1]) end
  local levelOK, levelValues = call(env, "UnitLevel", "player")
  if levelOK then result.level = numberValue(levelValues[1]) or 0 end
  return result
end

function Probe:ReadProfessions()
  local env = self.env
  local result = {
    functions = functionMap(env, { "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo" }),
    enumeration = { attempted = false, ok = false, slots = 0, infoResults = 0 },
    skillLines = { attempted = false, ok = false, count = 0, readableRows = 0, errors = 0 },
  }

  if result.functions.GetProfessions and result.functions.GetProfessionInfo then
    result.enumeration.attempted = true
    local ok, values = call(env, "GetProfessions")
    if ok then
      result.enumeration.ok = true
      for slot = 1, 6 do
        local index = tonumber(values[slot])
        if index and index > 0 then
          result.enumeration.slots = result.enumeration.slots + 1
          local infoOK, infoValues = call(env, "GetProfessionInfo", index)
          if infoOK and present(infoValues[1]) then
            result.enumeration.infoResults = result.enumeration.infoResults + 1
          end
        end
      end
    end
  end

  if result.functions.GetNumSkillLines and result.functions.GetSkillLineInfo then
    result.skillLines.attempted = true
    local ok, values = call(env, "GetNumSkillLines")
    if ok then
      result.skillLines.ok = true
      result.skillLines.count = math.max(0, tonumber(values[1]) or 0)
      -- A bounded loop avoids hanging a malformed fixture or client while
      -- still proving that the row API returns readable data.
      local limit = math.min(result.skillLines.count, 200)
      for index = 1, limit do
        local rowOK, rowValues = call(env, "GetSkillLineInfo", index)
        if rowOK and present(rowValues[1]) then
          result.skillLines.readableRows = result.skillLines.readableRows + 1
        elseif not rowOK then
          result.skillLines.errors = result.skillLines.errors + 1
        end
      end
    end
  end
  return result
end

function Probe:ReadTradeSkills()
  local env = self.env
  local names = {
    "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo",
    "GetTradeSkillRecipeLink", "GetTradeSkillItemLink", "GetTradeSkillIcon",
    "GetTradeSkillNumMade", "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo",
    "GetTradeSkillReagentItemLink",
  }
  local result = { functions = functionMap(env, names), lineAvailable = false, count = 0, readableRows = 0,
    recipeLinkReadable = false, itemLinkReadable = false }
  local lineOK, lineValues = call(env, "GetTradeSkillLine")
  result.lineAvailable = lineOK and present(lineValues[1]) or false
  local countOK, countValues = call(env, "GetNumTradeSkills")
  if countOK then
    result.count = math.max(0, tonumber(countValues[1]) or 0)
    local limit = math.min(result.count, 200)
    for index = 1, limit do
      local rowOK, rowValues = call(env, "GetTradeSkillInfo", index)
      if rowOK and present(rowValues[1]) then result.readableRows = result.readableRows + 1 end
    end
    if result.count > 0 then
      local recipeOK, recipeValues = call(env, "GetTradeSkillRecipeLink", 1)
      result.recipeLinkReadable = recipeOK and present(recipeValues[1]) or false
      local itemOK, itemValues = call(env, "GetTradeSkillItemLink", 1)
      result.itemLinkReadable = itemOK and present(itemValues[1]) or false
    end
  end
  return result
end

local function readContainerInfo(container, bag, slot)
  local ok, values = invoke(container.GetContainerItemInfo, bag, slot)
  if not ok then return false, false, 0 end
  local info = values[1]
  if type(info) == "table" then
    local quantity = tonumber(info.stackCount or info.count) or 0
    local occupied = present(info.hyperlink or info.link) or present(info.itemID) or quantity > 0
    return true, occupied, occupied and math.max(1, quantity) or 0
  end
  -- Legacy GetContainerItemInfo returns texture, count, ..., link.
  local quantity = tonumber(values[2]) or 0
  local occupied = present(values[1]) or present(values[7]) or quantity > 0
  return true, occupied, occupied and math.max(1, quantity) or 0
end

function Probe:ReadBags()
  local env = self.env
  local container = env.C_Container
  local source
  if type(container) == "table" and hasFunction(container, "GetContainerNumSlots")
    and hasFunction(container, "GetContainerItemInfo") then
    source = "C_Container"
  elseif type(env.GetContainerNumSlots) == "function" and type(env.GetContainerItemInfo) == "function" then
    source = "legacy"
  end
  local result = { available = source ~= nil, source = source or "none", bagCount = 0, containersScanned = 0,
    slotsReported = 0, slotsReadable = 0, itemSlots = 0, itemCount = 0, errors = 0 }
  if not source then return result end
  local bagCount = tonumber(env.NUM_BAG_SLOTS) or 4
  bagCount = math.max(0, math.min(20, bagCount))
  result.bagCount = bagCount + 1
  for bag = 0, bagCount do
    local slotOK, slotValues
    if source == "C_Container" then
      slotOK, slotValues = invoke(container.GetContainerNumSlots, bag)
    else
      slotOK, slotValues = call(env, "GetContainerNumSlots", bag)
    end
    local slots = slotOK and math.max(0, math.min(200, tonumber(slotValues[1]) or 0)) or 0
    if not slotOK then result.errors = result.errors + 1 end
    result.containersScanned = result.containersScanned + 1
    result.slotsReported = result.slotsReported + slots
    for slot = 1, slots do
      local readable, occupied, quantity
      if source == "C_Container" then
        readable, occupied, quantity = readContainerInfo(container, bag, slot)
      else
        local valuesOK, values = call(env, "GetContainerItemInfo", bag, slot)
        readable = valuesOK
        if valuesOK then
          local count = tonumber(values[2]) or 0
          occupied = present(values[1]) or present(values[7]) or count > 0
          quantity = occupied and math.max(1, count) or 0
        else
          occupied, quantity = false, 0
        end
      end
      if readable then
        result.slotsReadable = result.slotsReadable + 1
      else
        result.errors = result.errors + 1
      end
      if occupied then
        result.itemSlots = result.itemSlots + 1
        result.itemCount = result.itemCount + quantity
      end
    end
  end
  return result
end

function Probe:ReadBank()
  local env = self.env
  local container = env.C_Container
  local result = {
    cContainerFunctions = functionMap({}, { "GetContainerNumSlots", "GetContainerItemInfo" }, container),
    legacyFunctions = functionMap(env, { "GetContainerNumSlots", "GetContainerItemInfo" }),
    accessFunction = type(env.IsBagOpen) == "function",
    bankFrameFunction = type(env.BankFrame) == "table" and type(env.BankFrame.IsShown) == "function",
    accessibleKnown = false,
    accessible = nil,
    slotProbePerformed = false,
  }
  if result.accessFunction then
    local ok, values = call(env, "IsBagOpen", -1)
    if ok and type(values[1]) == "boolean" then
      result.accessibleKnown = true
      result.accessible = values[1] == true
    end
  end
  if not result.accessibleKnown and result.bankFrameFunction then
    local ok, values = invoke(env.BankFrame.IsShown, env.BankFrame)
    if ok and type(values[1]) == "boolean" then
      result.accessibleKnown = true
      result.accessible = values[1] == true
    end
  end
  return result
end

function Probe:ReadSavedVariables()
  local root = self.env.GamersTrackerForeverDB
  local products = type(root) == "table" and root.products or nil
  local activeProduct = self.api and type(self.api.GetProduct) == "function" and self.api:GetProduct() or nil
  local keys = sortedKeys(products)
  return {
    rootType = type(root),
    rootPresent = type(root) == "table",
    productsType = type(products),
    partitionCount = #keys,
    partitionKeys = keys,
    activeProduct = stringValue(activeProduct),
    activePartitionPresent = type(products) == "table" and activeProduct ~= nil and type(products[activeProduct]) == "table",
    accountWideDeclaration = true,
    perCharacterDeclaration = false,
  }
end

function Probe:Run()
  local result = {
    at = type(GTF.Now) == "function" and GTF.Now() or 0,
    client = self:ReadClient(),
    character = self:ReadCharacter(),
    professions = self:ReadProfessions(),
    tradeSkills = self:ReadTradeSkills(),
    bags = self:ReadBags(),
    bank = self:ReadBank(),
    savedVariables = self:ReadSavedVariables(),
  }
  self.lastResult = result
  return result
end

local function yesNo(value)
  return value and "yes" or "no"
end

function Probe:FormatLines(result)
  result = result or self.lastResult or self:Run()
  local client, character = result.client, result.character
  local professions, trade, bags, bank, saved = result.professions, result.tradeSkills, result.bags, result.bank, result.savedVariables
  local lines = {
    "compatibility probe (read-only; no support claim)",
    "client version " .. (client.version ~= "" and client.version or "unknown") .. ", build " .. (client.build ~= "" and client.build or "unknown")
      .. ", interface " .. tostring(client.interface) .. ", project " .. tostring(client.projectID or "unknown")
      .. ", flavor " .. (client.flavor ~= "" and client.flavor or "unknown"),
    "character " .. (character.displayName ~= "" and character.displayName or "unknown") .. " @ "
      .. (character.realm ~= "" and character.realm or "unknown") .. ", faction "
      .. (character.faction ~= "" and character.faction or "unknown") .. ", level " .. tostring(character.level)
      .. ", GUID " .. (character.guid ~= "" and "present" or "missing"),
    "professions GetProfessions " .. yesNo(professions.functions.GetProfessions) .. " (" .. tostring(professions.enumeration.infoResults) .. " readable), skill lines "
      .. yesNo(professions.functions.GetNumSkillLines) .. " (" .. tostring(professions.skillLines.readableRows) .. " readable)",
    "trade skills line " .. yesNo(trade.functions.GetTradeSkillLine) .. ", count " .. yesNo(trade.functions.GetNumTradeSkills)
      .. " (" .. tostring(trade.readableRows) .. " readable rows), recipe/item links " .. yesNo(trade.recipeLinkReadable) .. "/" .. yesNo(trade.itemLinkReadable),
    "bags " .. (bags.available and bags.source or "unavailable") .. ": " .. tostring(bags.slotsReadable) .. "/" .. tostring(bags.slotsReported)
      .. " readable slots, " .. tostring(bags.itemSlots) .. " occupied, " .. tostring(bags.itemCount) .. " total items",
    "bank APIs C_Container " .. tostring(countTrue(bank.cContainerFunctions)) .. "/2, legacy " .. tostring(countTrue(bank.legacyFunctions))
      .. "/2; access " .. (bank.accessibleKnown and yesNo(bank.accessible) or "unknown") .. "; data probe skipped",
    "SavedVariables root " .. tostring(saved.rootType) .. ", product partitions " .. tostring(saved.partitionCount)
      .. ", active partition " .. yesNo(saved.activePartitionPresent) .. " (account-wide declaration; no per-character declaration)",
  }
  return lines
end

return Probe
