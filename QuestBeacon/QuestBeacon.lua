--[[
QuestBeacon
-----------
The game draws the floating "!" / "?" above quest NPCs as part of the world
scene, so walls and terrain hide it. Addons can't draw into the 3D world
directly. Nameplates are the exception: the engine positions them over units,
and they can be made fully visible when the unit is occluded
(nameplateOccludedAlphaMult). So QuestBeacon:

  1. Turns on friendly NPC nameplates and stops them fading when occluded.
  2. Puts a "!" / "?" icon on the nameplate of every NPC that has a quest for you.
  3. Optionally hides the regular friendly NPC nameplate (name/health bar), leaving just the icon.

The Lua API can't tell you directly whether an NPC is a quest giver, so the
quest data comes from:
  * Questie's database, if Questie is installed (full coverage), and
  * a cache learned from NPCs you talk to (gossip/quest dialogs), saved account-wide.
]]

local ADDON_NAME = ...

local DEFAULTS = {
    enabled = true,
    iconSize = 30,
    yOffset = 6,
    hideFriendlyPlates = true, -- hide the regular friendly NPC nameplate bar/name, keep only the icon
    showIncomplete = true,     -- grey "?" for quests in your log that aren't finished yet
    showTrivial = false,       -- "!" for grey (low level) quests
    useQuestie = true,
    manageCVars = true,
    occludedOnly = true,       -- auto-hide beacon icon when in direct line of sight (avoids double !)
    sortQuestLog = true,       -- sort completed quests to the top in the main quest log
}

-- CVars we set so nameplates work as "through-wall" markers.
-- When occludedOnly is enabled, nameplateOccludedAlphaMult is set to 0.4 so the client
-- signals occlusion via plate:GetAlpha() < 0.99.
local MANAGED_CVARS = {
    nameplateShowAll = "1",          -- show nameplates out of combat
    nameplateShowFriendlyNPCs = "1", -- show nameplates for friendly NPCs
    nameplateOccludedAlphaMult = "0.4", -- lowered to allow occlusion detection (plate alpha drops behind walls)
}
local MIN_MAX_DISTANCE = 41          -- raise nameplateMaxDistance to at least this

local STATUS_NONE, STATUS_INCOMPLETE, STATUS_AVAILABLE, STATUS_COMPLETE = 0, 1, 2, 3

local db, learned
local icons = setmetatable({}, { __mode = "k" })  -- plate -> icon frame
local hidden = setmetatable({}, { __mode = "k" }) -- plate -> true when we hid its UnitFrame
local activeUnits = {}                              -- unit token -> true
local pendingCVars = false

local function Print(msg)
    print("|cffffd200QuestBeacon|r: " .. tostring(msg))
end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

