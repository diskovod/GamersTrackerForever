-- Profession and learned-recipe scanner for Classic Era.
--
-- The scanner only commits complete snapshots.  A malformed row, unavailable
-- trade-skill source, or repository failure therefore leaves the previous
-- learned set and product recipe definitions untouched.

GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local Scanner = {}
Scanner.__index = Scanner
GTF.ProfessionScanner = Scanner

local function number(value, fallback)
  local result = tonumber(value)
  return result == nil and fallback or result
end

local function positive(value)
  value = tonumber(value)
  return value and value > 0 and value == math.floor(value) and value or nil
end

local function cleanName(value)
  value = tostring(value or ""):lower()
  return value:gsub("[^%w]", "")
end

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, child in pairs(value) do
    result[copy(key, seen)] = copy(child, seen)
  end
  return result
end

local function clock(self)
  if type(self.now) == "function" then
    return number(self.now(), 0)
  end
  if type(GTF.Now) == "function" then
    return number(GTF.Now(), 0)
  end
  return os.time()
end

local function contextKeys(self)
  local context = self.contextProvider and self.contextProvider() or nil
  if not context and self.api and type(self.api.GetCurrentContext) == "function" then
    context = self.api:GetCurrentContext()
  end
  context = type(context) == "table" and context or {}
  local client = type(context.client) == "table" and context.client or {}
  return context.productKey or context.product or client.productKey or client.product,
    context.characterKey or context.key,
    context
end

local function professionKey(profession)
  local id = positive(profession and profession.professionID)
  if id then return "profession:" .. tostring(id) end
  return "profession:" .. cleanName(profession and profession.name)
end

local function rowType(row)
  return tostring(row and (row.type or row.rowType) or ""):lower()
end

local function isHeader(row)
  local kind = rowType(row)
  return row and (row.isHeader == true or kind == "header" or kind == "subheader"
    or kind == "category" or kind == "separator") or false
end

local function isNonRecipe(row)
  local kind = rowType(row)
  return kind == "none" or kind == "cooldown" or kind == "enchant" and row and row.isRecipe == false
end

function Scanner:Create(env, api, repository, options)
  -- Permit both Scanner:Create(...) and Scanner.Create({ ... }) forms.
  if self ~= Scanner and type(self) == "table" and self ~= GTF.ProfessionScanner then
    options = repository
    repository = api
    api = env
    env = self
  end
  if type(env) == "table" and env.env and (not api or not api.GetCurrentContext) then
    options = env
    api, repository = options.api, options.repository
    env = options.env
  end
  options = type(options) == "table" and options or {}
  return setmetatable({
    env = env or _G,
    api = api,
    repository = repository,
    now = options.now,
    contextProvider = options.contextProvider,
    onResult = options.onResult,
    schedule = options.schedule,
    debounceSeconds = number(options.debounceSeconds, 0.05),
    dataVersion = options.dataVersion or (GTF.DATA_VERSION or 1),
    initialized = false,
    pendingTradeScan = false,
    tradeScanScheduled = false,
    tradeScanToken = 0,
    lastError = nil,
    lastProfessionScanAt = 0,
  }, Scanner)
end

function Scanner:Initialize(api, repository, options)
  if api then self.api = api end
  if repository then self.repository = repository end
  if type(options) == "table" then
    self.now = options.now or self.now
    self.contextProvider = options.contextProvider or self.contextProvider
    self.onResult = options.onResult or self.onResult
    self.schedule = options.schedule or self.schedule
    self.debounceSeconds = number(options.debounceSeconds, self.debounceSeconds)
    self.dataVersion = options.dataVersion or self.dataVersion
  end
  self.initialized = true
  return true
end

Scanner.New = Scanner.Create

function Scanner:GetProfessionKey(profession)
  return professionKey(profession)
end

function Scanner:GetLastError()
  return self.lastError
end

function Scanner:_setError(message)
  self.lastError = message and tostring(message) or nil
  if self.lastError and type(GTF.SetError) == "function" then
    GTF:SetError(self.lastError)
  end
end

