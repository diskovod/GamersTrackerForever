GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local CraftabilityService = {}
CraftabilityService.__index = CraftabilityService
GTF.CraftabilityService = CraftabilityService

-- This module deliberately contains no WoW API calls.  Repository records are
-- plain Lua values, so the calculation functions can be used by both the UI
-- and an out-of-game fixture harness.
local function number(value, fallback)
  value = tonumber(value)
  if value == nil then return fallback end
  return value
end

local function lower(value)
  return tostring(value or ""):lower()
end

local function sortedCharacterKeys(characters)
  local keys = {}
  for key, character in pairs(characters or {}) do
    if type(character) == "table" and character.tracked == true then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function(a, b)
    local ca, cb = characters[a] or {}, characters[b] or {}
    local ia, ib = ca.identity or {}, cb.identity or {}
    local na, nb = lower(ia.displayName), lower(ib.displayName)
    if na ~= nb then return na < nb end
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function settingsFrom(value)
  value = type(value) == "table" and value or {}
  local stale = number(value.staleAfterSeconds, 86400)
  local veryStale = number(value.veryStaleAfterSeconds, 604800)
  if stale < 0 then stale = 0 end
  if veryStale < stale then veryStale = stale end
  return { staleAfterSeconds = stale, veryStaleAfterSeconds = veryStale }
end

local function freshness(scannedAt, now, settings)
  scannedAt = number(scannedAt, 0)
  if scannedAt <= 0 then
    return { known = false, scannedAt = 0, age = nil, state = "never", label = "never scanned" }
  end
  local age = math.max(0, number(now, 0) - scannedAt)
  local state = "current"
  local label = "fresh"
  if age >= settings.veryStaleAfterSeconds then
    state, label = "very_stale", "very stale"
  elseif age >= settings.staleAfterSeconds then
    state, label = "stale", "stale"
  end
  return { known = true, scannedAt = scannedAt, age = age, state = state, label = label }
end

local function location(character, name, now, settings)
  local inventory = type(character) == "table" and character.inventory or nil
  inventory = type(inventory) == "table" and inventory or {}
  local scannedAt = name == "bags" and inventory.bagsScannedAt or inventory.bankScannedAt
  local counts = name == "bags" and inventory.bags or inventory.bank
  local fresh = freshness(scannedAt, now, settings)
  return {
    counts = type(counts) == "table" and counts or {},
    known = fresh.known,
    scannedAt = fresh.scannedAt,
    age = fresh.age,
    freshness = fresh.state,
    freshnessLabel = fresh.label,
  }
end

local function transferCompatible(character, transferGroup)
  -- A missing ecosystem is not evidence of compatibility.  The current
  -- character can still be evaluated in "available now" mode, but pooled
  -- calculations must remain unknown until the adapter supplies a group.
  if transferGroup == nil or transferGroup == "" then return false end
  local identity = type(character) == "table" and character.identity or {}
  return tostring(identity and identity.transferGroup or "") == tostring(transferGroup)
end

local function countFor(locationData, itemID)
  local count = locationData.counts[itemID]
  if count == nil then count = locationData.counts[tostring(itemID)] end
  count = number(count, 0)
  if count < 0 then count = 0 end
  return math.floor(count)
end

local function requirementKind(reagent)
  if type(reagent) ~= "table" then return "unknown" end
  local kind = lower(reagent.kind or "item")
  if kind == "item" or kind == "reagent" then
    local itemID, quantity = number(reagent.itemID, 0), number(reagent.quantity, 0)
    if itemID <= 0 or quantity <= 0 or itemID ~= math.floor(itemID) or quantity ~= math.floor(quantity) then
      return "unknown"
    end
    if reagent.soulbound or reagent.currency or reagent.tool or reagent.locationBound
      or reagent.quality or reagent.substitutable then
      return "special"
    end
    return "item"
  end
  if kind == "special" or kind == "tool" or kind == "currency" or kind == "cooldown"
    or kind == "location" or kind == "quality" or kind == "soulbound" then
    return "special"
  end
  return "unknown"
end

local function hasSpecialRequirements(recipe)
  if type(recipe) ~= "table" then return false end
  local requirements = recipe.specialRequirements or recipe.specialRequirementFlags
  if type(requirements) ~= "table" then
    return requirements ~= nil and requirements ~= false and requirements ~= ""
  end
  for _, value in pairs(requirements) do
    if value ~= nil and value ~= false and value ~= "" and value ~= 0 then return true end
  end
  return false
