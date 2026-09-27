-- Classic Era profession and trade-skill API compatibility helpers.
--
-- This file deliberately contains no persistence or event wiring.  It extends
-- the Classic adapter from ApiCompat.lua so the scanner can also be exercised
-- against small API fixtures outside of the game client.

GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local ApiCompat = GTF.ApiCompat or {}
local Classic = ApiCompat.Classic or {}
ApiCompat.Classic = Classic
GTF.ApiCompat = ApiCompat

local function fn(env, name)
  return type(env) == "table" and type(env[name]) == "function"
end

local function call(env, name, ...)
  if not fn(env, name) then
    return false, nil
  end
  return pcall(env[name], ...)
end

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
  value = value:gsub("[^%w]", "")
  return value
end

local knownProfessionIDs = {
  [40] = true,   -- Poisons
  [129] = true,  -- First Aid
  [164] = true,  -- Blacksmithing
  [165] = true,  -- Leatherworking
  [171] = true,  -- Alchemy
  [182] = true,  -- Herbalism
  [185] = true,  -- Cooking
  [186] = true,  -- Mining
  [197] = true,  -- Tailoring
  [202] = true,  -- Engineering
  [333] = true,  -- Enchanting
  [356] = true,  -- Fishing
  [393] = true,  -- Skinning
  [755] = true,  -- Jewelcrafting (present in some Classic branches)
  [773] = true,  -- Inscription (present in some Classic branches)
}

local knownProfessionNames = {
  alchemy = true, blacksmithing = true, enchanting = true, engineering = true,
  herbalism = true, fishing = true, cooking = true, firstaid = true,
  leatherworking = true, mining = true, skinning = true, tailoring = true,
  poisons = true, jewelcrafting = true, inscription = true,
}

local function isProfession(name, id)
  return (id and knownProfessionIDs[id]) or knownProfessionNames[cleanName(name)] or false
end

-- Parse IDs from WoW hyperlinks without depending on colour or display text.
-- Examples: |Hitem:123:..., |Hspell:456:..., |Htrade:171:...
function Classic:ParseLinkID(link, wantedKind)
  if type(link) ~= "string" then
    return nil
  end
  local lowerWanted = wantedKind and tostring(wantedKind):lower() or nil
  for kind, id in link:gmatch("|H([%w_]+):(%d+)") do
    kind = kind:lower()
    if not lowerWanted or kind == lowerWanted then
      return tonumber(id), kind
    end
  end
  -- A few fixture/client surfaces use the escaped pipe form.
  for kind, id in link:gmatch("H([%w_]+):(%d+)") do
    kind = kind:lower()
    if not lowerWanted or kind == lowerWanted then
      return tonumber(id), kind
    end
  end
  return nil
end

function Classic:ParseItemID(link)
  return self:ParseLinkID(link, "item")
end

function Classic:ParseRecipeID(link)
  if type(link) ~= "string" then
    return nil
  end
  -- Trade links are the canonical Classic recipe identity.  Spell/recipe
  -- links are accepted for clients and test fixtures that expose those.
  return self:ParseLinkID(link, "trade")
    or self:ParseLinkID(link, "spell")
    or self:ParseLinkID(link, "enchant")
    or self:ParseLinkID(link, "recipe")
end

local function professionRecord(index, name, icon, rank, maxRank, id, specializationID, source)
  id = positive(id)
  return {
    index = tonumber(index) or 0,
    name = tostring(name or ""),
    icon = icon or 0,
    rank = number(rank, 0),
    maxRank = number(maxRank, 0),
    professionID = id or 0,
    specializationID = positive(specializationID),
    source = source,
  }
end

