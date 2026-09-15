GamersTrackerForever = GamersTrackerForever or {}

-- UI-facing projections.  This file intentionally has no WoW frame/API calls;
-- fixtures and the in-game renderer can consume the same deterministic rows.
local GTF = GamersTrackerForever
local ViewModels = {}
GTF.ViewModels = ViewModels

local function text(value, fallback)
  if value == nil or value == "" then return fallback or "" end
  return tostring(value)
end

local function number(value, fallback)
  value = tonumber(value)
  return value == nil and (fallback or 0) or value
end

local function lower(value) return text(value):lower() end

local function keys(map)
  local result = {}
  for key, value in pairs(map or {}) do
    if type(value) == "table" then result[#result + 1] = key end
  end
  return result
end

local function mapKeys(map)
  local result = {}
  for key in pairs(map or {}) do result[#result + 1] = key end
  return result
end

local function characterName(character, key)
  local identity = character and character.identity or {}
  return text(identity.displayName, text(key, "Unknown"))
end

local function compareCharacters(characters, a, b)
  local na, nb = lower(characterName(characters[a], a)), lower(characterName(characters[b], b))
  if na ~= nb then return na < nb end
  return tostring(a) < tostring(b)
end

local function compareProfession(a, b)
  local na, nb = lower(a.name), lower(b.name)
  if na ~= nb then return na < nb end
  return tostring(a.key) < tostring(b.key)
end

local function age(now, scannedAt)
  scannedAt = number(scannedAt, 0)
  if scannedAt <= 0 then return nil end
  return math.max(0, number(now, 0) - scannedAt)
end

function ViewModels.Freshness(scannedAt, now, settings)
  settings = type(settings) == "table" and settings or {}
  local stamp = number(scannedAt, 0)
  local staleAfter = math.max(0, number(settings.staleAfterSeconds, 86400))
  local veryStale = math.max(staleAfter, number(settings.veryStaleAfterSeconds, 604800))
  if stamp <= 0 then
    return { state = "never", label = "never scanned", scannedAt = 0, age = nil, known = false }
  end
  local elapsed = age(now, stamp)
  local state, label = "current", "fresh"
  if elapsed >= veryStale then state, label = "very_stale", "very stale"
  elseif elapsed >= staleAfter then state, label = "stale", "stale" end
  return { state = state, label = label, scannedAt = stamp, age = elapsed, known = true }
end

function ViewModels.FormatAge(seconds)
  if seconds == nil then return "unknown" end
  seconds = math.max(0, math.floor(number(seconds, 0)))
  if seconds < 60 then return tostring(seconds) .. "s ago" end
  if seconds < 3600 then return tostring(math.floor(seconds / 60)) .. "m ago" end
  if seconds < 86400 then return tostring(math.floor(seconds / 3600)) .. "h ago" end
  return tostring(math.floor(seconds / 86400)) .. "d ago"
end

function ViewModels.FormatTimestamp(stamp, env)
  stamp = number(stamp, 0)
  if stamp <= 0 then return "unknown" end
  if env and type(env.date) == "function" then
    local ok, value = pcall(env.date, "%Y-%m-%d %H:%M:%S", stamp)
    if ok and value then return tostring(value) end
  end
  return tostring(stamp)
end

function ViewModels.BuildCharacters(product, options)
  options = type(options) == "table" and options or {}
  product = type(product) == "table" and product or {}
  local now, settings = number(options.now, 0), options.settings
  local characters, rows = product.characters or {}, {}
  local characterKeys = keys(characters)
  table.sort(characterKeys, function(a, b) return compareCharacters(characters, a, b) end)
  for _, key in ipairs(characterKeys) do
    local character = characters[key]
    if options.includeUntracked ~= false or character.tracked == true then
      local identity, inventory = character.identity or {}, character.inventory or {}
      local professionRows = {}
      for professionKey, profession in pairs(character.professions or {}) do
        if type(profession) == "table" then
          professionRows[#professionRows + 1] = {
            key = professionKey, professionID = number(profession.professionID, 0),
            name = text(profession.name, "Unknown profession"), rank = number(profession.rank, 0),
            maxRank = number(profession.maxRank, 0), specializationID = profession.specializationID,
            recipeScanState = text(profession.scanState, "never"),
            skillFreshness = ViewModels.Freshness(profession.skillScannedAt, now, settings),
            recipesFreshness = ViewModels.Freshness(profession.recipesScannedAt, now, settings),
            learnedCount = type(profession.learnedRecipes) == "table" and #mapKeys(profession.learnedRecipes) or 0,
          }
        end
      end
      table.sort(professionRows, compareProfession)
      rows[#rows + 1] = {
        key = key, tracked = character.tracked == true, name = characterName(character, key),
        level = number(character.level, 0), classID = number(identity.classID, 0),
        className = text(identity.className, ""), faction = text(identity.faction, ""),
        product = text(identity.product, options.productKey or ""), realm = identity.realm,
        region = identity.region, ruleset = identity.ruleset, transferGroup = identity.transferGroup,
        guid = identity.guid, lastSeenAt = number(character.lastSeenAt, 0),
        lastSeen = ViewModels.Freshness(character.lastSeenAt, now, settings),
        lastSeenLabel = ViewModels.FormatAge(age(now, character.lastSeenAt)),
        professions = professionRows,
        bagsFreshness = ViewModels.Freshness(inventory.bagsScannedAt, now, settings),
        bankFreshness = ViewModels.Freshness(inventory.bankScannedAt, now, settings),
        bagsScannedAt = number(inventory.bagsScannedAt, 0), bankScannedAt = number(inventory.bankScannedAt, 0),
        expanded = options.expanded and options.expanded[key] == true or false,
      }
    end
  end
  return rows
end

function ViewModels.BuildRecipes(catalog, productKey, query)
  query = type(query) == "table" and query or {}
  query.productKey = productKey or query.productKey
  if not catalog or type(catalog.ListRecipes) ~= "function" then return {} end
  local product = type(catalog.GetProduct) == "function" and catalog:GetProduct(productKey) or nil
  if query.knownBy and query.knownBy ~= "" and product and type(product.characters) == "table" then
    local wanted = lower(query.knownBy)
    for key, character in pairs(product.characters) do
      if lower(characterName(character, key)) == wanted then query.knownBy = key; break end
    end
  end
  local rows = catalog:ListRecipes(query)
  for _, row in ipairs(rows) do
    row.name = text(row.name, text(row.recipe and row.recipe.name, "Unknown recipe"))
    row.professionName = text(row.professionName, "Unknown profession")
    local knownNames = {}
    for _, key in ipairs(row.knownBy or {}) do knownNames[#knownNames + 1] = characterName(product and product.characters and product.characters[key], key) end
    row.knownLabel = table.concat(knownNames, ", ")
    row.transferLabel = row.transferReady and "ready" or "isolated"
  end
  return rows
end

local function itemInfo(itemID, resolver)
  if type(resolver) == "function" then
    local ok, name, link, icon = pcall(resolver, itemID)
    if ok and (name or link or icon) then return text(name, "Item " .. tostring(itemID)), link, icon end
  end
  return "Item " .. tostring(itemID), nil, nil
end

function ViewModels.BuildMaterialRows(recipe, calculation, options)
  options = type(options) == "table" and options or {}
  recipe = type(recipe) == "table" and recipe or {}
  calculation = type(calculation) == "table" and calculation or {}
  local rows, calculated = {}, calculation.reagents or {}
  for index, reagent in ipairs(calculated) do
    local source = reagent.requirement or (recipe.reagents and recipe.reagents[index]) or {}
    local name, link, icon = itemInfo(reagent.itemID, options.itemResolver)
    local after = reagent.afterTransfer or {}
    local now = reagent.availableNow or {}
    rows[#rows + 1] = {
      index = index, itemID = reagent.itemID, name = name, link = link, icon = icon,
      required = number(reagent.quantity, number(source.quantity, 0)), kind = reagent.kind,
      bagCount = number(reagent.bagCount, 0), bankCount = number(reagent.bankCount, 0),
      pooledOwned = number(reagent.pooledOwned, number(after.owned, 0)),
      shortage = reagent.shortage, status = text(reagent.status, text(after.status, "unknown")),
      availableNow = now, afterTransfer = after, requirement = source,
      characters = after.characters or now.characters or {},
      tooltip = { itemID = reagent.itemID, required = number(reagent.quantity, 0) },
    }
    rows[#rows].nowOwned = number(now.owned, 0)
    rows[#rows].nowShortage = now.shortage
    rows[#rows].nowStatus = text(now.status, "unknown")
    rows[#rows].afterTransferOwned = number(after.owned, 0)
    rows[#rows].afterTransferShortage = after.shortage
    rows[#rows].afterTransferStatus = text(after.status, "unknown")
  end
  return rows
end

function ViewModels.FormatAvailability(result)
  result = type(result) == "table" and result or {}
  return text(result.status, "unknown") .. " (" .. tostring(number(result.craftableCount, 0)) .. " crafts)"
end

function ViewModels.FormatMaterialCell(characterRow, location, env)
  characterRow = type(characterRow) == "table" and characterRow or {}
  local snapshot = location == "bank" and characterRow.bankSnapshot or characterRow.bagsSnapshot
  local count = location == "bank" and number(characterRow.bank, 0) or number(characterRow.bags, 0)
  if not snapshot or not snapshot.known then return "—", { known = false, count = count } end
  local freshness = snapshot.freshnessLabel or "fresh"
  return tostring(count) .. " " .. location .. " (" .. freshness .. ")", {
    known = true, count = count, location = location, scannedAt = snapshot.scannedAt,
    included = characterRow.included == true, stale = characterRow.stale == true,
    tooltip = "" .. characterName(characterRow, characterRow.characterKey) .. " — " .. location
      .. "\n" .. tostring(count) .. "\nscanned " .. ViewModels.FormatTimestamp(snapshot.scannedAt, env)
      .. "\n" .. (characterRow.included and "included in pooled total" or "excluded from pooled total"),
  }
end

function ViewModels.GetRecipeCalculation(service, recipe, product, options)
  if not service or type(service.Calculate) ~= "function" then return nil end
  local characters = product and product.characters or {}
  local ok, result = pcall(service.Calculate, service, recipe, characters, options or {})
  return ok and result or nil
end

return ViewModels
