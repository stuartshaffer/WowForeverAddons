--[[
WowDadJokes
-----------
Stores a collection of World of Warcraft dad jokes in-game.
  * Open the UI with /joke (or /dadjoke, /wdj)
  * Browse setups and punchlines with dedicated [Joke] and [Punchline] chat buttons
  * Add new jokes, edit existing ones, or delete jokes (saved in WowDadJokesDB)
  * Bind a key (directly in the UI or via Keybindings -> AddOns -> WoW Dad Jokes)
    for a two-step Random Joke: first press says a random setup, second press
    delivers the punchline!
]]

local ADDON_NAME = ...

-- Global strings for Bindings.xml
BINDING_HEADER_WOWDADJOKES = "WoW Dad Jokes"
BINDING_NAME_WOWDADJOKES_RANDOM = "Random Joke (Setup / Punchline)"
BINDING_NAME_WOWDADJOKES_CHANNEL = "Cycle Joke Chat Channel"
BINDING_NAME_WOWDADJOKES_TOGGLE = "Toggle WoW Dad Jokes Window"

local DEFAULT_JOKES = {
    {
        setup = "A Tauren threatened to leave the raid if he didn't get the next drop.",
        punchline = "But I could tell he was Thunderbluffing.",
    },
    {
        setup = "How does a Shadow Priest get the mob pack?",
        punchline = "Shadow Word: Pull!",
    },
    {
        setup = "What did the mage say to everyone near Brill who just missed the Zepplin?",
        punchline = "\"Wow, crappy day to not be a mage.\" Then he teleported to Orgrimmar.",
    },
    {
        setup = "What happened to the adventurer whose S key broke?",
        punchline = "There was no going back.",
    },
    {
        setup = "What do you call a Tauren visiting UC?",
        punchline = "Under ground beef.",
    },
    {
        setup = "Why does everyone like having enchanters at the campfire?",
        punchline = "They drop phat lutes!",
    },
    {
        setup = "Why don't you ever ask a Blackrock Depths boss for directions?",
        punchline = "Because it'll take you six hours just to get to the point.",
    },
    {
        setup = "Why did High Inquisitor Whitemane get fired from the Scarlet Monastery bakery?",
        punchline = "She kept yelling at the bread, \"Arise, my dough!\"",
    },
    {
        setup = "What kind of pets does Edwin VanCleef keep down in the Deadmines?",
        punchline = "Lapdogs, all of you!",
    },
    {
        setup = "What do you call a Troll pretending to be a Shaman?",
        punchline = "A pseudo-voodoo dude, mon.",
    },
    {
        setup = "Why was the gnome kicked out of the Ironforge Auction House?",
        punchline = "He kept trying to short the market.",
    },
    {
        setup = "Why did Mankrik cross the road?",
        punchline = "He thought someone in Barrens chat actually gave him the correct coordinates.",
    },
    {
        setup = "What do you call a Gnome Priest?",
        punchline = "A compact Disc.",
    },
    {
        setup = "What do Hunters equip in their leg slots in the summer?",
        punchline = "Multi-shorts",
    },
    {
        setup = "Why was the Feral Druid benched for the raid?",
        punchline = "His DPS was un-bear-able.",
    },
    {
        setup = "What do you call a Tauren getting buffed at a campfire?",
        punchline = "Ground beef.",
    },
    {
        setup = "Why do Rogues prefer leather armor?",
        punchline = "Because it's made of Hide!",
    },
    {
        setup = "Why did the Prot Warrior cross the road?",
        punchline = "Because the Priest aggro'd a chicken.",
    },
    {
        setup = "What is a Forsaken's favorite band?",
        punchline = "The Grateful Undead!",
    },
    {
        setup = "Where do Frost Mages keep their gold?",
        punchline = "In a snow bank!",
    },
    {
        setup = "What do you call a Tauren Rogue?",
        punchline = "Invisibull!",
    },
    {
        setup = "What do Paladins do to relax after running a dungeon?",
        punchline = "Bubble bath.",
    },
    {
        setup = "How does Naxxramas stay in the air?",
        punchline = "With four wings and a prayer!",
    },
    {
        setup = "What's a Murloc's favorite movie?",
        punchline = "Mrgl-Mrgl Grrgh Muerrl.",
    },
    {
        setup = "Why did Ragnaros get fired from the bakery?",
        punchline = "Because he kept taking things out of the oven TOO SOON!",
    },
    {
        setup = "Why did the Paladin get pulled over in Stratholme?",
        punchline = "He was caught speeding to beat the 45-minute Baron timer.",
    },
    {
        setup = "What do you call a Warlock who refuses to summon anyone?",
        punchline = "A shard-ass.",
    },
    {
        setup = "What do you call a group of Tauren singing around the campfire?",
        punchline = "A moo-sical.",
    },
}

