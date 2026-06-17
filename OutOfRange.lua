-- =============================================================================
--  OutOfRange  -  core
--  Built for World of Warcraft: Midnight (12.x)
--
--  Uses C_Spell.IsSpellInRange against a tracked ability to detect when the
--  current target has stepped out of range, then flashes an on-screen warning.
--
--  By default the tracked ability is auto-picked from a per-class melee table,
--  but the options panel lets any class override it with any ability.
-- =============================================================================

local addonName, ns = ...

-- Shared API table consumed by Options.lua. Populated further down.
ns.API = ns.API or {}

-- ---------------------------------------------------------------------------
-- Defaults. OutOfRangeDB is declared SavedVariablesPerCharacter in the .toc,
-- so every character keeps its own independent copy of these settings.
-- ---------------------------------------------------------------------------
local defaults = {
    enabled        = true,
    soundEnabled   = false,
    soundKey       = "BLEEP",                      -- key into SOUND_LIST below
    soundChannel   = "SFX",                        -- WoW audio channel: SFX / Dialog / Ambience / Music / Master
    onlyInCombat   = false,
    scale          = 1.0,
    point          = "CENTER",
    relativePoint  = "CENTER",
    x              = 0,
    y              = -140,
    text           = "|cffff2020! OUT OF RANGE !|r",
    locked         = true,
    throttle       = 0.3,                          -- seconds between range checks
    useCustomSpell = false,                        -- false = auto-detect class melee ability
    customSpell    = "",                           -- spell name or numeric ID
    trackedUnit    = "target",                     -- which unit token to range-check against
}
ns.defaults = defaults

-- Unit tokens the user can pick from in the options panel.
local UNIT_OPTIONS = {
    { key = "target",    label = "Target",    desc = "Your current target (default; standard hostile-spell behavior)." },
    { key = "mouseover", label = "Mouseover", desc = "The unit your cursor is hovering, useful for healers using mouseover or click-cast bindings." },
    { key = "focus",     label = "Focus",     desc = "Your focus target." },
}
ns.UNIT_OPTIONS = UNIT_OPTIONS

-- ---------------------------------------------------------------------------
-- Class -> ordered list of 5-yard melee ability spell IDs.
-- Used when "auto-detect" is on. The first one IsPlayerSpell() returns true
-- for is used, so it adapts to spec / talent changes. Universal interrupts
-- (Pummel, Rebuke, Kick) are listed first since every spec of those classes
-- learns them.
-- ---------------------------------------------------------------------------
local CLASS_MELEE_SPELLS = {
    WARRIOR     = {  6552,   1464,  12294,  23922,  23881, 184367 }, -- Pummel, Slam, MS, Shield Slam, Bloodthirst, Rampage
    PALADIN     = { 96231,  35395,  85256,  53600                  }, -- Rebuke, Crusader Strike, Templar's Verdict, Shield of the Righteous
    HUNTER      = {186270                                           }, -- Raptor Strike (Survival)
    ROGUE       = {  1766,   1752,   1329,     53, 196819          }, -- Kick, Sinister Strike, Mutilate, Backstab, Eviscerate
    DEATHKNIGHT = { 49998,  49020, 206930,  85948                  }, -- Death Strike, Obliterate, Heart Strike, Festering Strike
    SHAMAN      = { 17364,  60103                                  }, -- Stormstrike, Lava Lash (Enhancement)
    DRUID       = { 33917,   5221,   6807, 213764                  }, -- Mangle, Shred, Maul, Swipe
    MONK        = {100780, 100784, 107428                          }, -- Tiger Palm, Blackout Kick, Rising Sun Kick
    DEMONHUNTER = {162794, 162243, 228477, 203782                  }, -- Chaos Strike, Demon's Bite, Soul Cleave, Shear
    EVOKER      = {},                                                  -- Ranged class; no class default
}

-- ---------------------------------------------------------------------------
-- Per-spec profile system (added in 1.10.0)
--
-- OutOfRangeDB is laid out as:
--   {
--     schemaVersion = 2,
--     minimap = { ... },                  -- shared across all specs (LDBIcon)
--     profiles = {
--       [<specID>] = { full settings copy for this spec },
--     },
--   }
--
-- `activeProfile` is a local reference to the currently active spec's profile
-- table. Every code path reads and writes per-spec settings through this
-- reference - NEVER directly through OutOfRangeDB except for the explicitly
-- shared keys (`minimap` and `schemaVersion`).
--
-- On a spec change, SetActiveProfile() repoints `activeProfile`, the tracked
-- spell is re-resolved, ApplySettings re-applies appearance / position, and
-- the options panel (if open) refreshes via ns.API.OnProfileChanged.
-- ---------------------------------------------------------------------------
local activeProfile

