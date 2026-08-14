local addonName, addonTable = ...
local LootRememberer = LibStub("AceAddon-3.0"):GetAddon("LootRememberer")
local AceGUI = LibStub("AceGUI-3.0")

AceGUI:RegisterLayout("LootRemembererRow", function(content, children)
    local headerBtn = children[1]
    local deleteBtn = children[2]
    
    local contentWidth = content:GetWidth() or 550
    if contentWidth < 50 then contentWidth = 550 end
    
    local deleteWidth = 18
    local padding = 10
    
    if deleteBtn then
        deleteBtn:SetWidth(deleteWidth)
        deleteBtn:SetHeight(deleteWidth)
        deleteBtn.frame:ClearAllPoints()
        deleteBtn.frame:SetPoint("RIGHT", content.obj.frame, "RIGHT", 0, 0)
    end
    
    if headerBtn then
        local labelWidth = contentWidth - deleteWidth - padding - 15
        headerBtn:SetWidth(labelWidth)
        headerBtn.frame:ClearAllPoints()
        headerBtn.frame:SetPoint("LEFT", content.obj.frame, "LEFT", 0, 0)
        headerBtn.frame:SetHeight(24)
    end
    
    content:SetHeight(24)
    if content.obj and content.obj.frame then
        content.obj.frame:SetHeight(24)
    end
end)

local History = {}
LibStub("AceEvent-3.0"):Embed(History)
LootRememberer.History = History

function History:Initialize()
    self.currentSession = nil

    self:RegisterEvent("ACTIVE_MANASTORM_UPDATED")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("CHAT_MSG_SYSTEM")
    self:RegisterEvent("CHAT_MSG_LOOT")
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    
    -- Scrape SpecTip's custom spec names since Ascension API doesn't catch them without inspecting
    local function CacheSpecTip(text)
        local icon, spec = string.match(text, "|HAiLC|h%s*|T(.-):.-|t%s*(.*)")
        if not icon then
            spec = string.match(text, "|HAiLC|h%s*(.*)")
        end
        if spec then
            spec = string.gsub(spec, "|r", "")
            spec = string.gsub(spec, "|c%x%x%x%x%x%x%x%x", "")
            local tooltipName = GameTooltip:GetUnit()
            local name = tooltipName or UnitName("mouseover") or UnitName("target")
            if name then
                name = string.match(name, "^([^-]+)") or name
                LootRememberer.SpecCache = LootRememberer.SpecCache or {}
                LootRememberer.SpecCache[name] = { spec = spec, icon = icon }
            end
        end
    end

    hooksecurefunc(GameTooltip, "AddLine", function(self, text)
        if text and type(text) == "string" and string.find(text, "|HAiLC|h") then
            CacheSpecTip(text)
        end
    end)
    hooksecurefunc(GameTooltip, "AddDoubleLine", function(self, textL, textR)
        if textL and type(textL) == "string" and string.find(textL, "|HAiLC|h") then
            CacheSpecTip(textL)
        end
    end)
    for i = 2, 10 do
        local line = _G["GameTooltipTextLeft" .. i]
        if line then
            hooksecurefunc(line, "SetText", function(self, text)
                if text and type(text) == "string" and string.find(text, "|HAiLC|h") then
                    CacheSpecTip(text)
                end
            end)
        end
    end
    
    self:PruneOldSessions()
end

local function GetCacheData(unit)
    local n = UnitName(unit)
    if not n then return nil, nil end
    n = string.match(n, "^([^-]+)") or n
    local locClass, c = UnitClass(unit)
    local _, r = UnitRace(unit)
    local l = UnitLevel(unit)
    local specName, specIcon = nil, nil
    if type(UnitSpecAndIcon) == "function" then
        local success, sn, si = pcall(UnitSpecAndIcon, unit)
        if success and sn and sn ~= "" and sn ~= locClass then
            specName, specIcon = sn, si
        end
    end
    if (not specName or specName == "") and LootRememberer.SpecCache and LootRememberer.SpecCache[n] then
        specName = LootRememberer.SpecCache[n].spec
        specIcon = LootRememberer.SpecCache[n].icon
    end
    local finalSpec = locClass
    if specName and specName ~= locClass and specName ~= "" then
        if string.find(string.lower(specName), string.lower(locClass), 1, true) then
            finalSpec = specName
        else
            finalSpec = specName .. " " .. (locClass or "")
        end
    end
    return n, { class = c or "UNKNOWN", race = r or "UNKNOWN", level = l or "??", spec = finalSpec, icon = specIcon }
end

local function ScanForWorldBoss(self)
    if not IsInInstance() then
        for _, unit in ipairs({"target", "mouseover"}) do
            if UnitExists(unit) and UnitClassification(unit) == "worldboss" then
                return UnitName(unit)
            end
        end
        local numRaid = GetNumRaidMembers()
        if numRaid > 0 then
            for i = 1, numRaid do
                local unit = "raid" .. i .. "target"
                if UnitExists(unit) and UnitClassification(unit) == "worldboss" then
                    return UnitName(unit)
                end
            end
        else
            local numParty = GetNumPartyMembers()
            if numParty > 0 then
                for i = 1, numParty do
                    local unit = "party" .. i .. "target"
                    if UnitExists(unit) and UnitClassification(unit) == "worldboss" then
                        return UnitName(unit)
                    end
                end
            end
        end
    end
    return nil
