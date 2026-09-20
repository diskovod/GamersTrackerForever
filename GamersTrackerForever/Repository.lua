GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local Repository = {}
Repository.__index = Repository
GTF.Repository = Repository

local function copy(value, seen)
  if type(value) ~= "table" then
    return value
  end
  seen = seen or {}
  if seen[value] then
    return seen[value]
  end
  local result = {}
  seen[value] = result
  for key, child in pairs(value) do
    result[copy(key, seen)] = copy(child, seen)
  end
  return result
end

-- SavedVariables may only contain plain Lua values. Metadata is copied through
-- this restricted path so scanner-provided tables cannot retain functions,
-- userdata, or other client objects in the durable recipe record.
local function safeCopy(value, seen)
  local valueType = type(value)
  if value == nil or valueType == "string" or valueType == "number" or valueType == "boolean" then
    return value
  end
  if valueType ~= "table" then
    return nil
  end
  seen = seen or {}
  if seen[value] then
    return nil
  end
  local result = {}
  seen[value] = result
  for key, child in pairs(value) do
    local safeKey = safeCopy(key, seen)
    local safeChild = safeCopy(child, seen)
    if safeKey ~= nil and type(safeKey) ~= "table" and safeChild ~= nil then
      result[safeKey] = safeChild
    end
  end
  seen[value] = nil
  return result
end

local function numberOr(value, fallback)
  local result = tonumber(value)
  if result == nil then
    return fallback
  end
  return result
end

local function stringOr(value, fallback)
  if value == nil then
    return fallback
  end
  return tostring(value)
end

local function optionalString(value)
  if value == nil or value == "" then
    return nil
  end
  return tostring(value)
end

local function map(value)
  return type(value) == "table" and value or {}
end

local function defaultSettings()
  return {
    staleAfterSeconds = 86400,
    veryStaleAfterSeconds = 604800,
    -- UI preferences are part of the normalized account settings so they
    -- survive a reload without being mistaken for scanner data.
    minimapButton = true,
    minimapAngle = 0,
    maxTrackedCharacters = 3,
    selectedCharacterKey = nil,
    uiGeometry = {
      point = "CENTER",
      relative = "CENTER",
      x = 0,
      y = 0,
      width = 900,
      height = 560,
    },
  }
end

local function defaultRecipe()
  return {
    recipeID = 0,
    professionID = 0,
    name = "",
    icon = 0,
    outputItemID = 0,
    outputMin = 1,
    outputMax = 1,
    reagents = {},
    specialRequirements = {},
    discoveredBuild = "",
  }
end

local function defaultProfession()
  return {
    professionID = 0,
    name = "",
    rank = 0,
    maxRank = 0,
    specializationID = nil,
    learnedRecipes = {},
    skillScannedAt = 0,
    recipesScannedAt = 0,
    scanState = "never",
  }
end

local function defaultInventory()
  return {
    bags = {},
    bank = {},
    bagsScannedAt = 0,
    bankScannedAt = 0,
  }
end

local function defaultCharacter()
  return {
    tracked = true,
    identity = {
      guid = "",
      displayName = "",
      realm = nil,
      region = nil,
      ruleset = nil,
      faction = "",
      classID = 0,
      transferGroup = "",
    },
    client = {
      productID = 0,
      version = "",
      build = "",
      interface = 0,
    },
    level = 0,
    lastSeenAt = 0,
    professions = {},
    inventory = defaultInventory(),
  }
end

local function defaultProduct()
  return {
    dataVersion = 1,
    recipes = {},
    characters = {},
  }
end

function Repository.DefaultDatabase()
  return {
    schemaVersion = 1,
    settings = defaultSettings(),
    products = {},
  }
end

Repository.DefaultSettings = defaultSettings
Repository.DefaultRecipe = defaultRecipe
Repository.DefaultProfession = defaultProfession
Repository.DefaultInventory = defaultInventory
Repository.DefaultCharacter = defaultCharacter
Repository.DefaultProduct = defaultProduct

local function validScanState(value)
  return value == "never" or value == "current" or value == "stale" or value == "unsupported"
end

