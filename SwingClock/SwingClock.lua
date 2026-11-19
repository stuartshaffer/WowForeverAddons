--[[
SwingClock
----------
Circular clock / pie-chart weapon swing timer for World of Warcraft: Forever.

Visual behavior:
  * 12 o'clock is the ready position.
  * While a weapon swing is recovering, a slightly opaque yellow pie slice fills
    clockwise from 12 o'clock all the way around to 12 o'clock.
  * When the timer reaches 12 o'clock (swing ready), the entire circle turns green
    and stays fully green while waiting for your next attack to fire.
  * When an attack fires (passing 12 o'clock), a subtle green pulse/glow radiates
    from the clock to confirm the swing happened.
  * Automatically shows an inner concentric ring when dual-wielding an off-hand
    weapon, and tracks Ranged (Auto Shot / Wand) swings on the clock face.
  * Optionally hides Blizzard's built-in cast-bar swing timer (showSwingTimer=0).
]]

local ADDON_NAME = ...

local TEX_DIR         = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Textures\\"
local TEX_DISC        = TEX_DIR .. "CircleDisc"
local TEX_BEZEL       = TEX_DIR .. "ClockBezel"
local TEX_INNER       = TEX_DIR .. "InnerRing"
local TEX_INNER_EDGE  = TEX_DIR .. "InnerRingBorder"
local TEX_PULSE       = TEX_DIR .. "PulseGlow"
local TEX_PIP         = TEX_DIR .. "Pip"
local TEX_SEAL_BOX    = TEX_DIR .. "SealBoxBezel"
local TEX_PIP_RING    = TEX_DIR .. "PipRing"

local SWING_MH, SWING_OH, SWING_RANGED = 0, 1, 2

local UNSEALED_WRATH_SPELL_ID = 1310735
local MAX_ECHO_STACKS         = 3

-- WoW Forever Unsealed Wrath Echo buffs (verified from DBCache.bin)
local ECHO_SPELL_IDS = {
    [1311701] = 135957, -- Echo of Fury (Seal of Fury)
    [1311703] = 132347, -- Echo of Command (Seal of Command)
    [1311704] = 132325, -- Echo of Righteousness (Seal of Righteousness)
    [1311705] = 135971, -- Echo of Justice (Seal of Justice)
    [1328198] = 135917, -- Echo of Light (Seal of Light)
    [1328206] = 135960, -- Echo of Wisdom (Seal of Wisdom)
}
local ECHO_SPELL_LIST = { 1311704, 1311703, 1311701, 1311705, 1328198, 1328206 }

-- Paladin Seal buff spell IDs across all Classic, TBC & WoW Forever ranks
local SEAL_SPELL_IDS = {
    -- Seal of Righteousness
    [20154] = 132325, [21084] = 132325, [20287] = 132325, [20288] = 132325,
    [20289] = 132325, [20290] = 132325, [20291] = 132325, [20292] = 132325, [20293] = 132325,
    [25742] = 132325, [25740] = 132325, [25713] = 132325,
    -- Seal of Command
    [20375] = 132347, [20915] = 132347, [20918] = 132347, [20919] = 132347, [20920] = 132347,
    [20424] = 132347, [27170] = 132347,
    -- Seal of Fury (WoW Forever custom Seal IDs 1311648..1311660) & Seal of the Crusader
    [1311648] = 135957, [1311649] = 135957, [1311650] = 135957, [1311651] = 135957,
    [1311652] = 135957, [1311653] = 135957, [1311654] = 135957, [1311655] = 135957,
    [1311656] = 135957, [1311657] = 135957, [1311658] = 135957, [1311659] = 135957, [1311660] = 135957,
    [21082] = 135957, [20162] = 135957, [20305] = 135957, [20306] = 135957, [20307] = 135957, [20308] = 135957,
    [27158] = 135957, [20163] = 135957, [20232] = 135957, [20419] = 135957, [20421] = 135957, [20422] = 135957, [20423] = 135957,
    -- Seal of Justice
    [20164] = 135971, [31895] = 135971,
    -- Seal of Light
    [20165] = 135917, [20347] = 135917, [20348] = 135917, [20349] = 135917, [27160] = 135917,
    -- Seal of Wisdom
    [20166] = 135960, [20356] = 135960, [20357] = 135960, [27166] = 135960,
}
local SEAL_SPELL_LIST = {
    20154, 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293, 25742, 25740, 25713,
    20375, 20915, 20918, 20919, 20920, 20424, 27170,
    1311649, 1311648, 1311650, 1311651, 1311652, 1311653, 1311654, 1311655, 1311656, 1311657, 1311658, 1311659, 1311660,
    21082, 20162, 20305, 20306, 20307, 20308, 27158, 20163, 20232, 20419, 20421, 20422, 20423,
    20164, 31895,
    20165, 20347, 20348, 20349, 27160,
    20166, 20356, 20357, 27166,
}
local HOLY_STRIKE_SPELL_IDS = {
    [678] = true, [679] = true, [680] = true, [1866] = true,
    [2495] = true, [5569] = true, [10332] = true, [10333] = true,
}
local SEAL_NAMES_LIST = {
    "Seal of Righteousness",
    "Seal of Command",
    "Seal of Fury",
    "Seal of the Crusader",
    "Seal of Justice",
    "Seal of Light",
    "Seal of Wisdom",
}
local ECHO_NAMES_LIST = {
    "Echo of Righteousness",
    "Echo of Command",
    "Echo of Fury",
    "Echo of Justice",
    "Echo of Light",
    "Echo of Wisdom",
}

local DEFAULTS = {
    enabled         = true,
    locked          = true,     -- click-through when locked so right-click camera turning is never blocked
    visualVersion   = 3,        -- v3 doubles default clock size (68 -> 136) & adds Paladin Seal / Unsealed Wrath UI
    snapToGrid      = true,     -- show alignment grid when unlocked & snap to grid intersections + center axes
    gridSize        = 20,       -- spacing in pixels between grid lines centered on screen (0, 0)
    snapThreshold   = 14,       -- pixel capture distance for screen center lines (X=0, Y=0)
    size            = 136,      -- clock diameter in pixels (doubled from original 68)
    point           = "CENTER",
    relPoint        = "CENTER",
    x               = 0,
    y               = -150,
    visibility      = "always", -- "always" | "combat" | "target"
    hideBlizzardBar = true,     -- set CVar showSwingTimer = 0 while enabled
    showOffHand     = true,     -- inner concentric ring when dual-wielding
    showRanged      = true,     -- Auto Shot / Shoot (Wand) support
    parryHaste      = true,     -- advance MH timer on player PARRY
    drawEdge        = true,     -- subtle clock-hand edge line on filling pie slice
    showText        = false,    -- optional remaining seconds text in center
    yellowAlpha     = 0.74,     -- opacity of the filling yellow pie slice
    readyAlpha      = 0.86,     -- opacity of the full green ready circle
    bgAlpha         = 0.74,     -- opacity of the dark warm umber dial behind the filling pie
    pulseStrength   = 1.00,     -- 0.0 (off) .. 2.0 (strong), 1.0 = subtle green pulse
    fillColor       = { r = 1.00, g = 0.82, b = 0.16 },
    ohFillColor     = { r = 1.00, g = 0.88, b = 0.28 },
    readyColor      = { r = 0.18, g = 0.78, b = 0.28 },
    pulseColor      = { r = 0.24, g = 0.96, b = 0.44 },
}

local PULSE_DURATION    = 0.36
local OH_PULSE_DURATION = 0.28

local db
local clockFrame, configFrame, optionsPanel, gridFrame
local pendingCVars = false
local hasNativePlayerSwing = false
local hasOffHandWeapon = false
local isEditModeOpen = false
local testTimers = {}
local testDualPreview = false
local testPaladinPreview = false
local isPaladinClass = false
local hasUnsealedWrath = false
local dragState = { active = false, startCurX = 0, startCurY = 0, startOffX = 0, startOffY = 0 }

local mhState = { active = false, startTime = 0, duration = 0, speed = 0, pulseTime = -1 }
local ohState = { active = false, startTime = 0, duration = 0, speed = 0, pulseTime = -1 }
local sealState = { active = false, icon = nil, duration = 0, expirationTime = 0, spellID = nil, auraInstanceID = nil }
local echoState = { active = false, icon = nil, stacks = 0, duration = 0, expirationTime = 0, spellID = nil, auraInstanceID = nil }

local function Print(msg)
    print("|cff33ff66SwingClock|r: " .. tostring(msg))
end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function CopyTable(src)
    local out = {}
    for k, v in pairs(src) do
        out[k] = type(v) == "table" and CopyTable(v) or v
    end
    return out
end

---------------------------------------------------------------------------
-- CVar Management (Blizzard's built-in showSwingTimer cast bar)
---------------------------------------------------------------------------
local function GetCV(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar and GetCVar(name)
end

local function SetCV(name, value)
    if GetCV(name) == nil then return false end
    local ok = pcall(function()
        if C_CVar and C_CVar.SetCVar then
            C_CVar.SetCVar(name, value)
        elseif SetCVar then
            SetCVar(name, value)
        end
    end)
    return ok
end

local function ApplyBlizzardBarCVar()
    if not db then return end
    if InCombatLockdown and InCombatLockdown() then
        pendingCVars = true
        return
    end
    local cur = GetCV("showSwingTimer")
    if cur == nil then return end

    if db.enabled and db.hideBlizzardBar then
        if db.savedShowSwingTimer == nil then
            db.savedShowSwingTimer = cur
        end
        if cur ~= "0" then
            SetCV("showSwingTimer", "0")
        end
    elseif db.savedShowSwingTimer ~= nil then
        SetCV("showSwingTimer", db.savedShowSwingTimer)
        db.savedShowSwingTimer = nil
    end
end

---------------------------------------------------------------------------
-- Weapon Speed & Off-Hand Detection (Secret-Safe)
---------------------------------------------------------------------------
local function SafePositiveNumber(v)
    if v == nil or IsSecret(v) or type(v) ~= "number" then return nil end
    if v > 0 then return v end
    return nil
end

local function GetPlayerWeaponSpeeds()
    if not UnitAttackSpeed then return nil, nil end
    local ok, mh, oh = pcall(UnitAttackSpeed, "player")
    if not ok then return nil, nil end
    return SafePositiveNumber(mh), SafePositiveNumber(oh)
end

local function GetPlayerRangedSpeed()
    if not UnitRangedDamage then return nil end
    local ok, speed = pcall(UnitRangedDamage, "player")
    if not ok then return nil end
    return SafePositiveNumber(speed)
end

local UpdateOffHandVisibility, UpdatePaladinUI, RefreshPaladinStatus, RefreshPaladinAuras, EnsureLoopRunning -- forward declarations

local function RefreshOffHandStatus()
    local _, ohSpeed = GetPlayerWeaponSpeeds()
    local nowHasOH = (ohSpeed ~= nil)
    if nowHasOH ~= hasOffHandWeapon then
        hasOffHandWeapon = nowHasOH
        if not hasOffHandWeapon and not testDualPreview then
            ohState.active = false
            ohState.pulseTime = -1
        end
        if UpdateOffHandVisibility then UpdateOffHandVisibility() end
    end
end

---------------------------------------------------------------------------
-- Paladin Class, Unsealed Wrath Talent & Seal / Echo Aura Tracking
---------------------------------------------------------------------------
local SEAL_NAME_ICONS = {
    ["righteousness"] = 132325,
    ["command"]       = 132347,
    ["fury"]          = 135957,
    ["crusader"]      = 135957,
    ["justice"]       = 135971,
    ["light"]         = 135917,
    ["wisdom"]        = 135960,
}

local UNSEALED_WRATH_DEF_ID = 273096

local pendingSealCast = nil
local prevSealSnapshot = nil
local paladinHooksInstalled = false
local lastHolyStrikeTime = 0
local lastTargetAvoidTime = 0
local lastKnownBuffCount = nil
local pendingEchoSwingToken = 0
local debugMode = false
local lastMHSwingTime = 0
local debugLines = {}
local debugStartTime = 0
local debugFrame = nil

local function RefreshDebugWindow()
    if not debugFrame or not debugFrame.editBox then return end
    debugFrame.editBox:SetText(table.concat(debugLines, "\n"))
    if debugFrame.scrollFrame and debugFrame.scrollFrame.UpdateScrollChildRect then
        debugFrame.scrollFrame:UpdateScrollChildRect()
    end
    if debugFrame.scrollFrame and debugFrame.scrollFrame.GetVerticalScrollRange then
        debugFrame.scrollFrame:SetVerticalScroll(debugFrame.scrollFrame:GetVerticalScrollRange() or 0)
    end
end

local function DebugLog(msg)
    if not debugMode then return end
    local now = GetTime()
    if debugStartTime == 0 then debugStartTime = now end
    debugLines[#debugLines + 1] = ("[%06.3f] %s"):format(now - debugStartTime, tostring(msg))
    if #debugLines > 200 then
        table.remove(debugLines, 1)
    end
    RefreshDebugWindow()
end

local function GetOrCreateDebugWindow()
    if debugFrame then return debugFrame end

    local f = CreateFrame("Frame", "SwingClockDebugFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(440, 280)
    f:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
        f:SetBackdropBorderColor(0.65, 0.52, 0.25, 1)
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    title:SetText("SwingClock Debug Log")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        debugMode = false
        f:Hide()
    end)

    local selectBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    selectBtn:SetSize(82, 20)
    selectBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -4, -4)
    selectBtn:SetText("Select All")
    selectBtn:SetScript("OnClick", function()
        if f.editBox then
            f.editBox:SetFocus()
            f.editBox:HighlightText()
        end
    end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(64, 20)
    clearBtn:SetPoint("RIGHT", selectBtn, "LEFT", -6, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        wipe(debugLines)
        debugStartTime = GetTime()
        RefreshDebugWindow()
    end)

    local scroll = CreateFrame("ScrollFrame", "SwingClockDebugScrollFrame", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 10)
    f.scrollFrame = scroll

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(395)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function()
        scroll:UpdateScrollChildRect()
    end)
    scroll:SetScrollChild(eb)
    f.editBox = eb

    debugFrame = f
    return f
end

local function FallbackIconForAura(name, spellID)
    if spellID then
        if ECHO_SPELL_IDS[spellID] then return ECHO_SPELL_IDS[spellID] end
        if SEAL_SPELL_IDS[spellID] then return SEAL_SPELL_IDS[spellID] end
    end
    if type(name) == "string" then
        local lower = name:lower()
        for key, iconID in pairs(SEAL_NAME_ICONS) do
            if lower:find(key, 1, true) then
                return iconID
            end
        end
    end
    return 132325
end

local function IsHolyStrikeSpell(spellID, spellName)
    if spellID and not IsSecret(spellID) and type(spellID) == "number" then
        if HOLY_STRIKE_SPELL_IDS[spellID] then
            return true
        end
        if C_Spell and C_Spell.GetSpellName then
            local okN, n = pcall(C_Spell.GetSpellName, spellID)
            if okN and not IsSecret(n) and type(n) == "string" and n:lower() == "holy strike" then
                HOLY_STRIKE_SPELL_IDS[spellID] = true
                return true
            end
        end
    end
    if spellName and not IsSecret(spellName) and type(spellName) == "string" then
        if spellName:lower() == "holy strike" then
            if spellID and not IsSecret(spellID) and type(spellID) == "number" then
                HOLY_STRIKE_SPELL_IDS[spellID] = true
            end
            return true
        end
    end
    return false
end

local function MarkHolyStrikeCast()
    lastHolyStrikeTime = GetTime()
    pendingEchoSwingToken = pendingEchoSwingToken + 1
end

-- Applies a landed white MH swing to Unsealed Wrath Echo stacks in combat when C_UnitAuras is secret.
-- (Filtered to exclude Holy Strike and target MISS/PARRY/DODGE/EVADE/IMMUNE.)
local function ApplyCombatEchoSwingHit()
    if not isPaladinClass or not hasUnsealedWrath or testPaladinPreview then return end
    local now = GetTime()
    if (now - lastHolyStrikeTime) < 0.35 then return end
    if (now - lastTargetAvoidTime) < 0.25 then return end

    if echoState.active and (not sealState.active or sealState.icon ~= echoState.icon) then
        -- Landing an attack with a different Seal (or without that Seal) consumes all stored Echo stacks
        echoState.active = false
        echoState.stacks = 0
        echoState.icon = nil
        echoState.spellID = nil
        echoState.duration = 0
        echoState.expirationTime = 0
    end

    if sealState.active and sealState.icon then
        if not echoState.active then
            echoState.active = true
            echoState.icon = sealState.icon
            echoState.spellID = sealState.spellID
            echoState.stacks = 1
            echoState.duration = 30
            echoState.expirationTime = now + 30
        elseif echoState.icon == sealState.icon then
            echoState.stacks = Clamp((echoState.stacks or 1) + 1, 1, MAX_ECHO_STACKS)
            echoState.duration = 30
            echoState.expirationTime = now + 30
        end
    end
    if UpdatePaladinUI then UpdatePaladinUI() end
end

local function RegisterPaladinSealSpell(spellID, iconID, spellName)
    if not spellID or IsSecret(spellID) or type(spellID) ~= "number" or spellID <= 0 then return end
    local resolvedIcon = (not IsSecret(iconID) and iconID) or SEAL_SPELL_IDS[spellID] or FallbackIconForAura(spellName, spellID)
    if not SEAL_SPELL_IDS[spellID] then
        SEAL_SPELL_IDS[spellID] = resolvedIcon
        SEAL_SPELL_LIST[#SEAL_SPELL_LIST + 1] = spellID
    elseif resolvedIcon and SEAL_SPELL_IDS[spellID] == 132325 and resolvedIcon ~= 132325 then
        SEAL_SPELL_IDS[spellID] = resolvedIcon
    end
end

local function IdentifyPaladinSealSpell(spellID, spellName)
    if spellID and not IsSecret(spellID) and type(spellID) == "number" then
        if SEAL_SPELL_IDS[spellID] then
            return true, SEAL_SPELL_IDS[spellID], spellName
        end
        if C_Spell and C_Spell.GetSpellName then
            local okN, n = pcall(C_Spell.GetSpellName, spellID)
            if okN and not IsSecret(n) and type(n) == "string" then
                spellName = spellName or n
                if n:lower():find("^seal of ") then
                    local icon = nil
                    if C_Spell.GetSpellTexture then
                        local okT, tex = pcall(C_Spell.GetSpellTexture, spellID)
                        if okT and not IsSecret(tex) and tex then icon = tex end
                    end
                    icon = icon or FallbackIconForAura(n, spellID)
                    RegisterPaladinSealSpell(spellID, icon, n)
                    return true, icon, n
                end
            end
        end
    end
    if spellName and not IsSecret(spellName) and type(spellName) == "string" then
        if spellName:lower():find("^seal of ") then
            local icon = FallbackIconForAura(spellName, spellID)
            if spellID and not IsSecret(spellID) and type(spellID) == "number" then
                RegisterPaladinSealSpell(spellID, icon, spellName)
            end
            return true, icon, spellName
        end
    end
    return false, nil, nil
end

local function HarvestFlyoutSeals(flyoutID)
    if not flyoutID or IsSecret(flyoutID) or type(flyoutID) ~= "number" then return end
    if not (GetFlyoutInfo and GetFlyoutSlotInfo) then return end
    local okF, _, _, numSlots = pcall(GetFlyoutInfo, flyoutID)
    if not okF or IsSecret(numSlots) or type(numSlots) ~= "number" or numSlots <= 0 then return end
    for s = 1, numSlots do
        local okS, spID, overrideSpellID = pcall(GetFlyoutSlotInfo, flyoutID, s)
        if okS then
            if spID and not IsSecret(spID) and type(spID) == "number" then
                IdentifyPaladinSealSpell(spID, nil)
            end
            if overrideSpellID and not IsSecret(overrideSpellID) and type(overrideSpellID) == "number" then
                IdentifyPaladinSealSpell(overrideSpellID, nil)
            end
        end
    end
end

local function HarvestKnownPaladinSeals()
    if not isPaladinClass then return end

    -- 1. Scan player spellbook slots (including the WoW Forever "Seals" flyout)
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
        local flyoutType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout or 4
        for slot = 1, 200 do
            local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
            if not ok or type(info) ~= "table" then break end
            local spID = not IsSecret(info.spellID) and info.spellID or nil
            local actID = not IsSecret(info.actionID) and info.actionID or nil
            local itemType = not IsSecret(info.itemType) and info.itemType or nil
            local name = not IsSecret(info.name) and info.name or nil
            local icon = not IsSecret(info.iconID) and info.iconID or nil
            if type(name) == "string" and name:lower():find("^seal of ") and type(spID) == "number" then
                RegisterPaladinSealSpell(spID, icon, name)
            elseif (itemType == flyoutType or (type(name) == "string" and name:lower() == "seals")) and type(actID) == "number" then
                HarvestFlyoutSeals(actID)
            end
        end
    end

    -- 2. Scan action bar slots 1..180 for any placed Seal spells or Seal flyouts
    if GetActionInfo then
        for slot = 1, 180 do
            local ok, actionType, id = pcall(GetActionInfo, slot)
            if ok and not IsSecret(actionType) and not IsSecret(id) then
                if actionType == "spell" and type(id) == "number" then
                    IdentifyPaladinSealSpell(id, nil)
                elseif actionType == "flyout" and type(id) == "number" then
                    HarvestFlyoutSeals(id)
                elseif actionType == "macro" and type(id) == "number" and GetMacroSpell then
                    local okM, macroSpellID = pcall(GetMacroSpell, id)
                    if okM and not IsSecret(macroSpellID) and type(macroSpellID) == "number" then
                        IdentifyPaladinSealSpell(macroSpellID, nil)
                    end
                end
            end
        end
    end
end

local function ActivateSealFromCast(spellID, spellName, iconOverride)
    if not isPaladinClass then return end
    local now = GetTime()
    prevSealSnapshot = {
        active         = sealState.active,
        icon           = sealState.icon,
        duration       = sealState.duration,
        expirationTime = sealState.expirationTime,
        spellID        = sealState.spellID,
        auraInstanceID = sealState.auraInstanceID,
        lastCastTime   = sealState.lastCastTime,
    }
    local resolvedIcon = (not IsSecret(iconOverride) and iconOverride)
        or (spellID and SEAL_SPELL_IDS[spellID])
        or FallbackIconForAura(spellName, spellID)
    if spellID and not IsSecret(spellID) and type(spellID) == "number" then
        RegisterPaladinSealSpell(spellID, resolvedIcon, spellName)
    end
    sealState.active = true
    sealState.spellID = (not IsSecret(spellID) and type(spellID) == "number") and spellID or sealState.spellID
    sealState.icon = resolvedIcon
    sealState.duration = 30
    sealState.expirationTime = now + 30
    sealState.lastCastTime = now

    if UpdatePaladinUI then UpdatePaladinUI() end
    if EnsureLoopRunning then EnsureLoopRunning() end
end

local function DetectPlayerIsPaladin()
    if not UnitClass then return false end
    local ok, _, cls = pcall(UnitClass, "player")
    if (not ok or not cls or IsSecret(cls)) and UnitClassBase then
        local ok2, cls2 = pcall(UnitClassBase, "player")
        if ok2 then cls = cls2 end
    end
    if not cls or IsSecret(cls) or type(cls) ~= "string" then return false end
    return cls:upper() == "PALADIN"
end

-- Checks a C_Traits configID for the Unsealed Wrath node (definitionID 273096 / spellID 1310735).
-- Returns: foundNode (boolean), isLearned (boolean)
local function CheckTraitConfigForUnsealedWrath(configID)
    if not configID or IsSecret(configID) or type(configID) ~= "number" then return false, false end
    if not (C_Traits and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo) then
        return false, false
    end

    local treeList = {}
    local seenTrees = {}
    local function AddTree(tid)
        if tid and not IsSecret(tid) and type(tid) == "number" and not seenTrees[tid] then
            seenTrees[tid] = true
            treeList[#treeList + 1] = tid
        end
    end

    if C_Traits.GetConfigInfo then
        local okInfo, cfg = pcall(C_Traits.GetConfigInfo, configID)
        if okInfo and type(cfg) == "table" and type(cfg.treeIDs) == "table" then
            for _, tid in ipairs(cfg.treeIDs) do
                AddTree(tid)
            end
        end
    end

    -- WoW Forever (Camelot) also exposes the class trait tree via C_ClassTalents.GetTraitTreeForSpec(specID)
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecializationInfo
        and C_ClassTalents and C_ClassTalents.GetTraitTreeForSpec then
        local okS, spec = pcall(C_SpecializationInfo.GetSpecialization)
        if okS and spec and not IsSecret(spec) then
            local okID, specID = pcall(C_SpecializationInfo.GetSpecializationInfo, spec)
            if okID and specID and not IsSecret(specID) then
                local okT, tid = pcall(C_ClassTalents.GetTraitTreeForSpec, specID)
                if okT then AddTree(tid) end
            end
        end
    end

    for _, treeID in ipairs(treeList) do
        local okNodes, nodes = pcall(C_Traits.GetTreeNodes, treeID)
        if okNodes and type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local okN, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
                if okN and type(nodeInfo) == "table" then
                    local rank = (not IsSecret(nodeInfo.activeRank) and tonumber(nodeInfo.activeRank))
                        or (not IsSecret(nodeInfo.currentRank) and tonumber(nodeInfo.currentRank))
                        or (not IsSecret(nodeInfo.ranksPurchased) and tonumber(nodeInfo.ranksPurchased))
                        or 0

                    local function MatchesEntry(entryID)
                        if not entryID or IsSecret(entryID) then return false end
                        local okE, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entryID)
                        if not okE or type(entryInfo) ~= "table" or not entryInfo.definitionID then return false end
                        local defID = not IsSecret(entryInfo.definitionID) and entryInfo.definitionID or nil
                        if defID == UNSEALED_WRATH_DEF_ID then return true end
                        local okD, defInfo = pcall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
                        if okD and type(defInfo) == "table" then
                            local spID = not IsSecret(defInfo.spellID) and defInfo.spellID or nil
                            local ovName = not IsSecret(defInfo.overrideName) and defInfo.overrideName or nil
                            if spID == UNSEALED_WRATH_SPELL_ID
                                or (type(ovName) == "string" and ovName:lower() == "unsealed wrath") then
                                return true
                            end
                        end
                        return false
                    end

                    local entryIDs = nodeInfo.entryIDs
                    if type(entryIDs) == "table" then
                        for _, entryID in ipairs(entryIDs) do
                            if MatchesEntry(entryID) then
                                return true, (rank > 0)
                            end
                        end
                    elseif type(nodeInfo.activeEntry) == "table" and nodeInfo.activeEntry.entryID then
                        if MatchesEntry(nodeInfo.activeEntry.entryID) then
                            return true, (rank > 0)
                        end
                    end
                end
            end
        end
    end
    return false, false
end

local function DetectUnsealedWrathTalent()
    if not isPaladinClass then return false end

    local foundNodeAtZero = false

    -- 1. Authoritative C_Traits check (WoW Forever runs Classic talent trees on C_Traits)
    if C_Traits then
        local seenConfigs = {}
        local function TryConfig(cid, isPrimaryActive)
            if cid and not IsSecret(cid) and type(cid) == "number" and not seenConfigs[cid] then
                seenConfigs[cid] = true
                local foundNode, isLearned = CheckTraitConfigForUnsealedWrath(cid)
                if foundNode then
                    if isLearned then
                        return true, true
                    end
                    foundNodeAtZero = true
                    if isPrimaryActive then
                        return true, false
                    end
                end
            end
            return false, false
        end

        if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
            local okC, cid = pcall(C_ClassTalents.GetActiveConfigID)
            if okC then
                local decided, learned = TryConfig(cid, true)
                if decided then return learned end
            end
        end
        if C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup then
            local activeGroup = 1
            if C_SpecializationInfo.GetActiveSpecGroup then
                local okG, grp = pcall(C_SpecializationInfo.GetActiveSpecGroup)
                if okG and not IsSecret(grp) and type(grp) == "number" and grp > 0 then
                    activeGroup = grp
                end
            end
            local okCC, ccid = pcall(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, activeGroup)
            if okCC then
                local decided, learned = TryConfig(ccid, true)
                if decided then return learned end
            end
        end
        if C_Traits.GetConfigIDBySystemID then
            for _, sysID in ipairs({ 1, 2, 45 }) do
                local okS, cid = pcall(C_Traits.GetConfigIDBySystemID, sysID)
                if okS then
                    local _, learned = TryConfig(cid, false)
                    if learned then return true end
                end
            end
        end
        if C_Traits.GetConfigsByType then
            for t = 0, 5 do
                local okL, list = pcall(C_Traits.GetConfigsByType, t)
                if okL and type(list) == "table" then
                    for _, cid in ipairs(list) do
                        local _, learned = TryConfig(cid, false)
                        if learned then return true end
                    end
                end
            end
        end
    end

    -- 2. C_SpecializationInfo.GetTalentInfo scan (strict numeric rank > 0 check)
    if C_SpecializationInfo and C_SpecializationInfo.GetTalentInfo then
        for tab = 1, 4 do
            local emptyStreak = 0
            for idx = 1, 32 do
                local okI, info = pcall(C_SpecializationInfo.GetTalentInfo, { specializationIndex = tab, talentIndex = idx })
                if okI and type(info) == "table" and (info.name or info.talentID or info.spellID) then
                    emptyStreak = 0
                    local tName = not IsSecret(info.name) and info.name or nil
                    local tSpell = not IsSecret(info.spellID) and info.spellID or nil
                    local tID = not IsSecret(info.talentID) and info.talentID or nil
                    if tSpell == UNSEALED_WRATH_SPELL_ID or tID == UNSEALED_WRATH_DEF_ID
                        or (type(tName) == "string" and tName:lower() == "unsealed wrath") then
                        local tRank = (not IsSecret(info.rank) and type(info.rank) == "number" and info.rank)
                            or (not IsSecret(info.currentRank) and type(info.currentRank) == "number" and info.currentRank)
                            or 0
                        return tRank > 0
                    end
                else
                    emptyStreak = emptyStreak + 1
                    if emptyStreak >= 4 then break end
                end
            end
        end
    end

    -- If the talent tree explicitly found the Unsealed Wrath node at rank 0, it is NOT taken
    if foundNodeAtZero then
        return false
    end

    -- 3. Strict learned-spell check (NEVER IsSpellInSpellBook / IsSpellKnownOrInSpellBook / legacy IsSpellKnown,
    -- which check spellbook SkillLineAbility membership rather than learned status)
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, UNSEALED_WRATH_SPELL_ID)
        if ok and not IsSecret(known) and known == true then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, UNSEALED_WRATH_SPELL_ID)
        if ok and not IsSecret(known) and known == true then return true end
    end

    return false
end

local function ExtractAuraFields(data)
    if type(data) ~= "table" then return false, nil end
    local hasSecretField = IsSecret(data.name) or IsSecret(data.spellId) or IsSecret(data.icon)
    local name = not IsSecret(data.name) and type(data.name) == "string" and data.name or nil
    local spellID = not IsSecret(data.spellId) and type(data.spellId) == "number" and data.spellId or nil
    local icon = not IsSecret(data.icon) and data.icon or nil
    local auraInstanceID = not IsSecret(data.auraInstanceID) and type(data.auraInstanceID) == "number" and data.auraInstanceID or nil
    local stacks = 0
    if not IsSecret(data.applications) and type(data.applications) == "number" and data.applications > 0 then
        stacks = data.applications
    elseif not IsSecret(data.count) and type(data.count) == "number" and data.count > 0 then
        stacks = data.count
    elseif type(data.points) == "table" then
        local p3 = data.points[3]
        local p1 = data.points[1]
        if not IsSecret(p3) and type(p3) == "number" and p3 > 0 then
            stacks = p3
        elseif not IsSecret(p1) and type(p1) == "number" and p1 > 0 then
            stacks = p1
        end
    end
    local duration = not IsSecret(data.duration) and type(data.duration) == "number" and data.duration or 0
    local expirationTime = not IsSecret(data.expirationTime) and type(data.expirationTime) == "number" and data.expirationTime or 0
    return hasSecretField, name, spellID, icon, stacks, duration, expirationTime, auraInstanceID
end

-- Returns: slotExists, isSecretSlot, name, spellID, icon, stacks, duration, expirationTime, auraInstanceID
local function ReadPlayerHelpfulAuraByIndex(index)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
        if ok then
            if type(data) == "table" then
                local isSecretSlot, name, spellID, icon, stacks, duration, expirationTime, auraInstanceID = ExtractAuraFields(data)
                return true, isSecretSlot, name, spellID, icon, stacks, duration, expirationTime, auraInstanceID
            elseif data == nil then
                return false, false, nil
            end
        end
    end
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        local ok, data = pcall(C_UnitAuras.GetBuffDataByIndex, "player", index)
        if ok then
            if type(data) == "table" then
                local isSecretSlot, name, spellID, icon, stacks, duration, expirationTime, auraInstanceID = ExtractAuraFields(data)
                return true, isSecretSlot, name, spellID, icon, stacks, duration, expirationTime, auraInstanceID
            elseif data == nil then
                return false, false, nil
            end
        end
    end
    if UnitAura then
        local ok, name, icon, count, _, duration, expirationTime, _, _, _, spellID = pcall(UnitAura, "player", index, "HELPFUL")
        if ok and name ~= nil then
            local isSecretSlot = IsSecret(name) or IsSecret(spellID)
            return true,
                isSecretSlot,
                (not IsSecret(name) and type(name) == "string") and name or nil,
                (not IsSecret(spellID) and type(spellID) == "number") and spellID or nil,
                (not IsSecret(icon)) and icon or nil,
                (not IsSecret(count) and type(count) == "number") and count or 0,
                (not IsSecret(duration) and type(duration) == "number") and duration or 0,
                (not IsSecret(expirationTime) and type(expirationTime) == "number") and expirationTime or 0,
                nil
        end
    end
    return false, false, nil
end

RefreshPaladinAuras = function()
    if testPaladinPreview then
        if UpdatePaladinUI then UpdatePaladinUI() end
        return
    end
    if not isPaladinClass then
        sealState.active = false
        sealState.auraInstanceID = nil
        echoState.active = false
        echoState.stacks = 0
        echoState.auraInstanceID = nil
        if UpdatePaladinUI then UpdatePaladinUI() end
        return
    end

    local foundSeal = false
    local sIcon, sDur, sExp, sID, sInstID = nil, 0, 0, nil, nil

    local foundEcho = false
    local eIcon, eStacks, eDur, eExp, eID, eInstID = nil, 0, 0, 0, nil, nil

    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    local sawSecretAura = false
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local okSec, shouldBeSec = pcall(C_Secrets.ShouldAurasBeSecret)
        if okSec and shouldBeSec then
            sawSecretAura = true
        end
    end

    -- 1. Direct spellID lookup via C_UnitAuras.GetPlayerAuraBySpellID (only out of combat when auras are not secret,
    -- to never trigger DenyTaintedAccessWhenAurasAreSecret UI blocks)
    if not inCombat and not sawSecretAura and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, spID in ipairs(SEAL_SPELL_LIST) do
            local ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spID)
            if ok and type(data) == "table" then
                local isSec, name, id, icon, _, dur, exp, instID = ExtractAuraFields(data)
                sawSecretAura = sawSecretAura or isSec
                foundSeal = true
                sID = id or spID
                sIcon = icon or SEAL_SPELL_IDS[spID] or FallbackIconForAura(name, sID)
                sDur = dur or 0
                sExp = exp or 0
                sInstID = instID
                break
            elseif not ok then
                sawSecretAura = true
                break
            end
        end
        for _, spID in ipairs(ECHO_SPELL_LIST) do
            local ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spID)
            if ok and type(data) == "table" then
                local isSec, name, id, icon, stacks, dur, exp, instID = ExtractAuraFields(data)
                sawSecretAura = sawSecretAura or isSec
                foundEcho = true
                eID = id or spID
                eIcon = icon or ECHO_SPELL_IDS[spID] or FallbackIconForAura(name, eID)
                eStacks = Clamp((stacks and stacks > 0) and stacks or 1, 1, MAX_ECHO_STACKS)
                eDur = dur or 0
                eExp = exp or 0
                eInstID = instID
                break
            elseif not ok then
                sawSecretAura = true
                break
            end
        end
    end

    -- 2. Direct spell-name lookup via C_UnitAuras.GetAuraDataBySpellName (only out of combat when auras are not secret)
    if not inCombat and not sawSecretAura and (not foundSeal or not foundEcho) and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        if not foundSeal then
            for _, sealName in ipairs(SEAL_NAMES_LIST) do
                local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", sealName, "HELPFUL")
                if ok and type(data) == "table" then
                    local isSec, name, id, icon, _, dur, exp, instID = ExtractAuraFields(data)
                    sawSecretAura = sawSecretAura or isSec
                    foundSeal = true
                    sID = id
                    sIcon = icon or FallbackIconForAura(name or sealName, id)
                    sDur = dur or 0
                    sExp = exp or 0
                    sInstID = instID
                    break
                elseif not ok then
                    sawSecretAura = true
                    break
                end
            end
        end
        if not foundEcho then
            for _, echoName in ipairs(ECHO_NAMES_LIST) do
                local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", echoName, "HELPFUL")
                if ok and type(data) == "table" then
                    local isSec, name, id, icon, stacks, dur, exp, instID = ExtractAuraFields(data)
                    sawSecretAura = sawSecretAura or isSec
                    foundEcho = true
                    eID = id
                    eIcon = icon or FallbackIconForAura(name or echoName, id)
                    eStacks = Clamp((stacks and stacks > 0) and stacks or 1, 1, MAX_ECHO_STACKS)
                    eDur = dur or 0
                    eExp = exp or 0
                    eInstID = instID
                    break
                elseif not ok then
                    sawSecretAura = true
                    break
                end
            end
        end
    end

    -- 3. Player buff index scan (only out of combat when auras are not globally secret)
    if not inCombat and not sawSecretAura and (not foundSeal or not foundEcho) then
        for i = 1, 40 do
            local slotExists, isSecretSlot, name, spID, icon, stacks, dur, exp, instID = ReadPlayerHelpfulAuraByIndex(i)
            if not slotExists then break end
            if isSecretSlot then
                sawSecretAura = true
                break
            end

            if not foundSeal and (name or spID) then
                local isSeal = (spID and SEAL_SPELL_IDS[spID] ~= nil)
                    or (type(name) == "string" and name:lower():find("^seal of ") ~= nil)
                if isSeal then
                    foundSeal = true
                    sID = spID
                    sIcon = icon or FallbackIconForAura(name, spID)
                    sDur = dur or 0
                    sExp = exp or 0
                    sInstID = instID
                    if spID then
                        RegisterPaladinSealSpell(spID, sIcon, name)
                    end
                end
            end

            if not foundEcho and (name or spID) then
                local isEcho = (spID and ECHO_SPELL_IDS[spID] ~= nil)
                    or (type(name) == "string" and name:lower():find("^echo of ") ~= nil)
                if isEcho then
                    foundEcho = true
                    eID = spID
                    eIcon = (spID and ECHO_SPELL_IDS[spID]) or icon or FallbackIconForAura(name, spID)
                    eStacks = Clamp((stacks and stacks > 0) and stacks or 1, 1, MAX_ECHO_STACKS)
                    eDur = dur or 0
                    eExp = exp or 0
                    eInstID = instID
                end
            end

            if foundSeal and foundEcho then break end
        end
    end

    local now = GetTime()
    local preserveCombatSeal = (sawSecretAura or inCombat or (sealState.lastCastTime and (now - sealState.lastCastTime) < 1.5))

    if foundSeal then
        local isNewSealInstance = (not sealState.active)
            or (sInstID and sealState.auraInstanceID and sInstID ~= sealState.auraInstanceID)
            or (sID and sealState.spellID and sID ~= sealState.spellID)
            or (sIcon and sealState.icon and sIcon ~= sealState.icon)

        sealState.active = true
        sealState.icon = sIcon
        sealState.spellID = sID
        sealState.auraInstanceID = sInstID
        sealState.duration = (sDur and sDur > 0) and sDur or 30

        if sExp and sExp > now then
            -- Exact non-secret expiration timestamp from C_UnitAuras
            sealState.expirationTime = sExp
        elseif isNewSealInstance or not sealState.expirationTime or sealState.expirationTime <= now then
            -- Fallback if expirationTime is secret in combat: start real-time 30s Seal countdown
            sealState.expirationTime = now + sealState.duration
        end
    elseif preserveCombatSeal and sealState.active and sealState.expirationTime and sealState.expirationTime > now then
        -- Keep active in-combat Seal and its real-time 30s countdown running while C_UnitAuras is secret
        sealState.active = true
    else
        sealState.active = false
        sealState.icon = nil
        sealState.duration = 0
        sealState.expirationTime = 0
        sealState.spellID = nil
        sealState.auraInstanceID = nil
        sealState.lastCastTime = nil
    end

    if foundEcho then
        local isNewEcho = (not echoState.active) or (eIcon and echoState.icon ~= eIcon) or (eID and echoState.spellID ~= eID)
        echoState.active = true
        echoState.icon = eIcon
        echoState.stacks = eStacks
        echoState.duration = (eDur and eDur > 0) and eDur or 30
        if eExp and eExp > now then
            echoState.expirationTime = eExp
        elseif isNewEcho or not echoState.expirationTime or echoState.expirationTime <= now then
            echoState.expirationTime = now + echoState.duration
        end
        echoState.spellID = eID
        echoState.auraInstanceID = eInstID
    elseif (sawSecretAura or inCombat) and echoState.active and (not echoState.expirationTime or echoState.expirationTime <= 0 or echoState.expirationTime > now) then
        -- Preserve active Echo buff state while C_UnitAuras is secret in combat;
        -- combat updates come from landed white swings (excluding Holy Strike and misses/parries/dodges)
        echoState.active = true
    else
        echoState.active = false
        echoState.icon = nil
        echoState.stacks = 0
        echoState.duration = 0
        echoState.expirationTime = 0
        echoState.spellID = nil
        echoState.auraInstanceID = nil
    end

    if UpdatePaladinUI then UpdatePaladinUI() end
    if sealState.active and sealState.expirationTime and sealState.expirationTime > now then
        if EnsureLoopRunning then EnsureLoopRunning() end
    end