local CHANNELS = {
    { id = "SAY",           label = "Say (/s)" },
    { id = "GENERAL",       label = "General (/1)" },
    { id = "PARTY",         label = "Party (/p)" },
    { id = "RAID",          label = "Raid (/ra)" },
    { id = "INSTANCE_CHAT", label = "Instance (/i)" },
    { id = "GUILD",         label = "Guild (/g)" },
    { id = "YELL",          label = "Yell (/y)" },
}

local db
local pendingJokeIndex = nil
local lastRandomIndex = nil
local editingIndex = nil -- nil = closed, 0 = adding new, >0 = editing existing joke
local searchFilter = ""

local mainFrame
local RefreshUI

local function Print(msg)
    print("|cffffd200WowDadJokes|r: " .. tostring(msg))
end

local function Trim(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function CopyDefaults()
    local list = {}
    for i, j in ipairs(DEFAULT_JOKES) do
        list[i] = { setup = j.setup, punchline = j.punchline }
    end
    return list
end

---------------------------------------------------------------------------
-- Chat Sending & Channel Resolution
---------------------------------------------------------------------------
local function ResolveChannel(preferred)
    preferred = preferred or (db and db.channel) or "SAY"
    if preferred == "GENERAL" then
        local chanId = GetChannelName and GetChannelName(1) or 1
        if (not chanId or chanId == 0) and GetChannelName then
            chanId = GetChannelName("General")
        end
        if chanId and chanId > 0 then
            return "CHANNEL", chanId
        end
        Print("Not in /1 General chat; sending to Say instead.")
        return "SAY", nil
    elseif preferred == "PARTY" then
        if IsInGroup and not IsInGroup() then
            Print("Not in a party; sending to Say instead.")
            return "SAY", nil
        end
    elseif preferred == "RAID" then
        if IsInRaid and not IsInRaid() then
            if IsInGroup and IsInGroup() then
                Print("Not in a raid; sending to Party instead.")
                return "PARTY", nil
            end
            Print("Not in a raid; sending to Say instead.")
            return "SAY", nil
        end
    elseif preferred == "INSTANCE_CHAT" then
        local inInstGroup = IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2)
        if not inInstGroup then
            if IsInRaid and IsInRaid() then return "RAID", nil end
            if IsInGroup and IsInGroup() then return "PARTY", nil end
            Print("Not in an instance group; sending to Say instead.")
            return "SAY", nil
        end
    elseif preferred == "GUILD" then
        if IsInGuild and not IsInGuild() then
            Print("Not in a guild; sending to Say instead.")
            return "SAY", nil
        end
    end
    return preferred, nil
end

local function SendJokeText(text)
    text = Trim(text)
    if text == "" then return end
    local chatType, target = ResolveChannel(db and db.channel or "SAY")
    local sendFn = SendChatMessage or (C_ChatInfo and C_ChatInfo.SendChatMessage)
    if sendFn then
        local ok, err = pcall(sendFn, text, chatType, nil, target)
        if not ok then
            Print("Could not send chat message: " .. tostring(err))
        end
    else
        Print(text)
    end
end

local function GetChannelLabel(channelId)
    for _, ch in ipairs(CHANNELS) do
        if ch.id == channelId then return ch.label end
    end
    return channelId
end

local CHANNEL_ALIASES = {
    say = "SAY", s = "SAY",
    general = "GENERAL", gen = "GENERAL", ["1"] = "GENERAL", ["/1"] = "GENERAL",
    party = "PARTY", p = "PARTY",
    raid = "RAID", ra = "RAID",
    instance = "INSTANCE_CHAT", inst = "INSTANCE_CHAT", i = "INSTANCE_CHAT", bg = "INSTANCE_CHAT",
    guild = "GUILD", g = "GUILD",
    yell = "YELL", y = "YELL",
}

local function SetChannelByName(input)
    local target = CHANNEL_ALIASES[Trim(input):lower()]
    if not target then return false end
    db.channel = target
    Print("Chat channel set to |cffffd200" .. GetChannelLabel(target) .. "|r.")
    if RefreshUI then RefreshUI() end
    return true
