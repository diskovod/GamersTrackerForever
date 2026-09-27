-- Narrow WoW Forever beta adapter.
--
-- The beta probe has proven character identity/level and C_Container bags on
-- build 1.60.1 (interface 16001).  It has not proven the legacy trade-skill
-- or recipe surfaces, and bank access was unavailable. Keep this adapter
-- deliberately small: it reuses identity/container normalization and the
-- verified profession name/rank enumeration, while recipe scanning stays off.

GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever
local ApiCompat = GTF.ApiCompat or {}
local Classic = ApiCompat.Classic or {}
GTF.ApiCompat = ApiCompat

local ForeverBeta = setmetatable({}, { __index = Classic })
ForeverBeta.__index = ForeverBeta
ApiCompat.ForeverBeta = ForeverBeta

local function hasFunction(env, name)
  return type(env) == "table" and type(env[name]) == "function"
end

local function normalize(value)
  if value == nil or value == "" then return "unknown" end
  return tostring(value):lower():gsub("[^%w%-]", "-")
end

local function safeString(value)
  return value == nil and "" or tostring(value)
end

-- Forever's beta UnitFullName returns the first and last parts of the
-- character name. GetRealmName is the separate realm authority.
function ForeverBeta.NormalizeUnitFullName(env, name, secondPart)
  name, secondPart = safeString(name), safeString(secondPart)
  local actualRealm = ""
  if hasFunction(env, "GetRealmName") then
    local ok, realm = pcall(env.GetRealmName)
    if ok then actualRealm = safeString(realm) end
  end
  local displayName = secondPart ~= "" and (name .. " " .. secondPart) or name
  return displayName:gsub("^%s+", ""), actualRealm
end

function ForeverBeta:ReadClientInfo()
  local version, build, date, interface = "", "", "", 0
  if hasFunction(self.env, "GetBuildInfo") then
    version, build, date, interface = self.env.GetBuildInfo()
  end
  return {
    productID = self.env.WOW_PROJECT_ID or 0,
    product = GTF.PRODUCT_FOREVER_BETA,
    version = safeString(version),
    build = safeString(build),
    date = safeString(date),
    interface = tonumber(interface) or 0,
    flavor = safeString(self.env.WOW_PROJECT_FLAVOR),
  }
end

function ForeverBeta:GetProduct()
  return GTF.PRODUCT_FOREVER_BETA
end

function ForeverBeta:GetAdapterName()
  return "ForeverBeta"
end

function ForeverBeta:IsSupported()
  return true
end

function ForeverBeta:GetCurrentIdentity()
  local identity = Classic.GetCurrentIdentity(self)
  if hasFunction(self.env, "UnitFullName") then
    local ok, name, secondPart = pcall(self.env.UnitFullName, "player")
    if ok then
      identity.displayName, identity.realm = ForeverBeta.NormalizeUnitFullName(self.env, name, secondPart)
    end
  end
  identity.ruleset = "forever_beta"
  return identity
end

function ForeverBeta:GetCharacterKey(identity)
  identity = identity or self:GetCurrentIdentity()
  if identity.guid and identity.guid ~= "" then return identity.guid end
  return table.concat({
    GTF.PRODUCT_FOREVER_BETA,
    normalize(identity.realm),
    normalize(identity.displayName),
    normalize(identity.faction),
  }, "|")
end

function ForeverBeta:GetTransferGroup(identity)
  -- Cross-character transfer rules are not proven by the beta probe yet.
  return nil
end

function ForeverBeta:GetCurrentContext()
  local identity = self:GetCurrentIdentity()
  local level = 0
  if hasFunction(self.env, "UnitLevel") then
    level = tonumber(self.env.UnitLevel("player")) or 0
  end
  return {
    key = self:GetCharacterKey(identity),
    characterKey = self:GetCharacterKey(identity),
    productKey = GTF.PRODUCT_FOREVER_BETA,
    identity = identity,
    level = level,
    client = self:GetClientInfo(),
    transferGroup = nil,
  }
end

function ForeverBeta:GetCapabilities()
  local env = self.env or _G
  local container = env.C_Container
  local bags = type(container) == "table"
    and hasFunction(container, "GetContainerNumSlots")
    and hasFunction(container, "GetContainerItemInfo")
  return {
    [GTF.CAPABILITY.PRODUCT_DETECTION] = true,
    [GTF.CAPABILITY.CHARACTER_IDENTITY] = hasFunction(env, "UnitName") or hasFunction(env, "UnitFullName"),
    [GTF.CAPABILITY.CHARACTER_LEVEL] = hasFunction(env, "UnitLevel"),
    [GTF.CAPABILITY.PROFESSION_ENUMERATION] = hasFunction(env, "GetProfessions") and hasFunction(env, "GetProfessionInfo"),
    [GTF.CAPABILITY.LEARNED_RECIPE_SCAN] = false,
    [GTF.CAPABILITY.BAG_INVENTORY_SCAN] = bags,
    [GTF.CAPABILITY.BANK_INVENTORY_SCAN] = false,
    [GTF.CAPABILITY.SAVED_VARIABLES] = true,
    [GTF.CAPABILITY.TRANSFER_GROUP] = false,
    [GTF.CAPABILITY.EVENT_DISPATCH] = true,
    [GTF.CAPABILITY.SLASH_COMMANDS] = true,
    [GTF.CAPABILITY.FOREVER_COMPATIBILITY_PROBE] = true,
    [GTF.CAPABILITY.SAVED_VARIABLES_PRODUCT_PARTITIONS] = true,
    [GTF.CAPABILITY.NATIVE_UI] = true,
  }
end

function ForeverBeta:GetProfessionEntries()
  local env = self.env or _G
  if not hasFunction(env, "GetProfessions") or not hasFunction(env, "GetProfessionInfo") then
    return nil, "Forever beta profession enumeration is unavailable"
  end
  local ok, p1, p2, p3, p4, p5, p6 = pcall(env.GetProfessions)
  if not ok then return nil, "Forever beta profession enumeration failed" end
  local slots = { p1, p2, p3, p4, p5, p6 }
  local entries, seen = {}, {}
  for slot = 1, 6 do
    local index = tonumber(slots[slot])
    if index and index > 0 then
      local infoOK, name, icon, rank, maxRank = pcall(env.GetProfessionInfo, index)
      if not infoOK then return nil, "Forever beta profession info failed" end
      if type(name) ~= "string" or name == "" then
        return nil, "Forever beta profession info incomplete"
      end
      rank, maxRank = tonumber(rank), tonumber(maxRank)
      if not rank or not maxRank or rank < 0 or maxRank < rank then
        return nil, "Forever beta profession ranks are unavailable"
      end
      local key = name:lower():gsub("[^%w]", "")
      if not seen[key] then
        seen[key] = true
        entries[#entries + 1] = {
          index = index, name = name, icon = icon or 0,
          rank = rank, maxRank = maxRank,
          professionID = 0, source = "GetProfessions",
        }
      end
    end
  end
  table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
  return entries
end

function ForeverBeta:GetLoadedProfession()
  return nil, "Forever beta trade-skill scanning is not enabled"
end

function ForeverBeta:GetTradeSkillCount()
  return nil, "Forever beta recipe scanning is not enabled"
end

return ForeverBeta