local function CurrentSpecID()
    local i = GetSpecialization and GetSpecialization()
    if i and i > 0 then
        local id = GetSpecializationInfo and GetSpecializationInfo(i)
        if id and id > 0 then return id end
    end
    return 0   -- "no specialization" bucket (low-level character)
end

local function GetCurrentSpecName()
    local i = GetSpecialization and GetSpecialization()
    if i and i > 0 then
        local _, name = GetSpecializationInfo(i)
        if name and name ~= "" then return name end
    end
    return "No specialization"
end

local function SetActiveProfile()
    local specID = CurrentSpecID()
    OutOfRangeDB.profiles = OutOfRangeDB.profiles or {}
    local profile = OutOfRangeDB.profiles[specID]
    if not profile then
        -- New spec encountered; seed from defaults.
        profile = {}
        for k, v in pairs(defaults) do profile[k] = v end
        OutOfRangeDB.profiles[specID] = profile
    else
        -- Existing profile - backfill any keys added in newer addon versions.
        for k, v in pairs(defaults) do
            if profile[k] == nil then profile[k] = v end
        end
    end
    activeProfile = profile
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local _, playerClass    = UnitClass("player")
local trackedSpellID    = nil
local lastCheck         = 0
local outOfRange        = false
local ShowConfigMode                              -- forward declaration; defined below

-- ---------------------------------------------------------------------------
-- Spell resolution
-- ---------------------------------------------------------------------------
local function FindClassMeleeSpell()
    local list = CLASS_MELEE_SPELLS[playerClass]
    if not list then return nil end
    for _, id in ipairs(list) do
        if IsPlayerSpell(id) then
            return id
        end
    end
    return nil
end

-- Resolve a user-typed name or numeric ID into a spell ID.
local function ResolveSpellInput(input)
    if not input or input == "" then return nil end
    local query = tonumber(input) or input
    local info = C_Spell.GetSpellInfo(query)
    if info and info.spellID then
        return info.spellID
    end
    return nil
end

local function ResolveTrackedSpell()
    if OutOfRangeDB and activeProfile.useCustomSpell then
        local id = ResolveSpellInput(activeProfile.customSpell)
        if id then return id end
        -- invalid custom entry: fall through to the class default
    end
    return FindClassMeleeSpell()
end

local function RefreshTrackedSpell()
    trackedSpellID = ResolveTrackedSpell()
end

-- ---------------------------------------------------------------------------
-- Unit / range checks
--
-- The unit validity check intentionally does NOT enforce a hostility
-- requirement, because friendly-unit tracking (heals on mouseover, etc.) is
-- supported. C_Spell.IsSpellInRange returns nil when the spell isn't a
-- meaningful match for the unit (e.g. a hostile spell on a friendly target),
-- and we treat nil as in-range, so the unit/spell mismatch case is handled
-- naturally without explicit checks.
-- ---------------------------------------------------------------------------
local function HasValidUnit(unit)
    if not UnitExists(unit) then return false end
    if UnitIsDead(unit) then return false end
    if not UnitIsVisible(unit) then return false end
    return true
end

local function IsUnitInRange(unit)
    if not trackedSpellID then return true end
    local result = C_Spell.IsSpellInRange(trackedSpellID, unit)
    if result == nil then return true end           -- spell can't validly target this unit; don't alert
    return result
end

-- ---------------------------------------------------------------------------
-- Warning sounds and volume routing
--
-- WoW's sound API does not accept a per-call volume, so "volume" is exposed
-- to the user by letting them route the sound through a different audio
-- channel - SFX, Dialog, Ambience, Music or Master - each of which has its
-- own slider in Game Menu -> System -> Sound. Picking SFX (the default)
-- means the alert follows the player's normal in-game sound effects volume,
-- which is far quieter than the previous Master routing.
-- ---------------------------------------------------------------------------
-- Sounds are short OGG files bundled in the addon's Sounds/ folder. Playing
-- our own audio gives us total control over duration and character, instead
-- of relying on the in-game sound database.
local SOUND_PATH = [[Interface\AddOns\OutOfRange\Sounds\]]

