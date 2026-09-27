-- Read-only runtime compatibility probe for the World of Warcraft Forever
-- beta.  This module intentionally does not select a Forever adapter or make
-- any claim that a beta build is supported.  It is inert until /gtf probe is
-- used and contains no file, network, or protected-action access. Recipe
-- detail APIs are summarized without retaining their names or identifiers.

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
  local betaApi = GTF.ApiCompat and GTF.ApiCompat.ForeverBeta
  local isForever = self.api and type(self.api.GetProduct) == "function"
    and self.api:GetProduct() == GTF.PRODUCT_FOREVER_BETA
  if ok and isForever and betaApi and type(betaApi.NormalizeUnitFullName) == "function" then
    result.displayName, result.realm = betaApi.NormalizeUnitFullName(env, values[1], values[2])
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
  result.modern = self:ReadModernTradeSkills()
  return result
end

-- Forever has the profession enumeration API, but not the old global
-- GetTradeSkill* functions.  Keep this diagnostic deliberately conservative:
-- it records namespace/function availability all the time, and calls only
-- bounded list/line methods after an already-open profession frame proves
-- that a profession window is visible.  It never asks for recipe details,
-- links, item names, or reagent data.
local modernTradeFunctions = {
  "IsTradeSkillReady",
  "GetTradeSkillLineInfo",
  "GetTradeSkillLineID",
  "GetTradeSkillDisplayLine",
  "GetTradeSkillListLink",
  "GetRecipesForSkillLine",
  "GetFilteredRecipeIDs",
  "GetAllRecipeIDs",
  "GetRecipeInfo",
  "GetRecipeSchematic",
  "GetRecipeItemLink",
  "GetRecipeLink",
}

local relatedProfessionNamespaces = {
  "C_TradeSkillUI",
  "C_Professions",
  "Professions",
  "ProfessionsUtil",
}

local function namespaceFunctionMap(env, namespace, names)
  local owner = env and env[namespace]
  return {
    present = type(owner) == "table",
    functions = functionMap({}, names, owner),
  }
end

local function boundedTableCount(value, limit)
  if type(value) ~= "table" then return 0 end
  local count = 0
  for _ in pairs(value) do
    count = count + 1
    if count >= limit then return limit end
  end
  return count
end

local function returnShape(ok, values)
  local first = values and values[1]
  return {
    attempted = true,
    ok = ok == true,
    returns = values and #values or 0,
    firstType = type(first),
    firstIsTable = type(first) == "table",
    firstCount = boundedTableCount(first, 200),
  }
end

local function visibleFrame(env, name)
  local frame = env and env[name]
  local frameType = type(frame)
  if (frameType ~= "table" and frameType ~= "userdata") or type(frame.IsShown) ~= "function" then
    return nil
  end
  local ok, values = invoke(frame.IsShown, frame)
  if ok and type(values[1]) == "boolean" then return values[1] end
  return nil
end

local function professionWindowState(env)
  -- Names differ between clients.  A known frame is stronger evidence than
  -- a readiness function because readiness may remain true after closing.
  local inspected = false
  for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame", "C_TradeSkillFrame" }) do
    local shown = visibleFrame(env, name)
    if shown ~= nil then
      inspected = true
      -- Do not let an earlier hidden candidate mask a later visible frame.
      if shown then return "open", true end
    end
  end
  return inspected and "closed" or "unknown", inspected
end