---------------------------------------------------------------------------
-- CVars
---------------------------------------------------------------------------
local function GetCV(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar and GetCVar(name)
end

local function SetCV(name, value)
    if GetCV(name) == nil then return false end -- CVar doesn't exist on this client
    local ok = pcall(function()
        if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar(name, value) else SetCVar(name, value) end
    end)
    return ok
end

local function ApplyCVars()
    if not db.manageCVars then return end
    if InCombatLockdown() then pendingCVars = true return end
    db.savedCVars = db.savedCVars or {}
    for name, value in pairs(MANAGED_CVARS) do
        local targetValue = value
        if name == "nameplateOccludedAlphaMult" then
            targetValue = db.occludedOnly and "0.4" or "1"
        end
        local cur = GetCV(name)
        if cur ~= nil then
            if db.savedCVars[name] == nil then db.savedCVars[name] = cur end
            if cur ~= targetValue then SetCV(name, targetValue) end
        end
    end
    local dist = tonumber(GetCV("nameplateMaxDistance"))
    if dist and dist < MIN_MAX_DISTANCE then
        if db.savedCVars.nameplateMaxDistance == nil then db.savedCVars.nameplateMaxDistance = tostring(dist) end
        SetCV("nameplateMaxDistance", tostring(MIN_MAX_DISTANCE))
    end
end

local function RestoreCVars()
    if InCombatLockdown() then Print("Can't change CVars in combat.") return end
    if not db.savedCVars then return end
    for name, value in pairs(db.savedCVars) do SetCV(name, value) end
    db.savedCVars = nil
end

---------------------------------------------------------------------------
-- Questie integration (optional)
---------------------------------------------------------------------------
local QuestieDB

local function GetQuestie()
    if not db or not db.useQuestie then return nil end
    if QuestieDB then return QuestieDB end
    if QuestieLoader and QuestieLoader.ImportModule then
        local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieDB")
        -- QueryNPCSingle only exists after Questie finished building its DB.
        if ok and type(mod) == "table" and type(mod.QueryNPCSingle) == "function" then
            QuestieDB = mod
        end
    end
    return QuestieDB
end

local function QuestieList(Q, npcID, field, into)
    local ok, list = pcall(Q.QueryNPCSingle, npcID, field)
    if ok and type(list) == "table" then
        for _, qid in pairs(list) do
            if type(qid) == "number" then into[qid] = true end
        end
    end
end

local function QuestieDoable(Q, qid)
    if type(Q.IsDoable) ~= "function" then return true end
    local ok, res = pcall(Q.IsDoable, qid)
    if ok and type(res) == "boolean" then return res end
    return true
end

local function QuestieLevel(Q, qid)
    if not Q or type(Q.QueryQuestSingle) ~= "function" then return nil end
    local ok, lvl = pcall(Q.QueryQuestSingle, qid, "questLevel")
    if ok and type(lvl) == "number" then return lvl end
end

-- QuestieDB.IsDoable doesn't check the minimum level, so do it here.
local function QuestieTooLow(Q, qid)
    if not Q or type(Q.QueryQuestSingle) ~= "function" then return false end
    local ok, req = pcall(Q.QueryQuestSingle, qid, "requiredLevel")
    return ok and type(req) == "number" and req > UnitLevel("player")
end

local function QuestieWhy(Q, qid)
    if not Q or type(Q.IsDoableVerbose) ~= "function" then return nil end
    local ok, txt = pcall(Q.IsDoableVerbose, qid, false, true, true)
    if ok and type(txt) == "string" then return (txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " ")) end
end

---------------------------------------------------------------------------
-- Quest log helpers
---------------------------------------------------------------------------
local recentCompleted = {}

local function InLog(qid)
    if QuestiePlayer and QuestiePlayer.currentQuestlog and QuestiePlayer.currentQuestlog[qid] then
        return true
    end
    local QLC = QuestieLoader and QuestieLoader.ImportModule and QuestieLoader:ImportModule("QuestLogCache")
    if QLC and QLC.questLog_DO_NOT_MODIFY and QLC.questLog_DO_NOT_MODIFY[qid] then
        return true
    end
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local idx = C_QuestLog.GetLogIndexForQuestID(qid)
        return idx ~= nil and idx > 0
    elseif GetQuestLogIndexByID then
        local i = GetQuestLogIndexByID(qid)
        return i ~= nil and i > 0
    end
    return false
end

local function IsReadyToTurnIn(qid)
    local Q = GetQuestie()
    if Q and type(Q.IsComplete) == "function" then
        local ok, comp = pcall(Q.IsComplete, qid)
        if ok and comp == 1 then return true end
    end
    if C_QuestLog then
        if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(qid) then return true end
        if C_QuestLog.IsComplete and C_QuestLog.IsComplete(qid) then return true end
        -- "Talk to X" quests have no objectives and are always ready.
        if C_QuestLog.GetQuestObjectives then
            local objs = C_QuestLog.GetQuestObjectives(qid)
            if type(objs) == "table" and #objs == 0 then return true end
        end
    elseif IsQuestComplete then
        return IsQuestComplete(qid) and true or false
    end
    return false
end

local function IsFlaggedCompleted(qid)
    if recentCompleted[qid] then
        return true
    end
    if Questie and Questie.db and Questie.db.char and Questie.db.char.complete and Questie.db.char.complete[qid] then
        return true
    end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(qid)
    elseif IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(qid)
    end
    return false