end

local function normalizeReagents(recipe)
  local result = {}
  local reagents = type(recipe) == "table" and recipe.reagents or nil
  if type(reagents) ~= "table" then return result end
  for index, reagent in ipairs(reagents) do
    local kind = requirementKind(reagent)
    local itemID = number(type(reagent) == "table" and reagent.itemID, 0)
    local quantity = number(type(reagent) == "table" and reagent.quantity, 0)
    result[#result + 1] = {
      index = index,
      itemID = itemID > 0 and math.floor(itemID) or nil,
      quantity = quantity > 0 and math.floor(quantity) or 0,
      kind = kind,
      source = reagent,
    }
  end
  return result
end

local function aggregate(recipe, characters, keys, itemID, required, now, settings, mode, currentKey, transferGroup)
  local rows = {}
  local knownOwned, unknownStorage, staleData = 0, false, false
  local hasEligible = false
  for _, key in ipairs(keys) do
    local character = characters[key]
    local compatible = (mode == "afterTransfer" and transferCompatible(character, transferGroup))
      or (mode == "now" and tostring(key) == tostring(currentKey))
    if compatible then
      hasEligible = true
      local bags = location(character, "bags", now, settings)
      local bank = location(character, "bank", now, settings)
      local bagCount, bankCount = countFor(bags, itemID), countFor(bank, itemID)
      local owned = 0
      -- Available-now is deliberately bags-only: bank data is not immediately
      -- usable, and an unscanned bank must not turn a known bag shortage into
      -- an unknown result. Bank contributes only to the transfer aggregate.
      if bags.known then owned = owned + bagCount else unknownStorage = true end
      if mode == "afterTransfer" then
        if bank.known then owned = owned + bankCount else unknownStorage = true end
      end
      knownOwned = knownOwned + owned
      if bags.known and bags.freshness ~= "current" then staleData = true end
      if mode == "afterTransfer" and bank.known and bank.freshness ~= "current" then staleData = true end
      rows[#rows + 1] = {
        characterKey = key,
        displayName = (character.identity or {}).displayName or tostring(key),
        included = true,
        compatible = mode == "now" or transferCompatible(character, transferGroup),
        bags = bagCount,
        bank = bankCount,
        owned = owned,
        bagsSnapshot = bags,
        bankSnapshot = bank,
        unknown = not bags.known or (mode == "afterTransfer" and not bank.known),
        stale = (bags.known and bags.freshness ~= "current")
          or (mode == "afterTransfer" and bank.known and bank.freshness ~= "current"),
      }
    else
      -- Incompatible tracked characters remain visible in the material matrix,
      -- but their values never enter the transferable aggregate.
      local bags = location(character, "bags", now, settings)
      local bank = location(character, "bank", now, settings)
      rows[#rows + 1] = {
        characterKey = key,
        displayName = (character.identity or {}).displayName or tostring(key),
        included = false,
        compatible = false,
        bags = countFor(bags, itemID),
        bank = countFor(bank, itemID),
        owned = (bags.known and countFor(bags, itemID) or 0) + (bank.known and countFor(bank, itemID) or 0),
        bagsSnapshot = bags,
        bankSnapshot = bank,
        unknown = not bags.known or not bank.known,
        stale = (bags.known and bags.freshness ~= "current") or (bank.known and bank.freshness ~= "current"),
      }
    end
  end
  if not hasEligible then unknownStorage = true end
  local status
  if knownOwned >= required then
    -- Unknown bank data is harmless when already-known bag/bank totals satisfy
    -- the requirement. This is the important "bag satisfies" exception.
    status = staleData and "stale" or "ready"
  elseif unknownStorage then
    status = "unknown"
  else
    status = "short"
  end
  return {
    owned = knownOwned,
    shortage = math.max(required - knownOwned, 0),
    status = status,
    stale = staleData,
    unknown = status == "unknown",
    basedOnStaleData = staleData,
    characters = rows,
  }
end

