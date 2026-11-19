-- Shared game IDs, saved-data keys, and sidebar sizes.

local Config = {
    CORE_REF = "bankcore",
    PREFERENCES_KEY = "bankcore:settings:v1",
    -- Saved changes that let Core restore the window after a crash.
    WINDOW_KEY = "bankcore:window:v1",
    BANK_INVENTORY_ID = id.Inv.BANK,
    -- Includes space after the content.
    SIDEBAR_COLUMN_WIDTH = 244,
    SIDEBAR_TAB_WIDTH = 32,
    SIDEBAR_TAB_GAP = 8,
    -- Leave eight pixels inside the native eight-pixel window bevel.
    CLASSIC_SIDEBAR_LEFT_PADDING = 16,
}
Config.SIDEBAR_WIDTH = Config.SIDEBAR_TAB_WIDTH + Config.SIDEBAR_TAB_GAP + Config.SIDEBAR_COLUMN_WIDTH

return Config
