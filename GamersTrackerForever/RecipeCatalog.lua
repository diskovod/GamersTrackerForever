GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local RecipeCatalog = {}
RecipeCatalog.__index = RecipeCatalog
GTF.RecipeCatalog = RecipeCatalog

local function lower(value)
  return tostring(value or ""):lower()
end

local function number(value, fallback)
  value = tonumber(value)
  return value == nil and fallback or value
end

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
  return result
end

local function sortedKeys(map)
  local keys = {}
  for key in pairs(map or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function characterSort(characters, a, b)
  local ca, cb = characters[a] or {}, characters[b] or {}
  local ia, ib = ca.identity or {}, cb.identity or {}
  local na, nb = lower(ia.displayName), lower(ib.displayName)
  if na ~= nb then return na < nb end
  return tostring(a) < tostring(b)
end

local function recipeIdentity(key, recipe)
  local recipeID = number(recipe and recipe.recipeID, 0)
  if recipeID > 0 then return "recipe:" .. tostring(math.floor(recipeID)) end
  local outputID = number(recipe and recipe.outputItemID, 0)
  if outputID > 0 then return "item:" .. tostring(math.floor(outputID)) end
  return "key:" .. tostring(key)
end

local function betterDefinition(a, b)
  if not a then return b end
  if not b then return a end
  local function score(recipe)
    local value = 0
    if lower(recipe.name) ~= "" then value = value + 8 end
    if number(recipe.recipeID, 0) > 0 then value = value + 4 end
    if number(recipe.outputItemID, 0) > 0 then value = value + 2 end
    if type(recipe.reagents) == "table" then value = value + 1 end
    return value
  end
  local sa, sb = score(a.recipe), score(b.recipe)
  if sa ~= sb then return sa > sb and a or b end
  return tostring(a.key) < tostring(b.key) and a or b
end

local function matchesText(row, search)
  if search == nil or tostring(search) == "" then return true end
  search = lower(search)
  local recipe = row.recipe or {}
  return lower(recipe.name):find(search, 1, true) ~= nil
    or lower(recipe.outputName):find(search, 1, true) ~= nil
    or lower(recipe.outputItemLink):find(search, 1, true) ~= nil
end

local function professionMatches(recipe, value)
  if value == nil or value == "" then return true end
  local wanted = lower(value)
  if type(value) == "number" or tonumber(value) then
    return number(recipe.professionID, 0) == tonumber(value)
  end
  return lower(recipe.professionName or recipe.profession):find(wanted, 1, true) ~= nil
end

local function professionDisplayName(product, recipe, knownBy)
  if recipe.professionName or recipe.profession then return recipe.professionName or recipe.profession end
  local professionID = number(recipe.professionID, 0)
  for _, characterKey in ipairs(knownBy or {}) do
    local character = product and product.characters and product.characters[characterKey]
    for _, profession in pairs((character and character.professions) or {}) do
      if type(profession) == "table" and number(profession.professionID, 0) == professionID then
        return profession.name or ""
      end
    end
  end
  return ""
end

local function statusRank(status)
  return ({ ready = 1, stale = 2, short = 3, unknown = 4, ["special requirement"] = 5 })[status] or 9
end

function RecipeCatalog:Create(repository, options)
  if type(repository) == "table" and repository.repository and options == nil then
    options = repository
    repository = options.repository
  end
  options = type(options) == "table" and options or {}
  return setmetatable({
    repository = repository,
    productKey = options.productKey,
    craftabilityService = options.craftabilityService,
  }, RecipeCatalog)
end

function RecipeCatalog:SetRepository(repository)
  self.repository = repository
  return self
end

function RecipeCatalog:SetCraftabilityService(service)
  self.craftabilityService = service
  return self
end

function RecipeCatalog:GetProduct(productKey)
  productKey = productKey or self.productKey
  if not productKey then return nil end
  if self.repository and type(self.repository.GetProduct) == "function" then
    return self.repository:GetProduct(productKey, false)
  end
  local db = self.repository and self.repository.db
  return db and db.products and db.products[productKey]
end

function RecipeCatalog:_deduplicated(productKey)
  local product = self:GetProduct(productKey)
  local groups, recipes = {}, {}
  if not product or type(product.recipes) ~= "table" then return recipes end
  for _, key in ipairs(sortedKeys(product.recipes)) do
    local recipe = product.recipes[key]
    if type(recipe) == "table" then
      local identity = recipeIdentity(key, recipe)
      groups[identity] = groups[identity] or {}
      groups[identity][#groups[identity] + 1] = { key = key, recipe = recipe }
    end
  end
  for identity, entries in pairs(groups) do
    local chosen
    for _, entry in ipairs(entries) do chosen = betterDefinition(chosen, entry) end
    local aliases = {}
    for _, entry in ipairs(entries) do aliases[#aliases + 1] = entry.key end
    table.sort(aliases, function(a, b) return tostring(a) < tostring(b) end)
    recipes[#recipes + 1] = {
      key = chosen.key,
      identity = identity,
      recipe = chosen.recipe,
      aliases = aliases,
    }
  end
  table.sort(recipes, function(a, b)
    local na, nb = lower(a.recipe.name), lower(b.recipe.name)
    if na ~= nb then return na < nb end
    return tostring(a.key) < tostring(b.key)
  end)
  return recipes
end

function RecipeCatalog:GetKnownByCharacters(productKey, recipeKey, options)
  options = type(options) == "table" and options or {}
  if self.productKey and self:GetProduct(productKey) == nil then
    options = type(recipeKey) == "table" and recipeKey or options
    recipeKey, productKey = productKey, self.productKey
  end
  local product = self:GetProduct(productKey)
  if not product or type(product.characters) ~= "table" then return {} end
  local wanted = tostring(recipeKey)
  local aliases = { [wanted] = true }
  for _, group in ipairs(self:_deduplicated(productKey)) do
    for _, alias in ipairs(group.aliases) do
      if tostring(alias) == wanted or tostring(group.key) == wanted then
        for _, alias2 in ipairs(group.aliases) do aliases[tostring(alias2)] = true end
        break
      end
    end
  end
  local result = {}
  for key, character in pairs(product.characters) do
    if type(character) == "table" and (options.includeUntracked == true or character.tracked == true) then
      local known = false
      for _, profession in pairs(character.professions or {}) do
        local learned = type(profession) == "table" and profession.learnedRecipes or nil
        if type(learned) == "table" then
          for learnedKey, value in pairs(learned) do
            if value == true and aliases[tostring(learnedKey)] then known = true break end
          end
        end
        if known then break end
      end
      if known then result[#result + 1] = key end
    end
  end
  table.sort(result, function(a, b) return characterSort(product.characters, a, b) end)
  return result
end

RecipeCatalog.GetKnownCharacters = RecipeCatalog.GetKnownByCharacters
RecipeCatalog.GetKnownBy = RecipeCatalog.GetKnownByCharacters

function RecipeCatalog:GetRecipe(productKey, recipeKey)
  if self.productKey and self:GetProduct(productKey) == nil then
    recipeKey, productKey = productKey, self.productKey
  end
  for _, group in ipairs(self:_deduplicated(productKey or self.productKey)) do
    if tostring(group.key) == tostring(recipeKey) then return group.recipe, group end
    for _, alias in ipairs(group.aliases) do
      if tostring(alias) == tostring(recipeKey) then return group.recipe, group end
    end
  end
  return nil
end

RecipeCatalog.GetDefinition = RecipeCatalog.GetRecipe

local function containsCharacter(list, wanted)
  if wanted == nil or wanted == "" then return true end
  if type(wanted) == "table" then
    for _, key in ipairs(list) do if wanted[key] or wanted[tostring(key)] then return true end end
    return false
  end
  for _, key in ipairs(list) do if tostring(key) == tostring(wanted) then return true end end
  return false
end

function RecipeCatalog:ListRecipes(query, filters)
  if type(query) ~= "table" then
    local productKey = query
    query = type(filters) == "table" and filters or {}
    query.productKey = productKey or query.productKey or self.productKey
  else
    query = query
  end
  local productKey = query.productKey or self.productKey
  local product = self:GetProduct(productKey)
  if not product then return {} end
  local allCharacters = product.characters or {}
  local rows = {}
  for _, group in ipairs(self:_deduplicated(productKey)) do
    local knownBy = self:GetKnownByCharacters(productKey, group.key, { includeUntracked = query.includeUntracked == true })
    if #knownBy > 0 then
      local recipe = copy(group.recipe)
      local row = {
        key = group.key,
        recipeKey = group.key,
        identity = group.identity,
        recipe = recipe,
        name = recipe.name or "",
        professionID = number(recipe.professionID, 0),
        professionName = recipe.professionName or recipe.profession or "",
        knownBy = knownBy,
        knownCount = #knownBy,
        aliases = copy(group.aliases),
      }
      row.professionName = professionDisplayName(product, recipe, knownBy)
      if matchesText(row, query.search or query.text) and professionMatches(row, query.profession or query.professionID)
        and containsCharacter(knownBy, query.knownBy or query.characterKey or query.knownByCharacter) then
        local transferGroup = query.transferGroup
        if transferGroup ~= nil then
          local compatibleKnown = {}
          for _, characterKey in ipairs(knownBy) do
            local character = allCharacters[characterKey]
            if character and tostring((character.identity or {}).transferGroup or "") == tostring(transferGroup) then
              compatibleKnown[#compatibleKnown + 1] = characterKey
            end
          end
          row.transferKnownBy, row.transferReady = compatibleKnown, #compatibleKnown > 0
          if query.transferEcosystem == true or query.transferOnly == true or query.transferReadyOnly == true then
            if #compatibleKnown == 0 then row = nil end
          end
        else
          row.transferKnownBy, row.transferReady = copy(knownBy), #knownBy > 0
        end
        if row and self.craftabilityService and (query.craftability or query.shortageFilter
          or query.craftableOnly or query.shortageOnly or query.calculate) then
          local calcOptions = copy(query)
          calcOptions.currentCharacterKey = calcOptions.currentCharacterKey or query.characterKey or query.currentCharacter
          local calculation = self.craftabilityService:Calculate(recipe, allCharacters, calcOptions)
          local availability = lower(query.availability or query.scope or query.mode or "afterTransfer")
          local summary = (availability == "now" or availability == "available-now")
            and calculation.availableNow or calculation.afterTransfer
          row.craftability, row.status = calculation, summary.status
          local filter = lower(query.craftability or query.shortageFilter
            or (query.craftableOnly and "craftable") or (query.shortageOnly and "short") or "")
          if filter == "craftable" or filter == "ready" then
            if summary.status ~= "ready" and summary.status ~= "stale" then row = nil end
          elseif filter ~= "" and filter ~= "all" and summary.status ~= filter then
            row = nil
          end
        end
        if row then rows[#rows + 1] = row end
      end
    end
  end
  local sortBy = lower(query.sortBy or "name")
  table.sort(rows, function(a, b)
    if sortBy == "profession" then
      local pa, pb = lower(a.professionName), lower(b.professionName)
      if pa ~= pb then return pa < pb end
    elseif sortBy == "craftability" or sortBy == "status" then
      local sa, sb = statusRank(a.status), statusRank(b.status)
      if sa ~= sb then return sa < sb end
    end
    local na, nb = lower(a.name), lower(b.name)
    if na ~= nb then return na < nb end
    local pa, pb = lower(a.professionName), lower(b.professionName)
    if pa ~= pb then return pa < pb end
    local ra, rb = number(a.recipe.recipeID, 0), number(b.recipe.recipeID, 0)
    if ra ~= rb then return ra < rb end
    return tostring(a.key) < tostring(b.key)
  end)
  if query.sortDescending then
    local reversed = {}
    for i = #rows, 1, -1 do reversed[#reversed + 1] = rows[i] end
    rows = reversed
  end
  return rows
end

RecipeCatalog.Query = RecipeCatalog.ListRecipes
RecipeCatalog.GetRecipes = RecipeCatalog.ListRecipes
RecipeCatalog.QueryRecipes = RecipeCatalog.ListRecipes

function RecipeCatalog:List(productKey, query)
  if type(productKey) == "table" and query == nil then return self:ListRecipes(productKey) end
  query = type(query) == "table" and query or {}
  query.productKey = productKey or query.productKey or self.productKey
  return self:ListRecipes(query)
end

RecipeCatalog.Query = function(self, productKey, query)
  return self:List(productKey, query)
end

return RecipeCatalog