local function calculate(recipe, characters, options)
  options = type(options) == "table" and options or {}
  recipe = type(recipe) == "table" and recipe or {}
  characters = type(characters) == "table" and characters or {}
  local settings = settingsFrom(options.settings)
  local now = number(options.now, type(GTF.Now) == "function" and GTF.Now() or 0)
  local keys = sortedCharacterKeys(characters)
  local currentKey = options.currentCharacterKey or options.characterKey or options.currentCharacter
  local current = currentKey and (characters[currentKey] or characters[tostring(currentKey)]) or nil
  local transferGroup = options.transferGroup
  if transferGroup == nil and current and type(current.identity) == "table" then
    transferGroup = current.identity.transferGroup
  end
  local compatibleKeys = {}
  for _, key in ipairs(keys) do
    if transferCompatible(characters[key], transferGroup) then compatibleKeys[#compatibleKeys + 1] = key end
  end
  local reagents = normalizeReagents(recipe)
  local result = {
    recipe = recipe,
    currentCharacterKey = currentKey,
    transferGroup = transferGroup,
    settings = settings,
    scannedAt = now,
    characters = keys,
    compatibleCharacters = compatibleKeys,
    reagents = {},
    availableNow = { craftableCount = 0, owned = 0, status = "ready", reagents = {} },
    afterTransfer = { craftableCount = 0, owned = 0, status = "ready", reagents = {} },
    specialRequirements = hasSpecialRequirements(recipe),
    canCraft = false,
  }
  local nowBlocked = false
  local nowStatus, transferStatus = "ready", "ready"
  local nowMin, transferMin
  local nowStale, transferStale = false, false
  local statusPriority = { ready = 1, stale = 2, short = 3, unknown = 4, ["special requirement"] = 5 }
  local function mergeStatus(current, candidate)
    if (statusPriority[candidate] or 0) > (statusPriority[current] or 0) then return candidate end
    return current
  end
  local reagentsComplete = type(recipe.reagents) == "table"
  for _, reagent in ipairs(reagents) do
    local row = {
      index = reagent.index,
      itemID = reagent.itemID,
      quantity = reagent.quantity,
      kind = reagent.kind,
      requirement = reagent.source,
    }
    if reagent.kind ~= "item" then
      row.status = reagent.kind == "special" and "special requirement" or "unknown"
      row.shortage = nil
      row.availableNow = { status = row.status, owned = 0, shortage = nil, stale = false, unknown = true, characters = {} }
      row.afterTransfer = { status = row.status, owned = 0, shortage = nil, stale = false, unknown = true, characters = {} }
      nowBlocked = true
      if row.status == "special requirement" then nowStatus, transferStatus = "special requirement", "special requirement"
      else
        nowStatus = mergeStatus(nowStatus, "unknown")
        transferStatus = mergeStatus(transferStatus, "unknown")
      end
    else
      local availableNow = aggregate(recipe, characters, keys, reagent.itemID, reagent.quantity, now, settings, "now", currentKey, transferGroup)
      local afterTransfer = aggregate(recipe, characters, keys, reagent.itemID, reagent.quantity, now, settings, "afterTransfer", currentKey, transferGroup)
      availableNow.bagCount, availableNow.bankCount = 0, 0
      result.availableNow.owned = availableNow.owned
      result.afterTransfer.owned = afterTransfer.owned
      row.availableNow, row.afterTransfer = availableNow, afterTransfer
      for _, characterRow in ipairs(availableNow.characters) do
        if characterRow.characterKey == currentKey then
          row.bagCount, row.bankCount = characterRow.bags, characterRow.bank
          break
        end
      end
      row.bagCount, row.bankCount = row.bagCount or 0, row.bankCount or 0
      availableNow.bagCount, availableNow.bankCount = row.bagCount, row.bankCount
      row.owned = afterTransfer.owned
      row.pooledOwned = afterTransfer.owned
      row.shortage = afterTransfer.shortage
      row.status = afterTransfer.status
      nowStatus = mergeStatus(nowStatus, availableNow.status)
      transferStatus = mergeStatus(transferStatus, afterTransfer.status)
      nowMin = nowMin and math.min(nowMin, math.floor(availableNow.owned / reagent.quantity)) or math.floor(availableNow.owned / reagent.quantity)
      transferMin = transferMin and math.min(transferMin, math.floor(afterTransfer.owned / reagent.quantity)) or math.floor(afterTransfer.owned / reagent.quantity)
      nowStale = nowStale or availableNow.basedOnStaleData
      transferStale = transferStale or afterTransfer.basedOnStaleData
    end
    result.reagents[#result.reagents + 1] = row
  end
  if not reagentsComplete then
    -- A missing/non-table reagent field is an incomplete recipe snapshot. An
    -- explicitly empty table remains valid and represents a no-material recipe.
    nowStatus, transferStatus = result.specialRequirements and "special requirement" or "unknown",
      result.specialRequirements and "special requirement" or "unknown"
    result.incompleteRecipeData = true
  elseif result.specialRequirements or nowBlocked then
    nowStatus = result.specialRequirements and "special requirement" or nowStatus
    transferStatus = result.specialRequirements and "special requirement" or transferStatus
  end
  result.availableNow.craftableCount = nowMin or 0
  result.afterTransfer.craftableCount = transferMin or 0
  result.availableNow.status = nowStatus
  result.afterTransfer.status = transferStatus
  result.availableNow.reagents = result.reagents
  result.afterTransfer.reagents = result.reagents
  result.availableNow.basedOnStaleData = nowStale
  result.afterTransfer.basedOnStaleData = transferStale
  result.availableNow.canCraft = nowStatus == "ready" or nowStatus == "stale"
  result.afterTransfer.canCraft = transferStatus == "ready" or transferStatus == "stale"
  result.craftableNow = result.availableNow.craftableCount
  result.craftableAfterTransfer = result.afterTransfer.craftableCount
  result.craftableCount = result.afterTransfer.craftableCount
  result.status = transferStatus
  result.canCraft = result.afterTransfer.canCraft and not result.specialRequirements and not result.incompleteRecipeData
  result.basedOnStaleData = nowStale or transferStale
  return result
end

CraftabilityService.CalculatePure = calculate
CraftabilityService.CalculateForCharacters = calculate
CraftabilityService.ClassifyFreshness = freshness
CraftabilityService.GetTrackedCharacterKeys = sortedCharacterKeys

function CraftabilityService:Create(repository, options)
  if type(repository) == "table" and repository.repository and options == nil then
    options = repository
    repository = options.repository
  end
  options = type(options) == "table" and options or {}
  return setmetatable({ repository = repository, productKey = options.productKey, now = options.now, settings = options.settings }, CraftabilityService)
end

function CraftabilityService:SetRepository(repository)
  self.repository = repository
  return self
end

function CraftabilityService:GetSettings(productKey)
  local db = self.repository and self.repository.db
  return (db and db.settings) or self.settings or settingsFrom(nil)
end

function CraftabilityService:Calculate(recipe, characters, options)
  -- Also accept Calculate(productKey, recipeKey, options) for callers that
  -- want repository lookup and calculation in one UI-facing operation.
  if type(recipe) == "string" and self.repository then
    if type(characters) == "string" or type(characters) == "number" then
      return self:CalculateRecipe(recipe, characters, options)
    elseif characters == nil then
      return self:CalculateRecipe(nil, recipe, options)
    end
  end
  -- Instance form accepts a recipe table and character map.  This is the
  -- preferred UI-facing method and remains pure with respect to its inputs.
  options = type(options) == "table" and options or {}
  if options.settings == nil then options.settings = self:GetSettings(options.productKey) end
  if options.now == nil and self.now then options.now = self.now() end
  return calculate(recipe, characters, options)
end

function CraftabilityService:CalculateRecipe(productKey, recipeKey, options)
  if type(recipeKey) == "table" and options == nil then
    options = recipeKey
    recipeKey, productKey = productKey, nil
  end
  options = type(options) == "table" and options or {}
  productKey = productKey or options.productKey or self.productKey
  local repository = self.repository
  local product = repository and type(repository.GetProduct) == "function"
    and repository:GetProduct(productKey, false)
  if not product then return nil, "product not found" end
  local recipe = product.recipes and (product.recipes[recipeKey] or product.recipes[tostring(recipeKey)])
  if not recipe then return nil, "recipe not found" end
  local characters = product.characters or {}
  options.productKey = productKey
  options.settings = options.settings or self:GetSettings(productKey)
  if options.now == nil and self.now then options.now = self.now() end
  local result = calculate(recipe, characters, options)
  result.recipeKey = recipeKey
  return result
end

return CraftabilityService
