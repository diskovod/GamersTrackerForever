GamersTrackerForever = GamersTrackerForever or {}

local GTF = GamersTrackerForever

GTF.ADDON_NAME = "GamersTrackerForever"
GTF.ADDON_VERSION = "0.3.0-beta.15"
GTF.SCHEMA_VERSION = 1
GTF.DATA_VERSION = 1
GTF.PRODUCT_CLASSIC_ERA = "classic_era"
-- WoW Forever beta has a distinct SavedVariables partition.  It must never
-- share snapshots with Classic Era even though the beta currently reports a
-- Classic-looking project constant.
GTF.PRODUCT_FOREVER_BETA = "forever_beta"
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
  FOREVER_COMPATIBILITY_PROBE = "forever_compatibility_probe",
  SAVED_VARIABLES_PRODUCT_PARTITIONS = "saved_variables_product_partitions",
  NATIVE_UI = "native_ui",
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
