-- =============================================================================
--  OutOfRange  -  options panel
--
--  A scrollable canvas registered into the Blizzard Settings window.
--  Widgets are built with small helper constructors (AddHeader / AddCheckbox /
--  AddSlider / AddEditBox / AddDropdown / AddButton), so adding a future option
--  is a single call - the layout cursor and scroll height adjust automatically.
-- =============================================================================

local addonName, ns = ...

-- Forward declarations for things referenced inside callbacks before they exist.
local RefreshAll, UpdatePreview, abilityDropdown, soundDropdown, channelDropdown, previewButton, unitDropdown, profileLabel

-- Shorthand: access the currently active spec's profile. Always read through
-- this rather than holding a cached reference, because SetActiveProfile()
-- replaces the table on every spec change.
local function P()
    return (ns.API.GetActiveProfile and ns.API.GetActiveProfile()) or {}
end

-- ---------------------------------------------------------------------------
-- Color helpers for the warning-text color picker.
--
-- The warning text supports any WoW UI color escape `|cAARRGGBB...|r`. The
-- "Color..." button next to the text field opens Blizzard's standard
-- ColorPickerFrame (color wheel + RGB sliders + hex entry), and on confirm
-- the chosen color is wrapped around the existing text (with any old codes
-- stripped first so the new color cleanly replaces them).
-- ---------------------------------------------------------------------------

-- Strip ALL WoW UI color codes from a string.
local function StripColorCodes(s)
    s = s or ""
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    return s
end

-- Pull r,g,b (0..1) out of the first |cAARRGGBB code in `text`. Returns the
-- default warning red if no code is found.
local function ParseTextColor(text)
    local _, rs, gs, bs = (text or ""):match("|c(%x%x)(%x%x)(%x%x)(%x%x)")
    if not (rs and gs and bs) then return 1.0, 0.125, 0.125 end
    return tonumber(rs, 16) / 255, tonumber(gs, 16) / 255, tonumber(bs, 16) / 255
end

local function RGBToHex(r, g, b)
    return string.format("%02x%02x%02x",
        math.floor((r or 0) * 255 + 0.5),
        math.floor((g or 0) * 255 + 0.5),
        math.floor((b or 0) * 255 + 0.5))
end

-- ---------------------------------------------------------------------------
-- Panel + scroll container
-- ---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "OutOfRangeOptionsPanel")
panel.name = "OutOfRange"

local scroll = CreateFrame("ScrollFrame", "OutOfRangeOptionsScroll", panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 10, -10)
scroll:SetPoint("BOTTOMRIGHT", -30, 10)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(580, 100)
scroll:SetScrollChild(content)
scroll:SetScript("OnSizeChanged", function(_, w)
    if w and w > 0 then content:SetWidth(w) end
end)

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------
local LEFT     = 18           -- left inset for widgets
local y        = -14          -- running vertical cursor (negative = downward)
local widgets  = {}           -- everything with a :Refresh() method

local function HideTooltip()
    GameTooltip:Hide()
end

local function AddHeader(text)
    y = y - 8
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", LEFT, y)
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
    y = y - 22

    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", LEFT, y)
    line:SetPoint("TOPRIGHT", -18, y)
    y = y - 12
end

local function AddDescription(text)
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", LEFT, y)
    fs:SetWidth(520)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    y = y - (fs:GetStringHeight() + 10)
end

