-- WoW Forever beta's modern profession window exposes a profession-scoped
-- all-recipe list. Never replace a learned set unless every returned ID and
-- every learned schematic has been validated first.
GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local Scanner = {}
Scanner.__index = Scanner
GTF.ForeverRecipeScanner = Scanner

local function positive(value)
  value = tonumber(value)
  return value and value > 0 and value == math.floor(value) and value or nil
end

local function sameName(a, b)
  local function clean(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
  end
  return clean(a) ~= "" and clean(a) == clean(b)
end

local function call(owner, method, ...)
  if type(owner) ~= "table" or type(owner[method]) ~= "function" then
    return nil, method .. " unavailable"
  end
  local ok, value = pcall(owner[method], ...)
  if not ok then return nil, method .. " failed" end
  return value
end

function Scanner:Create(env, api, repository, rankScanner, options)
  options = type(options) == "table" and options or {}
  return setmetatable({
    env = env or _G, api = api, repository = repository,
    rankScanner = rankScanner, onResult = options.onResult,
    pending = false, scheduled = false, token = 0, lastError = nil,
  }, Scanner)
end

function Scanner:_error(message)
  self.lastError = message
  if message and type(GTF.SetError) == "function" then GTF:SetError(message) end
  return { success = false, complete = false, error = message }
end

function Scanner:_collect(scanAt)
  local owner = self.env and self.env.C_TradeSkillUI
  local ids, listError = call(owner, "GetAllRecipeIDs")
  if type(ids) ~= "table" then return nil, listError or "recipe list unavailable" end

  local count, seen, recipes, learned = 0, {}, {}, {}
  local professionID, professionName
  for key, value in pairs(ids) do
    count = count + 1
    if count > 10000 then return nil, "recipe list exceeds safety limit" end
    local id = positive(type(value) == "number" and value or (value == true and key or nil))
    if not id then return nil, "recipe list contains an invalid ID" end
    if not seen[id] then
      seen[id] = true
      local info, infoError = call(owner, "GetRecipeInfo", id)
      if type(info) ~= "table" or positive(info.recipeID) ~= id
        or type(info.learned) ~= "boolean" then
        return nil, infoError or "recipe info is incomplete"
      end
      local profession, professionError = call(owner, "GetProfessionInfoByRecipeID", id)
      if type(profession) ~= "table" or not positive(profession.professionID)
        or type(profession.professionName) ~= "string" or profession.professionName == "" then
        return nil, professionError or "recipe profession is unavailable"
      end
      if professionID and (professionID ~= positive(profession.professionID)
        or not sameName(professionName, profession.professionName)) then
        return nil, "recipe list mixes professions"
      end
      professionID, professionName = positive(profession.professionID), profession.professionName
      if info.learned then
        local schematic, schematicError = call(owner, "GetRecipeSchematic", id, false)
        if type(schematic) ~= "table" or positive(schematic.outputItemID) == nil
          or positive(schematic.quantityMin) == nil or positive(schematic.quantityMax) == nil
          or schematic.quantityMax < schematic.quantityMin
          or type(schematic.reagentSlotSchematics) ~= "table" then
          return nil, schematicError or "learned recipe schematic is incomplete"
        end
        if type(info.name) ~= "string" or info.name == "" then
          return nil, "learned recipe name is unavailable"
        end
        local reagentByID = {}
        for _, slot in pairs(schematic.reagentSlotSchematics) do
          if type(slot) ~= "table" or not positive(slot.quantityRequired)
            or type(slot.reagents) ~= "table" then
            return nil, "reagent slot is incomplete"
          end
          local reagentID, choices = nil, 0
          for _, reagent in pairs(slot.reagents) do
            choices = choices + 1
            reagentID = type(reagent) == "table" and positive(reagent.itemID) or nil
          end
          if choices ~= 1 or not reagentID then
            return nil, "reagent slot is ambiguous or non-item"
          end
          reagentByID[reagentID] = (reagentByID[reagentID] or 0) + slot.quantityRequired
        end
        local reagents = {}
        for itemID, quantity in pairs(reagentByID) do
          reagents[#reagents + 1] = { itemID = itemID, quantity = quantity, kind = "item" }
        end
        table.sort(reagents, function(a, b) return a.itemID < b.itemID end)
        local recipeKey = "recipe:" .. tostring(id)
        recipes[recipeKey] = {
          success = true, complete = true, recipeID = id,
          professionID = professionID, professionName = professionName,
          name = info.name, icon = info.icon or 0,
          outputItemID = schematic.outputItemID,
          outputMin = schematic.quantityMin, outputMax = schematic.quantityMax,
          reagents = reagents, specialRequirements = {},
          discoveredBuild = self.api and self.api.GetClientInfo
            and tostring((self.api:GetClientInfo() or {}).build or "") or "",
          scannedAt = scanAt,
        }
        learned[recipeKey] = true
      end
    end
  end
  if not professionID then return nil, "recipe list is empty; previous snapshot preserved" end
  local entries, entriesError = self.api:GetProfessionEntries()
  if type(entries) ~= "table" then return nil, entriesError or "profession ranks unavailable" end
  local matching
  for _, entry in ipairs(entries) do
    if sameName(entry.name, professionName) then matching = entry; break end
  end
  if not matching then return nil, "recipe profession does not match a learned skill" end
  -- Forever's rank enumeration has no profession ID. The rank scanner keys
  -- by normalized name, while recipe definitions keep the beta's numeric ID.
  return { profession = matching, recipes = recipes, learnedRecipes = learned,
    complete = true, count = count, learnedCount = (function()
      local n = 0; for _ in pairs(learned) do n = n + 1 end; return n
    end)() }
end

function Scanner:ScanOpen(scanAt)
  if not self.rankScanner or type(self.rankScanner._commitFull) ~= "function" then
    return self:_error("profession commit path is unavailable")
  end
  scanAt = tonumber(scanAt) or (type(GTF.Now) == "function" and GTF.Now() or 0)
  local ok, collected, err = pcall(self._collect, self, scanAt)
  if not ok or not collected then return self:_error(ok and err or tostring(collected)) end
  local commitOK, success, commitError = pcall(self.rankScanner._commitFull,
    self.rankScanner, collected.profession, collected, scanAt)
  if not commitOK or not success then
    return self:_error(commitOK and commitError or tostring(success))
  end
  self.lastError = nil
  if GTF.Runtime then GTF.Runtime.lastError = nil end
  collected.success, collected.scannedAt = true, scanAt
  if type(self.onResult) == "function" then pcall(self.onResult, collected) end
  return collected
end

function Scanner:HandleEvent(event)
  if event == "TRADE_SKILL_CLOSE" then
    self.pending, self.scheduled = false, false
    self.token = self.token + 1
    return nil
  end
  if event ~= "TRADE_SKILL_SHOW" and event ~= "TRADE_SKILL_UPDATE" then return nil end
  self.pending = true
  if self.scheduled then return nil end
  local timer = self.env and self.env.C_Timer
  if type(timer) ~= "table" or type(timer.After) ~= "function" then
    self.pending = false
    return self:ScanOpen()
  end
  self.scheduled = true
  self.token = self.token + 1
  local token = self.token
  local ok = pcall(timer.After, 0.15, function()
    if token ~= self.token then return end
    self.scheduled = false
    if not self.pending then return end
    self.pending = false
    self:ScanOpen()
  end)
  if not ok then
    self.scheduled, self.pending = false, false
    return self:ScanOpen()
  end
  return nil
end

return Scanner