end

RefreshPaladinStatus = function()
    isPaladinClass = DetectPlayerIsPaladin()
    if isPaladinClass then
        HarvestKnownPaladinSeals()
    end
    hasUnsealedWrath = isPaladinClass and DetectUnsealedWrathTalent() or false
    RefreshPaladinAuras()
end

---------------------------------------------------------------------------
-- Visibility Logic
---------------------------------------------------------------------------
local function IsClockUnlocked()
    return (db and not db.locked) or isEditModeOpen
end

local function ShouldShowClock()
    if not db or not db.enabled then return false end
    if IsClockUnlocked() or testDualPreview or #testTimers > 0 then return true end

    local mode = db.visibility or "always"
    if mode == "always" then
        return true
    end

    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat or mhState.active or ohState.active or mhState.pulseTime >= 0 or ohState.pulseTime >= 0 then
        return true
    end

    if mode == "target" and UnitExists and UnitCanAttack then
        local okE, exists = pcall(UnitExists, "target")
        if okE and not IsSecret(exists) and exists then
            local okA, attackable = pcall(UnitCanAttack, "player", "target")
            local okD, dead = pcall(UnitIsDead, "target")
            if okA and not IsSecret(attackable) and attackable and not (okD and not IsSecret(dead) and dead) then
                return true
            end
        end
    end

    return false