local _RAW_SOUNDS = {
    { key = "BLEEP",  label = "Bleep (single tone, 80ms)",                   file = SOUND_PATH .. "bleep.ogg"  },
    { key = "BLOOP",  label = "Bloop (descending, 140ms)",                   file = SOUND_PATH .. "bloop.ogg"  },
    { key = "CHIRP",  label = "Chirp (rising sweep, 70ms)",                  file = SOUND_PATH .. "chirp.ogg"  },
    { key = "PIP",    label = "Pip (sharp tick, 45ms)",                      file = SOUND_PATH .. "pip.ogg"    },
    { key = "DING",   label = "Ding (small bell, 250ms)",                    file = SOUND_PATH .. "ding.ogg"   },
    -- Drier batch (square / triangle / noise, hard envelopes, no decay tails)
    { key = "BUZZ",   label = "Buzz (square wave, 60ms)",                    file = SOUND_PATH .. "buzz.ogg"   },
    { key = "TICK",   label = "Tick (dry noise click, 25ms)",                file = SOUND_PATH .. "tick.ogg"   },
    { key = "BOOP",   label = "Boop (low triangle, 80ms)",                   file = SOUND_PATH .. "boop.ogg"   },
    { key = "KNOCK",  label = "Knock (low thump, 35ms)",                     file = SOUND_PATH .. "knock.ogg"  },
    { key = "DOUBLE", label = "Double Tap (two quick blips, 110ms)",         file = SOUND_PATH .. "double.ogg" },
}

local SOUND_LIST   = {}
local SOUND_BY_KEY = {}
for _, s in ipairs(_RAW_SOUNDS) do
    if s.file then
        SOUND_LIST[#SOUND_LIST + 1] = s
        SOUND_BY_KEY[s.key] = s
    end
end

local CHANNELS = {
    { key = "SFX",      label = "Sound effects (SFX) - follows game SFX volume" },
    { key = "Dialog",   label = "Dialog - follows Dialog volume" },
    { key = "Ambience", label = "Ambient - follows Ambient volume" },
    { key = "Music",    label = "Music - follows Music volume" },
    { key = "Master",   label = "Always loud (Master) - ignores other sliders" },
}

ns.SOUND_LIST = SOUND_LIST
ns.CHANNELS   = CHANNELS

local function PlayWarningSound()
    local entry = SOUND_BY_KEY[activeProfile.soundKey or ""] or SOUND_LIST[1]
    if entry and entry.file and PlaySoundFile then
        PlaySoundFile(entry.file, activeProfile.soundChannel or "SFX")
    end
end

-- ---------------------------------------------------------------------------
-- Alert frame + animation
-- ---------------------------------------------------------------------------
local alertFrame = CreateFrame("Frame", "OutOfRangeFrame", UIParent, "BackdropTemplate")
alertFrame:SetSize(420, 56)
alertFrame:SetFrameStrata("HIGH")
alertFrame:SetMovable(true)
alertFrame:RegisterForDrag("LeftButton")
alertFrame:SetScript("OnDragStart", function(self)
    if not activeProfile.locked then self:StartMoving() end
end)
alertFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    activeProfile.point         = point
    activeProfile.relativePoint = relativePoint
    activeProfile.x             = x
    activeProfile.y             = y
end)
alertFrame:Hide()

local alertText = alertFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
alertText:SetAllPoints()
alertText:SetJustifyH("CENTER")
alertText:SetJustifyV("MIDDLE")

-- Close button that appears only while the frame is unlocked for positioning.
-- Clicking it locks the position (no slash command needed).
local closeBtn = CreateFrame("Button", nil, alertFrame, "UIPanelCloseButton")
closeBtn:SetSize(24, 24)
closeBtn:SetPoint("TOPRIGHT", alertFrame, "TOPRIGHT", 2, 2)
closeBtn:SetScript("OnClick", function()
    -- Route through SetUnlocked so the "reopen options on lock" logic fires
    -- if the user came from the options panel's Unlock button.
    if ns.API.SetUnlocked then ns.API.SetUnlocked(false) end
end)
closeBtn:Hide()