end

function WowDadJokes_CycleChannel(reverse)
    if not db then return end
    local cur = db.channel or "SAY"
    local curIdx = 1
    for i, ch in ipairs(CHANNELS) do
        if ch.id == cur then
            curIdx = i
            break
        end
    end
    local nextIdx
    if reverse then
        nextIdx = ((curIdx - 2) % #CHANNELS) + 1
    else
        nextIdx = (curIdx % #CHANNELS) + 1
    end
    db.channel = CHANNELS[nextIdx].id
    Print("Chat channel toggled to |cffffd200" .. CHANNELS[nextIdx].label .. "|r.")
    if RefreshUI then RefreshUI() end
end

---------------------------------------------------------------------------
-- Joke Actions & Two-Step Random Joke
---------------------------------------------------------------------------
local function JokeKey(item)
    return item and Trim(item.setup):lower() or ""
end

local function SaySetup(index)
    if not db or not db.jokes[index] then return end
    local item = db.jokes[index]
    SendJokeText(item.setup)
    if Trim(item.punchline) ~= "" then
        pendingJokeIndex = index
    else
        pendingJokeIndex = nil
    end
    db.toldRandom = db.toldRandom or {}
    local key = JokeKey(item)
    if key ~= "" then
        db.toldRandom[key] = true
    end
    lastRandomIndex = index
    if RefreshUI then RefreshUI() end
end

local function SayPunchline(index)
    if not db or not db.jokes[index] then return end
    local item = db.jokes[index]
    SendJokeText(item.punchline)
    if pendingJokeIndex == index then
        pendingJokeIndex = nil
    end
    if RefreshUI then RefreshUI() end
end

function WowDadJokes_RandomJoke()
    if not db or not db.jokes or #db.jokes == 0 then
        Print("No jokes saved! Open /joke to add or restore jokes.")
        return
    end

    -- Step 2: If a joke setup was already told, deliver its punchline
    if pendingJokeIndex and db.jokes[pendingJokeIndex] then
        local idx = pendingJokeIndex
        pendingJokeIndex = nil
        SayPunchline(idx)
        return
    end

    -- Step 1: Pick a random untold joke from the current cycle (no repeats until all have been told)
    db.toldRandom = db.toldRandom or {}
    local unseen = {}
    for i, item in ipairs(db.jokes) do
        local key = JokeKey(item)
        if key ~= "" and not db.toldRandom[key] then
            unseen[#unseen + 1] = i
        end
    end

    -- All jokes have been told in this cycle; reset and start a fresh cycle
    if #unseen == 0 then
        wipe(db.toldRandom)
        for i = 1, #db.jokes do
            if #db.jokes == 1 or i ~= lastRandomIndex then
                unseen[#unseen + 1] = i
            end
        end
    end

    local idx = unseen[math.random(1, #unseen)]
    SaySetup(idx)
end

-- Invisible button to support click-bindings as well as standard Bindings.xml
local clickBindBtn = CreateFrame("Button", "WowDadJokesRandomBindButton", UIParent)
clickBindBtn:RegisterForClicks("AnyDown", "AnyUp")
clickBindBtn:SetScript("OnClick", function(_, _, down)
    -- Only fire once per press
    if down == false then
        WowDadJokes_RandomJoke()
    end
end)

---------------------------------------------------------------------------
-- Keybinding Helpers
---------------------------------------------------------------------------
local BIND_ACTION = "WOWDADJOKES_RANDOM"
local BIND_CLICK_ACTION = "CLICK WowDadJokesRandomBindButton:LeftButton"

local function GetCurrentBoundKey()
    if not GetBindingKey then return nil end
    local k = GetBindingKey(BIND_ACTION)
    if not k then
        k = GetBindingKey(BIND_CLICK_ACTION)
    end
    return k
end

local function ClearCurrentBindings()
    if not GetBindingKey or not SetBinding then return end
    for _, action in ipairs({ BIND_ACTION, BIND_CLICK_ACTION }) do
        local keys = { GetBindingKey(action) }
        for _, k in ipairs(keys) do
            SetBinding(k, nil)
        end
    end
    if SaveBindings and GetCurrentBindingSet then
        SaveBindings(GetCurrentBindingSet())
    end
end

local function BindRandomJokeKey(key)
    if not SetBinding then return false end
    ClearCurrentBindings()
    local ok = SetBinding(key, BIND_ACTION)
    if not ok then
        ok = SetBinding(key, BIND_CLICK_ACTION)
    end
    if SaveBindings and GetCurrentBindingSet then
        SaveBindings(GetCurrentBindingSet())
    end
    return ok
end

---------------------------------------------------------------------------
-- UI Construction
---------------------------------------------------------------------------
local ROW_POOL = {}
local isListeningForKey = false

local function CreateMainUI()
    if mainFrame then return mainFrame end

    local f = CreateFrame("Frame", "WowDadJokesFrame", UIParent, "BackdropTemplate")
    f:SetSize(700, 520)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
    f:SetBackdropBorderColor(0.6, 0.5, 0.25, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    if UISpecialFrames then
        tinsert(UISpecialFrames, "WowDadJokesFrame")
    end

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("|cffffd200WoW Dad Jokes|r")

    -- Pending Punchline Status Indicator in header
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", title, "RIGHT", 14, 0)
    f.statusText = statusText

    local skipPendingBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    skipPendingBtn:SetSize(54, 18)
    skipPendingBtn:SetPoint("LEFT", statusText, "RIGHT", 6, 0)
    skipPendingBtn:SetText("Reset")
    skipPendingBtn:SetScript("OnClick", function()
        pendingJokeIndex = nil
        RefreshUI()
    end)
    f.skipPendingBtn = skipPendingBtn

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -----------------------------------------------------------------------
    -- Toolbar Row (Channel, Keybind, Random Joke, + Add Joke)
    -----------------------------------------------------------------------
    local chanLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chanLabel:SetPoint("TOPLEFT", 14, -40)
    chanLabel:SetText("Channel:")

    local chanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    chanBtn:SetSize(115, 24)
    chanBtn:SetPoint("LEFT", chanLabel, "RIGHT", 6, 0)
    chanBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.chanBtn = chanBtn

    -- Custom Dropdown Menu for Channel
    local chanMenu = CreateFrame("Frame", nil, chanBtn, "BackdropTemplate")
    chanMenu:SetSize(135, #CHANNELS * 22 + 10)
    chanMenu:SetPoint("TOPLEFT", chanBtn, "BOTTOMLEFT", 0, -2)
    chanMenu:SetFrameStrata("TOOLTIP")
    chanMenu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    chanMenu:SetBackdropColor(0.08, 0.08, 0.12, 0.98)
    chanMenu:Hide()
    f.chanMenuItems = {}

    for i, ch in ipairs(CHANNELS) do
        local itemBtn = CreateFrame("Button", nil, chanMenu)
        itemBtn:SetSize(125, 20)
        itemBtn:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 22)
        itemBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local txt = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", 6, 0)
        txt:SetText(ch.label)
        itemBtn.txt = txt
        itemBtn.channelId = ch.id
        itemBtn.baseLabel = ch.label
        f.chanMenuItems[i] = itemBtn

        itemBtn:SetScript("OnClick", function()
            db.channel = ch.id
            chanMenu:Hide()
            Print("Chat channel set to |cffffd200" .. ch.label .. "|r.")
            RefreshUI()
        end)
    end

    chanBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            chanMenu:Hide()
            WowDadJokes_CycleChannel()
            return
        end
        if chanMenu:IsShown() then
            chanMenu:Hide()
        else
            chanMenu:Show()
        end
    end)

    chanBtn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Joke Chat Channel", 1, 0.82, 0)
        GameTooltip:AddLine("Left-Click: Choose channel from list.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-Click: Toggle/cycle to next channel.", 0.4, 1, 0.6, true)
        GameTooltip:Show()
    end)
    chanBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Keybind Button
    local bindBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    bindBtn:SetSize(175, 24)
    bindBtn:SetPoint("LEFT", chanBtn, "RIGHT", 10, 0)
    bindBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f.bindBtn = bindBtn

    local function StopKeyCapture()
        isListeningForKey = false
        bindBtn:EnableKeyboard(false)
        RefreshUI()
    end

    bindBtn:SetScript("OnClick", function(_, button)
        if InCombatLockdown and InCombatLockdown() then
            Print("Cannot change keybindings while in combat.")
            return
        end
        if button == "RightButton" then
            ClearCurrentBindings()
            StopKeyCapture()
            Print("Cleared Random Joke keybind.")
            return
        end
        if isListeningForKey then
            StopKeyCapture()
        else
            isListeningForKey = true
            bindBtn:SetText("|cff00ff00Press a key... (Esc=Cancel)|r")
            bindBtn:EnableKeyboard(true)
        end
    end)

    bindBtn:SetScript("OnKeyDown", function(_, key)
        if not isListeningForKey then return end
        if key == "ESCAPE" then
            StopKeyCapture()
            return
        end
        -- Ignore standalone modifier keys until an actual key is pressed
        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
            return
        end

        local prefix = ""
        if IsAltKeyDown and IsAltKeyDown() then prefix = prefix .. "ALT-" end
        if IsControlKeyDown and IsControlKeyDown() then prefix = prefix .. "CTRL-" end
        if IsShiftKeyDown and IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
        local fullKey = prefix .. key

        BindRandomJokeKey(fullKey)
        Print("Bound Random Joke to |cffffd200" .. fullKey .. "|r (1st press = Setup, 2nd press = Punchline).")
        StopKeyCapture()
    end)

    bindBtn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Random Joke Keybind", 1, 0.82, 0)
        GameTooltip:AddLine("Left-Click: Press a key to bind Random Joke.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-Click: Unbind current key.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Pressing the bound key once says a random joke setup; pressing it again says the punchline!", 0.4, 1, 0.6, true)
        GameTooltip:Show()
    end)
    bindBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    -- Random Joke Action Button (in UI)
    local randomBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    randomBtn:SetSize(145, 24)
    randomBtn:SetPoint("LEFT", bindBtn, "RIGHT", 10, 0)
    randomBtn:SetScript("OnClick", function()
        WowDadJokes_RandomJoke()
    end)
    f.randomBtn = randomBtn

    -- + Add Joke Button
    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(105, 24)
    addBtn:SetPoint("TOPRIGHT", -14, -36)
    addBtn:SetText("+ Add Joke")
    f.addBtn = addBtn

    -----------------------------------------------------------------------
    -- Search / Filter Row
    -----------------------------------------------------------------------
    local searchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 14, -72)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    searchBox:SetSize(220, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        searchFilter = Trim(self:GetText()):lower()
        RefreshUI()
    end)
    f.searchBox = searchBox

    local clearSearchBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearSearchBtn:SetSize(48, 20)
    clearSearchBtn:SetPoint("LEFT", searchBox, "RIGHT", 4, 0)
    clearSearchBtn:SetText("Clear")
    clearSearchBtn:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:ClearFocus()
    end)

    local countLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLabel:SetPoint("LEFT", clearSearchBtn, "RIGHT", 12, 0)
    f.countLabel = countLabel

    local restoreBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    restoreBtn:SetSize(115, 20)
    restoreBtn:SetPoint("TOPRIGHT", -14, -68)
    restoreBtn:SetText("Restore Defaults")
    restoreBtn:SetScript("OnClick", function()
        local existing = {}
        for _, j in ipairs(db.jokes) do
            existing[Trim(j.setup):lower()] = true
        end
        local added = 0
        for _, def in ipairs(DEFAULT_JOKES) do
            if not existing[Trim(def.setup):lower()] then
                table.insert(db.jokes, { setup = def.setup, punchline = def.punchline })
                added = added + 1
            end
        end
        if added > 0 then
            Print(("Restored %d default dad joke(s)."):format(added))
        else
            Print("All default dad jokes are already in your collection.")
        end
        RefreshUI()
    end)

    -----------------------------------------------------------------------
    -- Scrollable Joke List
    -----------------------------------------------------------------------
    local listBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listBg:SetPoint("TOPLEFT", 12, -96)
    listBg:SetPoint("BOTTOMRIGHT", -12, 12)
    listBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    listBg:SetBackdropColor(0.02, 0.02, 0.04, 0.85)
    listBg:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.8)
    f.listBg = listBg

    local scroll = CreateFrame("ScrollFrame", "WowDadJokesScrollFrame", listBg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    f.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(636, 1)
    scroll:SetScrollChild(content)
    f.content = content

    -----------------------------------------------------------------------
    -- Add / Edit Joke Drawer (Bottom Panel)
    -----------------------------------------------------------------------
    local editor = CreateFrame("Frame", nil, f, "BackdropTemplate")
    editor:SetPoint("BOTTOMLEFT", 12, 12)
    editor:SetPoint("BOTTOMRIGHT", -12, 12)
    editor:SetHeight(130)
    editor:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    editor:SetBackdropColor(0.1, 0.1, 0.15, 0.98)
    editor:SetBackdropBorderColor(0.85, 0.7, 0.25, 1)
    editor:Hide()
    f.editor = editor

    local editorTitle = editor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorTitle:SetPoint("TOPLEFT", 12, -10)
    f.editorTitle = editorTitle

    local setupLbl = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    setupLbl:SetPoint("TOPLEFT", 12, -36)
    setupLbl:SetText("Joke / Setup:")

    local setupBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    setupBox:SetSize(540, 22)
    setupBox:SetPoint("TOPLEFT", 105, -31)
    setupBox:SetAutoFocus(false)
    setupBox:SetMaxLetters(255)
    f.setupBox = setupBox

    local punchLbl = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    punchLbl:SetPoint("TOPLEFT", 12, -66)
    punchLbl:SetText("Punchline:")

    local punchBox = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
    punchBox:SetSize(540, 22)
    punchBox:SetPoint("TOPLEFT", 105, -61)
    punchBox:SetAutoFocus(false)
    punchBox:SetMaxLetters(255)
    f.punchBox = punchBox

    local function SaveEditorJoke()
        local s = Trim(setupBox:GetText())
        local p = Trim(punchBox:GetText())
        if s == "" then
            Print("Please enter a joke setup before saving.")
            return
        end
        if editingIndex == 0 then
            table.insert(db.jokes, 1, { setup = s, punchline = p })
            if pendingJokeIndex then pendingJokeIndex = pendingJokeIndex + 1 end
            Print("Added new dad joke!")
        elseif editingIndex and db.jokes[editingIndex] then
            db.jokes[editingIndex].setup = s
            db.jokes[editingIndex].punchline = p
            Print(("Saved changes to joke #%d."):format(editingIndex))
        end
        editingIndex = nil
        setupBox:ClearFocus()
        punchBox:ClearFocus()
        RefreshUI()
    end

    local function CloseEditor()
        editingIndex = nil
        setupBox:ClearFocus()
        punchBox:ClearFocus()
        RefreshUI()
    end

    setupBox:SetScript("OnTabPressed", function() punchBox:SetFocus() end)
    punchBox:SetScript("OnTabPressed", function() setupBox:SetFocus() end)
    setupBox:SetScript("OnEnterPressed", function() punchBox:SetFocus() end)
    punchBox:SetScript("OnEnterPressed", SaveEditorJoke)
    setupBox:SetScript("OnEscapePressed", CloseEditor)
    punchBox:SetScript("OnEscapePressed", CloseEditor)

    local saveBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    saveBtn:SetSize(100, 24)
    saveBtn:SetPoint("BOTTOMRIGHT", -110, 10)
    saveBtn:SetText("Save Joke")
    saveBtn:SetScript("OnClick", SaveEditorJoke)

    local cancelBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    cancelBtn:SetSize(90, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", -12, 10)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", CloseEditor)

    local function OpenEditor(idx)
        editingIndex = idx
        if idx == 0 then
            editorTitle:SetText("|cffffd200Add New Dad Joke|r")
            setupBox:SetText("")
            punchBox:SetText("")
        elseif db.jokes[idx] then
            editorTitle:SetText(("|cffffd200Edit Dad Joke #%d|r"):format(idx))
            setupBox:SetText(db.jokes[idx].setup or "")
            punchBox:SetText(db.jokes[idx].punchline or "")
        end
        RefreshUI()
        setupBox:SetFocus()
    end
    f.OpenEditor = OpenEditor

    addBtn:SetScript("OnClick", function()
        OpenEditor(0)
    end)

    f:SetScript("OnHide", function()
        chanMenu:Hide()
        if isListeningForKey then
            StopKeyCapture()
        end
    end)

    mainFrame = f
    return f
end

local function AcquireRow(parent, idx)
    local row = ROW_POOL[idx]
    if row then return row end

    row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetWidth(636)
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    -- Text container on the left
    local setupText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    setupText:SetPoint("TOPLEFT", 10, -8)
    setupText:SetWidth(385)
    setupText:SetJustifyH("LEFT")
    setupText:SetWordWrap(true)
    row.setupText = setupText

    local punchText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    punchText:SetPoint("TOPLEFT", setupText, "BOTTOMLEFT", 0, -4)
    punchText:SetWidth(385)
    punchText:SetJustifyH("LEFT")
    punchText:SetWordWrap(true)
    row.punchText = punchText

    -- Action buttons on the right
    local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    delBtn:SetSize(40, 22)
    delBtn:SetPoint("RIGHT", -8, 0)
    delBtn:SetText("Del")
    row.delBtn = delBtn

    local editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    editBtn:SetSize(46, 22)
    editBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
    editBtn:SetText("Edit")
    row.editBtn = editBtn

    local punchBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    punchBtn:SetSize(78, 22)
    punchBtn:SetPoint("RIGHT", editBtn, "LEFT", -6, 0)
    punchBtn:SetText("Punchline")
    row.punchBtn = punchBtn

    local jokeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    jokeBtn:SetSize(56, 22)
    jokeBtn:SetPoint("RIGHT", punchBtn, "LEFT", -4, 0)
    jokeBtn:SetText("Joke")
    row.jokeBtn = jokeBtn

    ROW_POOL[idx] = row
    return row
end

RefreshUI = function()
    if not mainFrame or not mainFrame:IsShown() then return end

    -- Channel button & dropdown active indicator
    local activeChan = db.channel or "SAY"
    mainFrame.chanBtn:SetText(GetChannelLabel(activeChan))
    if mainFrame.chanMenuItems then
        for _, itemBtn in ipairs(mainFrame.chanMenuItems) do
            if itemBtn.channelId == activeChan then
                itemBtn.txt:SetText("|cffffd200> " .. itemBtn.baseLabel .. "|r")
            else
                itemBtn.txt:SetText("   " .. itemBtn.baseLabel)
            end
        end
    end

    -- Keybind button text
    if not isListeningForKey then
        local bound = GetCurrentBoundKey()
        if bound then
            mainFrame.bindBtn:SetText("Keybind: |cffffd200" .. bound .. "|r")
        else
            mainFrame.bindBtn:SetText("Keybind: |cffaaaaaaNot Bound|r")
        end
    end

    -- Pending punchline indicator & Random button label
    if pendingJokeIndex and db.jokes[pendingJokeIndex] then
        mainFrame.statusText:SetText(("|cff66ff99Punchline queued (#%d)|r"):format(pendingJokeIndex))
        mainFrame.skipPendingBtn:Show()
        mainFrame.randomBtn:SetText("Say Punchline!")
    else
        mainFrame.statusText:SetText("|cffaaaaaaNext random press: Setup|r")
        mainFrame.skipPendingBtn:Hide()
        mainFrame.randomBtn:SetText("Random Joke")
    end

    -- Editor visibility and list layout adjustment
    if editingIndex ~= nil then
        mainFrame.editor:Show()
        mainFrame.listBg:SetPoint("BOTTOMRIGHT", -12, 148)
    else
        mainFrame.editor:Hide()
        mainFrame.listBg:SetPoint("BOTTOMRIGHT", -12, 12)
    end

    -- Populate filtered jokes
    local yOffset = -4
    local visibleCount = 0
    local totalCount = #db.jokes

    for i, item in ipairs(db.jokes) do
        local s = item.setup or ""
        local p = item.punchline or ""
        local matches = (searchFilter == "")
            or s:lower():find(searchFilter, 1, true)
            or p:lower():find(searchFilter, 1, true)

        if matches then
            visibleCount = visibleCount + 1
            local row = AcquireRow(mainFrame.content, visibleCount)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 2, yOffset)

            local isQueued = (pendingJokeIndex == i)
            local isEditing = (editingIndex == i)

            if isEditing then
                row:SetBackdropColor(0.22, 0.18, 0.06, 0.9)
                row:SetBackdropBorderColor(1, 0.82, 0.2, 1)
            elseif isQueued then
                row:SetBackdropColor(0.06, 0.20, 0.12, 0.9)
                row:SetBackdropBorderColor(0.3, 0.9, 0.5, 1)
            elseif visibleCount % 2 == 0 then
                row:SetBackdropColor(0.09, 0.09, 0.13, 0.85)
                row:SetBackdropBorderColor(0.25, 0.25, 0.32, 0.7)
            else
                row:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
                row:SetBackdropBorderColor(0.22, 0.22, 0.28, 0.7)
            end

            row.setupText:SetText(("|cffffd200#%d Joke:|r %s"):format(i, s))
            row.punchText:SetText(("|cff66ff99Punchline:|r %s"):format(p ~= "" and p or "|cff888888(none)|r"))

            local textHeight = (row.setupText:GetStringHeight() or 14) + (row.punchText:GetStringHeight() or 14) + 22
            local rowHeight = math.max(50, textHeight)
            row:SetHeight(rowHeight)

            local jokeIndex = i
            row.jokeBtn:SetScript("OnClick", function()
                SaySetup(jokeIndex)
            end)
            row.punchBtn:SetEnabled(Trim(p) ~= "")
            row.punchBtn:SetScript("OnClick", function()
                SayPunchline(jokeIndex)
            end)
            row.editBtn:SetScript("OnClick", function()
                mainFrame.OpenEditor(jokeIndex)
            end)
            row.delBtn:SetScript("OnClick", function()
                table.remove(db.jokes, jokeIndex)
                if pendingJokeIndex == jokeIndex then
                    pendingJokeIndex = nil
                elseif pendingJokeIndex and pendingJokeIndex > jokeIndex then
                    pendingJokeIndex = pendingJokeIndex - 1
                end
                if editingIndex == jokeIndex then
                    editingIndex = nil
                elseif editingIndex and editingIndex > jokeIndex then
                    editingIndex = editingIndex - 1
                end
                RefreshUI()
            end)

            row:Show()
            yOffset = yOffset - rowHeight - 4
        end
    end

    -- Hide unused pooled rows
    for i = visibleCount + 1, #ROW_POOL do
        ROW_POOL[i]:Hide()
    end

    mainFrame.content:SetHeight(math.max(1, -yOffset + 6))
    mainFrame.countLabel:SetText(("Showing %d of %d jokes"):format(visibleCount, totalCount))
end

function WowDadJokes_ToggleUI()
    local f = CreateMainUI()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        RefreshUI()
    end
end

---------------------------------------------------------------------------
-- Initialization & Slash Commands
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        WowDadJokesDB = WowDadJokesDB or {}
        db = WowDadJokesDB
        db.channel = db.channel or "SAY"
        db.seenDefaults = db.seenDefaults or {}
        if type(db.jokes) ~= "table" or #db.jokes == 0 then
            db.jokes = CopyDefaults()
            for _, def in ipairs(DEFAULT_JOKES) do
                db.seenDefaults[Trim(def.setup):lower()] = true
            end
        else
            local existing = {}
            for _, j in ipairs(db.jokes) do
                if type(j.setup) == "string" then
                    j.setup = j.setup:gsub("Taruen", "Tauren"):gsub("campire", "campfire")
                    existing[Trim(j.setup):lower()] = true
                end
            end
            for _, def in ipairs(DEFAULT_JOKES) do
                local key = Trim(def.setup):lower()
                if not existing[key] and not db.seenDefaults[key] then
                    table.insert(db.jokes, { setup = def.setup, punchline = def.punchline })
                    existing[key] = true
                end
                db.seenDefaults[key] = true
            end
        end
    end
end)