end

local function RefreshVisibility()
    if not clockFrame then return end
    if ShouldShowClock() then
        if not clockFrame:IsShown() then clockFrame:Show() end
    else
        if clockFrame:IsShown() then clockFrame:Hide() end
    end
end

---------------------------------------------------------------------------
-- Clock UI Construction & Styling
---------------------------------------------------------------------------

local function ApplyReadyAppearance(isMH)
    if not clockFrame then return end
    local rc = db.readyColor or DEFAULTS.readyColor
    local readyAlpha = Clamp(db.readyAlpha or DEFAULTS.readyAlpha, 0.1, 1.0)

    if isMH then
        clockFrame.mhCooldown:Clear()
        clockFrame.mhCooldown:Hide()
        clockFrame.mhReadyTex:SetVertexColor(rc.r, rc.g, rc.b, readyAlpha)
        clockFrame.mhReadyTex:Show()
        clockFrame.bezelTex:SetVertexColor(1, 1, 1, 1)
        clockFrame.topPip:SetVertexColor(0.24, 0.92, 0.40, 0.94)
        clockFrame.timerText:SetText("")
    else
        clockFrame.ohCooldown:Clear()
        clockFrame.ohCooldown:Hide()
        clockFrame.ohReadyTex:SetVertexColor(rc.r, rc.g, rc.b, readyAlpha)
        clockFrame.ohReadyTex:Show()
    end
end

local function ApplyFillingAppearance(isMH)
    if not clockFrame then return end
    local yellowAlpha = Clamp(db.yellowAlpha or DEFAULTS.yellowAlpha, 0.1, 1.0)

    if isMH then
        local fc = db.fillColor or DEFAULTS.fillColor
        clockFrame.mhReadyTex:Hide()
        if clockFrame.mhCooldown.SetDrawEdge then
            clockFrame.mhCooldown:SetDrawEdge(db.drawEdge and true or false)
        end
        clockFrame.mhCooldown:SetSwipeColor(fc.r, fc.g, fc.b, yellowAlpha)
        clockFrame.mhCooldown:Show()
        clockFrame.bezelTex:SetVertexColor(1, 1, 1, 1)
        clockFrame.topPip:SetVertexColor(0.95, 0.78, 0.22, 0.88)
    else
        local ofc = db.ohFillColor or DEFAULTS.ohFillColor
        clockFrame.ohReadyTex:Hide()
        clockFrame.ohCooldown:SetSwipeColor(ofc.r, ofc.g, ofc.b, Clamp(yellowAlpha + 0.08, 0.1, 1.0))
        clockFrame.ohCooldown:Show()
    end
end

UpdateOffHandVisibility = function()
    if not clockFrame then return end
    local showOH = db.showOffHand and (hasOffHandWeapon or testDualPreview)
    if showOH then
        clockFrame.ohContainer:Show()
        clockFrame.ohBorderTex:Show()
        if ohState.active then
            ApplyFillingAppearance(false)
        else
            ApplyReadyAppearance(false)
        end
    else
        clockFrame.ohContainer:Hide()
        clockFrame.ohBorderTex:Hide()
        clockFrame.ohFlashTex:Hide()
    end
end

local function UpdateSealTimerText(now)
    if not clockFrame or not clockFrame.sealBox then return false end
    local sb = clockFrame.sealBox
    if not sealState.active or not sealState.expirationTime or sealState.expirationTime <= 0 then
        if sb.timerText:GetText() ~= "" then
            sb.timerText:SetText("")
        end
        return false
    end

    now = now or GetTime()
    local rem = sealState.expirationTime - now
    if rem <= 0 then
        sb.timerText:SetText("")
        return false
    end

    local secs = math.ceil(rem)
    if secs <= 5 then
        sb.timerText:SetTextColor(1.00, 0.38, 0.28, 1.0)
    else
        sb.timerText:SetTextColor(1.00, 0.84, 0.32, 1.0)
    end
    sb.timerText:SetText(("%ds"):format(secs))
    return true
end

UpdatePaladinUI = function()
    if not clockFrame or not clockFrame.sealBox or not clockFrame.echoBox then return end
    local showSealBox = isPaladinClass or testPaladinPreview
    local showEchoBox = (isPaladinClass and hasUnsealedWrath) or testPaladinPreview

    -- 1. Left Box: Active Seal (Paladin only)
    local sb = clockFrame.sealBox
    if showSealBox then
        sb:Show()
        if sealState.active and sealState.icon then
            sb.iconTex:SetTexture(sealState.icon)
            sb.iconTex:SetVertexColor(1, 1, 1, 1)
            sb.iconTex:Show()
        else
            sb.iconTex:Hide()
        end
        UpdateSealTimerText(GetTime())
    else
        sb:Hide()
    end

    -- 2. Right Box: Echoed Seal + 3 Minimap-style circular side pips (Paladin + Unsealed Wrath only)
    local eb = clockFrame.echoBox
    if showEchoBox then
        eb:Show()
        local stacks = (echoState.active and echoState.stacks) and Clamp(echoState.stacks, 0, MAX_ECHO_STACKS) or 0
        if echoState.active and stacks > 0 and echoState.icon then
            eb.iconTex:SetTexture(echoState.icon)
            eb.iconTex:SetVertexColor(1, 1, 1, 1)
            eb.iconTex:Show()
        else
            eb.iconTex:Hide()
            stacks = 0
        end

        local rc = (db and db.readyColor) or DEFAULTS.readyColor
        for i = 1, MAX_ECHO_STACKS do
            local pip = eb.pips[i]
            if pip then
                if i <= stacks then
                    pip.fillTex:SetVertexColor(
                        Clamp(rc.r + 0.04, 0, 1),
                        Clamp(rc.g + 0.14, 0, 1),
                        Clamp(rc.b + 0.06, 0, 1),
                        0.96
                    )
                    pip.fillTex:Show()
                else
                    pip.fillTex:Hide()
                end
            end
        end
    else
        eb:Hide()
    end