local pulse = alertFrame:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(1.0)
fade:SetToAlpha(0.3)
fade:SetDuration(0.35)
fade:SetSmoothing("IN_OUT")

-- One-shot flash used by the Test button (distinct from the looping alert pulse).
local flash = alertFrame:CreateAnimationGroup()
local flashIn = flash:CreateAnimation("Alpha")
flashIn:SetFromAlpha(0); flashIn:SetToAlpha(1); flashIn:SetDuration(0.12); flashIn:SetOrder(1)
local flashHold = flash:CreateAnimation("Alpha")
flashHold:SetFromAlpha(1); flashHold:SetToAlpha(1); flashHold:SetDuration(0.16); flashHold:SetOrder(2)
local flashOut = flash:CreateAnimation("Alpha")
flashOut:SetFromAlpha(1); flashOut:SetToAlpha(0); flashOut:SetDuration(0.32); flashOut:SetOrder(3)
flash:SetScript("OnFinished", function()
    alertFrame:SetAlpha(1)
    if not outOfRange then
        alertFrame:Hide()
    end
end)

local function ShowAlert()
    if outOfRange then return end
    outOfRange = true
    alertText:SetText(activeProfile.text)
    flash:Stop()
    alertFrame:SetAlpha(1)
    alertFrame:Show()
    pulse:Play()
    if activeProfile.soundEnabled then
        PlayWarningSound()
    end
end

local function HideAlert()
    if not outOfRange then return end
    outOfRange = false
    pulse:Stop()
    alertFrame:SetAlpha(1)
    if activeProfile.locked then
        alertFrame:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Update loop (throttled)
-- ---------------------------------------------------------------------------
local updater = CreateFrame("Frame")
updater:Hide()
updater:SetScript("OnUpdate", function(self, elapsed)
    lastCheck = lastCheck + elapsed
    if lastCheck < activeProfile.throttle then return end
    lastCheck = 0

    local unit = activeProfile.trackedUnit or "target"
    if (activeProfile.onlyInCombat and not UnitAffectingCombat("player"))
       or not HasValidUnit(unit) then
        -- Nothing worth watching right now. Stop the per-frame loop entirely;
        -- the events below restart it the moment a unit / combat reappears.
        self:Hide()
        HideAlert()
        return
    end

    if not trackedSpellID then
        RefreshTrackedSpell()
        if not trackedSpellID then return end
    end

    if IsUnitInRange(unit) then
        HideAlert()
    else
        ShowAlert()
    end
end)

-- ---------------------------------------------------------------------------
-- Polling gate
--
-- The OnUpdate loop above only needs to run when there is actually something
-- to range-check: the addon is enabled, the combat gate (if any) is met, and
-- the tracked unit exists / is alive / is visible. The rest of the time the
-- loop is fully stopped, so an idle player (no target, or out of combat in
-- combat-only mode) costs zero per-frame CPU. RefreshUpdater() is the single
-- place that starts or stops the loop; it's driven by ApplySettings and by
-- the target / focus / mouseover / combat events.
-- ---------------------------------------------------------------------------
local function ShouldPoll()
    if not (activeProfile and activeProfile.enabled) then return false end
    if activeProfile.onlyInCombat and not UnitAffectingCombat("player") then
        return false
    end
    return HasValidUnit(activeProfile.trackedUnit or "target")
end

local function RefreshUpdater()
    if ShouldPoll() then
        if not updater:IsShown() then
            lastCheck = activeProfile.throttle   -- range-check on the next frame
            updater:Show()
        end
    else
        updater:Hide()
        HideAlert()
    end
end

-- ---------------------------------------------------------------------------
-- Settings application
-- ---------------------------------------------------------------------------
local function ApplySettings()
    local db = activeProfile
    if not db then return end
    alertFrame:ClearAllPoints()
    alertFrame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
    alertFrame:SetScale(db.scale)
    alertText:SetText(db.text)

    RefreshUpdater()
end

function ShowConfigMode(on)
    if on then
        alertFrame:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile     = true,
            tileSize = 8,
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        alertFrame:SetBackdropColor(0, 0, 0, 0.6)
        alertFrame:EnableMouse(true)
        alertFrame:SetAlpha(1)
        alertFrame:Show()
        closeBtn:Show()
    else
        closeBtn:Hide()
        alertFrame:SetBackdrop(nil)
        alertFrame:EnableMouse(false)
        if not outOfRange then alertFrame:Hide() end
    end
