-- Luacheck configuration for the OutOfRange addon.
--
-- WoW runs Lua 5.1. The client also injects a large API surface (the C_*
-- namespaces, widget constructors, font objects, global helpers like wipe/
-- strtrim) that luacheck would otherwise flag as undefined. We declare the
-- pieces this addon actually touches as read_globals, and the handful of
-- globals the addon itself writes (saved variables, slash handlers, the
-- AddonCompartment callbacks) as writable globals.
--
-- Run from the repo root:   luacheck .

std = "lua51"

-- Bundled libraries are third-party; we don't lint them.
exclude_files = {
	"Libs/",
	".luacheckrc",
}

-- Warnings we deliberately silence project-wide.
ignore = {
	"212", -- unused argument (event handlers take args we don't always use)
	"432", -- shadowing an upvalue argument
}

max_line_length = false

-- Globals the addon legitimately creates / assigns.
globals = {
	"OutOfRangeDB",                          -- SavedVariablesPerCharacter
	"SLASH_OUTOFRANGE1",
	"SLASH_OUTOFRANGE2",
	"OutOfRange_OnAddonCompartmentClick",    -- TOC AddonCompartmentFunc
	"OutOfRange_OnAddonCompartmentEnter",
	"OutOfRange_OnAddonCompartmentLeave",
	-- Accidental-but-harmless module-level globals (could be localized later).
	"ShowConfigMode",
	"UpdatePreview",
	"RefreshAll",
	"SlashCmdList",
	"ColorPickerFrame", -- we assign .func / .cancelFunc / .hasOpacity on it
}

-- The slice of the WoW API this addon reads.
read_globals = {
	-- Namespaces / tables
	"C_Spell",
	"C_SpellBook",
	"C_Timer",
	"Enum",
	"Settings",
	"LibStub",

	-- Frame / UI
	"CreateFrame",
	"UIParent",
	"GameTooltip",
	"SettingsPanel",
	"HideUIPanel",
	"SetupColorPickerAndShow",
	"GetMinimapShape",

	-- Unit / spell / spec helpers
	"UnitClass",
	"UnitExists",
	"UnitIsDead",
	"UnitIsVisible",
	"UnitAffectingCombat",
	"IsPlayerSpell",
	"GetSpecialization",
	"GetSpecializationInfo",

	-- Sound
	"PlaySoundFile",

	-- Font objects referenced by name
	"ChatFontNormal",
	"GameFontHighlight",
	"GameFontHighlightLarge",
	"GameFontHighlightSmall",
	"GameFontNormalHuge",
	"GameFontNormalLarge",
	"GameFontDisableSmall",

	-- WoW-added global helpers
	"wipe",
	"strtrim",
	"format",
}