end

local function CacheGroupRoster(self)
    if not self.currentSession then return end
    self.currentSession.roster = {}
    
    local n, data = GetCacheData("player")
    if n then self.currentSession.roster[n] = data end

    for i=1, GetNumRaidMembers() do
        local n, data = GetCacheData("raid"..i)
        if n then self.currentSession.roster[n] = data end
    end
    for i=1, GetNumPartyMembers() do
        local n, data = GetCacheData("party"..i)
        if n then self.currentSession.roster[n] = data end
    end
end

function History:StartSession(type, name, data)
    local _, _, _, difficultyName = GetInstanceInfo()
    if not difficultyName or difficultyName == "" then difficultyName = nil end

    local sessionName = name
    if type == "world" and self.lastSeenWorldBoss and (time() - (self.lastSeenWorldBossTime or 0)) < 300 then
        sessionName = self.lastSeenWorldBoss
    end

    self.currentSession = {
        type = type,
        name = sessionName,
        difficulty = difficultyName,
        timestamp = time(),
        items = {},
        data = data or {},
        isLogged = false,
        roster = {}
    }
    
    CacheGroupRoster(self)
    
    if type == "dungeons" then
        local _, _, difficultyIndex = GetInstanceInfo()
        local diffName = "Normal"
        if difficultyIndex == 2 then
            diffName = "Heroic"
        elseif difficultyIndex == 3 then
            diffName = "Mythic"
        elseif difficultyIndex == 4 then
            diffName = "Ascended"
        end

        local minLevel, maxLevel = 100, 0
        for _, info in pairs(self.currentSession.roster) do
            if info.level then
                minLevel = math.min(minLevel, info.level)
                maxLevel = math.max(maxLevel, info.level)
            end
        end

        local isLeveling = false
        if maxLevel < 60 then
            isLeveling = true
        elseif maxLevel == 60 or maxLevel == 70 or maxLevel == 80 then
            if minLevel < maxLevel - 2 then
                isLeveling = true
            end
        else
            isLeveling = (minLevel < maxLevel)
        end

        if isLeveling then
            self.currentSession.difficulty = "Leveling"
        else
            self.currentSession.difficulty = "Lvl " .. maxLevel .. " " .. diffName
        end
    elseif type == "world" then
        local isHighRisk = false
        for i = 1, 40 do
            local _, _, _, _, _, _, _, _, _, _, currentSpellId = UnitAura("player", i)
            if not currentSpellId then break end
            if currentSpellId == 1004019 then -- HighRiskAura
                isHighRisk = true
                break
            end
        end
        self.currentSession.difficulty = isHighRisk and "High Risk" or "Low Risk"
    end
    if LootRemembererRollsFrame and LootRemembererRollsFrame:IsShown() then
        LootRemembererRollsFrame:UpdateList()
    end
end

function History:ClearAll()
    local h = LootRememberer:GetHistory()
    h.dungeons = {}
    h.raids = {}
    h.manastorm = {}
    h.world = {}
    self.currentSession = nil
    if LootRememberer.GUIMarkCacheDirty then
        LootRememberer:GUIMarkCacheDirty()
    end
    if self.accordionGroup then
        LootRememberer:GUIBuildHistoryTab(LootRememberer.historyTabGroup)
    end
    if LootRemembererRollsFrame and LootRemembererRollsFrame:IsShown() then
        LootRemembererRollsFrame:UpdateList()
    end
end

function History:PruneOldSessions()
    local val = LootRememberer:GetSettings().historyAutoClearValue or 30
    local unit = LootRememberer:GetSettings().historyAutoClearUnit or "Days"
    local cutoffSeconds = val * 24 * 60 * 60
    if unit == "Weeks" then cutoffSeconds = val * 7 * 24 * 60 * 60
    elseif unit == "Months" then cutoffSeconds = val * 30 * 24 * 60 * 60 end
    
    local threshold = time() - cutoffSeconds
    
    local h = LootRememberer:GetHistory()
    local removed = false
    for _, category in ipairs({"dungeons", "raids", "manastorm", "world"}) do
        if h[category] then
            for i = #h[category], 1, -1 do
                if h[category][i].timestamp < threshold then
                    table.remove(h[category], i)
                    removed = true
                end
            end
        end
    end
    if removed and LootRememberer.GUIMarkCacheDirty then
        LootRememberer:GUIMarkCacheDirty()
    end
end

local function GetManastormDifficulty()
    local raidMembers = GetNumRaidMembers()
    local partyMembers = GetNumPartyMembers()
    local totalMembers = 1
    if raidMembers > 0 then
        totalMembers = raidMembers
    elseif partyMembers > 0 then
        totalMembers = partyMembers + 1
    end
    
    local groupSize = "Solo"
    if totalMembers == 2 then groupSize = "Duo"
    elseif totalMembers == 3 then groupSize = "Trio"
    elseif totalMembers > 3 then groupSize = "Group" end
    
    local pLevel = UnitLevel("player")
    local levelMode = (pLevel == 60 or pLevel == 70 or pLevel == 80) and "Max-level" or "Leveling"
    
    return groupSize .. " (" .. levelMode .. ")"