end

-- ---------------------------------------------------------------------------
-- Public API (used by Options.lua)
-- ---------------------------------------------------------------------------
ns.API.ApplySettings     = ApplySettings
ns.API.RefreshSpell      = RefreshTrackedSpell
ns.API.GetTrackedSpellID = function() return trackedSpellID end
ns.API.GetPlayerClass    = function() return playerClass end
ns.API.PreviewSound      = PlayWarningSound

-- A brief one-shot flash so the player can preview placement / sound.
ns.API.TestAlert = function()
    if outOfRange then return end          -- a real alert is already showing
    if flash:IsPlaying() then return end
    alertText:SetText(activeProfile.text)
    alertFrame:SetAlpha(0)
    alertFrame:Show()
    flash:Play()
    if activeProfile.soundEnabled then
        PlayWarningSound()
    end
end

-- When the user clicks "Unlock frame to move" in the options panel, we hide
-- the settings UI so they can see what they're dragging. This flag remembers
-- that the unlock came from the options panel, so the X-button (or any other
-- lock action) can reopen options afterward. Slash-command unlocks
-- (`/oor unlock`) don't set this flag - typing a slash command doesn't imply
-- "and pop the settings panel back open when I'm done."
local reopenOptionsOnLock = false

ns.API.SetUnlocked = function(unlock, reopenOnLockFlag)
    activeProfile.locked = not unlock
    if unlock and reopenOnLockFlag then
        reopenOptionsOnLock = true
    end
    ShowConfigMode(unlock)
    if not unlock and reopenOptionsOnLock then
        reopenOptionsOnLock = false
        if ns.API.OpenOptions then ns.API.OpenOptions() end
    end
end

ns.API.ResetDefaults = function()
    -- Reset only the CURRENT spec's profile. Other profiles, the shared
    -- minimap state, and the LDBIcon db reference are left untouched.
    -- (A full nuke is available via /oor reset all.)
    local specID = CurrentSpecID()
    OutOfRangeDB.profiles = OutOfRangeDB.profiles or {}
    local fresh = {}
    for k, v in pairs(defaults) do fresh[k] = v end
    OutOfRangeDB.profiles[specID] = fresh
    activeProfile = fresh
    RefreshTrackedSpell()
    ApplySettings()
end

ns.API.ResetAllProfiles = function()
    -- Full wipe: every spec's profile plus the minimap state.
    OutOfRangeDB.profiles = {}
    local minimap = OutOfRangeDB.minimap
    if minimap then
        wipe(minimap)
        minimap.hide = false
    else
        OutOfRangeDB.minimap = { hide = false }
    end
    SetActiveProfile()
    RefreshTrackedSpell()
    ApplySettings()
    if LibStub then
        local LDBIcon = LibStub("LibDBIcon-1.0", true)
        if LDBIcon and LDBIcon:IsRegistered("OutOfRange") then
            LDBIcon:Refresh("OutOfRange", OutOfRangeDB.minimap)
        end
    end
end

-- Exposed so Options.lua and Minimap.lua can read profile data and react to
-- spec changes without holding their own reference (which would go stale
-- after a SetActiveProfile call on spec swap).
ns.API.GetActiveProfile  = function() return activeProfile end
ns.API.GetCurrentSpecName = GetCurrentSpecName

-- Resolve a name/ID for the options preview.
-- Returns: spellID, name, iconID, isKnownByPlayer  (or nil if unresolved)
ns.API.ResolveSpell = function(input)
    local id = ResolveSpellInput(input)
    if not id then return nil end
    local info = C_Spell.GetSpellInfo(id)
    if not info then return nil end
    return id, info.name, info.iconID, IsPlayerSpell(id)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_FOCUS_CHANGED")