-- Return all profession skill lines identified by the client.  GetProfessions
-- is preferred; the old skill-line API is a useful fallback on early Classic
-- builds and in unit fixtures.
function Classic:GetProfessionEntries()
  local env = self.env or _G
  local result, seen = {}, {}
  local attempted = false

  if fn(env, "GetProfessions") and fn(env, "GetProfessionInfo") then
    attempted = true
    local ok, p1, p2, p3, p4, p5, p6 = pcall(env.GetProfessions)
    if not ok then return nil, "profession enumeration failed" end
    if ok then
      local slots = { p1, p2, p3, p4, p5, p6 }
      -- Do not use ipairs here: GetProfessions may leave primary slots nil
      -- while exposing Cooking/Fishing/First Aid in a later slot.
      for slot = 1, 6 do
        local index = slots[slot]
        index = tonumber(index)
        if index and index > 0 then
          local infoOK, name, icon, rank, maxRank, numAbilities, spellOffset, skillLine, specialization =
            pcall(env.GetProfessionInfo, index)
          if not infoOK then return nil, "profession info failed" end
          if not name or name == "" then return nil, "profession info incomplete" end
          if name then
            -- In the Classic shape, numAbilities and spellOffset precede the
            -- skill-line ID.  Only the explicitly named skillLine return is
            -- accepted here; offsets and specialization indexes are not IDs.
            local id
            if knownProfessionIDs[positive(skillLine)] then
              id = positive(skillLine)
            end
            -- specializationIndex is not a stable profession ID and is not
            -- persisted unless a later adapter can prove its meaning.
            local entry = professionRecord(index, name, icon, rank, maxRank, id, nil, "GetProfessions")
            local key = entry.professionID > 0 and "id:" .. entry.professionID or "name:" .. cleanName(entry.name)
            if not seen[key] then
              seen[key] = true
              result[#result + 1] = entry
            end
          end
        end
      end
    end
  end

  if #result == 0 and fn(env, "GetNumSkillLines") and fn(env, "GetSkillLineInfo") then
    attempted = true
    local ok, count = pcall(env.GetNumSkillLines)
    if not ok then return nil, "skill-line enumeration failed" end
    count = tonumber(count) or 0
    for index = 1, count do
      local infoOK, name, isHeader, isExpanded, rank, maxRank, a6, a7, a8, a9 =
        pcall(env.GetSkillLineInfo, index)
      if not infoOK then return nil, "skill-line info failed" end
      if infoOK and name and not isHeader then
        -- GetSkillLineInfo changed its tail returns between Classic builds.
        -- Only promote a tail value when it is a known profession ID; rank,
        -- XP, offsets, and specialization indexes must never become IDs.
        local tail = { a9, a8, a7, a6 }
        local detectedID
        for _, candidate in ipairs(tail) do
          candidate = positive(candidate)
          if candidate and knownProfessionIDs[candidate] then
            detectedID = candidate
            break
          end
        end
        local id = detectedID
        if isProfession(name, id) then
          local entry = professionRecord(index, name, nil, rank, maxRank, id, nil, "GetSkillLineInfo")
          local key = entry.professionID > 0 and "id:" .. entry.professionID or "name:" .. cleanName(entry.name)
          if not seen[key] then
            seen[key] = true
            result[#result + 1] = entry
          end
        end
      end
    end
  end

  if not attempted then return nil, "profession enumeration is unavailable" end

  table.sort(result, function(a, b)
    local ak = a.professionID > 0 and ("0:" .. a.professionID) or ("1:" .. cleanName(a.name))
    local bk = b.professionID > 0 and ("0:" .. b.professionID) or ("1:" .. cleanName(b.name))
    return ak < bk
  end)
  return result
end

Classic.EnumerateProfessions = Classic.GetProfessionEntries

-- Classic Era serves most professions through the trade-skill window, but
-- Enchanting (and Beast Training) use the separate Craft window.  The scanner
-- selects the active family; the row methods below dispatch through it.
local SOURCES = {
  trade = {
    line = "GetTradeSkillLine", count = "GetNumTradeSkills", info = "GetTradeSkillInfo",
    recipeLink = "GetTradeSkillRecipeLink", itemLink = "GetTradeSkillItemLink",
    icon = "GetTradeSkillIcon", numMade = "GetTradeSkillNumMade",
    numReagents = "GetTradeSkillNumReagents", reagentInfo = "GetTradeSkillReagentInfo",
    reagentLink = "GetTradeSkillReagentItemLink", expand = { "ExpandTradeSkillSubClass", "ExpandTradeSkillCategory" },
  },
  craft = {
    line = "GetCraftDisplaySkillLine", count = "GetNumCrafts", info = "GetCraftInfo",
    -- Enchant crafts expose |Henchant:ID| through GetCraftItemLink; item
    -- crafts expose |Hitem:ID|.  ParseRecipeID/ParseItemID keep them apart.
    recipeLink = "GetCraftRecipeLink", itemLink = "GetCraftItemLink",
    icon = "GetCraftIcon", numMade = nil,
    numReagents = "GetCraftNumReagents", reagentInfo = "GetCraftReagentInfo",
    reagentLink = "GetCraftReagentItemLink", expand = { "ExpandCraftSkillLine" },
  },
}

function Classic:SetTradeSource(source)
  self.tradeSource = SOURCES[source] and source or "trade"
  return self.tradeSource
end

function Classic:GetTradeSource()
  return SOURCES[self.tradeSource] and self.tradeSource or "trade"
end

function Classic:GetTradeSourceNames()
  return SOURCES[self:GetTradeSource()]
end
Classic.GetProfessionsSnapshot = Classic.GetProfessionEntries
Classic.GetProfessionSkills = Classic.GetProfessionEntries

function Classic:GetLoadedProfession()
  local env = self.env or _G
  local names = self:GetTradeSourceNames()
  if not fn(env, names.line) then
    return nil, "trade-skill line API unavailable"
  end
  local ok, name, rank, maxRank, numAbilities, spellOffset, skillLine, specialization = pcall(env[names.line])
  if names == SOURCES.craft then skillLine = nil end -- craft lines return only name, rank, maxRank
  if not ok or not name or name == "" then
    return nil, "no profession is loaded"
  end
  local id
  if knownProfessionIDs[positive(skillLine)] then
    id = positive(skillLine)
  end
  -- A loaded line can be identified by matching the enumerated profession
  -- even when GetTradeSkillLine omits its skill-line ID.
  if not id then
    local entries = self:GetProfessionEntries()
    if type(entries) == "table" then
      for _, entry in ipairs(entries) do
        if cleanName(entry.name) == cleanName(name) then
          id = entry.professionID
          break
        end
      end
    end
  end
  -- The Craft window also serves Beast Training, which is not a profession.
  if names == SOURCES.craft and not (positive(id) or isProfession(name, nil)) then
    return nil, "loaded craft line is not a profession"
  end
  return professionRecord(0, name, nil, rank, maxRank, id, nil, names.line), nil
end

Classic.GetLoadedTradeSkill = Classic.GetLoadedProfession

function Classic:GetTradeSkillCount()
  local env = self.env or _G
  local names = self:GetTradeSourceNames()
  if not fn(env, names.count) then
    return nil, "trade-skill count API unavailable"
  end
  local ok, count = pcall(env[names.count])
  if not ok then
    return nil, "trade-skill count failed"
  end
  return tonumber(count) or 0
end

function Classic:GetTradeSkillInfo(index)
  local env = self.env or _G
  local names = self:GetTradeSourceNames()
  if not fn(env, names.info) then
    return nil, "trade-skill row API unavailable"
  end
  local ok, name, rowType, numAvailable, isExpanded, altVerb, numSkillUps
  if names == SOURCES.craft then
    -- name, subSpellName, craftType, numAvailable, isExpanded, trainingPointCost, requiredLevel
    ok, name, altVerb, rowType, numAvailable, isExpanded = pcall(env[names.info], index)
  else
    ok, name, rowType, numAvailable, isExpanded, altVerb, numSkillUps = pcall(env[names.info], index)
  end
  if not ok then
    return nil, "trade-skill row failed"
  end
  return {
    index = index,
    name = name,
    type = rowType,
    numAvailable = numAvailable,
    isExpanded = isExpanded,
    altVerb = altVerb,
    numSkillUps = numSkillUps,
  }
end

local function sourceCall(self, key, index)
  local env = self.env or _G
  local name = self:GetTradeSourceNames()[key]
  if not name or not fn(env, name) then return nil end
  local ok, value = pcall(env[name], index)
  return ok and value or nil
end

function Classic:GetTradeSkillRecipeLink(index)
  local link = sourceCall(self, "recipeLink", index)
  -- Classic Era craft rows carry the enchant link on GetCraftItemLink.
  if not link and self:GetTradeSource() == "craft" then link = sourceCall(self, "itemLink", index) end
  return link
end

function Classic:GetTradeSkillItemLink(index)
  return sourceCall(self, "itemLink", index)
end

function Classic:GetTradeSkillIcon(index)
  return sourceCall(self, "icon", index)
end

function Classic:GetTradeSkillNumMade(index)
  local env = self.env or _G
  local name = self:GetTradeSourceNames().numMade
  if not name or not fn(env, name) then return 1, 1 end
  local ok, minimum, maximum = pcall(env[name], index)
  if not ok then return nil, nil end
  minimum = positive(minimum) or 1
  maximum = positive(maximum) or minimum
  if maximum < minimum then maximum = minimum end
  return minimum, maximum
end

function Classic:GetTradeSkillReagents(index)
  local env = self.env or _G
  local names = self:GetTradeSourceNames()
  if not fn(env, names.numReagents) then
    return nil, "reagent count API unavailable"
  end
  local ok, count = pcall(env[names.numReagents], index)
  if not ok then return nil, "reagent count failed" end
  count = tonumber(count)
  if count == nil or count < 0 then return nil, "reagent count unavailable" end
  if count > 0 and (not fn(env, names.reagentInfo)
    or not fn(env, names.reagentLink)) then
    return nil, "reagent detail API unavailable"
  end
  local result = {}
  for reagentIndex = 1, count do
    local name, texture, required, playerCount
    if fn(env, names.reagentInfo) then
      local infoOK
      infoOK, name, texture, required, playerCount = pcall(env[names.reagentInfo], index, reagentIndex)
      if not infoOK then return nil, "reagent info failed" end
    end
    if tonumber(required) == nil then return nil, "reagent quantity unavailable" end
    local link
    if fn(env, names.reagentLink) then
      local linkOK
      linkOK, link = pcall(env[names.reagentLink], index, reagentIndex)
      if not linkOK then return nil, "reagent link failed" end
    end
    result[#result + 1] = {
      name = name,
      texture = texture,
      quantity = tonumber(required) or 0,
      playerCount = tonumber(playerCount) or 0,
      link = link,
      itemID = self:ParseItemID(link),
    }
  end
  return result, nil
end

-- Add fallback-aware capability reporting while retaining capabilities from
-- ApiCompat.lua when that file has already been loaded.
local previousCapabilities = Classic.GetCapabilities
function Classic:GetCapabilities()
  local capabilities = previousCapabilities and previousCapabilities(self) or {}
  local env = self.env or _G
  local professionEnumeration = (fn(env, "GetProfessions") and fn(env, "GetProfessionInfo"))
    or (fn(env, "GetNumSkillLines") and fn(env, "GetSkillLineInfo"))
  local recipeScan = (fn(env, "GetTradeSkillLine") and fn(env, "GetNumTradeSkills") and fn(env, "GetTradeSkillInfo"))
    or (fn(env, "GetCraftDisplaySkillLine") and fn(env, "GetNumCrafts") and fn(env, "GetCraftInfo"))
  capabilities[GTF.CAPABILITY and GTF.CAPABILITY.PROFESSION_ENUMERATION or "profession_enumeration"] = professionEnumeration
  capabilities[GTF.CAPABILITY and GTF.CAPABILITY.LEARNED_RECIPE_SCAN or "learned_recipe_scan"] = recipeScan
  return capabilities
end

GTF.ApiCompat.Classic = Classic