SLASH_WOWDADJOKES1 = "/joke"
SLASH_WOWDADJOKES2 = "/jokes"
SLASH_WOWDADJOKES3 = "/dadjoke"
SLASH_WOWDADJOKES4 = "/wdj"
SlashCmdList.WOWDADJOKES = function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "random" or cmd == "rand" or cmd == "r" then
        WowDadJokes_RandomJoke()
    elseif cmd == "channel" or cmd == "chan" or cmd == "chat" then
        if arg ~= "" then
            if not SetChannelByName(arg) then
                Print("Unknown channel '" .. arg .. "'. Options: say, general, party, raid, instance, guild, yell")
            end
        else
            WowDadJokes_CycleChannel()
        end
    elseif SetChannelByName(cmd) then
        -- Handled directly via /joke say, /joke general, /joke party, /joke raid, /joke instance, /joke guild, /joke yell
        return
    elseif cmd == "add" or cmd == "new" then
        local f = CreateMainUI()
        f:Show()
        f.OpenEditor(0)
    elseif cmd == "help" then
        Print("Commands:")
        print("  /joke - open/close the WoW Dad Jokes window")
        print("  /joke random - say a random joke setup (or the queued punchline)")
        print("  /joke channel [say|general|party|raid|instance|guild|yell] - toggle or set chat channel")
        print("  /joke <say|general|party|raid|instance|guild|yell> - quick switch to that chat channel")
        print("  /joke add - open the window directly to Add New Joke")
    else
        WowDadJokes_ToggleUI()
    end
end