end

function History:ACTIVE_MANASTORM_UPDATED(event, oldLevel, newLevel)
    if LootRememberer:GetSettings().enableHistory == false then return end
    if newLevel and newLevel > 0 then
        self.inManastorm = true
        LootRememberer:Print("|cff00ffff[LR Debug]|r Manastorm level " .. newLevel .. " detected! Tracking session...")
        if self.currentSession and self.currentSession.type == "manastorm" then
            -- Update the end level of the current session
            self.currentSession.data.endLevel = newLevel
            self.currentSession.name = "Manastorm " .. self.currentSession.data.startLevel .. "-" .. newLevel
        else
            -- Started a new Manastorm session
            self:StartSession("manastorm", "Manastorm " .. newLevel, { startLevel = newLevel, endLevel = newLevel })
            if self.currentSession then
                self.currentSession.difficulty = GetManastormDifficulty()
            end
            
            -- Force it to log immediately so the user can verify it in the UI even if solo
            if not self.currentSession.isLogged then
                self.currentSession.isLogged = true
                local h = LootRememberer:GetHistory()
                h["manastorm"] = h["manastorm"] or {}
                table.insert(h["manastorm"], self.currentSession)
                self:PruneOldSessions()
            end
        end
    else
        -- Left Manastorm
        if self.inManastorm then
            LootRememberer:Print("|cff00ffff[LR Debug]|r Manastorm ended. Stopped tracking.")
        end
        self.inManastorm = false
        self.currentSession = nil
        self:ZONE_CHANGED_NEW_AREA() -- Check if we immediately fell back into another tracked zone
    end
end

function History:ZONE_CHANGED_NEW_AREA()
    if LootRememberer:GetSettings().enableHistory == false then return end
    if self.inManastorm then return end -- Protect Manastorm sessions from being overridden
    local inInstance, instanceType = IsInInstance()
    local zoneName = GetRealZoneText()
    
    if instanceType == "party" then
        self:StartSession("dungeons", zoneName)
    elseif instanceType == "raid" then
        self:StartSession("raids", zoneName)
    elseif instanceType == "none" then
        -- We are in the world. Only track if we are in a group?
        if GetNumGroupMembers() > 0 then
            -- Don't spam new sessions if we just move between world zones, keep the same world session unless we drop group
            if not self.currentSession or self.currentSession.type ~= "world" then
                self:StartSession("world", "World Group - " .. zoneName)
            end
        else
            self.currentSession = nil
        end
    else
        self.currentSession = nil
    end
end

function History:GROUP_ROSTER_UPDATE()
    if LootRememberer:GetSettings().enableHistory == false then return end
    if not IsInInstance() then
        self:ZONE_CHANGED_NEW_AREA()
    end
end

function History:PLAYER_TARGET_CHANGED()
    local bossName = ScanForWorldBoss(self)
    if bossName then
        self.lastSeenWorldBoss = bossName
        self.lastSeenWorldBossTime = time()
        if self.currentSession and self.currentSession.type == "world" then
            self.currentSession.name = bossName
            if LootRememberer.History.currentContainer and LootRememberer.History.currentContainer:IsShown() then
                LootRememberer.History:BuildAccordion(LootRememberer.History.currentContainer, LootRememberer.History.currentCategory)
            end
        end
    end
end

function History:UPDATE_MOUSEOVER_UNIT()
    local bossName = ScanForWorldBoss(self)
    if bossName then
        self.lastSeenWorldBoss = bossName
        self.lastSeenWorldBossTime = time()
        if self.currentSession and self.currentSession.type == "world" then
            self.currentSession.name = bossName
            if LootRememberer.History.currentContainer and LootRememberer.History.currentContainer:IsShown() then
                LootRememberer.History:BuildAccordion(LootRememberer.History.currentContainer, LootRememberer.History.currentCategory)
            end
        end
    end
end

-- Helper to escape magic characters for lua patterns
local function EscapePattern(pattern)
    pattern = string.gsub(pattern, "%%s", "PLACEHOLDERS")
    pattern = string.gsub(pattern, "%%d", "PLACEHOLDERD")
    
    -- Escape all punctuation characters
    pattern = string.gsub(pattern, "(%p)", "%%%1")
    
    pattern = string.gsub(pattern, "PLACEHOLDERS", "(.-)")
    pattern = string.gsub(pattern, "PLACEHOLDERD", "(%%d+)")
    
    return "^" .. pattern .. "$"
end

local MATCH_NEED = EscapePattern(LOOT_ROLL_NEED or "%s has selected Need for: %s")
local MATCH_NEED_SELF = EscapePattern("You have selected Need for: %s")
local MATCH_GREED = EscapePattern(LOOT_ROLL_GREED or "%s has selected Greed for: %s")
local MATCH_GREED_SELF = EscapePattern("You have selected Greed for: %s")
local MATCH_PASS = EscapePattern(LOOT_ROLL_PASS or "%s passed on: %s")
local MATCH_PASS_SELF = EscapePattern("You passed on: %s")
local MATCH_ROLL = EscapePattern(RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)")
local MATCH_WON = EscapePattern(LOOT_ROLL_WON or "%s won: %s")
local MATCH_WON_SELF = EscapePattern(LOOT_ROLL_YOU_WON or "You won: %s")
local MATCH_DISENCHANT = EscapePattern(LOOT_ROLL_DISENCHANT or "%s has selected Disenchant for: %s")
local MATCH_DISENCHANT_SELF = EscapePattern("You have selected Disenchant for: %s")