function Probe:ReadModernTradeSkills()
  local env = self.env
  local namespaces = {}
  for _, name in ipairs(relatedProfessionNamespaces) do
    namespaces[name] = namespaceFunctionMap(env, name, modernTradeFunctions)
  end

  local owner = env.C_TradeSkillUI
  local functions = functionMap({}, modernTradeFunctions, owner)
  local window, windowKnown = professionWindowState(env)
  local result = {
    namespacePresent = type(owner) == "table",
    functions = functions,
    functionCount = countTrue(functions),
    functionTotal = #modernTradeFunctions,
    relatedNamespaces = namespaces,
    window = window,
    windowKnown = windowKnown,
    attempted = false,
    calls = 0,
    errors = 0,
    lineInfo = { attempted = false, ok = false, returns = 0, firstType = "nil", firstIsTable = false, firstCount = 0 },
    recipeLists = {
      getRecipesForSkillLine = { attempted = false, ok = false, returns = 0, firstType = "nil", firstIsTable = false, firstCount = 0 },
      getFilteredRecipeIDs = { attempted = false, ok = false, returns = 0, firstType = "nil", firstIsTable = false, firstCount = 0 },
      getAllRecipeIDs = { attempted = false, ok = false, returns = 0, firstType = "nil", firstIsTable = false, firstCount = 0 },
    },
    recipeDetails = {
      attempted = false, candidateCount = 0, sampledRecipeCount = 0, sampleLimit = 3,
      info = { calls = 0, errors = 0, tableResults = 0, learnedKnown = 0, learnedTrue = 0, learnedFalse = 0 },
      schematic = {
        calls = 0, errors = 0, tableResults = 0, reagentSlotsKnown = 0, reagentSlotsAvailable = 0,
        outputItemKnown = 0, quantityRangeKnown = 0, slotsInspected = 0,
        slotQuantityKnown = 0, exactlyOneItemReagent = 0, ambiguousOrMissingReagent = 0,
      },
    },
  }

  -- Function availability is useful with the window closed.  All calls that
  -- could enumerate current profession/recipe data are gated by visibility.
  if not result.namespacePresent or not windowKnown or window ~= "open" then
    return result
  end

  result.attempted = true
  local recipeIDCandidates, allRecipeIDCandidates = nil, nil
  local function inspect(name, target)
    if not functions[name] then return end
    result.calls = result.calls + 1
    local ok, values = invoke(owner[name])
    target.attempted = true
    target.ok = ok == true
    if ok then
      local shape = returnShape(ok, values)
      for key, value in pairs(shape) do target[key] = value end
      if name == "GetFilteredRecipeIDs" and type(values[1]) == "table" then recipeIDCandidates = values[1] end
      if name == "GetAllRecipeIDs" and type(values[1]) == "table" then allRecipeIDCandidates = values[1] end
    else
      result.errors = result.errors + 1
    end
  end

  inspect("GetTradeSkillLineInfo", result.lineInfo)
  inspect("GetRecipesForSkillLine", result.recipeLists.getRecipesForSkillLine)
  inspect("GetFilteredRecipeIDs", result.recipeLists.getFilteredRecipeIDs)
  inspect("GetAllRecipeIDs", result.recipeLists.getAllRecipeIDs)

  -- Inspect at most three IDs returned by the already-probed list APIs.
  -- Only aggregate result shapes are retained; recipe IDs, names, and raw
  -- reagent data never enter the report. This is diagnostic evidence only.
  local details = result.recipeDetails
  local ids = type(recipeIDCandidates) == "table" and next(recipeIDCandidates) ~= nil
    and recipeIDCandidates or allRecipeIDCandidates
  if type(ids) == "table" then
    local candidateCount = 0
    for _ in pairs(ids) do
      candidateCount = candidateCount + 1
      if candidateCount >= 200 then break end
    end
    details.candidateCount = candidateCount
    local sampleLimit = 3
    local idsVisited = 0
    for key, value in pairs(ids) do
      idsVisited = idsVisited + 1
      if idsVisited > 200 then break end
      if details.sampledRecipeCount >= sampleLimit then break end
      local recipeID = type(value) == "number" and value or (value == true and type(key) == "number" and key or nil)
      if type(recipeID) == "number" then
        details.sampledRecipeCount = details.sampledRecipeCount + 1
        if functions.GetRecipeInfo then
          local target = details.info
          target.calls = target.calls + 1
          details.attempted = true
          local infoOK, infoValues = invoke(owner.GetRecipeInfo, recipeID)
          if not infoOK then
            target.errors = target.errors + 1
          elseif type(infoValues[1]) == "table" then
            target.tableResults = target.tableResults + 1
            local learned = infoValues[1].learned
            if type(learned) == "boolean" then
              target.learnedKnown = target.learnedKnown + 1
              if learned then target.learnedTrue = target.learnedTrue + 1
              else target.learnedFalse = target.learnedFalse + 1 end
            end
          end
        end
        if functions.GetRecipeSchematic then
          local target = details.schematic
          target.calls = target.calls + 1
          details.attempted = true
          local schematicOK, schematicValues = invoke(owner.GetRecipeSchematic, recipeID, false)
          if not schematicOK then
            target.errors = target.errors + 1
          elseif type(schematicValues[1]) == "table" then
            target.tableResults = target.tableResults + 1
            local schematic = schematicValues[1]
            if type(schematic.outputItemID) == "number" then target.outputItemKnown = target.outputItemKnown + 1 end
            if type(schematic.quantityMin) == "number" and type(schematic.quantityMax) == "number" then
              target.quantityRangeKnown = target.quantityRangeKnown + 1
            end
            local slots = schematic.reagentSlotSchematics
            if type(slots) == "table" then
              target.reagentSlotsKnown = target.reagentSlotsKnown + 1
              local slotCount = 0
              for _, slot in pairs(slots) do
                slotCount = slotCount + 1
                if slotCount > 100 then break end
                target.slotsInspected = target.slotsInspected + 1
                if type(slot) == "table" then
                  if type(slot.quantityRequired) == "number" then
                    target.slotQuantityKnown = target.slotQuantityKnown + 1
                  end
                  local reagents = slot.reagents
                  local reagentCount, numericItemCount = 0, 0
                  if type(reagents) == "table" then
                    for _, reagent in pairs(reagents) do
                      reagentCount = reagentCount + 1
                      if reagentCount > 100 then break end
                      if type(reagent) == "table" and type(reagent.itemID) == "number" then
                        numericItemCount = numericItemCount + 1
                      end
                    end
                  end
                  if reagentCount == 1 and numericItemCount == 1 then
                    target.exactlyOneItemReagent = target.exactlyOneItemReagent + 1
                  else
                    target.ambiguousOrMissingReagent = target.ambiguousOrMissingReagent + 1
                  end
                else
                  target.ambiguousOrMissingReagent = target.ambiguousOrMissingReagent + 1
                end
              end
              if slotCount > 0 then target.reagentSlotsAvailable = target.reagentSlotsAvailable + 1 end
            end
          end
        end
      end
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
  local modern = trade.modern or {}
  local lists = modern.recipeLists or {}
  local function listShape(name)
    local shape = lists[name] or {}
    return yesNo(shape.ok) .. "/" .. tostring(shape.firstCount or 0)
  end
  local namespaceLine = {}
  for _, name in ipairs(relatedProfessionNamespaces) do
    local namespace = modern.relatedNamespaces and modern.relatedNamespaces[name]
    namespaceLine[#namespaceLine + 1] = name .. " " .. yesNo(namespace and namespace.present)
      .. " " .. tostring(namespace and countTrue(namespace.functions) or 0) .. "/" .. tostring(modern.functionTotal or #modernTradeFunctions)
  end
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
    "modern trade C_TradeSkillUI " .. yesNo(modern.namespacePresent) .. ", functions "
      .. tostring(modern.functionCount or 0) .. "/" .. tostring(modern.functionTotal or #modernTradeFunctions)
      .. ", window " .. tostring(modern.window or "unknown") .. ", probe " .. yesNo(modern.attempted),
    "modern profession namespaces " .. table.concat(namespaceLine, ", "),
    "modern trade line " .. yesNo(modern.lineInfo and modern.lineInfo.ok)
      .. ", recipe lists ok/count GetRecipesForSkillLine " .. listShape("getRecipesForSkillLine")
      .. ", filtered " .. listShape("getFilteredRecipeIDs") .. ", all " .. listShape("getAllRecipeIDs"),
    "recipe detail sampled " .. tostring(modern.recipeDetails and modern.recipeDetails.sampledRecipeCount or 0)
      .. "/" .. tostring(modern.recipeDetails and modern.recipeDetails.sampleLimit or 3)
      .. ", info calls/errors/tables " .. tostring(modern.recipeDetails and modern.recipeDetails.info.calls or 0)
      .. "/" .. tostring(modern.recipeDetails and modern.recipeDetails.info.errors or 0)
      .. "/" .. tostring(modern.recipeDetails and modern.recipeDetails.info.tableResults or 0)
      .. ", learned known/true/false " .. tostring(modern.recipeDetails and modern.recipeDetails.info.learnedKnown or 0)
      .. "/" .. tostring(modern.recipeDetails and modern.recipeDetails.info.learnedTrue or 0)
      .. "/" .. tostring(modern.recipeDetails and modern.recipeDetails.info.learnedFalse or 0)
      .. ", schematic calls/errors/tables " .. tostring(modern.recipeDetails and modern.recipeDetails.schematic.calls or 0)
      .. "/" .. tostring(modern.recipeDetails and modern.recipeDetails.schematic.errors or 0)
      .. "/" .. tostring(modern.recipeDetails and modern.recipeDetails.schematic.tableResults or 0),
    "recipe output/range known " .. tostring(modern.recipeDetails and modern.recipeDetails.schematic.outputItemKnown or 0)
      .. "/" .. tostring(modern.recipeDetails and modern.recipeDetails.schematic.quantityRangeKnown or 0)
      .. ", reagent slots quantity/exact/ambiguous " .. tostring(modern.recipeDetails and modern.recipeDetails.schematic.slotQuantityKnown or 0)
      .. "/" .. tostring(modern.recipeDetails and modern.recipeDetails.schematic.exactlyOneItemReagent or 0)
      .. "/" .. tostring(modern.recipeDetails and modern.recipeDetails.schematic.ambiguousOrMissingReagent or 0),
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
