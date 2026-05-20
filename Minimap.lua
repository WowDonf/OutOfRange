-- =============================================================================
-- OutOfRange — Minimap.lua
--
-- Registers a LibDataBroker launcher and a LibDBIcon minimap button.
--
-- LibDBIcon handles everything that used to be in this file:
--   * Orbiting the minimap edge by angle
--   * Adapting to round vs. square minimaps (via GetMinimapShape)
--   * Scaling with the minimap's actual width/height
--   * Drag-to-reposition
--   * Persisting the angle across sessions (it writes db.minimapPos)
--   * Show/hide via db.hide
--
-- We just hand it an icon, an OnClick, and an OnTooltipShow.
-- =============================================================================
local _, ns = ...

local ICON_NAME = "OutOfRange"  -- the name LibDBIcon registers under

-- ----------------------------------------------------------------------------
-- LibDataBroker launcher
-- ----------------------------------------------------------------------------
local LDB     = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0",      true)

if not LDB or not LDBIcon then
    -- Libraries missing - the addon still works, you just don't get a button.
    return
end

local launcher = LDB:NewDataObject(ICON_NAME, {
    type  = "launcher",
    text  = "OutOfRange",
    icon  = "Interface\\AddOns\\OutOfRange\\Icon.png",

    OnClick = function(_, button)
        if button == "RightButton" then
            local profile = ns.API.GetActiveProfile and ns.API.GetActiveProfile()
            if profile then
                profile.enabled = not profile.enabled
                if ns.API.ApplySettings then ns.API.ApplySettings() end
                if ns.Print then
                    ns.Print(profile.enabled
                        and "|cff40ff40Enabled|r"
                        or  "|cffaaaaaaDisabled|r")
                end
            end
        else
            if ns.API.OpenOptions then ns.API.OpenOptions() end
        end
    end,

    OnTooltipShow = function(tt)
        tt:AddLine("OutOfRange", 1, 1, 1)
        local profile = ns.API.GetActiveProfile and ns.API.GetActiveProfile()
        if profile then
            tt:AddLine(
                profile.enabled
                    and "|cff40ff40Enabled|r"
                    or  "|cffaaaaaaDisabled|r")
            local sid = ns.API and ns.API.GetTrackedSpellID and ns.API.GetTrackedSpellID()
            if sid then
                local info = C_Spell.GetSpellInfo(sid)
                if info and info.name then
                    tt:AddLine("Tracking: |cffffffff" .. info.name .. "|r",
                        0.8, 0.8, 0.8)
                end
            end
            if ns.API.GetCurrentSpecName then
                tt:AddLine("Profile: |cffffd700" .. ns.API.GetCurrentSpecName() .. "|r",
                    0.7, 0.7, 0.7)
            end
        end
        tt:AddLine(" ")
        tt:AddLine("|cffffff00Left-click|r: open options",      0.7, 0.7, 0.7)
        tt:AddLine("|cffffff00Right-click|r: toggle on / off",  0.7, 0.7, 0.7)
        tt:AddLine("|cffffff00Drag|r: move around the minimap", 0.7, 0.7, 0.7)
    end,
})

-- ----------------------------------------------------------------------------
-- Register with LibDBIcon on PLAYER_LOGIN.
--
-- LibDBIcon expects its db table to be persistent (it stores minimapPos and
-- hide there), so we store it inside OutOfRangeDB.minimap.
-- ----------------------------------------------------------------------------
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
    OutOfRangeDB         = OutOfRangeDB or {}
    OutOfRangeDB.minimap = OutOfRangeDB.minimap or { hide = false }

    LDBIcon:Register(ICON_NAME, launcher, OutOfRangeDB.minimap)
end)

-- ----------------------------------------------------------------------------
-- Public API for the options panel and slash commands.
-- ----------------------------------------------------------------------------
ns.API = ns.API or {}

ns.API.SetMinimapButtonShown = function(shown)
    if not OutOfRangeDB or not OutOfRangeDB.minimap then return end
    OutOfRangeDB.minimap.hide = not shown
    if shown then
        LDBIcon:Show(ICON_NAME)
    else
        LDBIcon:Hide(ICON_NAME)
    end
end

ns.API.IsMinimapButtonShown = function()
    return OutOfRangeDB and OutOfRangeDB.minimap and not OutOfRangeDB.minimap.hide
end