local pendingRolls = {}

local function GetItemRecord(self, itemLink, operation, playerForDeduplication)
    if not itemLink then return nil end
    if not self.currentSession then return nil end
    
    local baseKey = itemLink
    local index = 1
    
    if operation == "ADD_ROLL" then
        while true do
            local key = (index == 1) and baseKey or (baseKey .. "_" .. index)
            local record = self.currentSession.items[key]
            if not record then
                self.currentSession.items[key] = { link = itemLink, rolls = {}, winner = nil, timestamp = time() }
                self.currentSession.itemOrder = self.currentSession.itemOrder or {}
                table.insert(self.currentSession.itemOrder, key)
                
                if LootRememberer.GUIMarkCacheDirty then
                    LootRememberer:GUIMarkCacheDirty()
                end
                
                if not self.currentSession.isLogged then
                    self.currentSession.isLogged = true
                    if self.currentSession then
                        local h = LootRememberer:GetHistory()
                        h[self.currentSession.type] = h[self.currentSession.type] or {}
                        table.insert(h[self.currentSession.type], self.currentSession)
                    end
                    self:PruneOldSessions()
                end
                return self.currentSession.items[key]
            end
            
            local playerExists = false
            for _, r in ipairs(record.rolls) do
                if r.player == playerForDeduplication then playerExists = true; break end
            end
            if not playerExists then return record end
            index = index + 1
        end
        
    elseif operation == "UPDATE_VALUE" then
        while true do
            local key = (index == 1) and baseKey or (baseKey .. "_" .. index)
            local record = self.currentSession.items[key]
            if not record then return self.currentSession.items[baseKey] end
            for _, r in ipairs(record.rolls) do
                if r.player == playerForDeduplication and r.value == 0 then return record end
            end
            index = index + 1
        end
        
    elseif operation == "SET_WINNER" then
        while true do
            local key = (index == 1) and baseKey or (baseKey .. "_" .. index)
            local record = self.currentSession.items[key]
            if not record then return self.currentSession.items[(index == 2) and baseKey or (baseKey .. "_" .. (index - 1))] end
            if not record.winner then return record end
            index = index + 1
        end
    end
    return self.currentSession.items[baseKey]
end

local function FormatRace(race)
    if not race then return "" end
    if race == "BloodElf" or race == "Bloodelf" then return "Blood Elf" end
    if race == "NightElf" or race == "Nightelf" then return "Night Elf" end
    if race == "Scourge" then return "Undead" end
    return race:gsub("^%l", string.upper)
end

local function FormatClass(class)
    if not class then return "" end
    return class:sub(1,1):upper() .. class:sub(2):lower()
end

local function GetPlayerInfo(self, playerName)
    if self.currentSession and self.currentSession.roster then
        local cached = self.currentSession.roster[playerName]
        local n, data = GetCacheData(playerName)
        
        if n and data then
            if cached then
                if (data.icon and not cached.icon) or (data.spec and cached.spec and string.len(data.spec) > string.len(cached.spec)) then
                    self.currentSession.roster[playerName] = data
                    cached = data
                end
            else
                self.currentSession.roster[playerName] = data
                cached = data
            end
        end
        if cached then return cached end
    end
    return { class = "UNKNOWN", race = "UNKNOWN", level = "??" }
end

function History:TriggerUpdate()
    if self.currentContainer and self.currentContainer:IsShown() then
        self:BuildAccordion(self.currentContainer, self.currentCategory)
    end
    if LootRemembererRollsFrame and LootRemembererRollsFrame:IsShown() then
        LootRemembererRollsFrame:UpdateList()
    end
end

function History:CHAT_MSG_SYSTEM(event, text)
    if LootRememberer:GetSettings().enableHistory == false then return end
    if not self.currentSession then return end

    local roller, roll, minRoll, maxRoll = string.match(text, MATCH_ROLL)
    if roller and roll and minRoll == "1" and maxRoll == "100" then
        -- Ascension sends "You rolls N (1-100)" for the local player
        if roller == "You" then roller = UnitName("player") end
        roller = string.match(roller, "^([^-]+)") or roller
        pendingRolls[roller] = pendingRolls[roller] or {}
        table.insert(pendingRolls[roller], tonumber(roll))
        
        for link, record in pairs(self.currentSession.items) do
            for _, r in ipairs(record.rolls) do
                if r.player == roller and r.value == 0 and (r.type == "Need" or r.type == "Greed" or r.type == "Disenchant") then
                    r.value = table.remove(pendingRolls[roller], 1)
                    self:TriggerUpdate()
                    return
                end
            end
        end
        return
    end
end