end

local function IsTrivialLevel(questLevel)
    if not questLevel or questLevel <= 0 then return false end
    local greenRange = 8
    if GetQuestGreenRange then
        local ok, r = pcall(GetQuestGreenRange)
        if ok and type(r) == "number" then greenRange = r end
    end
    return (UnitLevel("player") - questLevel) > greenRange
end

---------------------------------------------------------------------------
-- NPC quest status
---------------------------------------------------------------------------
local function NpcIDFromUnit(unit)
    local guid = UnitGUID(unit)
    if not guid or IsSecret(guid) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" then return tonumber(id) end
    return nil
end

local function GetNpcStatus(npcID)
    local starts, ends = {}, {}
    local Q = GetQuestie()
    if Q then
        QuestieList(Q, npcID, "questStarts", starts)
        QuestieList(Q, npcID, "questEnds", ends)
    end
    local L = learned[npcID]
    if L then
        for qid in pairs(L.s) do starts[qid] = true end
        for qid in pairs(L.e) do ends[qid] = true end
    end

    local best = STATUS_NONE
    for qid in pairs(ends) do
        if InLog(qid) then
            if IsReadyToTurnIn(qid) then return STATUS_COMPLETE end
            if db.showIncomplete then best = STATUS_INCOMPLETE end
        end
    end

    for qid in pairs(starts) do
        if not InLog(qid) and not IsFlaggedCompleted(qid) then
            local ok = true
            if Q then ok = QuestieDoable(Q, qid) and not QuestieTooLow(Q, qid) end
            if ok and not db.showTrivial and IsTrivialLevel(QuestieLevel(Q, qid)) then ok = false end
            if ok then return STATUS_AVAILABLE end
        end
    end
    return best
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------
local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local ICON_STYLES = {
    [STATUS_AVAILABLE]  = { atlas = "QuestNormal",  file = "Interface\\GossipFrame\\AvailableQuestIcon" },
    [STATUS_COMPLETE]   = { atlas = "QuestTurnin",  file = "Interface\\GossipFrame\\ActiveQuestIcon" },
    [STATUS_INCOMPLETE] = { atlas = "QuestTurnin",  file = "Interface\\GossipFrame\\ActiveQuestIcon", grey = true },
}

local function IsPlateOccluded(plate)
    -- When nameplateOccludedAlphaMult < 1 (e.g. 0.4), Blizzard automatically reduces
    -- plate:GetAlpha() when the nameplate is obstructed/behind a wall or obstacle.
    local a = plate:GetAlpha()
    return a < 0.95
end

local function GetIcon(plate)
    local icon = icons[plate]
    if icon then return icon end
    icon = CreateFrame("Frame", nil, plate)
    icon:SetFrameLevel(plate:GetFrameLevel() + 10)
    if icon.SetIgnoreParentAlpha then icon:SetIgnoreParentAlpha(true) end
    icon.tex = icon:CreateTexture(nil, "OVERLAY")
    icon.tex:SetAllPoints()
    icons[plate] = icon

    -- Dynamically show/hide based on line-of-sight occlusion
    icon:SetScript("OnUpdate", function(self)
        if not db or not db.enabled or self.status == STATUS_NONE then
            if self:IsShown() then self:Hide() end
            return
        end
        if db.occludedOnly then
            local occluded = IsPlateOccluded(plate)
            if occluded and not self:IsShown() then
                self:Show()
            elseif not occluded and self:IsShown() then
                self:Hide()
            end
        else
            if not self:IsShown() then self:Show() end
        end
    end)

    return icon
end