end

local RefreshGridOverlay, UpdateDragLabel, ComputeSnappedPosition -- forward declarations

local function SetSolidLineColor(tex, r, g, b, a)
    if tex.SetColorTexture then
        tex:SetColorTexture(r, g, b, a)
    else
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetVertexColor(r, g, b, a)
    end
end

local function EnsureGridOverlay()
    if gridFrame then return gridFrame end

    local gf = CreateFrame("Frame", "SwingClockGridFrame", UIParent)
    gf:SetAllPoints(UIParent)
    gf:SetFrameStrata("BACKGROUND")
    gf:SetFrameLevel(0)
    gf:EnableMouse(false)
    gf.vLines = {}
    gf.hLines = {}

    local centerV = gf:CreateTexture(nil, "OVERLAY")
    centerV:SetTexture("Interface\\Buttons\\WHITE8X8")
    gf.centerV = centerV

    local centerH = gf:CreateTexture(nil, "OVERLAY")
    centerH:SetTexture("Interface\\Buttons\\WHITE8X8")
    gf.centerH = centerH

    gf:Hide()
    gridFrame = gf
    return gf
end

local function SetGridLinePool(pool, count, vertical, gf, step, w, h, lineThickness)
    for i = 1, count do
        local pairIdx = i * 2
        local posLine = pool[pairIdx - 1]
        local negLine = pool[pairIdx]
        if not posLine then
            posLine = gf:CreateTexture(nil, "BACKGROUND")
            posLine:SetTexture("Interface\\Buttons\\WHITE8X8")
            pool[pairIdx - 1] = posLine
        end
        if not negLine then
            negLine = gf:CreateTexture(nil, "BACKGROUND")
            negLine:SetTexture("Interface\\Buttons\\WHITE8X8")
            pool[pairIdx] = negLine
        end

        local offset = i * step
        posLine:ClearAllPoints()
        negLine:ClearAllPoints()
        if vertical then
            posLine:SetPoint("TOP", gf, "TOP", offset, 0)
            posLine:SetPoint("BOTTOM", gf, "BOTTOM", offset, 0)
            posLine:SetWidth(lineThickness)

            negLine:SetPoint("TOP", gf, "TOP", -offset, 0)
            negLine:SetPoint("BOTTOM", gf, "BOTTOM", -offset, 0)
            negLine:SetWidth(lineThickness)
        else
            posLine:SetPoint("LEFT", gf, "LEFT", 0, offset)
            posLine:SetPoint("RIGHT", gf, "RIGHT", 0, offset)
            posLine:SetHeight(lineThickness)

            negLine:SetPoint("LEFT", gf, "LEFT", 0, -offset)
            negLine:SetPoint("RIGHT", gf, "RIGHT", 0, -offset)
            negLine:SetHeight(lineThickness)
        end
    end

    for j = count * 2 + 1, #pool do
        pool[j]:Hide()
    end
end

RefreshGridOverlay = function(curX, curY, snapX, snapY)
    if not IsClockUnlocked() or not db then
        if gridFrame then gridFrame:Hide() end
        return
    end

    local gf = EnsureGridOverlay()
    local step = Clamp(tonumber(db.gridSize) or DEFAULTS.gridSize, 8, 64)
    local w = UIParent:GetWidth() or 1920
    local h = UIParent:GetHeight() or 1080
    local scale = UIParent:GetEffectiveScale() or 1
    local px = math.max(1 / scale, 0.85)
    local showMinor = (db.snapToGrid ~= false)

    local halfCols = math.min(math.floor((w * 0.5) / step), 160)
    local halfRows = math.min(math.floor((h * 0.5) / step), 120)

    if gf.builtStep ~= step or gf.builtCols ~= halfCols or gf.builtRows ~= halfRows or gf.builtPx ~= px then
        SetGridLinePool(gf.vLines, halfCols, true, gf, step, w, h, px)
        SetGridLinePool(gf.hLines, halfRows, false, gf, step, w, h, px)
        gf.builtStep = step
        gf.builtCols = halfCols
        gf.builtRows = halfRows
        gf.builtPx = px
    end

    local minorA = dragState.active and 0.14 or 0.08
    local majorA = dragState.active and 0.28 or 0.17

    for i = 1, halfCols do
        local isMajor = (i % 5 == 0)
        local pLine = gf.vLines[i * 2 - 1]
        local nLine = gf.vLines[i * 2]
        if showMinor then
            if isMajor then
                SetSolidLineColor(pLine, 1.0, 0.88, 0.52, majorA)
                SetSolidLineColor(nLine, 1.0, 0.88, 0.52, majorA)
            else
                SetSolidLineColor(pLine, 1.0, 1.0, 1.0, minorA)
                SetSolidLineColor(nLine, 1.0, 1.0, 1.0, minorA)
            end
            pLine:Show()
            nLine:Show()
        else
            pLine:Hide()
            nLine:Hide()
        end
    end

    for i = 1, halfRows do
        local isMajor = (i % 5 == 0)
        local pLine = gf.hLines[i * 2 - 1]
        local nLine = gf.hLines[i * 2]
        if showMinor then
            if isMajor then
                SetSolidLineColor(pLine, 1.0, 0.88, 0.52, majorA)
                SetSolidLineColor(nLine, 1.0, 0.88, 0.52, majorA)
            else
                SetSolidLineColor(pLine, 1.0, 1.0, 1.0, minorA)
                SetSolidLineColor(nLine, 1.0, 1.0, 1.0, minorA)
            end
            pLine:Show()
            nLine:Show()
        else
            pLine:Hide()
            nLine:Hide()
        end
    end

    local isCenteredX = snapX or (curX == 0)
    local isCenteredY = snapY or (curY == 0)

    gf.centerV:ClearAllPoints()
    gf.centerV:SetPoint("TOP", gf, "TOP", 0, 0)
    gf.centerV:SetPoint("BOTTOM", gf, "BOTTOM", 0, 0)
    gf.centerV:SetWidth(isCenteredX and (px * 2.5) or (px * 1.8))
    if isCenteredX then
        SetSolidLineColor(gf.centerV, 0.24, 1.00, 0.48, 0.92)
    else
        SetSolidLineColor(gf.centerV, 1.00, 0.82, 0.24, dragState.active and 0.65 or 0.42)
    end
    gf.centerV:Show()

    gf.centerH:ClearAllPoints()
    gf.centerH:SetPoint("LEFT", gf, "LEFT", 0, 0)
    gf.centerH:SetPoint("RIGHT", gf, "RIGHT", 0, 0)
    gf.centerH:SetHeight(isCenteredY and (px * 2.5) or (px * 1.8))
    if isCenteredY then
        SetSolidLineColor(gf.centerH, 0.24, 1.00, 0.48, 0.92)
    else
        SetSolidLineColor(gf.centerH, 1.00, 0.82, 0.24, dragState.active and 0.65 or 0.42)
    end
    gf.centerH:Show()

    gf:Show()
end

ComputeSnappedPosition = function(rawX, rawY)
    local halfW = math.max(100, ((UIParent:GetWidth() or 1920) * 0.5) - ((clockFrame and clockFrame:GetWidth() or 68) * 0.5))
    local halfH = math.max(100, ((UIParent:GetHeight() or 1080) * 0.5) - ((clockFrame and clockFrame:GetHeight() or 68) * 0.5))
    rawX = Clamp(rawX, -halfW, halfW)
    rawY = Clamp(rawY, -halfH, halfH)

    local shiftHeld = (IsShiftKeyDown and IsShiftKeyDown()) and true or false
    if shiftHeld then
        local x = math.floor(rawX + 0.5)
        local y = math.floor(rawY + 0.5)
        return x, y, (x == 0), (y == 0), true
    end

    local thresh = Clamp(tonumber(db and db.snapThreshold) or DEFAULTS.snapThreshold, 4, 40)
    local step = Clamp(tonumber(db and db.gridSize) or DEFAULTS.gridSize, 8, 64)
    local gridOn = (db == nil or db.snapToGrid ~= false)

    local x, y
    local snapX, snapY = false, false

    if math.abs(rawX) <= thresh then
        x = 0
        snapX = true
    elseif gridOn then
        x = math.floor(rawX / step + 0.5) * step
        snapX = (x == 0)
    else
        x = math.floor(rawX + 0.5)
    end

    if math.abs(rawY) <= thresh then
        y = 0
        snapY = true
    elseif gridOn then
        y = math.floor(rawY / step + 0.5) * step
        snapY = (y == 0)
    else
        y = math.floor(rawY + 0.5)
    end

    x = Clamp(x, -halfW, halfW)
    y = Clamp(y, -halfH, halfH)
    return x, y, snapX, snapY, false
end

UpdateDragLabel = function(x, y, snapX, snapY, freeMode)
    if not clockFrame or not clockFrame.unlockLabel then return end
    local tag
    if snapX and snapY then
        tag = " |cff44ff66[CENTER]|r"
    elseif snapX then
        tag = " |cff44ff66[Center X]|r"
    elseif snapY then
        tag = " |cff44ff66[Center Y]|r"
    elseif freeMode then
        tag = " |cffaaaaaa[Free]|r"
    else
        tag = ""
    end

    local prefix = isEditModeOpen and "|cff66ccffSwingClock|r" or "|cffffd200SwingClock|r"
    clockFrame.unlockLabel:SetText(("%s (%d, %d)%s"):format(prefix, x or 0, y or 0, tag))
end

local function ApplyClockLayout()
    if not clockFrame or not db then return end
    local sz = Clamp(tonumber(db.size) or DEFAULTS.size, 24, 320)
    clockFrame:SetSize(sz, sz)
    clockFrame:ClearAllPoints()
    clockFrame:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 0, db.y or -150)

    -- Inner disc container sits tightly inside the beveled brass bezel (inner lip r = 0.816..0.830)
    local discSz = sz * 0.828
    clockFrame.discContainer:SetSize(discSz, discSz)
    clockFrame.mhFlashTex:SetSize(discSz, discSz)

    -- 12 o'clock indicator sits nestled inside the recessed triangle pocket of the Minimap-style crest (y = 0.439)
    local pipSize = Clamp(math.floor(sz * 0.076 + 0.5), 5, 22)
    clockFrame.topPip:SetSize(pipSize, pipSize)
    clockFrame.topPip:ClearAllPoints()
    clockFrame.topPip:SetPoint("CENTER", clockFrame.overlay, "CENTER", 0, sz * 0.439)

    -- Warm dark Warcraft umber dial backdrop & natural antique-brass dual-wield border
    clockFrame.bgTex:SetVertexColor(0.14, 0.10, 0.06, Clamp(db.bgAlpha or DEFAULTS.bgAlpha, 0.0, 0.95))
    clockFrame.ohTrackTex:SetVertexColor(0.12, 0.09, 0.05, 0.78)
    clockFrame.ohBorderTex:SetVertexColor(1, 1, 1, 1)

    -- Paladin Left Seal Box & Right Unsealed Wrath Echo Box (half the size of the swing circle)
    local boxSz = Clamp(math.floor(sz * 0.50 + 0.5), 16, 160)
    local boxGap = Clamp(math.floor(sz * 0.10 + 0.5), 6, 36)
    local innerBoxSz = math.floor(boxSz * 0.80 + 0.5)

    if clockFrame.sealBox then
        local sb = clockFrame.sealBox
        sb:SetSize(boxSz, boxSz)
        sb:ClearAllPoints()
        sb:SetPoint("RIGHT", clockFrame, "LEFT", -boxGap, 0)
        sb.bgTex:SetSize(innerBoxSz, innerBoxSz)
        sb.iconTex:SetSize(innerBoxSz, innerBoxSz)
    end

    if clockFrame.echoBox then
        local eb = clockFrame.echoBox
        eb:SetSize(boxSz, boxSz)
        eb:ClearAllPoints()
        eb:SetPoint("LEFT", clockFrame, "RIGHT", boxGap, 0)
        eb.bgTex:SetSize(innerBoxSz, innerBoxSz)
        eb.iconTex:SetSize(innerBoxSz, innerBoxSz)

        -- 3 circular Minimap-style pips along the right side of the Echo Box
        local pipOrbSz = Clamp(math.floor(boxSz * 0.32 + 0.5), 10, 52)
        local pipFillSz = math.floor(pipOrbSz * 0.72 + 0.5)
        local pipX = math.floor(boxSz * 0.49 + 0.5)
        local pipStepY = math.floor(boxSz * 0.29 + 0.5)
        local yOffsets = { pipStepY, 0, -pipStepY }

        for i = 1, MAX_ECHO_STACKS do
            local pip = eb.pips[i]
            if pip then
                pip:SetSize(pipOrbSz, pipOrbSz)
                pip:ClearAllPoints()
                pip:SetPoint("CENTER", eb, "CENTER", pipX, yOffsets[i])
                pip.bgTex:SetSize(pipFillSz, pipFillSz)
                pip.fillTex:SetSize(pipFillSz, pipFillSz)
            end
        end
    end

    -- Lock / click-through handling via dedicated top-level dragOverlay
    if IsClockUnlocked() then
        local curX = db.x or 0
        local curY = db.y or -150
        clockFrame:SetMovable(true)
        clockFrame.dragOverlay:ClearAllPoints()
        local padX = (isPaladinClass or testPaladinPreview) and (boxSz + boxGap + math.floor(boxSz * 0.25)) or 0
        clockFrame.dragOverlay:SetPoint("TOPLEFT", clockFrame, "TOPLEFT", -padX, 0)
        clockFrame.dragOverlay:SetPoint("BOTTOMRIGHT", clockFrame, "BOTTOMRIGHT", padX, 0)
        clockFrame.dragOverlay:EnableMouse(true)
        clockFrame.dragOverlay:Show()
        clockFrame.unlockRing:Show()
        UpdateDragLabel(curX, curY, curX == 0, curY == 0, false)
        clockFrame.unlockLabel:Show()
        RefreshGridOverlay(curX, curY, curX == 0, curY == 0)
    else
        dragState.active = false
        clockFrame.dragOverlay:SetScript("OnUpdate", nil)
        clockFrame.dragOverlay:EnableMouse(false)
        clockFrame.dragOverlay:Hide()
        clockFrame.unlockRing:Hide()
        clockFrame.unlockLabel:Hide()
        if gridFrame then gridFrame:Hide() end
    end

    if mhState.active then
        ApplyFillingAppearance(true)
    else
        ApplyReadyAppearance(true)
    end
    UpdateOffHandVisibility()
    UpdatePaladinUI()
    RefreshVisibility()
end

---------------------------------------------------------------------------
-- Animation & Completion Loop (Runs ONLY while swinging or pulsing; 0% idle CPU)
---------------------------------------------------------------------------
local FinishSwing -- forward declaration