function Scanner:_entries()
  if not self.api or type(self.api.GetProfessionEntries) ~= "function" then
    return nil, "profession enumeration is unavailable"
  end
  local ok, entries = pcall(self.api.GetProfessionEntries, self.api)
  if not ok or type(entries) ~= "table" then
    return nil, "profession enumeration failed"
  end
  return entries
end

function Scanner:MarkStale()
  local productKey, characterKey = contextKeys(self)
  local repository = self.repository
  if not repository or not productKey or not characterKey then
    return false, "character context is unavailable"
  end
  local character = type(repository.GetCharacter) == "function"
    and repository:GetCharacter(productKey, characterKey, false) or nil
  if not character or type(character.professions) ~= "table" then return true end
  for _, profession in pairs(character.professions) do
    if type(profession) == "table" and profession.scanState == "current" then
      profession.scanState = "stale"
    end
  end
  return true
end

function Scanner:MarkUnsupported()
  local productKey, characterKey = contextKeys(self)
  local repository = self.repository
  if not repository or not productKey or not characterKey
    or type(repository.GetCharacter) ~= "function" then
    return false, "character context is unavailable"
  end
  local character = repository:GetCharacter(productKey, characterKey, false)
  if not character or type(character.professions) ~= "table" then return true end
  for _, profession in pairs(character.professions) do
    if type(profession) == "table" then profession.scanState = "unsupported" end
  end
  return true
end

function Scanner:SetDataVersion(version)
  version = version or (GTF.DATA_VERSION or 1)
  if self.dataVersion ~= nil and self.dataVersion ~= version then
    self:MarkStale()
  end
  self.dataVersion = version
  return self.dataVersion
end

Scanner.MarkStaleOnDataVersionChange = Scanner.SetDataVersion

function Scanner:RefreshRanks(scanAt)
  local entries, err = self:_entries()
  if not entries then
    self:MarkUnsupported()
    self:_setError(err)
    return { success = false, complete = false, scanState = "unsupported", error = err, professions = {} }
  end
  scanAt = number(scanAt, clock(self))
  local productKey, characterKey = contextKeys(self)
  local result = { success = true, complete = true, scannedAt = scanAt, professions = {}, updated = 0 }
  local oldProduct, oldCharacter, hadProduct, hadCharacter
  if self.repository and type(self.repository.db) == "table"
    and type(self.repository.db.products) == "table" and productKey then
    local product = self.repository.db.products[productKey]
    hadProduct = product ~= nil
    hadCharacter = hadProduct and characterKey ~= nil and type(product.characters) == "table"
      and product.characters[characterKey] ~= nil or false
    oldProduct = copy(product)
    oldCharacter = hadCharacter and copy(product.characters[characterKey]) or nil
  end
  local function restoreSkillCommits()
    if not self.repository or type(self.repository.db) ~= "table"
      or type(self.repository.db.products) ~= "table" then return end
    if hadProduct then
      self.repository.db.products[productKey] = oldProduct
      if oldProduct and type(oldProduct.characters) == "table" then
        if hadCharacter then oldProduct.characters[characterKey] = oldCharacter
        else oldProduct.characters[characterKey] = nil end
      end
    else
      self.repository.db.products[productKey] = nil
    end
  end
  for _, entry in ipairs(entries) do
    local snapshot = {
      success = true,
      complete = true,
      professionID = positive(entry.professionID) or 0,
      name = tostring(entry.name or ""),
      rank = number(entry.rank, 0),
      maxRank = number(entry.maxRank, 0),
      specializationID = positive(entry.specializationID),
      skillScannedAt = scanAt,
    }
    local key = professionKey(entry)
    result.professions[key] = snapshot
    if self.repository and productKey and characterKey
      and type(self.repository.CommitProfessionSkillSnapshot) == "function" then
      local callOK, ok, committed = pcall(self.repository.CommitProfessionSkillSnapshot, self.repository,
        productKey, characterKey, key, snapshot)
      if not callOK or not ok then
        restoreSkillCommits()
        result.success, result.complete = false, false
        result.error = callOK and (committed or "profession skill commit failed") or tostring(ok)
        self:_setError(result.error)
        return result
      end
      result.updated = result.updated + 1
    end
  end
  -- Enumeration succeeded, so a profession no longer present in the current
  -- skill lines has been abandoned.  This runs only after all new snapshots
  -- commit successfully; failures above preserve the prior profession map.
  if self.repository and productKey and characterKey
    and type(self.repository.GetCharacter) == "function"
    and not (type(self.repository.IsReadOnly) == "function" and self.repository:IsReadOnly()) then
    local character = self.repository:GetCharacter(productKey, characterKey, false)
    if character and type(character.professions) == "table" then
      for key in pairs(character.professions) do
        if result.professions[key] == nil then character.professions[key] = nil end
      end
    end
  end
  self.lastProfessionScanAt = scanAt
  self:_setError(nil)
  return result