local function StyleIcon(icon, status)
    if icon.status == status and icon.size == db.iconSize and icon.yOff == db.yOffset then return end
    icon.status, icon.size, icon.yOff = status, db.iconSize, db.yOffset
    icon:SetSize(db.iconSize, db.iconSize)
    icon:ClearAllPoints()
    icon:SetPoint("BOTTOM", icon:GetParent(), "CENTER", 0, db.yOffset)
    local style = ICON_STYLES[status]
    if HasAtlas(style.atlas) then
        icon.tex:SetAtlas(style.atlas)
    else
        icon.tex:SetTexture(style.file)
        icon.tex:SetTexCoord(0, 1, 0, 1)
    end
    icon.tex:SetDesaturated(style.grey or false)
    if style.grey then icon.tex:SetVertexColor(0.75, 0.75, 0.75) else icon.tex:SetVertexColor(1, 1, 1) end
end

local function SetPlateHidden(plate, hide)
    local uf = plate.UnitFrame
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end
    if hide then
        uf:SetAlpha(0)
        hidden[plate] = true
    elseif hidden[plate] then
        uf:SetAlpha(1)
        hidden[plate] = nil
    end
end

local function UpdateUnit(unit, cache)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end

    local status = STATUS_NONE
    local isFriendlyNPC = not UnitIsPlayer(unit) and not UnitCanAttack("player", unit)
    if db.enabled and not UnitIsPlayer(unit) then
        local npcID = NpcIDFromUnit(unit)
        if npcID then
            status = cache and cache[npcID]
            if status == nil then
                status = GetNpcStatus(npcID)
                if cache then cache[npcID] = status end
            end
        end
    end

    if status ~= STATUS_NONE then
        local icon = GetIcon(plate)
        StyleIcon(icon, status)
        if db.occludedOnly then
            if IsPlateOccluded(plate) then icon:Show() else icon:Hide() end
        else
            icon:Show()
        end
    elseif icons[plate] then
        icons[plate].status = STATUS_NONE
        icons[plate]:Hide()
    end

    SetPlateHidden(plate, db.enabled and db.hideFriendlyPlates and isFriendlyNPC)
end

local function RefreshAll()
    local cache = {}
    for unit in pairs(activeUnits) do UpdateUnit(unit, cache) end
end

local refreshQueued = false
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        RefreshAll()
    end)
end

---------------------------------------------------------------------------
-- Learning quest givers/enders from interactions
---------------------------------------------------------------------------
local function Learn(kind, qid)
    if type(qid) ~= "number" or qid <= 0 then return end
    local npcID = NpcIDFromUnit("npc")
    if not npcID then return end
    local L = learned[npcID]
    if not L then L = { s = {}, e = {} }; learned[npcID] = L end
    if not L[kind][qid] then
        L[kind][qid] = true
        QueueRefresh()
    end
end

local function LearnGossip()
    if not C_GossipInfo then return end
    for _, q in ipairs(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}) do
        Learn("s", q.questID)
    end
    for _, q in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
        Learn("e", q.questID)
    end
end

local function LearnGreeting()
    if GetNumAvailableQuests and GetAvailableQuestInfo then
        for i = 1, GetNumAvailableQuests() do
            local ok, _, _, _, _, qid = pcall(GetAvailableQuestInfo, i)
            if ok then Learn("s", qid) end
        end
    end
    if GetNumActiveQuests and GetActiveQuestID then
        for i = 1, GetNumActiveQuests() do
            local ok, qid = pcall(GetActiveQuestID, i)
            if ok then Learn("e", qid) end
        end
    end
end

---------------------------------------------------------------------------
-- Quest log sorting (main quest log / QuestScrollFrame)
---------------------------------------------------------------------------
local questLogHooked = false
local sortingQuestLog = false
local sortCheckButton

local function IsQuestEntryCompleted(titleFrame)
    local qid = titleFrame and titleFrame.questID
    if not qid and titleFrame and titleFrame.questLogIndex and C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then
        qid = C_QuestLog.GetQuestIDForLogIndex(titleFrame.questLogIndex)
    end
    if not qid or qid <= 0 then return false end
    return IsReadyToTurnIn(qid)
end

local function CollectActivePool(pool, into)
    if pool and pool.EnumerateActive then
        for f in pool:EnumerateActive() do
            into[f] = true
        end
    end
end