local function OnClockUpdate(_, elapsed)
    local now = GetTime()
    local keepRunning = false

    -- 1. Check Main Hand swing progress & optional timer text
    if mhState.active then
        local rem = (mhState.startTime + mhState.duration) - now
        if rem <= 0 then
            FinishSwing(SWING_MH)
        else
            keepRunning = true
            if db.showText then
                clockFrame.timerText:SetText(("%.1f"):format(rem))
            elseif clockFrame.timerText:GetText() ~= "" then
                clockFrame.timerText:SetText("")
            end
        end
    end

    -- 2. Check Off-Hand swing progress
    if ohState.active then
        local rem = (ohState.startTime + ohState.duration) - now
        if rem <= 0 then
            FinishSwing(SWING_OH)
        else
            keepRunning = true
        end
    end

    -- 3. Animate 12 o'clock Green Attack Pulse (Main Clock)
    if mhState.pulseTime >= 0 then
        mhState.pulseTime = mhState.pulseTime + elapsed
        local t = mhState.pulseTime / PULSE_DURATION
        local strength = Clamp(db.pulseStrength or 1.0, 0.0, 2.0)
        if t >= 1.0 or strength <= 0.01 then
            mhState.pulseTime = -1
            clockFrame.pulseGlowTex:Hide()
            clockFrame.mhFlashTex:Hide()
            -- Keep antique brass bezel natural; restore 12 o'clock pip for current state
            clockFrame.bezelTex:SetVertexColor(1, 1, 1, 1)
            if mhState.active then
                clockFrame.topPip:SetVertexColor(0.95, 0.78, 0.22, 0.88)
            else
                clockFrame.topPip:SetVertexColor(0.24, 0.92, 0.40, 0.94)
            end
        else
            keepRunning = true
            local pc = db.pulseColor or DEFAULTS.pulseColor
            -- Quick rise over first 18%, smooth quadratic ease-out decay over remaining 82%
            local env
            if t < 0.18 then
                env = t / 0.18
            else
                local d = (1.0 - t) / 0.82
                env = d * d
            end

            -- PulseGlow rim peak is at r=0.79, so scale 1.16 -> 1.28 hugs the outer bezel crest (r=0.922) subtly
            local sz = clockFrame:GetWidth()
            local scale = 1.16 + 0.12 * (1.0 - (1.0 - t) * (1.0 - t))
            clockFrame.pulseGlowTex:SetSize(sz * scale, sz * scale)
            clockFrame.pulseGlowTex:SetVertexColor(pc.r, pc.g, pc.b, Clamp(0.54 * env * strength, 0, 1))
            clockFrame.pulseGlowTex:Show()

            clockFrame.mhFlashTex:SetVertexColor(pc.r, pc.g, pc.b, Clamp(0.24 * env * strength, 0, 1))
            clockFrame.mhFlashTex:Show()

            -- Keep antique brass bezel intact while lighting the 12 o'clock crest triangle green
            clockFrame.bezelTex:SetVertexColor(1, 1, 1, 1)
            clockFrame.topPip:SetVertexColor(0.28, 0.98, 0.46, 1.00)
        end
    end

    -- 4. Animate Off-Hand Inner Ring Green Pulse
    if ohState.pulseTime >= 0 then
        ohState.pulseTime = ohState.pulseTime + elapsed
        local t = ohState.pulseTime / OH_PULSE_DURATION
        local strength = Clamp(db.pulseStrength or 1.0, 0.0, 2.0)
        if t >= 1.0 or strength <= 0.01 or not clockFrame.ohContainer:IsShown() then
            ohState.pulseTime = -1
            clockFrame.ohFlashTex:Hide()
        else
            keepRunning = true
            local pc = db.pulseColor or DEFAULTS.pulseColor
            local env = (t < 0.20) and (t / 0.20) or (((1.0 - t) / 0.80) ^ 2)
            clockFrame.ohFlashTex:SetVertexColor(pc.r, pc.g, pc.b, Clamp(0.65 * env * strength, 0, 1))
            clockFrame.ohFlashTex:Show()
        end
    end

    -- 5. Update Paladin Active Seal remaining seconds timer underneath the left Seal Box
    if (isPaladinClass or testPaladinPreview) and sealState.active and sealState.expirationTime and sealState.expirationTime > 0 then
        if UpdateSealTimerText(now) then
            keepRunning = true
        elseif not testPaladinPreview then
            RefreshPaladinAuras()
        end
    end

    if not keepRunning then
        clockFrame:SetScript("OnUpdate", nil)
        RefreshVisibility()
    end
end

EnsureLoopRunning = function()
    if clockFrame and clockFrame:GetScript("OnUpdate") == nil then
        clockFrame:SetScript("OnUpdate", OnClockUpdate)
    end
end

---------------------------------------------------------------------------
-- Swing State Transitions
---------------------------------------------------------------------------
local function TriggerPulse(isMH)
    if not db or (db.pulseStrength or 1.0) <= 0.01 then return end
    if isMH then
        mhState.pulseTime = 0
    else
        ohState.pulseTime = 0
    end
    EnsureLoopRunning()
end

FinishSwing = function(slot)
    if slot == SWING_OH then
        if not ohState.active then return end
        ohState.active = false
        ohState.startTime = 0
        ohState.duration = 0
        ApplyReadyAppearance(false)
    else
        if not mhState.active then return end
        mhState.active = false
        mhState.startTime = 0
        mhState.duration = 0
        ApplyReadyAppearance(true)
    end
end

local function StartSwing(slot, duration, pulse)
    if not clockFrame or not db or not db.enabled then return end
    if not duration or duration <= 0 then
        FinishSwing(slot)
        return
    end

    local now = GetTime()

    if slot == SWING_OH then
        if not db.showOffHand then return end
        if not hasOffHandWeapon and not testDualPreview then
            hasOffHandWeapon = true
            UpdateOffHandVisibility()
        end
        if pulse ~= false then TriggerPulse(false) end
        local _, ohSpeed = GetPlayerWeaponSpeeds()
        ohState.active = true
        ohState.startTime = now
        ohState.duration = duration
        ohState.speed = ohSpeed or duration

        ApplyFillingAppearance(false)
        clockFrame.ohCooldown:SetCooldown(now, duration)
        local ofc = db.ohFillColor or DEFAULTS.ohFillColor
        clockFrame.ohCooldown:SetSwipeColor(ofc.r, ofc.g, ofc.b, Clamp((db.yellowAlpha or DEFAULTS.yellowAlpha) + 0.08, 0.1, 1.0))
    else
        if pulse ~= false then TriggerPulse(true) end
        local mhSpeed = (slot == SWING_RANGED) and GetPlayerRangedSpeed() or select(1, GetPlayerWeaponSpeeds())
        mhState.active = true
        mhState.startTime = now
        mhState.duration = duration
        mhState.speed = mhSpeed or duration
        mhState.isRanged = (slot == SWING_RANGED)

        ApplyFillingAppearance(true)
        clockFrame.mhCooldown:SetCooldown(now, duration)
        local fc = db.fillColor or DEFAULTS.fillColor
        clockFrame.mhCooldown:SetSwipeColor(fc.r, fc.g, fc.b, Clamp(db.yellowAlpha or DEFAULTS.yellowAlpha, 0.1, 1.0))
    end

    RefreshVisibility()
    EnsureLoopRunning()
end

local SaveClockPosition, RefreshConfigUI, RefreshOptionsPanel -- forward declarations

SaveClockPosition = function()
    if not clockFrame or not db then return end
    local cx, cy = clockFrame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if cx and cy and ux and uy then
        db.point = "CENTER"
        db.relPoint = "CENTER"
        db.x = math.floor((cx - ux) + 0.5)
        db.y = math.floor((cy - uy) + 0.5)
    else
        local point, _, relPoint, x, y = clockFrame:GetPoint(1)
        if point then
            db.point = point
            db.relPoint = relPoint or point
            db.x = math.floor((x or 0) + 0.5)
            db.y = math.floor((y or 0) + 0.5)
        end
    end
    if clockFrame.SetUserPlaced then
        pcall(clockFrame.SetUserPlaced, clockFrame, false)
    end
    ApplyClockLayout()
    if RefreshConfigUI then RefreshConfigUI() end
    if RefreshOptionsPanel then RefreshOptionsPanel() end
end