end

Scanner.ScanProfessionSkills = Scanner.RefreshRanks
Scanner.ScanProfessions = Scanner.RefreshRanks
Scanner.RefreshProfessionRanks = Scanner.RefreshRanks

function Scanner:_expand(index)
  local env = self.env or (self.api and self.api.env) or _G
  local names = { "ExpandTradeSkillSubClass", "ExpandTradeSkillCategory" }
  for _, name in ipairs(names) do
    if type(env[name]) == "function" then
      local ok = pcall(env[name], index)
      return ok
    end
  end
  return false
end

function Scanner:FlushPendingTradeSkill(scanAt)
  if not self.pendingTradeScan then
    return { success = true, complete = true, pending = false }
  end
  self.pendingTradeScan = false
  self.tradeScanScheduled = false
  self.tradeScanToken = self.tradeScanToken + 1 -- invalidate a queued callback
  local result = self:ScanLoadedProfession(scanAt)
  if type(self.onResult) == "function" then pcall(self.onResult, result) end
  return result
end

function Scanner:_scheduleTradeSkill()
  if self.tradeScanScheduled then return true end
  local schedule = self.schedule
  if not schedule then
    local timer = self.env and self.env.C_Timer
    schedule = timer and timer.After
  end
  if type(schedule) ~= "function" then return false end
  self.tradeScanScheduled = true
  self.tradeScanToken = self.tradeScanToken + 1
  local token = self.tradeScanToken
  local ok = pcall(schedule, self.debounceSeconds, function()
    if self.tradeScanToken ~= token then return end
    self.tradeScanScheduled = false
    self:FlushPendingTradeSkill()
  end)
  if not ok then self.tradeScanScheduled = false return false end
  return true
end