local function TryAddRoll(self, player, itemLink, type)
    if not player or not itemLink then return false end
    player = string.match(player, "^([^-]+)") or player
    if player == "You" then player = UnitName("player") end
    
    local record = GetItemRecord(self, itemLink, "ADD_ROLL", player)
    if not record then return false end
    
    local val = 0
    if pendingRolls[player] and #pendingRolls[player] > 0 then
        val = table.remove(pendingRolls[player], 1)
    end
    
    table.insert(record.rolls, { player = player, info = GetPlayerInfo(self, player), type = type, value = val })
    record.timestamp = time()
    
    if LootRememberer.GUIMarkCacheDirty then
        LootRememberer:GUIMarkCacheDirty()
    end
    
    self:TriggerUpdate()
    return true
end

function History:CHAT_MSG_LOOT(event, text)
    if LootRememberer:GetSettings().enableHistory == false then return end
    if not self.currentSession then return end
    
    -- Check for Ascension's custom direct roll format
    local rType, rValue, itemLink, player = string.match(text, "([%a]+) Roll .- (%d+) for (.-) by (.*)")
    if rType and rValue and itemLink and player then
        player = string.gsub(player, "|c%x%x%x%x%x%x%x%x", "")
        player = string.gsub(player, "|r", "")
        player = string.match(player, "^([^-]+)") or player
        if player == "You" then player = UnitName("player") end
        player = string.gsub(player, "%s+$", "")
        local record = GetItemRecord(self, itemLink, "UPDATE_VALUE", player)
        if record then
            local updated = false
            for _, r in ipairs(record.rolls) do
                if r.player == player then
                    if r.value == 0 or tonumber(rValue) > 0 then
                        r.value = tonumber(rValue)
                        r.type = rType
                    end
                    updated = true
                    break
                end
            end
            if not updated then
                table.insert(record.rolls, { player = player, info = GetPlayerInfo(self, player), type = rType, value = tonumber(rValue) })
            end
            record.timestamp = time()
            if LootRememberer.GUIMarkCacheDirty then
                LootRememberer:GUIMarkCacheDirty()
            end
            self:TriggerUpdate()
        end
        return
    end

    local matchPlayer, matchItem = string.match(text, MATCH_NEED)
    if not matchPlayer then matchItem = string.match(text, MATCH_NEED_SELF); matchPlayer = UnitName("player") end
    if TryAddRoll(self, matchPlayer, matchItem, "Need") then return end

    matchPlayer, matchItem = string.match(text, MATCH_GREED)
    if not matchPlayer then matchItem = string.match(text, MATCH_GREED_SELF); matchPlayer = UnitName("player") end
    if TryAddRoll(self, matchPlayer, matchItem, "Greed") then return end

    matchPlayer, matchItem = string.match(text, MATCH_DISENCHANT)
    if not matchPlayer then matchItem = string.match(text, MATCH_DISENCHANT_SELF); matchPlayer = UnitName("player") end
    if TryAddRoll(self, matchPlayer, matchItem, "Disenchant") then return end

    matchPlayer, matchItem = string.match(text, MATCH_PASS)
    if not matchPlayer then matchItem = string.match(text, MATCH_PASS_SELF); matchPlayer = UnitName("player") end
    if TryAddRoll(self, matchPlayer, matchItem, "Pass") then return end

    local matchPlayer, matchItem = string.match(text, MATCH_WON)
    if matchPlayer == "You" then
        matchPlayer = UnitName("player")
    elseif not matchPlayer then 
        matchItem = string.match(text, MATCH_WON_SELF)
        if matchItem then matchPlayer = UnitName("player") end
    end
    if matchPlayer and matchItem then
        matchPlayer = string.gsub(matchPlayer, "|c%x%x%x%x%x%x%x%x", "")
        matchPlayer = string.gsub(matchPlayer, "|r", "")
        matchPlayer = string.match(matchPlayer, "^([^-]+)") or matchPlayer
        local record = GetItemRecord(self, matchItem, "SET_WINNER")
        if record then
            record.winner = matchPlayer
            record.timestamp = time()
        end
        self:TriggerUpdate()
        return
    end
end

function LootRememberer:GUIBuildHistoryTab(container)
    self.History:BuildUI(container)
end