local function normalizeSettings(value, diagnostics)
  if type(value) ~= "table" then
    if value ~= nil then
      diagnostics.errors[#diagnostics.errors + 1] = "settings recovered"
    end
    return defaultSettings()
  end
  local defaults = defaultSettings()
  local geometry = value.uiGeometry
  if type(geometry) ~= "table" then
    geometry = defaults.uiGeometry
  else
    geometry = {
      point = stringOr(geometry.point, defaults.uiGeometry.point),
      relative = stringOr(geometry.relative, defaults.uiGeometry.relative),
      x = numberOr(geometry.x, defaults.uiGeometry.x),
      y = numberOr(geometry.y, defaults.uiGeometry.y),
      -- The two-pane layout needs room for the recipe filters and a genuinely
      -- larger detail pane.  Clamp legacy 610px saves during normalization so
      -- an old installation cannot reopen with clipped controls.
      width = math.max(760, numberOr(geometry.width, defaults.uiGeometry.width)),
      height = math.max(400, numberOr(geometry.height, defaults.uiGeometry.height)),
    }
  end
  return {
    staleAfterSeconds = numberOr(value.staleAfterSeconds, 86400),
    veryStaleAfterSeconds = numberOr(value.veryStaleAfterSeconds, 604800),
    minimapButton = value.minimapButton ~= false,
    minimapAngle = numberOr(value.minimapAngle, defaults.minimapAngle),
    maxTrackedCharacters = math.max(1, math.min(10, math.floor(numberOr(value.maxTrackedCharacters, defaults.maxTrackedCharacters)))),
    selectedCharacterKey = optionalString(value.selectedCharacterKey),
    uiGeometry = geometry,
  }
end

local function normalizeReagents(value, diagnostics, path)
  if value == nil then
    return {}
  end
  if type(value) ~= "table" then
    diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".reagents"
    return nil
  end
  local result = {}
  for index, reagent in ipairs(value) do
    if type(reagent) == "table" then
      local normalized = {
        itemID = numberOr(reagent.itemID, 0),
        quantity = numberOr(reagent.quantity, 0),
        kind = stringOr(reagent.kind, "item"),
      }
      local booleanFlags = { "soulbound", "currency", "tool", "locationBound", "substitutable" }
      for _, flag in ipairs(booleanFlags) do
        if reagent[flag] ~= nil then
          if type(reagent[flag]) == "boolean" then
            normalized[flag] = reagent[flag]
          else
            diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".reagents[" .. tostring(index) .. "]." .. flag
          end
        end
      end
      if reagent.quality ~= nil then
        local qualityType = type(reagent.quality)
        if qualityType == "string" or qualityType == "number" then
          normalized.quality = reagent.quality
        else
          diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".reagents[" .. tostring(index) .. "].quality"
        end
      end
      if reagent.unknownRequirements ~= nil then
        local unknown = safeCopy(reagent.unknownRequirements)
        if unknown ~= nil then
          normalized.unknownRequirements = unknown
        else
          diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".reagents[" .. tostring(index) .. "].unknownRequirements"
        end
      end
      result[#result + 1] = normalized
    else
      diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".reagents[" .. tostring(index) .. "]"
    end
  end
  return result
end

local function normalizeRecipe(value, diagnostics, path)
  if type(value) ~= "table" then
    diagnostics.quarantined[#diagnostics.quarantined + 1] = path
    return nil
  end
  local reagents = normalizeReagents(value.reagents, diagnostics, path)
  if reagents == nil then
    return nil
  end
  local specialRequirements = {}
  if value.specialRequirements ~= nil then
    if type(value.specialRequirements) ~= "table" then
      diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".specialRequirements"
    else
      specialRequirements = safeCopy(value.specialRequirements) or {}
    end
  end
  local unknownRequirements
  if value.unknownRequirements ~= nil then
    unknownRequirements = safeCopy(value.unknownRequirements)
    if unknownRequirements == nil then
      diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".unknownRequirements"
    end
  end
  return {
    recipeID = numberOr(value.recipeID, 0),
    professionID = numberOr(value.professionID, 0),
    name = stringOr(value.name, ""),
    icon = numberOr(value.icon, 0),
    outputItemID = numberOr(value.outputItemID, 0),
    outputMin = numberOr(value.outputMin, 1),
    outputMax = numberOr(value.outputMax, 1),
    reagents = reagents,
    specialRequirements = specialRequirements,
    unknownRequirements = unknownRequirements,
    discoveredBuild = stringOr(value.discoveredBuild, ""),
  }
end

local function normalizeRecipeMap(value, diagnostics, path)
  if type(value) ~= "table" then
    if value ~= nil then
      diagnostics.errors[#diagnostics.errors + 1] = path .. " recovered"
    end
    return {}
  end
  local result = {}
  for key, recipe in pairs(value) do
    local normalized = normalizeRecipe(recipe, diagnostics, path .. "[" .. tostring(key) .. "]")
    if normalized then
      result[key] = normalized
    end
  end
  return result
end

local function normalizeLearned(value, diagnostics, path)
  if type(value) ~= "table" then
    diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".learnedRecipes"
    return nil
  end
  local result = {}
  for recipeKey, known in pairs(value) do
    if known == true then
      result[recipeKey] = true
    elseif known ~= false and known ~= nil then
      diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".learnedRecipes[" .. tostring(recipeKey) .. "]"
    end
  end
  return result
end

local function normalizeProfession(value, diagnostics, path)
  if type(value) ~= "table" then
    diagnostics.quarantined[#diagnostics.quarantined + 1] = path
    return nil
  end
  local learnedInput = value.learnedRecipes
  if learnedInput == nil then
    learnedInput = {}
  end
  local learned = normalizeLearned(learnedInput, diagnostics, path)
  if learned == nil then
    return nil
  end
  local scanState = validScanState(value.scanState) and value.scanState or "never"
  return {
    professionID = numberOr(value.professionID, 0),
    name = stringOr(value.name, ""),
    rank = numberOr(value.rank, 0),
    maxRank = numberOr(value.maxRank, 0),
    specializationID = value.specializationID == nil and nil or numberOr(value.specializationID, 0),
    learnedRecipes = learned,
    skillScannedAt = numberOr(value.skillScannedAt, 0),
    recipesScannedAt = numberOr(value.recipesScannedAt, 0),
    scanState = scanState,
  }
end

local function normalizeItemMap(value, diagnostics, path)
  if type(value) ~= "table" then
    if value ~= nil then
      diagnostics.quarantined[#diagnostics.quarantined + 1] = path
    end
    return {}
  end
  local result = {}
  for itemID, quantity in pairs(value) do
    local numericID = type(itemID) == "number" and itemID or nil
    local numericQuantity = type(quantity) == "number" and quantity or nil
    local validID = numericID and numericID > 0 and numericID == math.floor(numericID)
    local validQuantity = numericQuantity and numericQuantity >= 0 and numericQuantity == math.floor(numericQuantity)
    if validID and validQuantity then
      if numericQuantity > 0 then
        result[numericID] = numericQuantity
      end
    else
      diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. "[" .. tostring(itemID) .. "]"
    end
  end
  return result
end

local function validSnapshotItemMap(value)
  if type(value) ~= "table" then
    return false
  end
  for itemID, quantity in pairs(value) do
    local numericID = type(itemID) == "number" and itemID or nil
    local numericQuantity = type(quantity) == "number" and quantity or nil
    if numericID == nil or numericID <= 0 or numericID ~= math.floor(numericID)
      or numericQuantity == nil or numericQuantity < 0 or numericQuantity ~= math.floor(numericQuantity) then
      return false
    end
  end
  return true
end

local function normalizeInventory(value, diagnostics, path)
  if type(value) ~= "table" then
    if value ~= nil then
      diagnostics.quarantined[#diagnostics.quarantined + 1] = path
    end
    return defaultInventory()
  end
  return {
    bags = normalizeItemMap(value.bags, diagnostics, path .. ".bags"),
    bank = normalizeItemMap(value.bank, diagnostics, path .. ".bank"),
    bagsScannedAt = numberOr(value.bagsScannedAt, 0),
    bankScannedAt = numberOr(value.bankScannedAt, 0),
  }
end

local function normalizeIdentity(value, diagnostics, path)
  if type(value) ~= "table" then
    if value ~= nil then
      diagnostics.quarantined[#diagnostics.quarantined + 1] = path
    end
    return defaultCharacter().identity
  end
  return {
    guid = stringOr(value.guid, ""),
    displayName = stringOr(value.displayName, ""),
    realm = optionalString(value.realm),
    region = optionalString(value.region),
    ruleset = optionalString(value.ruleset),
    faction = stringOr(value.faction, ""),
    classID = numberOr(value.classID, 0),
    transferGroup = stringOr(value.transferGroup, ""),
  }
end

local function normalizeClient(value, diagnostics, path)
  if type(value) ~= "table" then
    if value ~= nil then
      diagnostics.quarantined[#diagnostics.quarantined + 1] = path
    end
    return defaultCharacter().client
  end
  return {
    productID = numberOr(value.productID, 0),
    version = stringOr(value.version, ""),
    build = stringOr(value.build, ""),
    interface = numberOr(value.interface, 0),
  }
end

local function normalizeCharacter(value, diagnostics, path)
  if type(value) ~= "table" then
    diagnostics.quarantined[#diagnostics.quarantined + 1] = path
    return nil
  end
  local result = defaultCharacter()
  result.tracked = value.tracked ~= false
  result.identity = normalizeIdentity(value.identity, diagnostics, path .. ".identity")
  result.client = normalizeClient(value.client, diagnostics, path .. ".client")
  result.level = numberOr(value.level, 0)
  result.lastSeenAt = numberOr(value.lastSeenAt, 0)
  result.inventory = normalizeInventory(value.inventory, diagnostics, path .. ".inventory")
  if value.professions ~= nil and type(value.professions) ~= "table" then
    diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".professions"
  else
    for professionKey, profession in pairs(map(value.professions)) do
      local normalized = normalizeProfession(profession, diagnostics, path .. ".professions[" .. tostring(professionKey) .. "]")
      if normalized then
        result.professions[professionKey] = normalized
      end
    end
  end
  return result
end

local function normalizeProduct(value, diagnostics, path)
  if type(value) ~= "table" then
    diagnostics.quarantined[#diagnostics.quarantined + 1] = path
    return nil
  end
  local result = defaultProduct()
  result.dataVersion = numberOr(value.dataVersion, 1)
  result.recipes = normalizeRecipeMap(value.recipes, diagnostics, path .. ".recipes")
  if value.characters ~= nil and type(value.characters) ~= "table" then
    diagnostics.quarantined[#diagnostics.quarantined + 1] = path .. ".characters"
  else
    for characterKey, character in pairs(map(value.characters)) do
      local normalized = normalizeCharacter(character, diagnostics, path .. ".characters[" .. tostring(characterKey) .. "]")
      if normalized then
        result.characters[characterKey] = normalized
      end
    end
  end
  return result
end

local function migrationOne(value, diagnostics)
  -- Version 1 is the first durable format. Missing/zero schema versions are
  -- legacy roots whose records can still be normalized without data loss.
  if value.schemaVersion == nil or value.schemaVersion == 0 then
    diagnostics.migrated = true
  end
  value.schemaVersion = 1
  return value
end

function Repository:Create(env)
  return setmetatable({ env = env or _G, db = nil, readOnly = false, readOnlyReason = nil, unsupportedSchema = false, diagnostics = { errors = {}, quarantined = {}, migrated = false } }, Repository)
end

function Repository:RegisterMigration(version, migration)
  if type(version) ~= "number" or type(migration) ~= "function" then
    return false
  end
  self.migrations = self.migrations or {}
  self.migrations[version] = migration
  return true
end

function Repository:Migrate(root)
  local diagnostics = self.diagnostics
  local version = tonumber(root.schemaVersion) or 0
  if version > (GTF.SCHEMA_VERSION or 1) then
    self.unsupportedSchema = true
    self.readOnly = true
    diagnostics.errors[#diagnostics.errors + 1] = "unsupported schema version " .. tostring(version)
    return nil
  end
  if version < 1 then
    root = migrationOne(root, diagnostics)
    version = 1
  end
  if self.migrations then
    for nextVersion = version + 1, GTF.SCHEMA_VERSION do
      local migration = self.migrations[nextVersion]
      if migration then
        local ok, migrated = pcall(migration, root)
        if not ok or type(migrated) ~= "table" then
          diagnostics.errors[#diagnostics.errors + 1] = "migration to " .. tostring(nextVersion) .. " failed"
          return nil
        end
        root = migrated
      end
    end
  end
  root.schemaVersion = GTF.SCHEMA_VERSION or 1
  return root
end

function Repository:Initialize(savedVariables, api)
  self.diagnostics = { errors = {}, quarantined = {}, migrated = false }
  self.readOnly = false
  self.readOnlyReason = nil
  self.unsupportedSchema = false
  self.api = api or self.api
  local root = savedVariables
  if root == nil then
    root = self.env.GamersTrackerForeverDB
    if root == nil and type(self.env.AltCraftTrackerDB) == "table" then
      -- Preserve data from releases that used the old SavedVariables name.
      -- Copy instead of aliasing so later writes to the active database do
      -- not mutate or reserialize the legacy table through a shared reference.
      root = copy(self.env.AltCraftTrackerDB)
      self.diagnostics.migrated = true
      self.diagnostics.legacySavedVariables = true
    end
  end
  if type(root) ~= "table" then
    if root ~= nil then
      self.diagnostics.errors[#self.diagnostics.errors + 1] = "root recovered"
    end
    root = Repository.DefaultDatabase()
  else
    local originalRoot = root
    -- Normalize a copy so loading SavedVariables never destroys evidence of
    -- malformed records before a second repository/fixture can diagnose it.
    root = copy(root)
    root = self:Migrate(root)
    if not root then
      if self.unsupportedSchema then
        self.db = originalRoot
        self.env.GamersTrackerForeverDB = self.db
        return self.db
      end
      root = Repository.DefaultDatabase()
    end
  end
  if type(root) ~= "table" then
    root = Repository.DefaultDatabase()
  end
  root.schemaVersion = 1
  root.settings = normalizeSettings(root.settings, self.diagnostics)
  local products = {}
  if type(root.products) ~= "table" then
    if root.products ~= nil then
      self.diagnostics.errors[#self.diagnostics.errors + 1] = "products recovered"
    end
  else
    for productKey, product in pairs(root.products) do
      local normalized = normalizeProduct(product, self.diagnostics, "products[" .. tostring(productKey) .. "]")
      if normalized then
        products[productKey] = normalized
      end
    end
  end
  root.products = products
  self.db = root
  self.env.GamersTrackerForeverDB = root
  return root
end

function Repository:GetDatabase()
  return self.db
end

function Repository:GetDiagnostics()
  return self.diagnostics
end

function Repository:IsReadOnly()
  return self.readOnly == true
end

function Repository:SetReadOnly(reason)
  self.readOnly = true
  self.readOnlyReason = reason and tostring(reason) or self.readOnlyReason or "read-only"
  return self
end

function Repository:GetReadOnlyReason()
  return self.readOnlyReason
end

function Repository:GetProduct(productKey, create)
  if productKey == nil or productKey == "" or not self.db then
    return nil
  end
  local product = self.db.products[productKey]
  if product == nil and create then
    if self.readOnly then
      return nil
    end
    product = defaultProduct()
    self.db.products[productKey] = product
  end
  return product
end

function Repository:GetCharacter(productKey, characterKey, create)
  local product = self:GetProduct(productKey, create)
  if not product or characterKey == nil or characterKey == "" then
    return nil
  end
  local character = product.characters[characterKey]
  if character == nil and create then
    if self.readOnly then
      return nil
    end
    character = defaultCharacter()
    product.characters[characterKey] = character
  end
  return character
end

Repository.EnsureProduct = function(self, key) return self:GetProduct(key, true) end
Repository.EnsureCharacter = function(self, productKey, characterKey) return self:GetCharacter(productKey, characterKey, true) end

local function contextKeys(context)
  if type(context) ~= "table" then
    return nil, nil
  end
  local client = type(context.client) == "table" and context.client or {}
  local productKey = context.productKey or context.product or client.productKey or client.product
  return productKey, context.characterKey or context.key
end

function Repository:UpsertCharacter(productKey, characterKey, context)
  if type(productKey) == "table" and characterKey == nil then
    context = productKey
    productKey, characterKey = contextKeys(context)
  end
  if self.readOnly then
    return nil, "repository is read-only for a newer schema"
  end
  if not self.db or productKey == nil or characterKey == nil then
    return nil, "product and character keys are required"
  end
  local character = self:GetCharacter(productKey, characterKey, true)
  context = context or {}
  if type(context.identity) == "table" then
    character.identity = normalizeIdentity(context.identity, self.diagnostics, "context.identity")
  end
  if type(context.client) == "table" then
    character.client = normalizeClient(context.client, self.diagnostics, "context.client")
  end
  if context.level ~= nil then
    character.level = numberOr(context.level, character.level)
  end
  if context.lastSeenAt ~= nil then
    character.lastSeenAt = numberOr(context.lastSeenAt, character.lastSeenAt)
  end
  if type(context.inventory) == "table" then
    local incoming = normalizeInventory(context.inventory, self.diagnostics, "context.inventory")
    local previous = character.inventory or defaultInventory()
    character.inventory = {
      bags = context.inventory.bags ~= nil and incoming.bags or previous.bags,
      bank = context.inventory.bank ~= nil and incoming.bank or previous.bank,
      bagsScannedAt = context.inventory.bagsScannedAt ~= nil and incoming.bagsScannedAt or previous.bagsScannedAt,
      bankScannedAt = context.inventory.bankScannedAt ~= nil and incoming.bankScannedAt or previous.bankScannedAt,
    }
  end
  return character
end

function Repository:CommitCharacterContext(context, seenAt)
  if self.readOnly then
    return false, "repository is read-only for a newer schema"
  end
  local productKey, characterKey = contextKeys(context)
  if not productKey or not characterKey then
    return false, "context does not contain product and character keys"
  end
  context = copy(context)
  context.lastSeenAt = seenAt or context.lastSeenAt or (type(GTF.Now) == "function" and GTF.Now() or 0)
  local character, err = self:UpsertCharacter(productKey, characterKey, context)
  return character ~= nil, err
end

function Repository:UpsertCurrentCharacter(seenAt)
  if not self.api or type(self.api.GetCurrentContext) ~= "function" then
    return false, "API context is unavailable"
  end
  return self:CommitCharacterContext(self.api:GetCurrentContext(), seenAt)
end

function Repository:SetTracked(productKey, characterKey, tracked)
  if self.readOnly then
    return false
  end
  local character = self:GetCharacter(productKey, characterKey, false)
  if not character or type(tracked) ~= "boolean" then
    return false
  end
  if tracked and character.tracked ~= true then
    local settings = self.db and self.db.settings or defaultSettings()
    local limit = math.max(1, math.min(10, math.floor(numberOr(settings.maxTrackedCharacters, 3))))
    local count = 0
    local product = self:GetProduct(productKey, false)
    for _, candidate in pairs(product and product.characters or {}) do
      if type(candidate) == "table" and candidate.tracked == true then count = count + 1 end
    end
    if count >= limit then
      return false, "tracking limit reached (" .. tostring(limit) .. ")"
    end
  end
  character.tracked = tracked
  return true
end

function Repository:GetMaxTrackedCharacters()
  local settings = self.db and self.db.settings or defaultSettings()
  return math.max(1, math.min(10, math.floor(numberOr(settings.maxTrackedCharacters, 3))))
end

function Repository:SetMaxTrackedCharacters(value)
  if self.readOnly then return false, "repository is read-only for a newer schema" end
  local limit = tonumber(value)
  if not limit then return false, "tracking limit must be a number" end
  limit = math.max(1, math.min(10, math.floor(limit)))
  self.db.settings.maxTrackedCharacters = limit
  return true, limit
end

function Repository:GetSelectedCharacterKey()
  return self.db and self.db.settings and self.db.settings.selectedCharacterKey or nil
end

function Repository:SetSelectedCharacterKey(characterKey)
  if self.readOnly then return false, "repository is read-only for a newer schema" end
  if characterKey == nil or characterKey == "" then
    self.db.settings.selectedCharacterKey = nil
  else
    self.db.settings.selectedCharacterKey = tostring(characterKey)
  end
  return true
end

function Repository:CommitInventorySnapshot(productKey, characterKey, snapshot)
  if self.readOnly then
    return false, "repository is read-only for a newer schema"
  end
  if type(snapshot) ~= "table" or snapshot.success == false or snapshot.complete == false then
    return false, "inventory snapshot is incomplete"
  end
  if snapshot.bags ~= nil and not validSnapshotItemMap(snapshot.bags) then
    return false, "bag snapshot is invalid"
  end
  if snapshot.bankAccessible ~= false and snapshot.bank ~= nil and not validSnapshotItemMap(snapshot.bank) then
    return false, "bank snapshot is invalid"
  end
  local character = self:GetCharacter(productKey, characterKey, true)
  if not character then
    return false, "product and character keys are required"
  end
  -- A scanner may commit either location independently. Omitted locations,
  -- including an inaccessible bank, retain their last successful snapshot.
  local candidate = copy(character.inventory)
  if snapshot.bags ~= nil then
    candidate.bags = normalizeItemMap(snapshot.bags, self.diagnostics, "snapshot.inventory.bags")
    candidate.bagsScannedAt = numberOr(snapshot.bagsScannedAt, candidate.bagsScannedAt)
  end
  if snapshot.bank ~= nil and snapshot.bankAccessible ~= false then
    candidate.bank = normalizeItemMap(snapshot.bank, self.diagnostics, "snapshot.inventory.bank")
    candidate.bankScannedAt = numberOr(snapshot.bankScannedAt, candidate.bankScannedAt)
  end
  character.inventory = candidate
  return true, character.inventory
end

function Repository:CommitProfessionSkillSnapshot(productKey, characterKey, professionKey, snapshot)
  if self.readOnly then
    return false, "repository is read-only for a newer schema"
  end
  if professionKey == nil or professionKey == "" or type(snapshot) ~= "table" or snapshot.success == false then
    return false, "profession skill snapshot is invalid"
  end
  local character = self:GetCharacter(productKey, characterKey, true)
  if not character then
    return false, "product and character keys are required"
  end
  local previous = character.professions[professionKey]
  if not previous then
    previous = defaultProfession()
  end
  -- This path intentionally changes only skill metadata. Learned recipes and
  -- their scan state remain untouched until a complete recipe scan commits.
  local candidate = {
    professionID = numberOr(snapshot.professionID, previous.professionID),
    name = stringOr(snapshot.name, previous.name),
    rank = numberOr(snapshot.rank, previous.rank),
    maxRank = numberOr(snapshot.maxRank, previous.maxRank),
    specializationID = snapshot.specializationID == nil and previous.specializationID or numberOr(snapshot.specializationID, previous.specializationID or 0),
    learnedRecipes = copy(previous.learnedRecipes or {}),
    skillScannedAt = numberOr(snapshot.skillScannedAt, previous.skillScannedAt),
    recipesScannedAt = previous.recipesScannedAt,
    scanState = previous.scanState,
  }
  character.professions[professionKey] = candidate
  return true, candidate
end

Repository.CommitSkillSnapshot = Repository.CommitProfessionSkillSnapshot

function Repository:CommitProfessionSnapshot(productKey, characterKey, professionKey, snapshot)
  if self.readOnly then
    return false, "repository is read-only for a newer schema"
  end
  if professionKey == nil or professionKey == "" or type(snapshot) ~= "table" or snapshot.success == false or snapshot.complete == false then
    return false, "profession snapshot is incomplete"
  end
  local candidate = normalizeProfession(snapshot, self.diagnostics, "snapshot.profession")
  if not candidate then
    return false, "profession snapshot is invalid"
  end
  local character = self:GetCharacter(productKey, characterKey, true)
  if not character then
    return false, "product and character keys are required"
  end
  character.professions[professionKey] = candidate
  return true, candidate
end

function Repository:CommitLearnedRecipeSet(productKey, characterKey, professionKey, learnedRecipes, scannedAt)
  if self.readOnly then
    return false, "repository is read-only for a newer schema"
  end
  if professionKey == nil or professionKey == "" then
    return false, "profession key is required"
  end
  if type(learnedRecipes) ~= "table" then
    return false, "learned recipe set is invalid"
  end
  local normalized = normalizeLearned(learnedRecipes, self.diagnostics, "snapshot")
  if not normalized then
    return false, "learned recipe set is invalid"
  end
  local character = self:GetCharacter(productKey, characterKey, true)
  if not character then
    return false, "product and character keys are required"
  end
  local profession = character.professions[professionKey]
  if not profession then
    profession = defaultProfession()
    character.professions[professionKey] = profession
  end
  profession.learnedRecipes = normalized
  profession.recipesScannedAt = numberOr(scannedAt, profession.recipesScannedAt)
  profession.scanState = "current"
  return true, profession
end

function Repository:CommitBagsSnapshot(productKey, characterKey, bags, scannedAt)
  if self.readOnly then
    return false, "repository is read-only for a newer schema"
  end
  if not validSnapshotItemMap(bags) then
    return false, "bag snapshot is invalid"
  end
  local normalized = normalizeItemMap(bags, self.diagnostics, "snapshot.bags")
  local character = self:GetCharacter(productKey, characterKey, true)
  if not character then
    return false, "product and character keys are required"
  end
  character.inventory.bags = normalized
  character.inventory.bagsScannedAt = numberOr(scannedAt, character.inventory.bagsScannedAt)
  return true, character.inventory
end

function Repository:CommitBankSnapshot(productKey, characterKey, bank, scannedAt, accessible)
  if self.readOnly then
    return false, "repository is read-only for a newer schema"
  end
  if accessible == false or not validSnapshotItemMap(bank) then
    return false, "bank snapshot is inaccessible"
  end
  local normalized = normalizeItemMap(bank, self.diagnostics, "snapshot.bank")
  local character = self:GetCharacter(productKey, characterKey, true)
  if not character then
    return false, "product and character keys are required"
  end
  character.inventory.bank = normalized
  character.inventory.bankScannedAt = numberOr(scannedAt, character.inventory.bankScannedAt)
  return true, character.inventory
end

Repository.CommitBagSnapshot = Repository.CommitBagsSnapshot
Repository.CommitCharacterSnapshot = Repository.CommitCharacterContext

function Repository:CommitRecipeSnapshot(productKey, recipeKey, recipe)
  if self.readOnly then
    return false, "repository is read-only for a newer schema"
  end
  if recipeKey == nil or type(recipe) ~= "table" or recipe.success == false or recipe.complete == false then
    return false, "recipe snapshot is incomplete"
  end
  local candidate = normalizeRecipe(recipe, self.diagnostics, "snapshot.recipe")
  if not candidate then
    return false, "recipe snapshot is invalid"
  end
  local product = self:GetProduct(productKey, true)
  if not product then
    return false, "product key is required"
  end
  product.recipes[recipeKey] = candidate
  return true, candidate
end

function Repository:CommitSnapshot(productKey, characterKey, snapshotType, snapshotKey, snapshot)
  if snapshot == nil then
    snapshot = snapshotKey
    snapshotKey = nil
  end
  if snapshotType == "inventory" then
    return self:CommitInventorySnapshot(productKey, characterKey, snapshot)
  elseif snapshotType == "profession" then
    return self:CommitProfessionSnapshot(productKey, characterKey, snapshotKey, snapshot)
  elseif snapshotType == "recipe" then
    return self:CommitRecipeSnapshot(productKey, snapshotKey, snapshot)
  elseif snapshotType == "learnedRecipes" then
    return self:CommitLearnedRecipeSet(productKey, characterKey, snapshotKey, snapshot, nil)
  end
  return false, "unknown snapshot type"
end

function Repository:ForgetCharacter(productKey, characterKey)
  if self.readOnly then
    return false
  end
  local product = self:GetProduct(productKey, false)
  if not product or product.characters[characterKey] == nil then
    return false
  end
  product.characters[characterKey] = nil
  return true
end