events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        OutOfRangeDB = OutOfRangeDB or {}

        -- Schema migration (pre-1.10.0 -> 1.10.0): per-spec profiles arrive.
        -- Move any flat top-level settings into a profile bucket for the
        -- player's CURRENT spec; other specs will get fresh defaults the
        -- first time the player switches to them.
        if not OutOfRangeDB.profiles then
            local flat = {}
            for k, v in pairs(OutOfRangeDB) do
                if k ~= "minimap" and k ~= "schemaVersion" then
                    flat[k] = v
                end
            end
            for k in pairs(flat) do OutOfRangeDB[k] = nil end
            OutOfRangeDB.profiles = {}
            if next(flat) then
                OutOfRangeDB.profiles[CurrentSpecID()] = flat
            end
        end
        OutOfRangeDB.schemaVersion = 2

        -- Pick the active profile (creates it from defaults if this is a
        -- never-before-configured spec; backfills missing keys otherwise).
        SetActiveProfile()

        -- Per-profile migrations (idempotent, run every load).
        if not SOUND_BY_KEY[activeProfile.soundKey or ""] then
            activeProfile.soundKey = defaults.soundKey
        end
        activeProfile.tooCloseText = nil   -- removed in 1.8.2

        -- Shared (top-level) migrations: pre-1.7.0 minimap keys.
        OutOfRangeDB.minimap = OutOfRangeDB.minimap or {}
        if OutOfRangeDB.minimap.angle ~= nil
           and OutOfRangeDB.minimap.minimapPos == nil then
            OutOfRangeDB.minimap.minimapPos = OutOfRangeDB.minimap.angle
        end
        OutOfRangeDB.minimap.angle       = nil
        OutOfRangeDB.minimap.radiusNudge = nil

        ApplySettings()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Spec change: swap to the new spec's profile, then re-resolve the
        -- tracked spell and re-apply appearance / position / unlocked state.
        SetActiveProfile()
        RefreshTrackedSpell()
        ApplySettings()
        if ns.API.OnProfileChanged then ns.API.OnProfileChanged() end
    elseif event == "PLAYER_LOGIN"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "SPELLS_CHANGED" then
        RefreshTrackedSpell()
        RefreshUpdater()   -- start polling if we logged in / reloaded with a target
    elseif event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_FOCUS_CHANGED"
        or event == "UPDATE_MOUSEOVER_UNIT"
        or event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" then
        -- A trackable unit appeared/changed, or combat state flipped. Start
        -- the polling loop when there's now something to check, and stop it
        -- (clearing any alert) when there isn't. Reacting on the event rather
        -- than waiting for the throttled loop also makes the UI feel snappier.
        RefreshUpdater()
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_OUTOFRANGE1 = "/oor"
SLASH_OUTOFRANGE2 = "/outofrange"

local function Print(msg)
    print("|cff66ccffOutOfRange:|r " .. msg)
end
ns.Print = Print