local function CreateClockFrame()
    if clockFrame then return clockFrame end

    local f = CreateFrame("Frame", "SwingClockFrame", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    if f.SetDontSavePosition then
        pcall(f.SetDontSavePosition, f, true)
    end

    local baseLevel = f:GetFrameLevel()

    -- Disc container sized to 0.885 of clockFrame so the pie slice and optional edge spark stay strictly inside the bezel
    local discContainer = CreateFrame("Frame", nil, f)
    discContainer:SetFrameLevel(baseLevel)
    discContainer:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.discContainer = discContainer

    -- 1. Dark translucent clock dial backdrop
    local bgTex = discContainer:CreateTexture(nil, "BACKGROUND", nil, 0)
    bgTex:SetAllPoints()
    bgTex:SetTexture(TEX_DISC)
    f.bgTex = bgTex

    -- 2. Full green ready circle (shown when swing is at 12 o'clock & waiting to fire)
    local mhReadyTex = discContainer:CreateTexture(nil, "ARTWORK", nil, 0)
    mhReadyTex:SetAllPoints()
    mhReadyTex:SetTexture(TEX_DISC)
    f.mhReadyTex = mhReadyTex

    -- 3. Main Hand clockwise yellow pie-chart fill
    local mhCD = CreateFrame("Cooldown", nil, discContainer)
    mhCD:SetFrameLevel(baseLevel + 1)
    mhCD:SetAllPoints()
    mhCD:SetSwipeTexture(TEX_DISC)
    mhCD:SetReverse(true) -- 0% at 12 o'clock -> sweeps clockwise to 100% at 12 o'clock
    if mhCD.SetUseCircularEdge then mhCD:SetUseCircularEdge(true) end
    if mhCD.SetDrawBling then mhCD:SetDrawBling(false) end
    if mhCD.SetHideCountdownNumbers then mhCD:SetHideCountdownNumbers(true) end
    mhCD.noCooldownCount = true -- suppresses OmniCC / third-party cooldown text addons
    mhCD:SetScript("OnCooldownDone", function()
        if mhState.active and (mhState.startTime + mhState.duration) - GetTime() > 0.05 then return end
        FinishSwing(SWING_MH)
    end)
    f.mhCooldown = mhCD

    -- 4. Optional Off-Hand Inner Concentric Ring
    local ohContainer = CreateFrame("Frame", nil, f)
    ohContainer:SetFrameLevel(baseLevel + 2)
    ohContainer:SetAllPoints()
    f.ohContainer = ohContainer

    local ohTrackTex = ohContainer:CreateTexture(nil, "BACKGROUND", nil, 0)
    ohTrackTex:SetAllPoints()
    ohTrackTex:SetTexture(TEX_INNER)
    f.ohTrackTex = ohTrackTex

    local ohReadyTex = ohContainer:CreateTexture(nil, "ARTWORK", nil, 0)
    ohReadyTex:SetAllPoints()
    ohReadyTex:SetTexture(TEX_INNER)
    f.ohReadyTex = ohReadyTex

    local ohCD = CreateFrame("Cooldown", nil, ohContainer)
    ohCD:SetFrameLevel(baseLevel + 3)
    ohCD:SetAllPoints()
    ohCD:SetSwipeTexture(TEX_INNER)
    ohCD:SetReverse(true)
    if ohCD.SetUseCircularEdge then ohCD:SetUseCircularEdge(true) end
    if ohCD.SetDrawBling then ohCD:SetDrawBling(false) end
    if ohCD.SetDrawEdge then ohCD:SetDrawEdge(false) end
    if ohCD.SetHideCountdownNumbers then ohCD:SetHideCountdownNumbers(true) end
    ohCD.noCooldownCount = true
    ohCD:SetScript("OnCooldownDone", function()
        if ohState.active and (ohState.startTime + ohState.duration) - GetTime() > 0.05 then return end
        FinishSwing(SWING_OH)
    end)
    f.ohCooldown = ohCD

    -- 5. Top Overlay (clock bezel, 12 o'clock pip, green pulse glow, optional countdown)
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetFrameLevel(baseLevel + 5)
    overlay:SetAllPoints()
    f.overlay = overlay

    local ohBorderTex = overlay:CreateTexture(nil, "ARTWORK", nil, 0)
    ohBorderTex:SetAllPoints()
    ohBorderTex:SetTexture(TEX_INNER_EDGE)
    f.ohBorderTex = ohBorderTex

    local bezelTex = overlay:CreateTexture(nil, "ARTWORK", nil, 1)
    bezelTex:SetAllPoints()
    bezelTex:SetTexture(TEX_BEZEL)
    f.bezelTex = bezelTex

    local topPip = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
    topPip:SetTexture(TEX_PIP)
    f.topPip = topPip

    local mhFlashTex = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
    mhFlashTex:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    mhFlashTex:SetTexture(TEX_DISC)
    mhFlashTex:SetBlendMode("ADD")
    mhFlashTex:Hide()
    f.mhFlashTex = mhFlashTex

    local ohFlashTex = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
    ohFlashTex:SetAllPoints()
    ohFlashTex:SetTexture(TEX_INNER)
    ohFlashTex:SetBlendMode("ADD")
    ohFlashTex:Hide()
    f.ohFlashTex = ohFlashTex

    local pulseGlowTex = overlay:CreateTexture(nil, "OVERLAY", nil, 4)
    pulseGlowTex:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    pulseGlowTex:SetTexture(TEX_PULSE)
    pulseGlowTex:SetBlendMode("ADD")
    pulseGlowTex:Hide()
    f.pulseGlowTex = pulseGlowTex

    local timerText = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timerText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    timerText:SetText("")
    f.timerText = timerText

    -- Unlocked drag indicator
    local unlockRing = overlay:CreateTexture(nil, "OVERLAY", nil, 5)
    unlockRing:SetPoint("TOPLEFT", -4, 4)
    unlockRing:SetPoint("BOTTOMRIGHT", 4, -4)
    unlockRing:SetTexture(TEX_PULSE)
    unlockRing:SetBlendMode("ADD")
    unlockRing:SetVertexColor(0.3, 1.0, 0.5, 0.35)
    unlockRing:Hide()
    f.unlockRing = unlockRing

    local unlockLabel = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unlockLabel:SetPoint("BOTTOM", f, "TOP", 0, 4)
    unlockLabel:SetText("|cffffd200SwingClock (Drag)|r")
    unlockLabel:Hide()
    f.unlockLabel = unlockLabel

    -- 6. Paladin Active Seal Box (Left of the swing circle, half circle size, with remaining seconds underneath)
    local sealBox = CreateFrame("Frame", nil, f)
    sealBox:SetFrameLevel(baseLevel + 2)
    sealBox:EnableMouse(false)

    local sbBg = sealBox:CreateTexture(nil, "BACKGROUND", nil, 0)
    sbBg:SetPoint("CENTER", sealBox, "CENTER", 0, 0)
    SetSolidLineColor(sbBg, 0.12, 0.09, 0.05, 0.86)
    sealBox.bgTex = sbBg

    local sbIcon = sealBox:CreateTexture(nil, "ARTWORK", nil, 0)
    sbIcon:SetPoint("CENTER", sealBox, "CENTER", 0, 0)
    sbIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    sbIcon:Hide()
    sealBox.iconTex = sbIcon

    local sbBezel = sealBox:CreateTexture(nil, "OVERLAY", nil, 1)
    sbBezel:SetAllPoints(sealBox)
    sbBezel:SetTexture(TEX_SEAL_BOX)
    sealBox.bezelTex = sbBezel

    local sbTimer = sealBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sbTimer:SetPoint("TOP", sealBox, "BOTTOM", 0, -3)
    sbTimer:SetJustifyH("CENTER")
    sbTimer:SetText("")
    sealBox.timerText = sbTimer

    -- Dedicated real-time countdown ticker on sealBox so the Seal timer always updates every second
    -- regardless of whether a weapon swing is active
    local sealTickAccum = 0
    local auraPollAccum = 0
    sealBox:SetScript("OnUpdate", function(_, elapsed)
        sealTickAccum = sealTickAccum + (elapsed or 0)
        auraPollAccum = auraPollAccum + (elapsed or 0)
        if sealTickAccum >= 0.08 then
            sealTickAccum = 0
            local now = GetTime()
            if sealState.active and sealState.expirationTime and sealState.expirationTime > 0 then
                if not UpdateSealTimerText(now) and not testPaladinPreview then
                    RefreshPaladinAuras()
                end
            end
        end
        if auraPollAccum >= 0.25 then
            auraPollAccum = 0
            if not testPaladinPreview and isPaladinClass then
                RefreshPaladinAuras()
            end
        end
    end)

    sealBox:Hide()
    f.sealBox = sealBox

    -- 7. Paladin Unsealed Wrath Echo Box (Right of the swing circle, same size as Seal Box, with 3 Minimap-style circular side pips)
    local echoBox = CreateFrame("Frame", nil, f)
    echoBox:SetFrameLevel(baseLevel + 2)
    echoBox:EnableMouse(false)

    local ebBg = echoBox:CreateTexture(nil, "BACKGROUND", nil, 0)
    ebBg:SetPoint("CENTER", echoBox, "CENTER", 0, 0)
    SetSolidLineColor(ebBg, 0.12, 0.09, 0.05, 0.86)
    echoBox.bgTex = ebBg

    local ebIcon = echoBox:CreateTexture(nil, "ARTWORK", nil, 0)
    ebIcon:SetPoint("CENTER", echoBox, "CENTER", 0, 0)
    ebIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ebIcon:Hide()
    echoBox.iconTex = ebIcon

    local ebBezel = echoBox:CreateTexture(nil, "OVERLAY", nil, 1)
    ebBezel:SetAllPoints(echoBox)
    ebBezel:SetTexture(TEX_SEAL_BOX)
    echoBox.bezelTex = ebBezel

    echoBox.pips = {}
    for i = 1, MAX_ECHO_STACKS do
        local pip = CreateFrame("Frame", nil, echoBox)
        pip:SetFrameLevel(baseLevel + 5)
        pip:EnableMouse(false)

        local pBg = pip:CreateTexture(nil, "BACKGROUND", nil, 0)
        pBg:SetPoint("CENTER", pip, "CENTER", 0, 0)
        pBg:SetTexture(TEX_DISC)
        pBg:SetVertexColor(0.11, 0.08, 0.05, 0.90)
        pip.bgTex = pBg

        local pFill = pip:CreateTexture(nil, "ARTWORK", nil, 0)
        pFill:SetPoint("CENTER", pip, "CENTER", 0, 0)
        pFill:SetTexture(TEX_DISC)
        pFill:SetVertexColor(0.22, 0.92, 0.34, 0.96)
        pFill:Hide()
        pip.fillTex = pFill

        local pRing = pip:CreateTexture(nil, "OVERLAY", nil, 1)
        pRing:SetAllPoints(pip)
        pRing:SetTexture(TEX_PIP_RING)
        pip.ringTex = pRing

        echoBox.pips[i] = pip
    end

    echoBox:Hide()
    f.echoBox = echoBox

    -- Dedicated top-level drag hitbox with live grid + screen-center magnetic snapping
    local dragOverlay = CreateFrame("Frame", nil, f)
    dragOverlay:SetFrameLevel(baseLevel + 12)
    dragOverlay:SetAllPoints(f)
    dragOverlay:RegisterForDrag("LeftButton")
    dragOverlay:EnableMouse(false)
    dragOverlay:Hide()

    local function FinishDragging()
        if not dragState.active then return end
        dragState.active = false
        dragOverlay:SetScript("OnUpdate", nil)
        SaveClockPosition()
    end

    dragOverlay:SetScript("OnDragStart", function(self)
        if not IsClockUnlocked() then return end
        local scale = f:GetEffectiveScale() or UIParent:GetEffectiveScale() or 1
        local curX, curY = GetCursorPosition()
        curX, curY = curX / scale, curY / scale

        local fx, fy = f:GetCenter()
        local ux, uy = UIParent:GetCenter()
        dragState.active = true
        dragState.startCurX = curX
        dragState.startCurY = curY
        dragState.startOffX = (fx and ux) and (fx - ux) or (db.x or 0)
        dragState.startOffY = (fy and uy) and (fy - uy) or (db.y or -150)

        self:SetScript("OnUpdate", function()
            if not dragState.active or not IsClockUnlocked() then
                self:SetScript("OnUpdate", nil)
                return
            end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                FinishDragging()
                return
            end
            local s = f:GetEffectiveScale() or UIParent:GetEffectiveScale() or 1
            local cx, cy = GetCursorPosition()
            cx, cy = cx / s, cy / s
            local rawX = dragState.startOffX + (cx - dragState.startCurX)
            local rawY = dragState.startOffY + (cy - dragState.startCurY)
            local x, y, snapX, snapY, freeMode = ComputeSnappedPosition(rawX, rawY)

            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "CENTER", x, y)
            db.point = "CENTER"
            db.relPoint = "CENTER"
            db.x = x
            db.y = y
            RefreshGridOverlay(x, y, snapX, snapY)
            UpdateDragLabel(x, y, snapX, snapY, freeMode)
        end)
    end)
    dragOverlay:SetScript("OnDragStop", function()
        FinishDragging()
    end)
    dragOverlay:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and dragState.active then
            FinishDragging()
        elseif button == "MiddleButton" and db and IsClockUnlocked() then
            if IsShiftKeyDown and IsShiftKeyDown() then
                db.x = 0
                db.y = 0
                Print("Centered clock at screen center |cff44ff66(0, 0)|r.")
            else
                db.x = 0
                Print(("Aligned clock to horizontal screen center |cff44ff66X = 0|r (Y = %d)."):format(db.y or -150))
            end
            ApplyClockLayout()
            if RefreshConfigUI then RefreshConfigUI() end
            if RefreshOptionsPanel then RefreshOptionsPanel() end
        elseif button == "RightButton" and db and not db.locked and not isEditModeOpen then
            FinishDragging()
            db.locked = true
            ApplyClockLayout()
            if RefreshConfigUI then RefreshConfigUI() end
            if RefreshOptionsPanel then RefreshOptionsPanel() end
            Print("Position |cff44ff66locked|r (click-through).")
        end
    end)
    dragOverlay:SetScript("OnEnter", function(self)
        if GameTooltip and IsClockUnlocked() then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("SwingClock (Unlocked)", 1, 0.82, 0.25)
            GameTooltip:AddLine("Left-Click & Drag to move (snaps to grid & center)", 1, 1, 1)
            GameTooltip:AddLine("Hold SHIFT while dragging for free movement", 0.85, 0.85, 0.85)
            GameTooltip:AddLine("Middle-Click to align X = 0 (Shift: 0, 0)", 0.4, 0.85, 1)
            if isEditModeOpen then
                GameTooltip:AddLine("Exit Edit Mode to lock", 0.6, 0.85, 1)
            else
                GameTooltip:AddLine("Right-Click to lock in place", 0.4, 1, 0.5)
            end
            GameTooltip:Show()
        end
    end)
    dragOverlay:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    dragOverlay:SetScript("OnHide", function()
        FinishDragging()
        f:StopMovingOrSizing()
    end)
    f.dragOverlay = dragOverlay

    clockFrame = f
    return f
end

---------------------------------------------------------------------------
-- Events (WoW Forever PLAYER_SWING + Haste & Parry Haste Adjustments)
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

local function NormalizeSwingType(rawType)
    if rawType == nil or IsSecret(rawType) then
        return SWING_MH
    end
    local ohEnum = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.OffHand or 1
    local rgEnum = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.Ranged or 2
    if rawType == ohEnum or rawType == "OffHand" or rawType == "offhand" then
        return SWING_OH
    elseif rawType == rgEnum or rawType == "Ranged" or rawType == "ranged" then
        return SWING_RANGED
    end
    return SWING_MH
end

function handlers.PLAYER_SWING(swingDuration, swingType)
    if not db or not db.enabled then return end
    local slot = NormalizeSwingType(swingType)

    if slot == SWING_RANGED and not db.showRanged then
        return
    elseif slot == SWING_OH and not db.showOffHand then
        return
    end

    local dur = nil
    if swingDuration ~= nil then
        if IsSecret(swingDuration) then
            -- Fallback safely to non-secret unit weapon speed if duration is ever marked secret
            if slot == SWING_OH then
                _, dur = GetPlayerWeaponSpeeds()
            elseif slot == SWING_RANGED then
                dur = GetPlayerRangedSpeed()
            else
                dur = select(1, GetPlayerWeaponSpeeds())
            end
        elseif type(swingDuration) == "number" then
            if swingDuration <= 0 then
                FinishSwing(slot)
                return
            end
            dur = swingDuration
        end
    else
        -- 0-arg PLAYER_SWING fallback
        if slot == SWING_OH then
            _, dur = GetPlayerWeaponSpeeds()
        elseif slot == SWING_RANGED then
            dur = GetPlayerRangedSpeed()
        else
            dur = select(1, GetPlayerWeaponSpeeds())
        end
    end

    if dur and dur > 0 then
        -- Ranged swings drive the main clock face (unless MH melee is actively mid-swing)
        if slot == SWING_RANGED and mhState.active and not mhState.isRanged then
            return
        end
        StartSwing(slot, dur, true)

        if isPaladinClass and hasUnsealedWrath and not testPaladinPreview then
            if slot == SWING_MH then
                local now = GetTime()
                lastMHSwingTime = now
                if debugMode then
                    DebugLog(("PLAYER_SWING MH (hsDelta=%.0fms, avoidDelta=%.0fms)"):format((now - lastHolyStrikeTime) * 1000, (now - lastTargetAvoidTime) * 1000))
                end
                if (now - lastHolyStrikeTime) >= 0.35 and (now - lastTargetAvoidTime) >= 0.20 then
                    pendingEchoSwingToken = pendingEchoSwingToken + 1
                    local myToken = pendingEchoSwingToken
                    if C_Timer and C_Timer.After then
                        -- Defer 0.15s so Holy Strike (UNIT_SPELLCAST_SUCCEEDED) or
                        -- target MISS/PARRY/DODGE (UNIT_COMBAT) cancels this swing before it updates Echo stacks
                        C_Timer.After(0.15, function()
                            if pendingEchoSwingToken == myToken then
                                ApplyCombatEchoSwingHit()
                                if debugMode then
                                    DebugLog(("ApplyCombatEchoSwingHit -> echo=%s stacks=%d"):format(tostring(echoState.active), echoState.stacks or 0))
                                end
                                RefreshPaladinAuras()
                            elseif debugMode then
                                DebugLog("MH swing cancelled before 150ms commit")
                            end
                        end)
                    else
                        ApplyCombatEchoSwingHit()
                    end
                end
            end
            RefreshPaladinAuras()
        end
    end
end

-- Rescale active swing smoothly when haste changes mid-swing (Flurry, Slice and Dice, Bloodlust, etc.)
local function RescaleActiveSwing(state, cdWidget, newSpeed, isMH)
    if not state.active or not newSpeed or newSpeed <= 0 or state.speed <= 0 then return end
    if math.abs(newSpeed - state.speed) < 0.005 then return end

    local now = GetTime()
    local elapsed = now - state.startTime
    local rem = (state.startTime + state.duration) - now
    if rem <= 0 or state.duration <= 0 then return end

    local progress = Clamp(elapsed / state.duration, 0.0, 0.999)
    local ratio = newSpeed / state.speed
    local newRem = rem * ratio
    local newDuration = newRem / (1.0 - progress)
    local newStart = now - (progress * newDuration)

    state.speed = newSpeed
    state.startTime = newStart
    state.duration = newDuration
    cdWidget:SetCooldown(newStart, newDuration)
    ApplyFillingAppearance(isMH)
end

function handlers.UNIT_ATTACK_SPEED(unit)
    if IsSecret(unit) or unit ~= "player" or not clockFrame then return end
    RefreshOffHandStatus()
    local mhSpeed, ohSpeed = GetPlayerWeaponSpeeds()
    if mhState.active then
        local targetSpeed = mhState.isRanged and GetPlayerRangedSpeed() or mhSpeed
        RescaleActiveSwing(mhState, clockFrame.mhCooldown, targetSpeed, true)
    end
    if ohState.active and ohSpeed then
        RescaleActiveSwing(ohState, clockFrame.ohCooldown, ohSpeed, false)
    end
end

-- Classic / Forever Parry Haste + Target Miss/Parry/Dodge cancellation for Unsealed Wrath
function handlers.UNIT_COMBAT(unit, action)
    if not db or not db.enabled then return end
    if IsSecret(unit) or IsSecret(action) then
        if debugMode then
            DebugLog(("UNIT_COMBAT SECRET (unitSecret=%s, actionSecret=%s)"):format(tostring(IsSecret(unit)), tostring(IsSecret(action))))
        end
        return
    end
    if debugMode and (unit == "target" or unit == "player") then
        DebugLog(("UNIT_COMBAT unit=%s action=%s (+%.0fms from MH)"):format(tostring(unit), tostring(action), (GetTime() - lastMHSwingTime) * 1000))
    end

    if isPaladinClass and unit == "target" then
        if action == "MISS" or action == "PARRY" or action == "DODGE" or action == "EVADE"
            or action == "IMMUNE" or action == "DEFLECT" or action == "ABSORB" then
            lastTargetAvoidTime = GetTime()
            pendingEchoSwingToken = pendingEchoSwingToken + 1
        end
    end

    if not db.parryHaste then return end
    if unit ~= "player" or action ~= "PARRY" then return end
    if not mhState.active or mhState.isRanged or mhState.duration <= 0 then return end

    local now = GetTime()
    local rem = (mhState.startTime + mhState.duration) - now
    if rem <= 0 then return end

    local frac = rem / mhState.duration
    local newRem = rem
    if frac > 0.60 then
        newRem = rem - (0.40 * mhState.duration)
    elseif frac > 0.20 then
        newRem = 0.20 * mhState.duration
    else
        return
    end

    local shift = rem - newRem
    if shift > 0.01 then
        mhState.startTime = mhState.startTime - shift
        clockFrame.mhCooldown:SetCooldown(mhState.startTime, mhState.duration)
        ApplyFillingAppearance(true)
    end
end

function handlers.PLAYER_EQUIPMENT_CHANGED(slot)
    if IsSecret(slot) then return end
    if slot == 16 or slot == 17 or slot == 18 then
        RefreshOffHandStatus()
    end
end

function handlers.PLAYER_ENTERING_WORLD()
    ApplyBlizzardBarCVar()
    RefreshOffHandStatus()
    RefreshPaladinStatus()
    ApplyClockLayout()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, function()
            if isPaladinClass then
                RefreshPaladinStatus()
                ApplyClockLayout()
            end
        end)
        C_Timer.After(2.0, function()
            if isPaladinClass then
                RefreshPaladinStatus()
                ApplyClockLayout()
            end
        end)
    end
end

function handlers.UNIT_AURA(unit)
    if IsSecret(unit) or unit ~= "player" then return end
    if not isPaladinClass then return end

    RefreshPaladinAuras()
end

function handlers.UNIT_SPELLCAST_SENT(unit, _, _, spellID)
    if not isPaladinClass or IsSecret(unit) or unit ~= "player" then return end
    if not IsSecret(spellID) and type(spellID) == "number" then
        if IsHolyStrikeSpell(spellID, nil) then
            MarkHolyStrikeCast()
            return
        end
        local isSeal, icon, spName = IdentifyPaladinSealSpell(spellID, nil)
        if isSeal then
            pendingSealCast = { spellID = spellID, name = spName, icon = icon, time = GetTime() }
            ActivateSealFromCast(spellID, spName, icon)
        end
    end
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    if not isPaladinClass or IsSecret(unit) or unit ~= "player" then return end
    local now = GetTime()
    if not IsSecret(spellID) and type(spellID) and type(spellID) == "number" then
        if IsHolyStrikeSpell(spellID, nil) then
            MarkHolyStrikeCast()
            return
        end
        local isSeal, icon, spName = IdentifyPaladinSealSpell(spellID, nil)
        if isSeal then
            pendingSealCast = nil
            prevSealSnapshot = nil
            ActivateSealFromCast(spellID, spName, icon)
        end
    elseif pendingSealCast and (now - pendingSealCast.time) < 1.0 then
        -- spellID is secret in combat, confirm the pending Seal cast captured from UseAction / CastSpell
        local p = pendingSealCast
        pendingSealCast = nil
        prevSealSnapshot = nil
        ActivateSealFromCast(p.spellID, p.name, p.icon)
    end
    RefreshPaladinAuras()
end

local function RevertFailedPendingSealCast(unit)
    if not isPaladinClass or IsSecret(unit) or unit ~= "player" then return end
    local now = GetTime()
    if pendingSealCast and prevSealSnapshot and (now - pendingSealCast.time) < 0.35 then
        sealState.active         = prevSealSnapshot.active
        sealState.icon           = prevSealSnapshot.icon
        sealState.duration       = prevSealSnapshot.duration
        sealState.expirationTime = prevSealSnapshot.expirationTime
        sealState.spellID        = prevSealSnapshot.spellID
        sealState.auraInstanceID = prevSealSnapshot.auraInstanceID
        sealState.lastCastTime   = prevSealSnapshot.lastCastTime
        pendingSealCast = nil
        prevSealSnapshot = nil
        if UpdatePaladinUI then UpdatePaladinUI() end
    end
end

function handlers.UNIT_SPELLCAST_FAILED(unit)
    RevertFailedPendingSealCast(unit)
end

function handlers.UNIT_SPELLCAST_FAILED_QUIET(unit)
    RevertFailedPendingSealCast(unit)
end

function handlers.ACTIONBAR_SLOT_CHANGED()
    if isPaladinClass then
        HarvestKnownPaladinSeals()
    end
end

function handlers.CHARACTER_POINTS_CHANGED()
    if isPaladinClass then
        RefreshPaladinStatus()
        ApplyClockLayout()
    end
end

function handlers.PLAYER_TALENT_UPDATE()
    if isPaladinClass then
        RefreshPaladinStatus()
        ApplyClockLayout()
    end
end

function handlers.SPELLS_CHANGED()
    if isPaladinClass then
        RefreshPaladinStatus()
        ApplyClockLayout()
    end
end

function handlers.TRAIT_CONFIG_UPDATED()
    if isPaladinClass then
        RefreshPaladinStatus()
        ApplyClockLayout()
    end
end