function History:BuildUI(container)
    container:SetLayout("Fill")
    
    local tabs = AceGUI:Create("TabGroup")
    tabs:SetFullWidth(true)
    tabs:SetFullHeight(true)
    tabs:SetLayout("Fill")
    tabs:SetTabs({
        {text="Dungeons", value="dungeons"},
        {text="Manastorm", value="manastorm"},
        {text="Raids", value="raids"},
        {text="World", value="world"},
    })
    tabs:SetCallback("OnGroupSelected", function(c, event, group)
        self.currentContainer = c
        self.currentCategory = group
        self:BuildAccordion(c, group)
    end)
    container:AddChild(tabs)

    self.qualityFilters = self.qualityFilters or {
        [2] = true,  -- Uncommon
        [3] = true,  -- Rare
        [4] = true,  -- Epic
        [5] = true,  -- Legendary
        [6] = true,  -- Vanity
    }

    local ITEM_QUALITIES = {
        [2] = {name="Uncommon", hex="1eff00"},
        [3] = {name="Rare", hex="0070dd"},
        [4] = {name="Epic", hex="a335ee"},
        [5] = {name="Legendary", hex="ff8000"},
        [6] = {name="Vanity", hex="e6cc80"}
    }
    local ITEM_QUALITY_ORDER = {2, 3, 4, 5, 6}

    local filterGroup = AceGUI:Create("SimpleGroup")
    filterGroup:SetLayout("Flow")
    filterGroup:SetWidth(150)
    filterGroup:SetHeight(40)
    
    local filterDropdown = AceGUI:Create("Dropdown")
    filterDropdown:SetLabel("")
    filterDropdown:SetMultiselect(true)
    filterDropdown:SetText("Quality:")
    local filterList = {}
    for _, k in ipairs(ITEM_QUALITY_ORDER) do
        local q = ITEM_QUALITIES[k]
        filterList[k] = "|cff" .. q.hex .. q.name .. "|r"
    end
    filterDropdown:SetList(filterList)
    
    for k, v in pairs(self.qualityFilters) do
        filterDropdown:SetItemValue(k, v)
    end

    filterDropdown:SetCallback("OnValueChanged", function(widget, event, key, checked)
        self.qualityFilters[key] = checked
        if self.currentContainer and self.currentCategory then
            self:BuildAccordion(self.currentContainer, self.currentCategory)
        end
    end)
    filterDropdown:SetWidth(150)
    filterGroup:AddChild(filterDropdown)
    
    filterGroup.frame:SetParent(container.frame)
    filterGroup.frame:ClearAllPoints()
    filterGroup.frame:SetPoint("TOPRIGHT", container.frame, "TOPRIGHT", -15, 0)
    filterGroup.frame:Show()

    tabs:SelectTab("dungeons")
end

local function GetRelativeTime(timestamp)
    local diff = time() - timestamp
    if diff < 60 then return diff .. " secs ago" end
    if diff < 3600 then return math.floor(diff/60) .. " mins ago" end
    if diff < 86400 then return math.floor(diff/3600) .. " hours ago" end
    return math.floor(diff/86400) .. " days ago"
end

local ICONS = {
    ["Need"] = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    ["Greed"] = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    ["Pass"] = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    ["Disenchant"] = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
}

local CATEGORY_ICONS = {
    ["dungeons"] = "|TInterface\\Icons\\INV_Misc_Bone_Skull_02:16|t ",
    ["raids"] = "|TInterface\\Icons\\Achievement_Boss_Ragnaros:16|t ",
    ["manastorm"] = "|TInterface\\Icons\\Spell_Arcane_PortalDalaran:16|t ",
    ["world"] = "|TInterface\\Icons\\Achievement_Zone_ArathiHighlands_01:16|t ",
}