SlashCmdList.OUTOFRANGE = function(msg)
    msg = strtrim(msg or ""):lower()
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")

    if cmd == "" or cmd == "config" or cmd == "options" then
        if ns.API.OpenOptions then
            ns.API.OpenOptions()
        else
            Print("Type |cffffff00/oor help|r for commands.")
        end
    elseif cmd == "help" then
        Print("Commands:")
        print("  |cffffff00/oor|r or |cffffff00/oor config|r - open the options panel")
        print("  |cffffff00/oor toggle|r - enable/disable the addon")
        print("  |cffffff00/oor sound|r  - toggle the warning sound")
        print("  |cffffff00/oor combat|r - only alert while in combat")
        print("  |cffffff00/oor unlock|r - drag the frame to reposition")
        print("  |cffffff00/oor lock|r   - finish positioning")
        print("  |cffffff00/oor scale <0.5-3>|r - adjust the warning size")
        print("  |cffffff00/oor test|r   - flash the alert once")
        print("  |cffffff00/oor reset|r  - reset the active spec's profile to defaults")
        print("  |cffffff00/oor reset all|r - wipe every profile and the minimap state")
        print("  |cffffff00/oor status|r - show what's being tracked (and which profile is active)")
    elseif cmd == "toggle" then
        activeProfile.enabled = not activeProfile.enabled
        ApplySettings()
        Print("Enabled: " .. tostring(activeProfile.enabled))
    elseif cmd == "sound" then
        activeProfile.soundEnabled = not activeProfile.soundEnabled
        Print("Sound: " .. tostring(activeProfile.soundEnabled))
    elseif cmd == "combat" then
        activeProfile.onlyInCombat = not activeProfile.onlyInCombat
        ApplySettings()
        Print("Only in combat: " .. tostring(activeProfile.onlyInCombat))
    elseif cmd == "unlock" then
        ns.API.SetUnlocked(true)
        Print("Drag to reposition. Click the |cffffff00X|r on the warning to lock it.")
    elseif cmd == "lock" then
        ns.API.SetUnlocked(false)
        Print("Position locked.")
    elseif cmd == "scale" then
        local n = tonumber(rest)
        if n and n >= 0.5 and n <= 3 then
            activeProfile.scale = n
            ApplySettings()
            Print("Scale: " .. n)
        else
            Print("Usage: /oor scale 0.5 to 3")
        end
    elseif cmd == "test" then
        ns.API.TestAlert()
    elseif cmd == "minimap" then
        local sub = string.match(rest or "", "^(%S+)")
        if sub == "show" then
            if ns.API.SetMinimapButtonShown then ns.API.SetMinimapButtonShown(true) end
            Print("Minimap button: |cff40ff40shown|r.")
        elseif sub == "hide" then
            if ns.API.SetMinimapButtonShown then ns.API.SetMinimapButtonShown(false) end
            Print("Minimap button: |cffaaaaaahidden|r.")
        elseif sub == "reset" then
            if OutOfRangeDB.minimap then
                OutOfRangeDB.minimap.minimapPos = nil
            end
            if LibStub then
                local LDBIcon = LibStub("LibDBIcon-1.0", true)
                if LDBIcon then LDBIcon:Refresh("OutOfRange", OutOfRangeDB.minimap) end
            end
            Print("Minimap button position reset.")
        else
            Print("Minimap commands:")
            Print("  |cffffff00/oor minimap show|r / |cffffff00hide|r")
            Print("  |cffffff00/oor minimap reset|r - reset position to default")
        end
    elseif cmd == "reset" then
        local sub = string.match(rest or "", "^(%S+)")
        if sub == "all" then
            ns.API.ResetAllProfiles()
            Print("All profiles reset.")
        else
            ns.API.ResetDefaults()
            Print(("Profile reset: |cffffff00%s|r."):format(GetCurrentSpecName()))
        end
    elseif cmd == "status" then
        Print("Active profile: |cffffff00" .. GetCurrentSpecName() .. "|r")
        Print("Enabled: " .. tostring(activeProfile.enabled))
        Print("Class: " .. playerClass)
        Print("Tracked unit: " .. (activeProfile.trackedUnit or "target"))
        Print("Mode: " .. (activeProfile.useCustomSpell and "custom ability" or "class default (melee)"))
        if trackedSpellID then
            local info = C_Spell.GetSpellInfo(trackedSpellID)
            Print(("Tracking via: %s (ID %d)"):format(info and info.name or "?", trackedSpellID))
        else
            Print("No ability resolved - addon is idle. Set one with |cffffff00/oor config|r.")
        end
    else
        Print("Unknown command. Try |cffffff00/oor help|r")
    end
end

-- ---------------------------------------------------------------------------
-- Addon compartment integration (the dropdown next to the minimap)
--
-- These three functions must be globals - Blizzard looks them up in _G by
-- the names declared in the .toc. Click opens options; right-click toggles
-- the addon on/off; hover shows a status tooltip.
-- ---------------------------------------------------------------------------
function OutOfRange_OnAddonCompartmentClick(_, buttonName)
    if buttonName == "RightButton" then
        activeProfile.enabled = not activeProfile.enabled
        ApplySettings()
        Print("Enabled: " .. tostring(activeProfile.enabled))
    else
        if ns.API.OpenOptions then ns.API.OpenOptions() end
    end
end

function OutOfRange_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:SetText("OutOfRange", 1, 1, 1)
    if activeProfile then
        GameTooltip:AddLine(
            activeProfile.enabled
                and "|cff40ff40Enabled|r"
                or  "|cffaaaaaaDisabled|r")
        if trackedSpellID then
            local info = C_Spell.GetSpellInfo(trackedSpellID)
            if info and info.name then
                GameTooltip:AddLine("Tracking: |cffffffff" .. info.name .. "|r",
                    0.8, 0.8, 0.8)
            end
        end
        GameTooltip:AddLine("Profile: |cffffd700" .. GetCurrentSpecName() .. "|r",
            0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffff00Left-click|r: open options",       0.7, 0.7, 0.7)
    GameTooltip:AddLine("|cffffff00Right-click|r: toggle on / off",   0.7, 0.7, 0.7)
    GameTooltip:Show()
end

function OutOfRange_OnAddonCompartmentLeave(_)
    GameTooltip:Hide()
end
