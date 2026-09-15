GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever

GTF.ADDON_NAME = "GamersTrackerForever"
GTF.ADDON_VERSION = "0.1.0"
GTF.SCHEMA_VERSION = 1
GTF.DATA_VERSION = 1
GTF.PRODUCT_CLASSIC_ERA = "classic_era"
-- Blizzard resolves these globals when Bindings.xml is loaded. Keep the
-- machine-readable names stable while presenting readable key-bind labels.
GTF.BINDING_HEADER = "GAMERSTRACKERFOREVER"
GTF.BINDING_TOGGLE = "GAMERSTRACKERFOREVER_TOGGLE"
BINDING_HEADER_GAMERSTRACKERFOREVER = "GamersTrackerForever"
BINDING_NAME_GAMERSTRACKERFOREVER_TOGGLE = "Toggle GamersTrackerForever"
GTF.CAPABILITY = {
  PRODUCT_DETECTION = "product_detection",
  CHARACTER_IDENTITY = "character_identity",
  CHARACTER_LEVEL = "character_level",
  PROFESSION_ENUMERATION = "profession_enumeration",
  LEARNED_RECIPE_SCAN = "learned_recipe_scan",
  BAG_INVENTORY_SCAN = "bag_inventory_scan",
  BANK_INVENTORY_SCAN = "bank_inventory_scan",
  SAVED_VARIABLES = "saved_variables",
  TRANSFER_GROUP = "transfer_group",
  EVENT_DISPATCH = "event_dispatch",
  SLASH_COMMANDS = "slash_commands",
}

GTF.EVENTS = {
  "ADDON_LOADED",
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD",
  "PLAYER_LEVEL_UP",
  "SKILL_LINES_CHANGED",
  "TRADE_SKILL_SHOW",
  "TRADE_SKILL_UPDATE",
  "TRADE_SKILL_CLOSE",
  "BAG_UPDATE_DELAYED",
  "BAG_UPDATE",
  "BANKFRAME_OPENED",
  "PLAYERBANKSLOTS_CHANGED",
  "BANKFRAME_CLOSED",
  "PLAYER_LOGOUT",
}