local function AddCheckbox(label, tooltip, getter, setter)
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", LEFT, y)
    cb:SetSize(26, 26)

    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    fs:SetText(label)

    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked() and true or false)
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", HideTooltip)
    end

    cb.Refresh = function() cb:SetChecked(getter() and true or false) end
    widgets[#widgets + 1] = cb
    y = y - 30
    return cb
end

local function AddSlider(label, minV, maxV, step, getter, setter)
    y = y - 4
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", LEFT, y)
    title:SetText(label)
    local valFS = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    y = y - 18

    local s = CreateFrame("Slider", nil, content)
    s:SetPoint("TOPLEFT", LEFT + 4, y)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(360, 18)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = s:GetThumbTexture()
    if thumb then thumb:SetSize(20, 20) end

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0, 0, 0, 0.45)
    track:SetHeight(6)
    track:SetPoint("LEFT", 4, 0)
    track:SetPoint("RIGHT", -4, 0)

    valFS:SetPoint("LEFT", s, "RIGHT", 14, 0)

    s:SetScript("OnValueChanged", function(_, v)
        valFS:SetText(string.format("%.2f", v))
        setter(v)
    end)
    s.Refresh = function()
        local v = getter() or minV
        s:SetValue(v)
        valFS:SetText(string.format("%.2f", v))
    end
    widgets[#widgets + 1] = s
    y = y - 32
    return s
end

local function AddEditBox(label, getter, setter, width)
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", LEFT, y)
    title:SetText(label)
    y = y - 20

    local eb = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    eb:SetPoint("TOPLEFT", LEFT + 6, y)
    eb:SetSize(width or 320, 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject("ChatFontNormal")

    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        setter(self:GetText())
    end)
    eb:SetScript("OnEditFocusLost", function(self) setter(self:GetText()) end)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if self.Refresh then self.Refresh() end
    end)

    eb.Refresh = function()
        eb:SetText(getter() or "")
        eb:SetCursorPosition(0)
    end
    widgets[#widgets + 1] = eb
    y = y - 32
    return eb
end

local function AddDropdown(label, width)
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    title:SetPoint("TOPLEFT", LEFT, y)
    title:SetText(label)
    y = y - 22

    local dd = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    dd:SetPoint("TOPLEFT", LEFT + 6, y)
    dd:SetSize(width or 340, 30)
    y = y - 40
    return dd
end

local function AddButton(label, onClick, width)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", LEFT + 6, y)
    b:SetSize(width or 160, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    y = y - 32
    return b
end

local function AddGap(px)
    y = y - (px or 10)
end

-- ---------------------------------------------------------------------------
-- Range / spellbook helpers
-- ---------------------------------------------------------------------------
local function RangeText(minR, maxR)
    minR = minR or 0
    maxR = maxR or 0
    if maxR <= 0 then
        return "melee"
    elseif minR > 0 then
        return string.format("%d-%d yd", minR, maxR)
    else
        return string.format("%d yd", maxR)
    end
end

-- Spellbook scan -> list of skills that have a distance limit (maxRange > 0).
local spellList = {}

local function RebuildSpellList()
    wipe(spellList)
    if not C_SpellBook or not C_SpellBook.GetNumSpellBookSkillLines then return end

    local bank     = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local SPELL_T  = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
    local seen     = {}

    for line = 1, numLines do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
        -- Filter to ACTIVE-spec lines only:
        --   * isGuild       - guild perks, not our class
        --   * shouldHide    - flagged by Blizzard to be invisible (off-spec residue)
        --   * offSpecID > 0 - the line belongs to a non-active specialization
        local lineOK = lineInfo
            and not lineInfo.isGuild
            and not lineInfo.shouldHide
            and (not lineInfo.offSpecID or lineInfo.offSpecID == 0)
        if lineOK then
            local offset = lineInfo.itemIndexOffset or 0
            local count  = lineInfo.numSpellBookItems or 0
            for i = offset + 1, offset + count do
                local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                local typeOK = (not SPELL_T) or (item and item.itemType == SPELL_T)
                if item and item.spellID and not item.isPassive and typeOK then
                    local id = item.spellID
                    -- Second filter: IsPlayerSpell returns true only for spells
                    -- the player actually has access to in the current spec
                    -- (including talented). Catches anything that slips past
                    -- the line-level filter above.
                    if not seen[id] and IsPlayerSpell(id) then
                        seen[id] = true
                        local info = C_Spell.GetSpellInfo(id)
                        local maxR = (info and info.maxRange) or 0
                        local minR = (info and info.minRange) or 0
                        -- Only skills that actually have a distance limit.
                        if maxR > 0 then
                            local name = (info and info.name) or item.name or ("Spell " .. id)
                            spellList[#spellList + 1] = {
                                id    = id,
                                name  = name,
                                icon  = (info and info.iconID) or item.iconID,
                                minR  = minR,
                                maxR  = maxR,
                                label = string.format("%s  (%s)", name, RangeText(minR, maxR)),
                            }
                        end
                    end
                end
            end
        end
    end

    table.sort(spellList, function(a, b) return a.name < b.name end)
end

-- Menu generator for the skill dropdown (skills only - auto-detect is a checkbox).
local function GenerateAbilityMenu(_, root)
    -- Build the list right here, every time the menu is generated. This keeps
    -- it always fresh - across spec changes, newly learned spells, etc. - and
    -- avoids a first-open race where the generator runs before the panel's
    -- OnShow handler has had a chance to populate the list.
    RebuildSpellList()

    root:CreateTitle("Skills with a distance limit")

    if #spellList == 0 then
        local none = root:CreateButton("(no skills found)", function() end)
        if none and none.SetEnabled then none:SetEnabled(false) end
        return
    end

    for _, s in ipairs(spellList) do
        root:CreateRadio(s.label,
            function()
                return P().customSpell == tostring(s.id)
            end,
            function()
                P().useCustomSpell = true
                P().customSpell    = tostring(s.id)
                ns.API.RefreshSpell()
                UpdatePreview()
                -- Refresh the closed-dropdown text next frame (menu is shut by then).
                C_Timer.After(0, function()
                    if abilityDropdown then abilityDropdown:GenerateMenu() end
                end)
            end)
    end
end

-- Menu generators for the sound + volume-channel dropdowns.
local function GenerateSoundMenu(_, root)
    root:CreateTitle("Warning sound")
    for _, s in ipairs(ns.SOUND_LIST or {}) do
        local key = s.key
        root:CreateRadio(s.label,
            function() return P().soundKey == key end,
            function()
                P().soundKey = key
                C_Timer.After(0, function()
                    if soundDropdown then soundDropdown:GenerateMenu() end
                end)
            end)
    end
end

local function GenerateChannelMenu(_, root)
    root:CreateTitle("Sound channel / volume routing")
    for _, c in ipairs(ns.CHANNELS or {}) do
        local key = c.key
        root:CreateRadio(c.label,
            function() return P().soundChannel == key end,
            function()
                P().soundChannel = key
                C_Timer.After(0, function()
                    if channelDropdown then channelDropdown:GenerateMenu() end
                end)
            end)
    end
end

local function GenerateUnitMenu(_, root)
    root:CreateTitle("Track range to which unit")
    for _, u in ipairs(ns.UNIT_OPTIONS or {}) do
        local key = u.key
        root:CreateRadio(u.label,
            function() return (P().trackedUnit or "target") == key end,
            function()
                P().trackedUnit = key
                C_Timer.After(0, function()
                    if unitDropdown then unitDropdown:GenerateMenu() end
                end)
            end)
    end
end

-- ===========================================================================
-- Profile label  (shows which spec's settings are currently being edited)
-- ===========================================================================
profileLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
profileLabel:SetPoint("TOPLEFT", LEFT, y)
profileLabel:SetTextColor(0.45, 0.85, 1)   -- light blue, distinct from section headers
profileLabel:SetText("Configuring profile: ...")
y = y - 26

local function UpdateProfileLabel()
    local name = (ns.API.GetCurrentSpecName and ns.API.GetCurrentSpecName()) or "?"
    profileLabel:SetText(string.format("Configuring profile: |cffffd700%s|r", name))
end

-- ===========================================================================
-- General
-- ===========================================================================
AddHeader("General")

AddCheckbox("Enable OutOfRange",
    "Master on/off switch for the range alert.",
    function() return P().enabled end,
    function(v) P().enabled = v; ns.API.ApplySettings() end)

AddCheckbox("Only alert while in combat",
    "Suppress the warning unless you are in combat.",
    function() return P().onlyInCombat end,
    function(v) P().onlyInCombat = v end)

AddCheckbox("Show minimap button",
    "Show a draggable button on the edge of the minimap. Left-click opens this panel, right-click toggles the addon on/off.",
    function() return ns.API.IsMinimapButtonShown and ns.API.IsMinimapButtonShown() end,
    function(v) if ns.API.SetMinimapButtonShown then ns.API.SetMinimapButtonShown(v) end end)

AddCheckbox("Play warning sound",
    "Play a sound the moment your target leaves range. Off by default.",
    function() return P().soundEnabled end,
    function(v) P().soundEnabled = v; RefreshAll() end)

soundDropdown = AddDropdown("Sound", 300)
soundDropdown:SetDefaultText("Choose a sound")
soundDropdown:SetupMenu(GenerateSoundMenu)
soundDropdown.Refresh = function() soundDropdown:GenerateMenu() end
widgets[#widgets + 1] = soundDropdown

channelDropdown = AddDropdown("Volume  (which game audio slider controls it)", 360)
channelDropdown:SetDefaultText("Choose a channel")
channelDropdown:SetupMenu(GenerateChannelMenu)
channelDropdown.Refresh = function() channelDropdown:GenerateMenu() end
widgets[#widgets + 1] = channelDropdown

previewButton = AddButton("Preview sound", function()
    if ns.API.PreviewSound then ns.API.PreviewSound() end
end, 160)

-- ===========================================================================
-- Appearance
-- ===========================================================================
AddHeader("Appearance")

AddSlider("Warning size", 0.5, 3.0, 0.1,
    function() return P().scale end,
    function(v) P().scale = v; ns.API.ApplySettings() end)

AddSlider("Update interval (seconds)  -  lower is more responsive", 0.05, 0.5, 0.05,
    function() return P().throttle end,
    function(v) P().throttle = v end)

local textEditBox = AddEditBox("Warning text  (UI color codes supported)",
    function() return P().text end,
    function(v) P().text = v; ns.API.ApplySettings() end, 360)

-- Helper used by the color picker: write a new RGB color into the warning
-- text, replacing any color codes already there.
local function ApplyWarningColor(r, g, b)
    local stripped = StripColorCodes(P().text or "")
    if stripped == "" then stripped = "! OUT OF RANGE !" end  -- don't strand the user with empty text
    local newText = "|cff" .. RGBToHex(r, g, b) .. stripped .. "|r"
    P().text = newText
    if textEditBox then
        textEditBox:SetText(newText)
        textEditBox:SetCursorPosition(0)
    end
    if ns.API.ApplySettings then ns.API.ApplySettings() end
end

-- "Color..." button opens the standard Blizzard ColorPickerFrame.
-- Drag any slider for live preview; OK confirms, Cancel restores the
-- text the user had before opening.
local colorBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
colorBtn:SetPoint("LEFT", textEditBox, "RIGHT", 12, 0)
colorBtn:SetSize(82, 22)
colorBtn:SetText("Color...")
colorBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Warning color", 1, 1, 1)
    GameTooltip:AddLine(
        "Opens a color picker with wheel, RGB sliders, and hex entry. "
        .. "Drag any slider for live preview; Cancel restores the previous color.",
        0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
colorBtn:SetScript("OnLeave", HideTooltip)

colorBtn:SetScript("OnClick", function()
    if not ColorPickerFrame then return end

    local originalText = P().text
    local r, g, b      = ParseTextColor(originalText)

    local function swatchFunc()
        local rr, gg, bb = ColorPickerFrame:GetColorRGB()
        ApplyWarningColor(rr, gg, bb)
    end

    local function cancelFunc()
        P().text = originalText
        if textEditBox then
            textEditBox:SetText(originalText or "")
            textEditBox:SetCursorPosition(0)
        end
        if ns.API.ApplySettings then ns.API.ApplySettings() end
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        -- Modern (Dragonflight onward) API: pass everything as a spec table.
        ColorPickerFrame:SetupColorPickerAndShow({
            r          = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = swatchFunc,
            cancelFunc = cancelFunc,
        })
    else
        -- Legacy fallback. Should never trigger on Midnight (12.x)
        -- but keeps the picker working on older clients if anyone backports.
        ColorPickerFrame.func        = swatchFunc
        ColorPickerFrame.cancelFunc  = cancelFunc
        ColorPickerFrame.hasOpacity  = false
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()  -- force OnShow to fire fresh
        ColorPickerFrame:Show()
    end
end)

AddButton("Unlock frame to move", function()
    ns.API.SetUnlocked(true, true)   -- second arg = reopen options when the user locks
    if SettingsPanel then HideUIPanel(SettingsPanel) end
    ns.Print("Drag the warning where you want it, then click the |cffffff00X|r in its corner to lock it.")
end, 200)

-- ===========================================================================
-- Trigger Ability
-- ===========================================================================
AddHeader("Trigger Ability")

AddDescription("Choose which unit to range-check against, then pick the ability "
    .. "to use as the range yardstick. The alert fires when the unit is beyond "
    .. "the ability's max range.")

unitDropdown = AddDropdown("Track range to", 240)
unitDropdown:SetDefaultText("Choose a unit")
unitDropdown:SetupMenu(GenerateUnitMenu)
unitDropdown.Refresh = function() unitDropdown:GenerateMenu() end
widgets[#widgets + 1] = unitDropdown

AddCheckbox("Auto-detect my class's melee ability",
    "When ticked, OutOfRange tracks a melee ability chosen automatically for your "
    .. "current spec. Untick to pick a specific skill from the dropdown below.",
    function() return not P().useCustomSpell end,
    function(v)
        P().useCustomSpell = not v
        ns.API.RefreshSpell()
        RefreshAll()
    end)

abilityDropdown = AddDropdown("Tracked skill", 340)
abilityDropdown:SetDefaultText("Select a skill")
abilityDropdown:SetupMenu(GenerateAbilityMenu)
abilityDropdown.Refresh = function() abilityDropdown:GenerateMenu() end
widgets[#widgets + 1] = abilityDropdown

-- Live preview: icon + resolved name + range + status.
local previewIcon = content:CreateTexture(nil, "ARTWORK")
previewIcon:SetSize(22, 22)
previewIcon:SetPoint("TOPLEFT", LEFT + 6, y)
local previewText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
previewText:SetPoint("LEFT", previewIcon, "RIGHT", 8, 0)
previewText:SetWidth(460)
previewText:SetJustifyH("LEFT")
y = y - 36

-- ===========================================================================
-- Tools
-- ===========================================================================
AddHeader("Tools")

AddButton("Test alert", function()
    ns.API.TestAlert()
end, 160)

AddButton("Reset this profile to defaults", function()
    ns.API.ResetDefaults()
    RefreshAll()
    ns.Print(("Profile reset: |cffffff00%s|r."):format(ns.API.GetCurrentSpecName and ns.API.GetCurrentSpecName() or "?"))
end, 240)

AddButton("Reset ALL profiles", function()
    if ns.API.ResetAllProfiles then ns.API.ResetAllProfiles() end
    RefreshAll()
    ns.Print("All profiles reset.")
end, 200)

AddGap(16)

-- Lock in the scroll height now that every widget has been placed.
content:SetHeight(-y + 20)

-- ===========================================================================
-- Refresh logic
-- ===========================================================================
function UpdatePreview()
    if not OutOfRangeDB then return end

    if P().useCustomSpell then
        local input = P().customSpell
        if not input or input == "" then
            previewIcon:SetTexture(nil)
            previewText:SetText("|cffaaaaaaNo skill chosen - falling back to class default.|r")
            return
        end
        local id, name, icon, known = ns.API.ResolveSpell(input)
        if not id then
            previewIcon:SetTexture(134400) -- question mark icon
            previewText:SetText("|cffff4040Selected skill could not be resolved.|r")
        else
            local info = C_Spell.GetSpellInfo(id)
            local rtxt = info and RangeText(info.minRange, info.maxRange) or "?"
            previewIcon:SetTexture(icon)
            if known then
                previewText:SetText(string.format("%s (%s)  |cff40ff40(tracking range)|r", name, rtxt))
            else
                previewText:SetText(string.format("%s (%s)  |cffff8800(you don't know this - it won't alert)|r", name, rtxt))
            end
        end
    else
        local id = ns.API.GetTrackedSpellID()
        if id then
            local info = C_Spell.GetSpellInfo(id)
            local rtxt = info and RangeText(info.minRange, info.maxRange) or "?"
            previewIcon:SetTexture(info and info.iconID or nil)
            previewText:SetText(string.format("%s (%s)  |cffaaaaaa(class default)|r",
                (info and info.name) or "?", rtxt))
        else
            previewIcon:SetTexture(nil)
            previewText:SetText("|cffaaaaaaNo melee ability for your class - untick the box and pick a skill.|r")
        end
    end
end

function RefreshAll()
    if not OutOfRangeDB then return end
    UpdateProfileLabel()
    for _, w in ipairs(widgets) do
        if w.Refresh then w.Refresh() end
    end
    -- The skill dropdown is only usable when auto-detect is off.
    if abilityDropdown and abilityDropdown.SetEnabled then
        abilityDropdown:SetEnabled(P().useCustomSpell and true or false)
    end
    -- Sound widgets follow the soundEnabled checkbox.
    local soundOn = P().soundEnabled and true or false
    if soundDropdown   and soundDropdown.SetEnabled   then soundDropdown:SetEnabled(soundOn)   end
    if channelDropdown and channelDropdown.SetEnabled then channelDropdown:SetEnabled(soundOn) end
    if previewButton   and previewButton.SetEnabled   then previewButton:SetEnabled(soundOn)   end
    UpdatePreview()
end

-- Called by OutOfRange.lua's PLAYER_SPECIALIZATION_CHANGED handler so the
-- panel reflects the new spec's profile while it's open.
ns.API.OnProfileChanged = function()
    if panel and panel:IsShown() then
        RefreshAll()
    end
end

panel:SetScript("OnShow", function()
    RefreshAll()
end)
panel.OnDefault = function()
    ns.API.ResetDefaults()
    RefreshAll()
end
panel.OnRefresh = RefreshAll

-- ===========================================================================
-- Register with the Blizzard Settings window
-- ===========================================================================
if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "OutOfRange")
    Settings.RegisterAddOnCategory(category)

    ns.API.OpenOptions = function()
        Settings.OpenToCategory(category:GetID())
    end
end