function History:BuildAccordion(container, category)
    local oldScroll = 0
    if self.lastBuiltCategory == category and self.accordionGroup and self.accordionGroup.localstatus then
        oldScroll = self.accordionGroup.localstatus.scrollvalue or 0
    end
    self.lastBuiltCategory = category

    container:ReleaseChildren()
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetLayout("Flow")
    container:AddChild(scroll)
    self.accordionGroup = scroll
    
    local sessions = LootRememberer:GetHistory()[category] or {}
    if #sessions == 0 then
        local empty = AceGUI:Create("Label")
        empty:SetText("No history recorded yet.")
        empty:SetFullWidth(true)
        scroll:AddChild(empty)
        return
    end

    self.expandedSessions = self.expandedSessions or {}
    self.expandedItems = self.expandedItems or {}
    self.expandedDays = self.expandedDays or {}

    -- Sort a copy of the sessions by timestamp descending (newest first)
    local sortedSessions = {}
    for _, s in ipairs(sessions) do
        table.insert(sortedSessions, s)
    end
    table.sort(sortedSessions, function(a, b)
        return a.timestamp > b.timestamp
    end)

    -- Helper to check if a timestamp belongs to today
    local function IsToday(timestamp)
        return date("%Y-%m-%d", timestamp) == date("%Y-%m-%d", time())
    end

    -- Group sessions into Today vs Past Days
    local todaySessions = {}
    local pastDays = {}
    local pastDaysMap = {}

    for _, s in ipairs(sortedSessions) do
        if IsToday(s.timestamp) then
            table.insert(todaySessions, s)
        else
            local dayLabel = date("%B %d, %Y", s.timestamp)
            if not pastDaysMap[dayLabel] then
                local dayGroup = { dayLabel = dayLabel, timestamp = s.timestamp, sessions = {} }
                table.insert(pastDays, dayGroup)
                pastDaysMap[dayLabel] = dayGroup
            end
            table.insert(pastDaysMap[dayLabel].sessions, s)
        end
    end

    -- Core function to render a single session
    local function RenderSession(session, isFromDayCategory)
        local timeStr = GetRelativeTime(session.timestamp)
        local diffStr = session.difficulty and (" |cff00ccff(" .. session.difficulty .. ")|r") or ""
        local titleText = "|cffffd100" .. session.name .. "|r" .. diffStr .. " |cffaaaaaa(" .. timeStr .. ")|r"
        
        local headerGroup = AceGUI:Create("SimpleGroup")
        headerGroup:SetFullWidth(true)
        headerGroup:SetHeight(24)
        if headerGroup.frame.SetBackdrop then
            headerGroup.frame:SetBackdrop(nil)
        end
        if headerGroup.frame.backdrop then
            headerGroup.frame.backdrop:Hide()
        end
        headerGroup:SetLayout("LootRemembererRow")
        
        local headerBtn = AceGUI:Create("InteractiveLabel")
        headerBtn:SetFontObject(GameFontNormalHuge)
        if headerBtn.label then
            headerBtn.label:SetFont("Fonts\\ARIALN.TTF", 18)
        end
        local isExpanded = self.expandedSessions[session.timestamp]
        
        local expandIcon = isExpanded and "Interface\\AddOns\\LootRememberer\\Media\\ElvUI\\MinusButton" or "Interface\\AddOns\\LootRememberer\\Media\\ElvUI\\PlusButton"
        local indent = isFromDayCategory and "    " or ""
        headerBtn:SetText(string.format("%s|T%s:16|t %s", indent, expandIcon, titleText))
        headerBtn:SetCallback("OnClick", function()
            self.expandedSessions[session.timestamp] = not isExpanded
            if isExpanded then
                -- if we are collapsing it, clear all item expand states
                for link in pairs(session.items) do
                    self.expandedItems[session.timestamp .. link] = nil
                end
            end
            self:BuildAccordion(container, category)
        end)
        headerBtn:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPRIGHT")
            GameTooltip:ClearLines()
            GameTooltip:SetText(session.name, 1, 0.82, 0)
            local dateStr = date("%B %d, %Y at %I:%M %p", session.timestamp)
            GameTooltip:AddLine("Date: " .. dateStr, 1, 1, 1)
            if session.difficulty then
                GameTooltip:AddLine("Difficulty: " .. session.difficulty, 0, 0.8, 1)
            end
            GameTooltip:Show()
        end)
        headerBtn:SetCallback("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        local deleteBtn = AceGUI:Create("Icon")
        deleteBtn:SetImageSize(18, 18)
        deleteBtn:SetImage("Interface\\AddOns\\LootRememberer\\Media\\ElvUI\\close")
        deleteBtn:SetWidth(18)
        deleteBtn:SetHeight(18)
        deleteBtn:SetCallback("OnClick", function()
            StaticPopupDialogs["LOOTREMEMBERER_DELETE_SESSION"] = {
                text = "Are you sure you want to delete the history for " .. session.name .. "?",
                button1 = "Yes",
                button2 = "No",
                OnAccept = function()
                    local h = LootRememberer:GetHistory()
                    local originalIndex = nil
                    for idx, s in ipairs(h[category]) do
                        if s == session then
                            originalIndex = idx
                            break
                        end
                    end
                    if originalIndex then
                        table.remove(h[category], originalIndex)
                        if LootRememberer.GUIMarkCacheDirty then
                            LootRememberer:GUIMarkCacheDirty()
                        end
                    end
                    self:BuildAccordion(container, category)
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("LOOTREMEMBERER_DELETE_SESSION")
        end)
        
        headerGroup:AddChild(headerBtn)
        headerGroup:AddChild(deleteBtn)
        scroll:AddChild(headerGroup)

        if isExpanded then
            local orderedItems = session.itemOrder or {}
            -- If session is old and lacks itemOrder, build it
            if #orderedItems == 0 then
                for link in pairs(session.items) do table.insert(orderedItems, link) end
            end

            for _, link in ipairs(orderedItems) do
                local item = session.items[link]
                if item then
                    local _, _, quality = GetItemInfo(link)
                    local showItem = true
                    if quality and self.qualityFilters and self.qualityFilters[quality] == false then
                        showItem = false
                    end
                    
                    if showItem then
                        local itemTitle = "|T" .. (GetItemIcon(link) or "") .. ":16|t " .. link
                        
                        local itemHeader = AceGUI:Create("InteractiveLabel")
                        itemHeader:SetFontObject(GameFontNormalLarge)
                        if itemHeader.label then
                            itemHeader.label:SetFont("Fonts\\ARIALN.TTF", 14)
                        end
                        local isItemExpanded = self.expandedItems[session.timestamp .. link]
                        
                        local itemExpandIcon = isItemExpanded and "Interface\\AddOns\\LootRememberer\\Media\\ElvUI\\MinusButton" or "Interface\\AddOns\\LootRememberer\\Media\\ElvUI\\PlusButton"
                        local itemIndent = isFromDayCategory and "        " or "    "
                        itemHeader:SetText(string.format("%s|T%s:16|t %s", itemIndent, itemExpandIcon, itemTitle))
                        itemHeader:SetFullWidth(true)
                        itemHeader:SetCallback("OnClick", function()
                            self.expandedItems[session.timestamp .. link] = not isItemExpanded
                            self:BuildAccordion(container, category)
                        end)
                        itemHeader:SetCallback("OnEnter", function(widget)
                            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOPRIGHT")
                            GameTooltip:SetHyperlink(link)
                            GameTooltip:Show()
                        end)
                        itemHeader:SetCallback("OnLeave", function()
                            GameTooltip:Hide()
                        end)
                        scroll:AddChild(itemHeader)
                        
                        if isItemExpanded then
                            local rolls = {}
                            for _, r in ipairs(item.rolls) do table.insert(rolls, r) end
                            
                            local PRIO = { ["Need"] = 4, ["Greed"] = 3, ["Disenchant"] = 3, ["Pass"] = 1 }
                            table.sort(rolls, function(a, b) 
                                local aWin = (a.player == item.winner)
                                local bWin = (b.player == item.winner)
                                if aWin and not bWin then return true end
                                if bWin and not aWin then return false end
                                
                                local aPrio = PRIO[a.type] or 0
                                local bPrio = PRIO[b.type] or 0
                                if aPrio ~= bPrio then return aPrio > bPrio end
                                
                                local valA, valB = a.value or 0, b.value or 0
                                if valA ~= valB then return valA > valB end
                                
                                return a.player < b.player
                            end)
                            
                            if #rolls == 0 then
                                local label = AceGUI:Create("Label")
                                label:SetFontObject(GameFontNormal)
                                if label.label then
                                    label.label:SetFont("Fonts\\ARIALN.TTF", 12)
                                end
                                local noRollsIndent = isFromDayCategory and "                " or "            "
                                label:SetText(noRollsIndent .. "|cffaaaaaaNo rolls recorded.|r")
                                label:SetFullWidth(true)
                                scroll:AddChild(label)
                            end
                            
                            for _, r in ipairs(rolls) do
                                local label = AceGUI:Create("Label")
                                label:SetFontObject(GameFontNormal)
                                if label.label then
                                    label.label:SetFont("Fonts\\ARIALN.TTF", 12)
                                end
                                
                                local pClass = r.info and r.info.class or "UNKNOWN"
                                local pSpec = r.info and r.info.spec or pClass
                                local specIconStr = (r.info and r.info.icon) and ("|T" .. r.info.icon .. ":16|t ") or ""
                                
                                local cr, cg, cb
                                if GetClassColor then
                                    cr, cg, cb = GetClassColor(pClass)
                                end
                                if not cr then
                                    local c = RAID_CLASS_COLORS[pClass] or {r=1, g=1, b=1}
                                    cr, cg, cb = c.r, c.g, c.b
                                end
                                local hex = string.format("%02x%02x%02x", (cr or 1)*255, (cg or 1)*255, (cb or 1)*255)
                                
                                local infoStr = ""
                                if pClass ~= "UNKNOWN" then
                                    infoStr = string.format(" |cff888888(Lvl %d %s %s)|r", r.info.level or 0, FormatRace(r.info.race or ""), pSpec)
                                end
                                
                                local icon = ICONS[r.type] or ICONS["Pass"]
                                local val = r.value or 0
                                local valStr = (val > 0) and (val .. " - ") or ""
                                
                                local text = string.format("|T%s:16|t %s%s|cff%s%s|r%s", icon, valStr, specIconStr, hex, r.player, infoStr)
                                local rollIndent = isFromDayCategory and "                " or "            "
                                
                                if r.player == item.winner then
                                    text = string.format("|T%s:16|t |cff00ff00Winner:|r %s%s|cff%s%s|r%s", icon, valStr, specIconStr, hex, r.player, infoStr)
                                    label:SetFontObject(GameFontNormalLarge)
                                    if label.label then
                                        label.label:SetFont("Fonts\\ARIALN.TTF", 14)
                                    end
                                    rollIndent = isFromDayCategory and "              " or "          "
                                end
                                
                                label:SetText(rollIndent .. text)
                                label:SetFullWidth(true)
                                scroll:AddChild(label)
                            end
                        end
                    end
                end
            end
        end
    end

    -- 1. Render Today's sessions
    for _, session in ipairs(todaySessions) do
        RenderSession(session, false)
    end

    -- 2. Render separator line if we have BOTH today's sessions and past sessions
    if #todaySessions > 0 and #pastDays > 0 then
        local separator = AceGUI:Create("Heading")
        separator:SetText("")
        separator:SetFullWidth(true)
        scroll:AddChild(separator)
    end

    -- 3. Render Past Days (grouped by day, collapsible)
    for _, dayGroup in ipairs(pastDays) do
        local isDayExpanded = self.expandedDays[dayGroup.dayLabel]
        local dayExpandIcon = isDayExpanded and "Interface\\AddOns\\LootRememberer\\Media\\ElvUI\\MinusButton" or "Interface\\AddOns\\LootRememberer\\Media\\ElvUI\\PlusButton"
        
        local dayHeader = AceGUI:Create("InteractiveLabel")
        dayHeader:SetFontObject(GameFontNormalHuge)
        if dayHeader.label then
            dayHeader.label:SetFont("Fonts\\ARIALN.TTF", 18)
        end
        dayHeader:SetText(string.format("|T%s:16|t |cff00ccff%s|r |cffaaaaaa(%d runs)|r", dayExpandIcon, dayGroup.dayLabel, #dayGroup.sessions))
        dayHeader:SetFullWidth(true)
        dayHeader:SetCallback("OnClick", function()
            self.expandedDays[dayGroup.dayLabel] = not isDayExpanded
            self:BuildAccordion(container, category)
        end)
        scroll:AddChild(dayHeader)
        
        if isDayExpanded then
            for _, session in ipairs(dayGroup.sessions) do
                RenderSession(session, true)
            end
        end
    end

    if oldScroll > 0 then
        C_Timer.After(0, function()
            if scroll.SetScroll then
                scroll:SetScroll(oldScroll)
            end
        end)
    end
end