function Scanner:_scanRows(profession, scanAt)
  local api = self.api
  if not api or type(api.GetTradeSkillCount) ~= "function" or type(api.GetTradeSkillInfo) ~= "function" then
    return nil, "learned recipe API is unavailable"
  end
  local countOK, count, err = pcall(api.GetTradeSkillCount, api)
  if not countOK or not count then return nil, err or "trade-skill count unavailable" end
  count = tonumber(count) or 0
  local attempts, expanded = 0, {}
  local rows = {}
  local index = 1
  while index <= count do
    local rowOK, row, rowErr = pcall(api.GetTradeSkillInfo, api, index)
    if not rowOK or not row then return nil, rowErr or "trade-skill row unavailable" end
    if isHeader(row) then
      if row.isExpanded == false or row.isExpanded == nil then
        local expansionKey = tostring(index) .. ":" .. tostring(row.name or "")
        if not expanded[expansionKey] then
          expanded[expansionKey] = true
          if not self:_expand(index) then
            return nil, "trade-skill category is collapsed and cannot be expanded"
          end
          attempts = attempts + 1
          if attempts > 100 then return nil, "trade-skill category expansion limit reached" end
          local countOK, nextCount = pcall(api.GetTradeSkillCount, api)
          count = countOK and (nextCount or count) or count
          index = 1
          rows = {}
        else
          index = index + 1
        end
      else
        index = index + 1
      end
    else
      rows[#rows + 1] = row
      index = index + 1
    end
  end

  local recipes, learned = {}, {}
  for _, row in ipairs(rows) do
    if not isNonRecipe(row) then
      local recipe, recipeErr = self:_normalizeRecipe(profession, row.index, row, scanAt)
      if not recipe then return nil, recipeErr or "recipe row is incomplete" end
      recipes[recipe.key] = recipe.definition
      learned[recipe.key] = true
    end
  end
  return { recipes = recipes, learnedRecipes = learned, rows = rows, complete = true }
end

function Scanner:_normalizeRecipe(profession, index, row, scanAt)
  local api = self.api
  local recipeLink = type(api.GetTradeSkillRecipeLink) == "function" and api:GetTradeSkillRecipeLink(index) or nil
  local outputLink = type(api.GetTradeSkillItemLink) == "function" and api:GetTradeSkillItemLink(index) or nil
  local recipeID = type(api.ParseRecipeID) == "function" and positive(api:ParseRecipeID(recipeLink)) or nil
  local outputItemID = type(api.ParseItemID) == "function" and positive(api:ParseItemID(outputLink)) or nil
  if not recipeID and not outputItemID then
    return nil, "recipe row has neither a recipe ID nor output item ID"
  end
  local key = recipeID and ("recipe:" .. tostring(recipeID)) or ("item:" .. tostring(outputItemID))
  local minimum, maximum = 1, 1
  if type(api.GetTradeSkillNumMade) == "function" then
    minimum, maximum = api:GetTradeSkillNumMade(index)
    if minimum == nil or maximum == nil then return nil, "output quantity is unavailable" end
  end
  local rawReagents, reagentErr = {}, nil
  if type(api.GetTradeSkillReagents) ~= "function" then
    return nil, "reagent API is unavailable"
  end
  rawReagents, reagentErr = api:GetTradeSkillReagents(index)
  if rawReagents == nil then return nil, reagentErr or "reagent data unavailable" end
  local reagentByID = {}
  for _, reagent in ipairs(rawReagents) do
    local quantity = tonumber(reagent.quantity) or 0
    if quantity < 0 then return nil, "reagent quantity is invalid" end
    if quantity > 0 then
      local itemID = positive(reagent.itemID)
      if not itemID then return nil, "reagent item link is unavailable" end
      reagentByID[itemID] = (reagentByID[itemID] or 0) + quantity
    end
  end
  local reagents = {}
  for itemID, quantity in pairs(reagentByID) do
    reagents[#reagents + 1] = { itemID = itemID, quantity = quantity, kind = "item" }
  end
  table.sort(reagents, function(a, b) return a.itemID < b.itemID end)
  local icon = type(api.GetTradeSkillIcon) == "function" and api:GetTradeSkillIcon(index) or 0
  local definition = {
    success = true,
    complete = true,
    recipeID = recipeID or 0,
    professionID = positive(profession.professionID) or 0,
    name = tostring(row.name or ""),
    icon = icon or 0,
    outputItemID = outputItemID or 0,
    outputItemLink = outputLink,
    outputMin = positive(minimum) or 1,
    outputMax = positive(maximum) or positive(minimum) or 1,
    reagents = reagents,
    discoveredBuild = self.api.GetClientInfo and ((self.api:GetClientInfo() or {}).build or "") or "",
    scannedAt = scanAt,
    recipeLink = recipeLink,
    specialRequirements = {},
  }
  return { key = key, definition = definition }
end

local function rollbackRepository(repository, productKey, characterKey, oldProduct, oldCharacter, hadProduct, hadCharacter)
  if not repository or not repository.db or type(repository.db.products) ~= "table" then return end
  if hadProduct then
    repository.db.products[productKey] = oldProduct
  else
    repository.db.products[productKey] = nil
  end
  if hadProduct and oldProduct and type(oldProduct.characters) == "table" then
    if hadCharacter then oldProduct.characters[characterKey] = oldCharacter
    else oldProduct.characters[characterKey] = nil end
  end
end

function Scanner:_commitFull(profession, result, scanAt)
  local repository = self.repository
  local productKey, characterKey = contextKeys(self)
  if not repository or not productKey or not characterKey then
    return true, result
  end
  do
    local originalProduct
    if type(repository.db) == "table" and type(repository.db.products) == "table" then
      originalProduct = repository.db.products[productKey]
    end
    local hadProduct = originalProduct ~= nil
    local originalCharacter = hadProduct and type(originalProduct.characters) == "table"
      and originalProduct.characters[characterKey] or nil
    local hadCharacter = originalCharacter ~= nil
    local oldProduct = copy(originalProduct)
    local oldCharacter = copy(originalCharacter)
    local function fail(message)
      rollbackRepository(repository, productKey, characterKey, oldProduct, oldCharacter, hadProduct, hadCharacter)
      self:_setError(message)
      return false, message
    end
    local skillSnapshot = {
      success = true, complete = true,
      professionID = profession.professionID,
      name = profession.name,
      rank = profession.rank,
      maxRank = profession.maxRank,
      specializationID = profession.specializationID,
      skillScannedAt = scanAt,
    }
    if type(repository.CommitProfessionSkillSnapshot) == "function" then
      local callOK, ok, err = pcall(repository.CommitProfessionSkillSnapshot, repository,
        productKey, characterKey, professionKey(profession), skillSnapshot)
      if not callOK or not ok then return fail(err or "profession skill commit failed") end
    end
    if type(repository.CommitRecipeSnapshot) == "function" then
      for key, recipe in pairs(result.recipes) do
        local callOK, ok, err = pcall(repository.CommitRecipeSnapshot, repository, productKey, key, recipe)
        if not callOK or not ok then return fail(err or "recipe commit failed") end
      end
    end
    if type(repository.CommitLearnedRecipeSet) == "function" then
      local callOK, ok, err = pcall(repository.CommitLearnedRecipeSet, repository,
        productKey, characterKey, professionKey(profession), result.learnedRecipes, scanAt)
      if not callOK or not ok then return fail(err or "learned recipe commit failed") end
    end
  end
  return true, result
end

function Scanner:ScanLoadedProfession(scanAt)
  if not self.api or type(self.api.GetLoadedProfession) ~= "function" then
    local err = "loaded profession API is unavailable"
    self:MarkUnsupported()
    self:_setError(err)
    return { success = false, complete = false, scanState = "unsupported", error = err }
  end
  local loadOK, profession, err = pcall(self.api.GetLoadedProfession, self.api)
  if not loadOK or not profession then
    self:_setError(err)
    return { success = false, complete = false, scanState = "never", error = err }
  end
  scanAt = number(scanAt, clock(self))
  local scanOK, rows, rowErr = pcall(self._scanRows, self, profession, scanAt)
  if not scanOK or not rows then
    self:_setError(rowErr)
    return { success = false, complete = false, scanState = "stale", profession = profession, error = rowErr }
  end
  rows.success, rows.scanState, rows.profession = true, "current", profession
  rows.recipesScannedAt = scanAt
  local commitCallOK, ok, commitResult = pcall(self._commitFull, self, profession, rows, scanAt)
  if not commitCallOK or not ok then
    if commitCallOK then
      commitResult = commitResult or "profession snapshot commit failed"
    else
      commitResult = tostring(ok)
    end
    rows.success, rows.complete, rows.scanState, rows.error = false, false, "stale", commitResult
    return rows
  end
  self.pendingTradeScan = false
  self.lastProfessionScanAt = scanAt
  self:_setError(nil)
  return rows
end

Scanner.ScanTradeSkill = Scanner.ScanLoadedProfession
Scanner.ScanLoaded = Scanner.ScanLoadedProfession
Scanner.ScanLoadedTradeSkill = Scanner.ScanLoadedProfession
Scanner.ScanRecipes = Scanner.ScanLoadedProfession

function Scanner:HandleEvent(event, ...)
  if event == "SKILL_LINES_CHANGED" then
    self:MarkStale()
    return self:RefreshRanks()
  elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
    or event == "PLAYER_LOGOUT" then
    return self:RefreshRanks()
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
    self.pendingTradeScan = true
    return { success = true, complete = false, pending = true, scheduled = self:_scheduleTradeSkill() }
  elseif event == "TRADE_SKILL_CLOSE" then
    local result = self:FlushPendingTradeSkill()
    result.closed = true
    return result
  end
  return nil
end

Scanner.OnEvent = Scanner.HandleEvent