function handlers.ACTIVE_TALENT_GROUP_CHANGED()
    if isPaladinClass then
        RefreshPaladinStatus()
        ApplyClockLayout()
    end
end

function handlers.PLAYER_LEVEL_UP()
    if isPaladinClass then
        RefreshPaladinStatus()
        ApplyClockLayout()
    end
end

function handlers.PLAYER_REGEN_DISABLED()
    RefreshVisibility()
end

function handlers.PLAYER_REGEN_ENABLED()
    pendingEchoSwingToken = pendingEchoSwingToken + 1
    if pendingCVars then
        pendingCVars = false
        ApplyBlizzardBarCVar()
    end
    if isPaladinClass then
        RefreshPaladinStatus()
        ApplyClockLayout()
    end
    RefreshVisibility()
end

function handlers.PLAYER_TARGET_CHANGED()
    RefreshVisibility()
end

function handlers.DISPLAY_SIZE_CHANGED()
    if IsClockUnlocked() then
        RefreshGridOverlay(db and db.x or 0, db and db.y or -150, db and db.x == 0, db and db.y == 0)
    end
end

function handlers.UI_SCALE_CHANGED()
    if IsClockUnlocked() then
        RefreshGridOverlay(db and db.x or 0, db and db.y or -150, db and db.x == 0, db and db.y == 0)
    end
end

-- Direct server combat log aura tracking (SPELL_AURA_APPLIED / DOSE / REMOVED) + non-Forever swing fallback
function handlers.COMBAT_LOG_EVENT_UNFILTERED()
    if not db or not db.enabled or not CombatLogGetCurrentEventInfo then return end
    local _, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, arg12, arg13, _, _, arg16, _, _, _, _, isOffHand = CombatLogGetCurrentEventInfo()
    if IsSecret(subevent) then return end
    local playerGUID = UnitGUID and UnitGUID("player") or nil
    if not playerGUID or IsSecret(playerGUID) then return end

    -- 1. Paladin Seal & Echo aura events directly from server combat log when non-secret
    if isPaladinClass and not testPaladinPreview and not IsSecret(destGUID) and destGUID == playerGUID then
        if subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_APPLIED_DOSE"
            or subevent == "SPELL_AURA_REMOVED_DOSE" or subevent == "SPELL_AURA_REFRESH"
            or subevent == "SPELL_AURA_REMOVED" then
            local spID = (not IsSecret(arg12) and type(arg12) == "number") and arg12 or nil
            local spName = (not IsSecret(arg13) and type(arg13) == "string") and arg13 or nil
            local dose = (not IsSecret(arg16) and type(arg16) == "number") and arg16 or nil

            local isEcho = (spID and ECHO_SPELL_IDS[spID] ~= nil)
                or (type(spName) == "string" and spName:lower():find("^echo of ") ~= nil)
            if isEcho then
                pendingEchoSwingToken = pendingEchoSwingToken + 1
                local now = GetTime()
                if subevent == "SPELL_AURA_REMOVED" then
                    if not echoState.spellID or not spID or echoState.spellID == spID then
                        echoState.active = false
                        echoState.stacks = 0
                        echoState.icon = nil
                        echoState.spellID = nil
                        echoState.duration = 0
                        echoState.expirationTime = 0
                    end
                elseif subevent == "SPELL_AURA_APPLIED_DOSE" then
                    echoState.active = true
                    echoState.spellID = spID or echoState.spellID
                    echoState.icon = (spID and ECHO_SPELL_IDS[spID]) or FallbackIconForAura(spName, spID)
                    echoState.stacks = Clamp((dose and dose > 0) and dose or ((echoState.stacks or 1) + 1), 1, MAX_ECHO_STACKS)
                    echoState.duration = 30
                    echoState.expirationTime = now + 30
                elseif subevent == "SPELL_AURA_REMOVED_DOSE" then
                    echoState.stacks = Clamp((dose and dose > 0) and dose or ((echoState.stacks or 2) - 1), 1, MAX_ECHO_STACKS)
                else
                    echoState.active = true
                    echoState.spellID = spID or echoState.spellID
                    echoState.icon = (spID and ECHO_SPELL_IDS[spID]) or FallbackIconForAura(spName, spID)
                    echoState.stacks = Clamp((dose and dose > 0) and dose or 1, 1, MAX_ECHO_STACKS)
                    echoState.duration = 30
                    echoState.expirationTime = now + 30
                end
                if UpdatePaladinUI then UpdatePaladinUI() end
                return
            end

            local isSeal, sealIcon, sealName = IdentifyPaladinSealSpell(spID, spName)
            if isSeal then
                if subevent == "SPELL_AURA_REMOVED" then
                    if not sealState.spellID or not spID or sealState.spellID == spID then
                        sealState.active = false
                        sealState.expirationTime = 0
                        sealState.icon = nil
                        sealState.spellID = nil
                        sealState.lastCastTime = nil
                        if UpdatePaladinUI then UpdatePaladinUI() end
                    end
                else
                    ActivateSealFromCast(spID, sealName, sealIcon)
                end
                return
            end
        end
    end

    -- 2. Fallback swing detection ONLY for non-Forever Classic clients that lack native PLAYER_SWING
    if hasNativePlayerSwing or IsSecret(sourceGUID) or sourceGUID ~= playerGUID then return end

    if subevent == "SWING_DAMAGE" then
        local off = (type(arg12) == "boolean" and arg12) or (type(isOffHand) == "boolean" and isOffHand)
        local mh, oh = GetPlayerWeaponSpeeds()
        if off and oh then
            StartSwing(SWING_OH, oh, true)
        elseif mh then
            StartSwing(SWING_MH, mh, true)
        end
    elseif subevent == "SWING_MISSED" then
        local off = (type(isOffHand) == "boolean" and isOffHand)
        local mh, oh = GetPlayerWeaponSpeeds()
        if off and oh then
            StartSwing(SWING_OH, oh, true)
        elseif mh then
            StartSwing(SWING_MH, mh, true)
        end
    elseif (subevent == "RANGE_DAMAGE" or subevent == "RANGE_MISSED") and db.showRanged then
        local rSpeed = GetPlayerRangedSpeed()
        if rSpeed then StartSwing(SWING_RANGED, rSpeed, true) end
    end
end

---------------------------------------------------------------------------
-- Demo / Test Simulation (/sc test)
---------------------------------------------------------------------------
local function CancelTestTimers()
    for i = #testTimers, 1, -1 do
        local t = testTimers[i]
        if t and t.Cancel then t:Cancel() end
        testTimers[i] = nil
    end
    if testDualPreview then
        testDualPreview = false
        UpdateOffHandVisibility()
    end
    if testPaladinPreview then
        testPaladinPreview = false
        RefreshPaladinAuras()
        ApplyClockLayout()
    end
    RefreshVisibility()
end

local function RunTestSimulation(dualMode)
    CancelTestTimers()
    if not C_Timer or not C_Timer.NewTimer then
        StartSwing(SWING_MH, 2.4, true)
        return
    end

    local mhDur = 2.2
    local ohDur = 1.4

    -- If on a Paladin (or always during test on a Paladin), also preview Active Seal + Unsealed Wrath 1->2->3 Echo stack pips!
    if isPaladinClass then
        testPaladinPreview = true
        local now = GetTime()
        sealState.active = true
        sealState.icon = 132325 -- Seal of Righteousness
        sealState.duration = 30
        sealState.expirationTime = now + 28.0

        echoState.active = true
        echoState.icon = 132325
        echoState.stacks = 1
        ApplyClockLayout()
        EnsureLoopRunning()

        testTimers[#testTimers + 1] = C_Timer.NewTimer(mhDur, function()
            echoState.stacks = 2
            UpdatePaladinUI()
        end)
        testTimers[#testTimers + 1] = C_Timer.NewTimer(mhDur * 2, function()
            echoState.stacks = 3
            UpdatePaladinUI()
        end)
        -- Switch seal & expend Echo stacks on the 3rd swing!
        testTimers[#testTimers + 1] = C_Timer.NewTimer(mhDur * 2 + 1.4, function()
            sealState.icon = 132347 -- Seal of Command
            sealState.expirationTime = GetTime() + 30.0
            echoState.active = false
            echoState.stacks = 0
            UpdatePaladinUI()
        end)
    end

    if dualMode then
        testDualPreview = true
        UpdateOffHandVisibility()
        Print("Testing Dual-Wield swings (Main Hand 2.4s + Inner Off-Hand 1.5s)...")
    else
        Print("Testing Weapon Swings (watch yellow pie fill -> 12 o'clock green pulse -> ready green)...")
    end

    -- Swing 1 immediately, Swing 2 right at 12 o'clock (continuous attack), then let it turn solid green & fire Swing 3 after a pause!
    StartSwing(SWING_MH, mhDur, true)
    if dualMode then
        testTimers[#testTimers + 1] = C_Timer.NewTimer(0.35, function()
            StartSwing(SWING_OH, ohDur, true)
        end)
        testTimers[#testTimers + 1] = C_Timer.NewTimer(0.35 + ohDur, function()
            StartSwing(SWING_OH, ohDur, true)
        end)
    end

    -- Continuous back-to-back swing passing 12 o'clock
    testTimers[#testTimers + 1] = C_Timer.NewTimer(mhDur, function()
        StartSwing(SWING_MH, mhDur, true)
    end)

    -- After 2nd swing finishes at 2*mhDur (4.4s), pause for 1.4s so user sees it rest in full Ready Green, then fire 1 more swing!
    testTimers[#testTimers + 1] = C_Timer.NewTimer(mhDur * 2 + 1.4, function()
        StartSwing(SWING_MH, mhDur, true)
        if dualMode then
            StartSwing(SWING_OH, ohDur, true)
        end
    end)

    testTimers[#testTimers + 1] = C_Timer.NewTimer(mhDur * 3 + 2.2, function()
        CancelTestTimers()
    end)
end

---------------------------------------------------------------------------
-- Settings UI (/sc) & Blizzard AddOns Options Panel
---------------------------------------------------------------------------
local function MakeStepRow(parent, y, labelText, onMinus, onPlus)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 16, y)
    lbl:SetText(labelText)

    local plusBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    plusBtn:SetSize(26, 22)
    plusBtn:SetPoint("TOPRIGHT", -16, y + 4)
    plusBtn:SetText("+")
    plusBtn:SetScript("OnClick", onPlus)

    local valTxt = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valTxt:SetWidth(64)
    valTxt:SetPoint("RIGHT", plusBtn, "LEFT", -4, 0)
    valTxt:SetJustifyH("CENTER")

    local minusBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    minusBtn:SetSize(26, 22)
    minusBtn:SetPoint("RIGHT", valTxt, "LEFT", -4, 0)
    minusBtn:SetText("-")
    minusBtn:SetScript("OnClick", onMinus)

    return valTxt
end

local function MakeToggleBtn(parent, x, y, w, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(w, 24)
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetScript("OnClick", onClick)
    return btn
end

local function CreateConfigUI()
    if configFrame then return configFrame end

    local f = CreateFrame("Frame", "SwingClockConfigFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(330, 404)
    f:SetPoint("CENTER", 220, 20)
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.08, 0.06, 0.04, 0.94)
        f:SetBackdropBorderColor(0.68, 0.55, 0.34, 0.95)
    end
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "SwingClockConfigFrame")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("|cffdfca9aSwingClock|r")

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetText("Circular 12 o'clock Weapon Swing Timer")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Top Action Row: Unlock & Drag + Test Swing + Test Dual
    f.lockBtn = MakeToggleBtn(f, 16, -48, 106, function()
        db.locked = not db.locked
        ApplyClockLayout()
        RefreshConfigUI()
        if RefreshOptionsPanel then RefreshOptionsPanel() end
    end)

    local testBtn = MakeToggleBtn(f, 126, -48, 92, function()
        RunTestSimulation(false)
    end)
    testBtn:SetText("Test Swing")

    local testDualBtn = MakeToggleBtn(f, 222, -48, 92, function()
        RunTestSimulation(true)
    end)
    testDualBtn:SetText("Test Dual")

    f.dragHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.dragHint:SetPoint("TOPLEFT", 16, -77)
    f.dragHint:SetText("|cffaaaaaaUnlock to see alignment grid & snap to center (Shift = free).|r")

    -- Position assist row: Grid Snap cycle + Center Clock X=0 (Shift: 0, 0)
    f.snapBtn = MakeToggleBtn(f, 16, -102, 145, function()
        if db.snapToGrid ~= false then
            if (db.gridSize or 20) <= 20 then
                db.gridSize = 32
            else
                db.snapToGrid = false
            end
        else
            db.snapToGrid = true
            db.gridSize = 20
        end
        ApplyClockLayout()
        RefreshConfigUI()
    end)

    f.centerBtn = MakeToggleBtn(f, 169, -102, 145, function()
        if IsShiftKeyDown and IsShiftKeyDown() then
            db.x = 0
            db.y = 0
            Print("Centered clock at screen center |cff44ff66(0, 0)|r.")
        else
            db.x = 0
            Print(("Aligned clock to horizontal center |cff44ff66X = 0|r (Y = %d)."):format(db.y or -150))
        end
        ApplyClockLayout()
        RefreshConfigUI()
        if RefreshOptionsPanel then RefreshOptionsPanel() end
    end)
    f.centerBtn:SetText("Center X=0")

    -- Numeric step controls
    f.sizeVal = MakeStepRow(f, -136, "Clock Size", function()
        db.size = Clamp((db.size or DEFAULTS.size) - 4, 24, 320)
        ApplyClockLayout()
        RefreshConfigUI()
    end, function()
        db.size = Clamp((db.size or DEFAULTS.size) + 4, 24, 320)
        ApplyClockLayout()
        RefreshConfigUI()
    end)

    f.yellowVal = MakeStepRow(f, -166, "Yellow Pie Opacity", function()
        db.yellowAlpha = Clamp(math.floor(((db.yellowAlpha or DEFAULTS.yellowAlpha) - 0.05) * 100 + 0.5) / 100, 0.15, 1.0)
        ApplyClockLayout()
        RefreshConfigUI()
    end, function()
        db.yellowAlpha = Clamp(math.floor(((db.yellowAlpha or DEFAULTS.yellowAlpha) + 0.05) * 100 + 0.5) / 100, 0.15, 1.0)
        ApplyClockLayout()
        RefreshConfigUI()
    end)

    f.pulseVal = MakeStepRow(f, -196, "12:00 Green Pulse", function()
        db.pulseStrength = Clamp(math.floor(((db.pulseStrength or 1.0) - 0.20) * 100 + 0.5) / 100, 0.0, 2.0)
        TriggerPulse(true)
        RefreshConfigUI()
    end, function()
        db.pulseStrength = Clamp(math.floor(((db.pulseStrength or 1.0) + 0.20) * 100 + 0.5) / 100, 0.0, 2.0)
        TriggerPulse(true)
        RefreshConfigUI()
    end)

    -- Feature toggles (2 columns)
    f.ohBtn = MakeToggleBtn(f, 16, -232, 145, function()
        db.showOffHand = not db.showOffHand
        UpdateOffHandVisibility()
        RefreshConfigUI()
    end)

    f.rangedBtn = MakeToggleBtn(f, 169, -232, 145, function()
        db.showRanged = not db.showRanged
        RefreshConfigUI()
    end)

    f.edgeBtn = MakeToggleBtn(f, 16, -262, 145, function()
        db.drawEdge = not db.drawEdge
        ApplyClockLayout()
        RefreshConfigUI()
    end)

    f.textBtn = MakeToggleBtn(f, 169, -262, 145, function()
        db.showText = not db.showText
        if not db.showText and clockFrame then clockFrame.timerText:SetText("") end
        RefreshConfigUI()
    end)

    f.blizzBtn = MakeToggleBtn(f, 16, -292, 298, function()
        db.hideBlizzardBar = not db.hideBlizzardBar
        ApplyBlizzardBarCVar()
        RefreshConfigUI()
    end)

    f.visBtn = MakeToggleBtn(f, 16, -322, 298, function()
        if db.visibility == "always" then
            db.visibility = "target"
        elseif db.visibility == "target" then
            db.visibility = "combat"
        else
            db.visibility = "always"
        end
        RefreshVisibility()
        RefreshConfigUI()
    end)

    -- Bottom row: Enable/Disable + Reset Defaults
    f.enableBtn = MakeToggleBtn(f, 16, -362, 145, function()
        db.enabled = not db.enabled
        ApplyBlizzardBarCVar()
        ApplyClockLayout()
        RefreshConfigUI()
    end)

    local resetBtn = MakeToggleBtn(f, 169, -362, 145, function()
        local savedCVar = db.savedShowSwingTimer
        wipe(db)
        for k, v in pairs(DEFAULTS) do
            db[k] = type(v) == "table" and CopyTable(v) or v
        end
        db.savedShowSwingTimer = savedCVar
        ApplyBlizzardBarCVar()
        ApplyClockLayout()
        RefreshConfigUI()
        if RefreshOptionsPanel then RefreshOptionsPanel() end
        Print("Reset settings and position to defaults.")
    end)
    resetBtn:SetText("Reset Defaults")

    configFrame = f
    return f