local function SortQuestScrollFrame()
    if sortingQuestLog or not db or not db.sortQuestLog then return end
    if not QuestScrollFrame or not QuestScrollFrame.Contents then return end
    local contents = QuestScrollFrame.Contents
    if not contents.GetLayoutChildren or not contents.Layout then return end

    sortingQuestLog = true
    local ok, err = pcall(function()
        local isTitle, isObj, isHeader = {}, {}, {}
        CollectActivePool(QuestScrollFrame.titleFramePool, isTitle)
        CollectActivePool(QuestScrollFrame.objectiveFramePool, isObj)
        CollectActivePool(QuestScrollFrame.headerFramePool, isHeader)
        CollectActivePool(QuestScrollFrame.campaignHeaderFramePool, isHeader)
        CollectActivePool(QuestScrollFrame.covenantCallingsHeaderFramePool, isHeader)

        local children = contents:GetLayoutChildren()
        if not children or #children == 0 then return end

        local leading = {}
        local sections = {}
        local currentSection, currentQuest

        for _, child in ipairs(children) do
            if isHeader[child] then
                currentSection = {
                    header = child,
                    quests = {},
                    trailing = {},
                    hasCompleted = false,
                    order = #sections + 1,
                }
                sections[#sections + 1] = currentSection
                currentQuest = nil
            elseif isTitle[child] then
                if not currentSection then
                    currentSection = {
                        header = nil,
                        quests = {},
                        trailing = {},
                        hasCompleted = false,
                        order = #sections + 1,
                    }
                    sections[#sections + 1] = currentSection
                end
                local done = IsQuestEntryCompleted(child)
                currentQuest = {
                    title = child,
                    objectives = {},
                    completed = done,
                    order = #currentSection.quests + 1,
                }
                currentSection.quests[#currentSection.quests + 1] = currentQuest
                if done then currentSection.hasCompleted = true end
            elseif isObj[child] then
                if currentQuest then
                    currentQuest.objectives[#currentQuest.objectives + 1] = child
                elseif currentSection then
                    currentSection.trailing[#currentSection.trailing + 1] = child
                else
                    leading[#leading + 1] = child
                end
            else
                if not currentSection then
                    leading[#leading + 1] = child
                else
                    currentSection.trailing[#currentSection.trailing + 1] = child
                end
            end
        end

        if #sections == 0 then return end

        table.sort(sections, function(a, b)
            if a.hasCompleted ~= b.hasCompleted then return a.hasCompleted end
            return a.order < b.order
        end)

        for _, sec in ipairs(sections) do
            table.sort(sec.quests, function(a, b)
                if a.completed ~= b.completed then return a.completed end
                return a.order < b.order
            end)
        end

        local idx = 1
        local function assign(f)
            f.layoutIndex = idx
            idx = idx + 1
        end

        for _, f in ipairs(leading) do assign(f) end
        for _, sec in ipairs(sections) do
            if sec.header then assign(sec.header) end
            for _, q in ipairs(sec.quests) do
                assign(q.title)
                for _, obj in ipairs(q.objectives) do assign(obj) end
            end
            for _, tr in ipairs(sec.trailing) do assign(tr) end
        end

        contents:Layout()
    end)
    sortingQuestLog = false
    if not ok then
        -- Fail silently in production, or could debug-print if needed
    end
end

local function RefreshQuestLogSort()
    if sortCheckButton and db then
        sortCheckButton:SetChecked(db.sortQuestLog and true or false)
    end
    if type(QuestLogQuests_Update) == "function" then
        QuestLogQuests_Update()
    end
end

local function EnsureQuestLogSortButton()
    if sortCheckButton or not QuestScrollFrame then return end
    local parent = (QuestMapFrame and QuestMapFrame.QuestsFrame)
        or (QuestScrollFrame.GetParent and QuestScrollFrame:GetParent())
        or QuestScrollFrame
    local btn = CreateFrame("CheckButton", "QuestBeaconSortCheckButton", parent, "UICheckButtonTemplate")
    btn:SetSize(22, 22)
    btn:SetFrameLevel(parent:GetFrameLevel() + 15)
    btn:SetPoint("TOPRIGHT", QuestScrollFrame, "TOPRIGHT", -28, 24)
    btn:SetChecked(db and db.sortQuestLog and true or false)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("RIGHT", btn, "LEFT", -2, 0)
    label:SetText("Sort: Done")

    btn:SetScript("OnClick", function(self)
        if not db then return end
        db.sortQuestLog = self:GetChecked() and true or false
        RefreshQuestLogSort()
    end)

    sortCheckButton = btn
end

local mapShowHooked = false
local function SetupQuestLogSort()
    if not questLogHooked and type(QuestLogQuests_Update) == "function" and QuestScrollFrame then
        hooksecurefunc("QuestLogQuests_Update", SortQuestScrollFrame)
        questLogHooked = true
    end
    if questLogHooked then
        EnsureQuestLogSortButton()
    end
    if not mapShowHooked then
        local mapPanel = (QuestMapFrame and QuestMapFrame.QuestsFrame) or QuestMapFrame or WorldMapFrame
        if mapPanel and mapPanel.HookScript then
            mapPanel:HookScript("OnShow", function()
                SetupQuestLogSort()
                if sortCheckButton and db then
                    sortCheckButton:SetChecked(db.sortQuestLog and true or false)
                end
                C_Timer.After(0, SortQuestScrollFrame)
            end)
            mapShowHooked = true
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name == ADDON_NAME then
        QuestBeaconDB = QuestBeaconDB or {}
        QuestBeaconLearned = QuestBeaconLearned or {}
        db, learned = QuestBeaconDB, QuestBeaconLearned
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
    end
    if name == ADDON_NAME or name == "Blizzard_WorldMap" then
        SetupQuestLogSort()
    end
end

function handlers.PLAYER_ENTERING_WORLD()
    if db.enabled then ApplyCVars() end
    SetupQuestLogSort()
    RefreshQuestLogSort()
    QueueRefresh()
end

function handlers.PLAYER_REGEN_ENABLED()
    if pendingCVars then
        pendingCVars = false
        ApplyCVars()
    end
end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
    activeUnits[unit] = true
    UpdateUnit(unit)
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
    activeUnits[unit] = nil
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate then
        if icons[plate] then icons[plate]:Hide() end
        SetPlateHidden(plate, false)
    end
end

function handlers.QUEST_TURNED_IN(questId)
    if type(questId) == "number" and questId > 0 then
        recentCompleted[questId] = true
    end
    QueueRefresh()
end

function handlers.QUEST_ACCEPTED(questLogIndex, questId)
    -- On Classic, questLogIndex is arg1, questId is arg2.
    -- On Forever/Retail, questId might be arg1.
    local qid = (type(questId) == "number" and questId > 0) and questId or (type(questLogIndex) == "number" and questLogIndex > 0 and questLogIndex)
    if qid and recentCompleted[qid] then
        recentCompleted[qid] = nil
    end
    QueueRefresh()
end

function handlers.QUEST_REMOVED(questId)
    QueueRefresh()
end

function handlers.QUEST_LOG_UPDATE()
    QueueRefresh()
end

function handlers.QUEST_WATCH_UPDATE(questId)
    QueueRefresh()
end

function handlers.UNIT_QUEST_LOG_CHANGED(unit)
    QueueRefresh()
end

function handlers.PLAYER_LEVEL_UP()
    QueueRefresh()
end

handlers.GOSSIP_SHOW = LearnGossip
handlers.QUEST_GREETING = LearnGreeting
function handlers.QUEST_DETAIL() Learn("s", GetQuestID()) end
function handlers.QUEST_PROGRESS() Learn("e", GetQuestID()) end
function handlers.QUEST_COMPLETE() Learn("e", GetQuestID()) end

for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event) -- tolerate events missing on this client
end
frame:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h then h(...) end
end)

-- Periodic full refresh. Catches status that was computed before Questie finished loading
-- the character's quest history, and re-asserts plate hiding if Blizzard resets alpha.
C_Timer.NewTicker(1, function()
    if db then RefreshAll() end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function OnOff(v) return v and "|cff00ff00on|r" or "|cffff4040off|r" end

local function PrintStatus()
    Print(("enabled %s | size %d | offset %d | hide plates %s | auto-hide LOS %s | sort log %s | grey ? %s | trivial %s | questie %s (%s) | cvars %s"):format(
        OnOff(db.enabled), db.iconSize, db.yOffset, OnOff(db.hideFriendlyPlates), OnOff(db.occludedOnly), OnOff(db.sortQuestLog), OnOff(db.showIncomplete),
        OnOff(db.showTrivial), OnOff(db.useQuestie), GetQuestie() and "found" or "not found", OnOff(db.manageCVars)))
    local n = 0
    for _ in pairs(learned) do n = n + 1 end
    Print(("Learned NPCs: %d"):format(n))
end

local function PrintHelp()
    Print("commands:")
    print("  /qb toggle - enable/disable")
    print("  /qb autohide - toggle auto-hiding icon when in direct line of sight (avoids double !)")
    print("  /qb sort - toggle sorting completed quests to the top of the quest log")
    print("  /qb size <n> - icon size (default 30)")
    print("  /qb offset <n> - vertical offset (default 6)")
    print("  /qb plates - toggle hiding regular friendly NPC nameplates")
    print("  /qb grey - toggle grey ? for unfinished quests")
    print("  /qb trivial - toggle low-level quest !")
    print("  /qb questie - toggle Questie database usage")
    print("  /qb cvars - toggle CVar management (off restores your old values)")
    print("  /qb target - debug info for your target")
    print("  /qb forget - wipe learned NPC data")
    print("  /qb status")
end

local function DebugTarget()
    local out = {}
    local function add(s) out[#out + 1] = s end
    local function yn(v) return v and "Y" or "n" end

    add(("QuestBeacon debug | enabled=%s hidePlates=%s autohide=%s questie=%s"):format(
        yn(db.enabled), yn(db.hideFriendlyPlates), yn(db.occludedOnly), GetQuestie() and "found" or "NOT found"))
    local cv = {}
    for name in pairs(MANAGED_CVARS) do cv[#cv + 1] = name .. "=" .. tostring(GetCV(name)) end
    cv[#cv + 1] = "nameplateMaxDistance=" .. tostring(GetCV("nameplateMaxDistance"))
    cv[#cv + 1] = "nameplateShowFriends=" .. tostring(GetCV("nameplateShowFriends"))
    add("CVars: " .. table.concat(cv, " "))
    local nActive = 0
    for _ in pairs(activeUnits) do nActive = nActive + 1 end
    add("active nameplates: " .. nActive)

    local guid = UnitGUID("target")
    add("target: " .. tostring(UnitName("target")) .. " GUID: " .. (IsSecret(guid) and "<secret>" or tostring(guid)))
    local id = NpcIDFromUnit("target")
    if not id then
        add("target is not an NPC")
        return out
    end
    local names = { [0] = "none", "incomplete ?", "available !", "complete ?" }
    local okS, status = pcall(GetNpcStatus, id)
    add(("npcID %d -> %s | player level %d"):format(id, okS and names[status] or ("ERROR: " .. tostring(status)),
        UnitLevel("player")))

    local Q = GetQuestie()
    local starts, ends = {}, {}
    if Q then
        QuestieList(Q, id, "questStarts", starts)
        QuestieList(Q, id, "questEnds", ends)
    end
    local L = learned[id]
    if L then
        for q in pairs(L.s) do starts[q] = true end
        for q in pairs(L.e) do ends[q] = true end
    end
    for qid in pairs(starts) do
        local doable = Q and QuestieDoable(Q, qid)
        local lvl = QuestieLevel(Q, qid)
        add(("  start %d: inLog=%s done=%s doable=%s tooLow=%s lvl=%s trivial=%s"):format(qid,
            yn(InLog(qid)), yn(IsFlaggedCompleted(qid)), tostring(doable), yn(QuestieTooLow(Q, qid)), tostring(lvl),
            yn(IsTrivialLevel(lvl))))
        local why = doable == false and QuestieWhy(Q, qid)
        if why then add("      why: " .. why) end
    end
    for qid in pairs(ends) do
        add(("  end %d: inLog=%s ready=%s"):format(qid, yn(InLog(qid)), yn(InLog(qid) and IsReadyToTurnIn(qid))))
    end
    if next(starts) == nil and next(ends) == nil then add("  no quests known for this NPC") end

    local plate = C_NamePlate.GetNamePlateForUnit("target")
    local icon = plate and icons[plate]
    local plateAlpha = plate and plate:GetAlpha() or nil
    add(("plate=%s alpha=%s occluded=%s icon=%s shown=%s hiddenUF=%s"):format(
        tostring(plate ~= nil), tostring(plateAlpha), tostring(plate and IsPlateOccluded(plate) or false),
        tostring(icon ~= nil), tostring(icon and icon:IsShown()), tostring(plate and hidden[plate] or false)))
    return out
end

local copyFrame
local function ShowCopyWindow(lines)
    local text = table.concat(lines, "\n")
    db.lastDebug = text -- also lands in WTF\...\SavedVariables\QuestBeacon.lua on /reload or logout
    for _, l in ipairs(lines) do print(l) end

    if not copyFrame then
        local f = CreateFrame("Frame", "QuestBeaconCopyFrame", UIParent, "BackdropTemplate")
        f:SetSize(620, 320)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0, 0, 0, 0.9)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 12, -10)
        title:SetText("QuestBeacon debug - Ctrl+A, Ctrl+C to copy")

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(570)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit
        copyFrame = f
    end
    copyFrame.edit:SetText(text)
    copyFrame:Show()
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText()
end

SLASH_QUESTBEACON1 = "/qb"
SLASH_QUESTBEACON2 = "/questbeacon"
SlashCmdList.QUESTBEACON = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "toggle" then
        db.enabled = not db.enabled
        if db.enabled then ApplyCVars() end
        Print("enabled " .. OnOff(db.enabled))
    elseif cmd == "autohide" or cmd == "los" or cmd == "occluded" then
        db.occludedOnly = not db.occludedOnly
        ApplyCVars()
        Print("auto-hide in line of sight " .. OnOff(db.occludedOnly))
    elseif cmd == "sort" or cmd == "sortlog" then
        db.sortQuestLog = not db.sortQuestLog
        RefreshQuestLogSort()
        Print("sort quest log by completed " .. OnOff(db.sortQuestLog))
    elseif cmd == "size" and tonumber(arg) then
        db.iconSize = math.max(8, math.min(128, tonumber(arg)))
    elseif cmd == "offset" and tonumber(arg) then
        db.yOffset = tonumber(arg)
    elseif cmd == "plates" then
        db.hideFriendlyPlates = not db.hideFriendlyPlates
        Print("hide friendly NPC plates " .. OnOff(db.hideFriendlyPlates))
    elseif cmd == "grey" or cmd == "gray" then
        db.showIncomplete = not db.showIncomplete
        Print("grey ? " .. OnOff(db.showIncomplete))
    elseif cmd == "trivial" then
        db.showTrivial = not db.showTrivial
        Print("trivial quests " .. OnOff(db.showTrivial))
    elseif cmd == "questie" then
        db.useQuestie = not db.useQuestie
        QuestieDB = nil
        Print("Questie " .. OnOff(db.useQuestie))
    elseif cmd == "cvars" then
        db.manageCVars = not db.manageCVars
        if db.manageCVars then ApplyCVars() else RestoreCVars() end
        Print("CVar management " .. OnOff(db.manageCVars))
    elseif cmd == "forget" then
        wipe(learned)
        Print("learned data wiped")
    elseif cmd == "target" then
        ShowCopyWindow(DebugTarget())
    elseif cmd == "status" then
        PrintStatus()
    else
        PrintHelp()
        return
    end
    QueueRefresh()
end