end

local function TagOnOff(v)
    return v and "|cff44ff66ON|r" or "|cffff5555OFF|r"
end

RefreshConfigUI = function()
    if not configFrame or not configFrame:IsShown() then return end
    configFrame.lockBtn:SetText(db.locked and "Unlock & Drag" or "|cffffd200Lock Position|r")
    if db.locked then
        configFrame.dragHint:SetText("|cffaaaaaaUnlock to see alignment grid & snap to center (Shift = free).|r")
    else
        configFrame.dragHint:SetText(("|cff66ff99Unlocked (%d, %d): Drag snaps to grid/center (Right-Click locks).|r"):format(db.x or 0, db.y or 0))
    end
    if db.snapToGrid ~= false then
        configFrame.snapBtn:SetText(("Grid Snap: |cff44ff66%dpx|r"):format(db.gridSize or 20))
    else
        configFrame.snapBtn:SetText("Snap: |cffffd200Center Only|r")
    end
    configFrame.sizeVal:SetText(("%d px"):format(db.size or DEFAULTS.size))
    configFrame.yellowVal:SetText(("%d%%"):format(math.floor((db.yellowAlpha or DEFAULTS.yellowAlpha) * 100 + 0.5)))
    configFrame.pulseVal:SetText(("%d%%"):format(math.floor((db.pulseStrength or 1.0) * 100 + 0.5)))

    configFrame.ohBtn:SetText("Off-Hand: " .. TagOnOff(db.showOffHand))
    configFrame.rangedBtn:SetText("Ranged: " .. TagOnOff(db.showRanged))
    configFrame.edgeBtn:SetText("Clock Edge: " .. TagOnOff(db.drawEdge))
    configFrame.textBtn:SetText("Numbers: " .. TagOnOff(db.showText))
    configFrame.blizzBtn:SetText("Hide Blizzard Swing Bar: " .. TagOnOff(db.hideBlizzardBar))

    local visLabels = {
        always = "Always Visible (Stays Green)",
        target = "Combat or Attackable Target",
        combat = "In Combat Only",
    }
    configFrame.visBtn:SetText("Show: |cffffd200" .. (visLabels[db.visibility] or visLabels.always) .. "|r")
    configFrame.enableBtn:SetText("Addon: " .. TagOnOff(db.enabled))
end

local function ToggleConfigUI()
    local f = CreateConfigUI()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        RefreshConfigUI()
    end
end

RefreshOptionsPanel = function()
    if not optionsPanel or not db then return end
    optionsPanel.lockBtn:SetText(db.locked and "Unlock & Drag Clock" or "Lock Clock Position")
    optionsPanel.posText:SetText(("Current Position: %s (%d, %d) — %s"):format(
        db.point or "CENTER", db.x or 0, db.y or 0,
        db.locked and "|cff44ff66Locked|r" or "|cffffd200Unlocked (Drag Clock)|r"
    ))
end

local function RegisterBlizzardOptionsPanel()
    if optionsPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "SwingClock"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cffdfca9aSwingClock|r")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetText("Circular antique-brass WoW UI weapon swing clock with 12 o'clock green ready state & attack pulse.")

    local posText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    posText:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    panel.posText = posText

    local lockBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    lockBtn:SetSize(160, 26)
    lockBtn:SetPoint("TOPLEFT", posText, "BOTTOMLEFT", 0, -12)
    lockBtn:SetScript("OnClick", function()
        if not db then return end
        db.locked = not db.locked
        ApplyClockLayout()
        RefreshConfigUI()
        RefreshOptionsPanel()
    end)
    panel.lockBtn = lockBtn

    local openBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openBtn:SetSize(170, 26)
    openBtn:SetPoint("LEFT", lockBtn, "RIGHT", 10, 0)
    openBtn:SetText("Open SwingClock Settings")
    openBtn:SetScript("OnClick", function()
        local f = CreateConfigUI()
        f:Show()
        RefreshConfigUI()
    end)

    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(110, 26)
    testBtn:SetPoint("LEFT", openBtn, "RIGHT", 10, 0)
    testBtn:SetText("Test Swing")
    testBtn:SetScript("OnClick", function()
        RunTestSimulation(false)
    end)

    local centerBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    centerBtn:SetSize(160, 26)
    centerBtn:SetPoint("TOPLEFT", lockBtn, "BOTTOMLEFT", 0, -12)
    centerBtn:SetText("Center Horizontally (X=0)")
    centerBtn:SetScript("OnClick", function()
        if not db then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            db.x = 0
            db.y = 0
        else
            db.x = 0
        end
        ApplyClockLayout()
        RefreshConfigUI()
        RefreshOptionsPanel()
    end)

    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 26)
    resetBtn:SetPoint("LEFT", centerBtn, "RIGHT", 10, 0)
    resetBtn:SetText("Reset Position")
    resetBtn:SetScript("OnClick", function()
        if not db then return end
        db.point = DEFAULTS.point
        db.relPoint = DEFAULTS.relPoint
        db.x = DEFAULTS.x
        db.y = DEFAULTS.y
        ApplyClockLayout()
        RefreshConfigUI()
        RefreshOptionsPanel()
    end)

    local cmds = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cmds:SetPoint("TOPLEFT", centerBtn, "BOTTOMLEFT", 0, -18)
    cmds:SetJustifyH("LEFT")
    cmds:SetText("Slash commands:\n  /sc — Open settings window\n  /sc unlock — Unlock, show grid, and drag (snaps to center & grid)\n  /sc lock — Lock clock position (click-through)\n  /sc center — Align clock to horizontal center (X=0, or /sc center all)\n  /sc snap [20|32|off] — Toggle grid snapping while keeping center snap\n  /sc test — Simulate weapon swings (or /sc test dual)")

    panel:SetScript("OnShow", RefreshOptionsPanel)
    optionsPanel = panel

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, panel.name)
        if ok and category then
            category.ID = panel.name
            pcall(Settings.RegisterAddOnCategory, category)
        end
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, panel)
    end
end

---------------------------------------------------------------------------
-- Initialization & Slash Commands
---------------------------------------------------------------------------
function handlers.ADDON_LOADED(name)
    if name ~= ADDON_NAME then return end
    SwingClockDB = SwingClockDB or {}
    db = SwingClockDB
    local prevVersion = (db.enabled ~= nil) and (db.visualVersion or 1) or 3
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            db[k] = type(v) == "table" and CopyTable(v) or v
        end
    end
    if prevVersion < 2 then
        -- Upgrade v1 neon-copper defaults to WoW UI antique-brass / warm umber palette cleanly
        db.bgAlpha = DEFAULTS.bgAlpha
        db.yellowAlpha = DEFAULTS.yellowAlpha
        db.readyAlpha = DEFAULTS.readyAlpha
        db.fillColor = CopyTable(DEFAULTS.fillColor)
        db.ohFillColor = CopyTable(DEFAULTS.ohFillColor)
        db.readyColor = CopyTable(DEFAULTS.readyColor)
        db.pulseColor = CopyTable(DEFAULTS.pulseColor)
    end
    if prevVersion < 3 then
        -- Upgrade old 68px default clock diameter to the doubled 136px default
        if db.size == nil or db.size == 68 then
            db.size = DEFAULTS.size
        end
        db.visualVersion = 3
    end

    CreateClockFrame()
    RegisterBlizzardOptionsPanel()
    RefreshOffHandStatus()
    RefreshPaladinStatus()
    ApplyClockLayout()
    ApplyBlizzardBarCVar()

    -- Integrate seamlessly with WoW Forever's Edit Mode so dragging works there too
    if EventRegistry and EventRegistry.RegisterCallback then
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", function()
            isEditModeOpen = true
            ApplyClockLayout()
            RefreshConfigUI()
            RefreshOptionsPanel()
        end, ADDON_NAME)
        pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", function()
            isEditModeOpen = false
            dragState.active = false
            if clockFrame then
                if clockFrame.dragOverlay then clockFrame.dragOverlay:SetScript("OnUpdate", nil) end
                clockFrame:StopMovingOrSizing()
            end
            ApplyClockLayout()
            RefreshConfigUI()
            RefreshOptionsPanel()
        end, ADDON_NAME)
    end
end

-- Register events safely (tolerating client flavor differences)
hasNativePlayerSwing = pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_SWING")
for event in pairs(handlers) do
    if event ~= "PLAYER_SWING" then
        if event ~= "COMBAT_LOG_EVENT_UNFILTERED" or not hasNativePlayerSwing then
            pcall(eventFrame.RegisterEvent, eventFrame, event)
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h then h(...) end
end)

local function PrintHelp()
    Print("commands:")
    print("  /sc - open/close the SwingClock settings window")
    print("  /sc unlock - unlock the clock, show alignment grid, and drag (snaps to center & grid)")
    print("  /sc lock - lock the clock position (click-through)")
    print("  /sc center [all] - snap horizontally to X=0 (or 'all' for exact screen center 0, 0)")
    print("  /sc snap [off|<8-64>] - toggle grid snapping or set grid spacing in px (default 20)")
    print("  /sc test [dual] - simulate weapon swings (or dual-wield swings)")
    print("  /sc size <24-320> - set clock diameter in pixels (default 136)")
    print("  /sc alpha <15-100> - set yellow pie-chart opacity % (default 74)")
    print("  /sc pulse <0-200> - set 12 o'clock green pulse strength % (default 100)")
    print("  /sc show <always|target|combat> - set when the clock is shown")
    print("  /sc offhand - toggle inner Off-Hand ring when dual-wielding")
    print("  /sc ranged - toggle Ranged (Auto Shot / Wand) swing tracking")
    print("  /sc blizzard - toggle hiding Blizzard's built-in swing bar (showSwingTimer)")
    print("  /sc text - toggle countdown numbers in the center")
    print("  /sc reset - reset position and settings to defaults")
end

SLASH_SWINGCLOCK1 = "/sc"
SLASH_SWINGCLOCK2 = "/swingclock"
SlashCmdList.SWINGCLOCK = function(msg)
    if not db then return end
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

    if cmd == "" or cmd == "config" or cmd == "options" then
        ToggleConfigUI()
    elseif cmd == "unlock" or cmd == "move" or cmd == "drag" then
        db.locked = false
        ApplyClockLayout()
        RefreshConfigUI()
        RefreshOptionsPanel()
        Print("Position |cffffd200unlocked|r — Left-drag the clock to move it, Right-click it (or /sc lock) to lock.")
    elseif cmd == "lock" then
        db.locked = not db.locked
        ApplyClockLayout()
        RefreshConfigUI()
        RefreshOptionsPanel()
        Print(db.locked and "Position |cff44ff66locked|r (click-through)." or "Position |cffffd200unlocked|r — Left-drag the clock to move it, Right-click it (or /sc lock) to lock.")
    elseif cmd == "center" then
        if arg == "all" or arg == "both" or arg == "screen" or arg == "xy" then
            db.x = 0
            db.y = 0
            Print("Centered clock at exact screen center |cff44ff66(0, 0)|r.")
        else
            db.x = 0
            Print(("Aligned clock to horizontal screen center |cff44ff66X = 0|r (Y = %d)."):format(db.y or -150))
        end
        ApplyClockLayout()
        RefreshConfigUI()
        RefreshOptionsPanel()
    elseif cmd == "snap" or cmd == "grid" then
        local pxArg = tonumber(arg)
        if arg == "off" or arg == "center" or arg == "false" then
            db.snapToGrid = false
            Print("Grid snap disabled (Center X=0 / Y=0 magnetic snap stays active).")
        elseif arg == "on" or arg == "true" then
            db.snapToGrid = true
            Print(("Grid snap |cff44ff66ON|r (%dpx grid + center snap)."):format(db.gridSize or 20))
        elseif pxArg then
            db.snapToGrid = true
            db.gridSize = Clamp(math.floor(pxArg + 0.5), 8, 64)
            Print(("Grid snap |cff44ff66ON|r (%dpx grid + center snap)."):format(db.gridSize))
        else
            db.snapToGrid = not (db.snapToGrid ~= false)
            if db.snapToGrid then
                Print(("Grid snap |cff44ff66ON|r (%dpx grid + center snap)."):format(db.gridSize or 20))
            else
                Print("Grid snap |cffffd200OFF|r (Center X=0 / Y=0 snap remains active).")
            end
        end
        ApplyClockLayout()
        RefreshConfigUI()
    elseif cmd == "test" or cmd == "demo" then
        RunTestSimulation(arg == "dual" or arg == "dw" or arg == "oh")
    elseif cmd == "size" and tonumber(arg) then
        db.size = Clamp(math.floor(tonumber(arg) + 0.5), 24, 320)
        ApplyClockLayout()
        RefreshConfigUI()
        Print(("Clock size set to %d px."):format(db.size))
    elseif cmd == "alpha" and tonumber(arg) then
        local v = tonumber(arg)
        if v > 1 then v = v / 100 end
        db.yellowAlpha = Clamp(v, 0.15, 1.0)
        ApplyClockLayout()
        RefreshConfigUI()
        Print(("Yellow pie opacity set to %d%%."):format(math.floor(db.yellowAlpha * 100 + 0.5)))
    elseif cmd == "pulse" and tonumber(arg) then
        local v = tonumber(arg)
        if v > 2 then v = v / 100 end
        db.pulseStrength = Clamp(v, 0.0, 2.0)
        TriggerPulse(true)
        RefreshConfigUI()
        Print(("Green pulse strength set to %d%%."):format(math.floor(db.pulseStrength * 100 + 0.5)))
    elseif cmd == "show" or cmd == "vis" or cmd == "visibility" then
        if arg == "always" or arg == "target" or arg == "combat" then
            db.visibility = arg
        else
            db.visibility = (db.visibility == "always" and "target") or (db.visibility == "target" and "combat") or "always"
        end
        RefreshVisibility()
        RefreshConfigUI()
        Print("Visibility mode: " .. db.visibility)
    elseif cmd == "offhand" or cmd == "oh" then
        db.showOffHand = not db.showOffHand
        UpdateOffHandVisibility()
        RefreshConfigUI()
        Print("Inner Off-Hand ring " .. TagOnOff(db.showOffHand))
    elseif cmd == "ranged" then
        db.showRanged = not db.showRanged
        RefreshConfigUI()
        Print("Ranged tracking " .. TagOnOff(db.showRanged))
    elseif cmd == "blizzard" or cmd == "blizz" or cmd == "cvar" then
        db.hideBlizzardBar = not db.hideBlizzardBar
        ApplyBlizzardBarCVar()
        RefreshConfigUI()
        Print("Hide Blizzard swing bar " .. TagOnOff(db.hideBlizzardBar))
    elseif cmd == "text" or cmd == "numbers" then
        db.showText = not db.showText
        if not db.showText and clockFrame then clockFrame.timerText:SetText("") end
        RefreshConfigUI()
        Print("Center countdown text " .. TagOnOff(db.showText))
    elseif cmd == "debug" then
        debugMode = not debugMode
        local win = GetOrCreateDebugWindow()
        if debugMode then
            if #debugLines == 0 then debugStartTime = GetTime() end
            RefreshDebugWindow()
            win:Show()
        else
            win:Hide()
        end
        Print("Debug logging " .. TagOnOff(debugMode))
    elseif cmd == "toggle" then
        db.enabled = not db.enabled
        ApplyBlizzardBarCVar()
        ApplyClockLayout()
        RefreshConfigUI()
        Print("SwingClock " .. TagOnOff(db.enabled))
    elseif cmd == "reset" then
        local savedCVar = db.savedShowSwingTimer
        wipe(db)
        for k, v in pairs(DEFAULTS) do
            db[k] = type(v) == "table" and CopyTable(v) or v
        end
        db.savedShowSwingTimer = savedCVar
        ApplyBlizzardBarCVar()
        ApplyClockLayout()
        RefreshConfigUI()
        if RefreshOptionsPanel then RefreshOptionsPanel() end
        Print("Reset settings and position to defaults.")
    else
        PrintHelp()
    end
end
