local addonName, NS = ...
_G.SummonAssistant = NS

NS.VERSION = "1.4.0"
NS.PREFIX = "SumAssistant"
NS.CHANNEL_NAME = "SumAssistantSync"
NS.SOUL_SHARD_ID = 6265
NS.RITUAL_OF_SUMMONING_ID = 698

NS.DEFAULT_AD_TEMPLATE = "WTS Summons to {loc} ({price}) - Whisper '{kw}' for instant auto-invite! ({shards} shards ready)"
NS.DEFAULT_WHISPER_TEMPLATE = "[Summon Assistant] Invited! Destination: {loc} - Price: {price} - Summoner: {summoner}. Please accept invite and have trade ready!"

NS.SERVICE_AREA_PRESETS = {
    "UC / Undercity",
    "Org / Orgrimmar",
    "TB / Thunder Bluff",
    "SW / Stormwind",
    "IF / Ironforge",
    "Darnassus",
    "Booty Bay",
    "ZG / Yojamba",
    "Felwood / Songflower",
    "Dire Maul",
    "BRM",
    "Silithus / AQ",
    "Plaguelands",
    "Kargath",
    "Grom'gol / STV",
    "Winterspring",
}

NS.DESTINATION_PATTERNS = {
    { tag = "UC / Undercity",     keys = { "undercity", "uc" } },
    { tag = "Org / Orgrimmar",    keys = { "orgrimmar", "org" } },
    { tag = "TB / Thunder Bluff", keys = { "thunder bluff", "thunderbluff", "tb" } },
    { tag = "SW / Stormwind",     keys = { "stormwind", "sw" } },
    { tag = "IF / Ironforge",     keys = { "ironforge", "if" } },
    { tag = "Darnassus",          keys = { "darnassus", "darn" } },
    { tag = "Booty Bay",          keys = { "booty bay", "bootybay", "bb" } },
    { tag = "ZG / Yojamba",       keys = { "zulgurub", "zul'gurub", "zg", "yojamba" } },
    { tag = "Felwood / SF",       keys = { "songflower", "felwood", "sf" } },
    { tag = "Dire Maul",          keys = { "dire maul", "diremaul", "dmt", "dmn", "dme", "dmw", "dm" } },
    { tag = "BRM",                keys = { "blackrock", "brm", "molten core", "mc", "bwl", "ubrs", "lbrs", "brd" } },
    { tag = "Silithus / AQ",      keys = { "silithus", "aq40", "aq20", "aq", "cenarion" } },
    { tag = "Plaguelands",        keys = { "plaguelands", "epl", "wpl", "naxx", "naxxramas", "strat", "stratholme", "scholo", "lhc" } },
    { tag = "Kargath",            keys = { "kargath", "badlands" } },
    { tag = "Grom'gol / STV",     keys = { "gromgol", "grom'gol", "gg", "stv", "stranglethorn" } },
    { tag = "Winterspring",       keys = { "winterspring", "everlook", "ws" } },
    { tag = "Tanaris",            keys = { "tanaris", "gadgetzan", "gadget", "zf" } },
    { tag = "Maraudon",           keys = { "maraudon", "mara", "desolace" } },
    { tag = "Scarlet Monastery",  keys = { "scarlet", "sm" } },
    { tag = "Onyxia",             keys = { "onyxia", "ony", "dustwallow", "theramore" } },
}

NS.warlocks = {}        -- [shortName] = { name, fullName, shards, summonsDone, online, hasAddon, version, serviceArea }
NS.addonPeers = {}      -- [key] = { name, shards, summonsDone, hasAddon, version, serviceArea, lastSeen }
NS.rotationOrder = {}   -- ordered array of shortName
NS.rotationIndex = 1
NS.queue = {}           -- ordered array of { key, name, shortName, source, status, time, msg, excerpt, destTag, channelName, bnSenderID, bnetGameAccountID }

local defaults = {
    enabled = true,
    autoInvite = true,
    scanPublicChat = true,
    autoConvertRaid = true,
    announceRotation = true,
    whisperCustomer = true,
    autoSyncBlacklist = true,
    filterQueueByMyArea = false,
    chatWatchFilter = "",
    minReportsRequired = 1,
    priceText = "2g",
    locationText = "Felwood / Songflower",
    adChannels = "2, 8",
    adTemplate = NS.DEFAULT_AD_TEMPLATE,
    whisperTemplate = NS.DEFAULT_WHISPER_TEMPLATE,
    keywords = { "123", "sum", "summon", "inv", "invite" },
    blacklist = {},
    whitelist = {},
    windowPos = nil,
    minimapAngle = 220,
}

-- Secret-value safe string validator for WoW Forever (1.60.1 / Midnight UI engine)
function NS.IsSafeString(val)
    if val == nil then return false end
    if issecretvalue and issecretvalue(val) then return false end
    return type(val) == "string"
end

function NS.NormalizeName(name)
    if not NS.IsSafeString(name) or name == "" then return nil, nil, nil end
    local trimmed = strtrim(name)
    if trimmed == "" then return nil, nil, nil end
    local short = trimmed:match("^([^%-]+)") or trimmed
    if Ambiguate then
        local ok, amb = pcall(Ambiguate, trimmed, "short")
        if ok and NS.IsSafeString(amb) and amb ~= "" then
            short = amb:match("^([^%-]+)") or amb
        end
    end
    return short:lower(), short, trimmed
end

-- Strips unescaped pipe characters '|' (which WoW's chat parser treats as invalid escape codes and silently drops)
function NS.SanitizeChatText(text)
    if not NS.IsSafeString(text) then return "" end
    local clean = text:gsub("|", "-"):gsub("[\r\n]+", " ")
    clean = strtrim(clean)
    if #clean > 255 then
        clean = clean:sub(1, 255)
    end
    return clean
end

-- Resolves whisper recipient name cleanly (strips same-realm suffix so SendChatMessage never fails)
function NS.GetWhisperTarget(targetName)
    if not NS.IsSafeString(targetName) or targetName == "" then return nil end
    local trimmed = strtrim(targetName)
    if Ambiguate then
        local ok, amb = pcall(Ambiguate, trimmed, "none")
        if ok and NS.IsSafeString(amb) and amb ~= "" then
            return amb
        end
    end
    local charPart, realmPart = trimmed:match("^([^%-]+)%-(.+)$")
    if charPart and realmPart then
        local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName():gsub("%s+", "")) or ""
        if myRealm ~= "" and realmPart:gsub("%s+", ""):lower() == myRealm:lower() then
            return charPart
        end
    end
    return trimmed
end

-- Safe wrapper for sending chat messages across WoW client builds
function NS.SendChatSafe(msg, chatType, language, target)
    local safeMsg = NS.SanitizeChatText(msg)
    if safeMsg == "" then return false end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        local ok = pcall(C_ChatInfo.SendChatMessage, safeMsg, chatType, language, target)
        if ok then return true end
    end
    if SendChatMessage then
        local ok = pcall(SendChatMessage, safeMsg, chatType, language, target)
        if ok then return true end
    end
    return false
end

function NS.GetMyServiceArea()
    local area = SummonAssistantDB and SummonAssistantDB.locationText
    if NS.IsSafeString(area) and strtrim(area) ~= "" then
        return strtrim(area)
    end
    local zone = GetRealZoneText and GetRealZoneText()
    if NS.IsSafeString(zone) and zone ~= "" then
        return zone
    end
    return "Unassigned"
end

function NS.SetMyServiceArea(newArea, shouldBroadcast)
    if not NS.IsSafeString(newArea) then return end
    local clean = strtrim(newArea)
    if clean == "" then return end
    SummonAssistantDB.locationText = clean
    local me = NS.GetMyShortName()
    if NS.warlocks[me] then
        NS.warlocks[me].serviceArea = clean
    end
    if shouldBroadcast ~= false and NS.BroadcastHello then
        NS.BroadcastHello()
    end
    if NS.RefreshUI then NS.RefreshUI() end
end

-- Detect destination tag (e.g. "UC / Undercity") from a chat message
function NS.DetectSummonDestination(msg)
    if not NS.IsSafeString(msg) or msg == "" then return nil end
    local lower = msg:lower()
    local padded = " " .. lower:gsub("[%p]", " ") .. " "

    for _, entry in ipairs(NS.DESTINATION_PATTERNS) do
        for _, kw in ipairs(entry.keys) do
            if padded:find(" " .. kw .. " ", 1, true) then
                return entry.tag
            end
        end
    end
    return nil
end

-- Check whether a public chat summon request passes the user's Chat Watch Filter / Service Area Filter
function NS.MatchesChatWatchFilter(msg, detectedDest)
    if not NS.IsSafeString(msg) then return false end
    local lowerMsg = msg:lower()
    local paddedMsg = " " .. lowerMsg:gsub("[%p]", " ") .. " "
    local lowerDest = (detectedDest and detectedDest:lower()) or ""

    local terms = {}

    -- 1. Custom comma-separated filter terms from Settings -> Chat Watch Filter
    local customFilter = SummonAssistantDB.chatWatchFilter
    if NS.IsSafeString(customFilter) and strtrim(customFilter) ~= "" then
        for word in customFilter:gmatch("[^,]+") do
            local clean = strtrim(word):lower()
            if clean ~= "" then
                table.insert(terms, clean)
            end
        end
    end

    -- 2. Optional toggle: filter public queue to match my own Servicing Area
    if SummonAssistantDB.filterQueueByMyArea then
        local myArea = NS.GetMyServiceArea():lower()
        for part in myArea:gmatch("[^/%-,]+") do
            local clean = strtrim(part)
            if clean ~= "" and clean ~= "unassigned" then
                table.insert(terms, clean)
            end
        end
    end

    -- If no filter terms are configured, accept all public summon requests
    if #terms == 0 then
        return true
    end

    for _, term in ipairs(terms) do
        if lowerDest ~= "" and lowerDest:find(term, 1, true) then
            return true
        end
        if paddedMsg:find(" " .. term .. " ", 1, true) or (#term >= 4 and lowerMsg:find(term, 1, true)) then
            return true
        end
    end

    return false
end

-- Dynamic token formatter for customizable ad and whisper templates
function NS.FormatCustomTemplate(template, playerName)
    if not NS.IsSafeString(template) or strtrim(template) == "" then
        return ""
    end
    local nextLock = NS.GetNextWarlock and NS.GetNextWarlock() or nil
    local summonerName = (nextLock and nextLock.name) or NS.GetMyShortName()
    local firstKw = (SummonAssistantDB.keywords and SummonAssistantDB.keywords[1]) or "123"
    local allKws = (SummonAssistantDB.keywords and table.concat(SummonAssistantDB.keywords, ", ")) or "123"
    local loc = NS.GetMyServiceArea()
    local price = SummonAssistantDB.priceText or "2g"
    local shards = tostring(NS.GetMyShards())
    local _, shortPlayer = NS.NormalizeName(playerName or "")
    local customer = shortPlayer or playerName or "Customer"

    local result = template
    result = result:gsub("{loc}", loc)
    result = result:gsub("{location}", loc)
    result = result:gsub("{price}", price)
    result = result:gsub("{kw}", firstKw)
    result = result:gsub("{keyword}", firstKw)
    result = result:gsub("{keywords}", allKws)
    result = result:gsub("{shards}", shards)
    result = result:gsub("{summoner}", summonerName)
    result = result:gsub("{player}", customer)
    result = result:gsub("{target}", customer)

    return NS.SanitizeChatText(result)
end

function NS.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9[Summon Assistant]|r " .. tostring(msg))
end

function NS.GetMyShortName()
    local name = UnitName("player")
    if not NS.IsSafeString(name) then return "Unknown" end
    local _, short = NS.NormalizeName(name)
    return short or name
end

function NS.GetMyShards()
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(NS.SOUL_SHARD_ID) or 0
    elseif GetItemCount then
        return GetItemCount(NS.SOUL_SHARD_ID) or 0
    end
    return 0
end

-- Fixed group chat channel resolver (avoids returning INSTANCE_CHAT when LE_PARTY_CATEGORY_INSTANCE is nil)
function NS.GetGroupChatChannel()
    if IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
            return "INSTANCE_CHAT"
        end
        return "PARTY"
    end
    return nil
end

function NS.EnsureRaidCapacity()
    if not IsInRaid() and IsInGroup() and GetNumGroupMembers() >= 5 and UnitIsGroupLeader("player") then
        if SummonAssistantDB.autoConvertRaid then
            if C_PartyInfo and C_PartyInfo.ConvertToRaid then
                C_PartyInfo.ConvertToRaid()
            elseif ConvertToRaid then
                ConvertToRaid()
            end
        end
    end
end

function NS.InvitePlayer(targetName, bnetGameAccountID)
    if NS.IsSafeString(targetName) and targetName ~= "" then
        local key, short = NS.NormalizeName(targetName)
        if key and NS.IsBlacklisted(key) then
            local entry = SummonAssistantDB.blacklist[key]
            NS.Print("|cffff3333Blocked invite to blacklisted player " .. short .. "|r (" .. (entry.reason or "Blacklisted") .. ")")
            return false
        end
    end

    NS.EnsureRaidCapacity()

    if bnetGameAccountID and BNInviteFriend then
        local ok = pcall(BNInviteFriend, bnetGameAccountID)
        if ok then
            return true
        end
    end

    if not NS.IsSafeString(targetName) or targetName == "" then
        return false
    end

    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(targetName)
    elseif InviteUnit then
        InviteUnit(targetName)
    end
    return true
end

function NS.KickPlayer(targetName)
    if not NS.IsSafeString(targetName) or targetName == "" then return end
    if C_PartyInfo and C_PartyInfo.UninviteUnit then
        C_PartyInfo.UninviteUnit(targetName)
    elseif UninviteUnit then
        UninviteUnit(targetName)
    end
end

-- Blacklist helpers
function NS.IsBlacklisted(name)
    local key = NS.NormalizeName(name)
    if not key then return false end
    if SummonAssistantDB.whitelist[key] then return false end
    local entry = SummonAssistantDB.blacklist[key]
    if not entry then return false end
    local reports = 1
    if entry.reporters then
        reports = 0
        for _ in pairs(entry.reporters) do reports = reports + 1 end
    end
    return reports >= (SummonAssistantDB.minReportsRequired or 1)
end

function NS.AddBlacklistEntry(name, reason, addedBy, timestamp, isRemote)
    local key, short = NS.NormalizeName(name)
    if not key then return false end
    if SummonAssistantDB.whitelist[key] then
        if not isRemote then
            NS.Print(short .. " is on your local whitelist. Remove them from whitelist first.")
        end
        return false
    end

    reason = (NS.IsSafeString(reason) and strtrim(reason) ~= "") and strtrim(reason) or "Scammer / No payment"
    addedBy = (NS.IsSafeString(addedBy) and addedBy ~= "") and addedBy or NS.GetMyShortName()
    timestamp = tonumber(timestamp) or time()

    local existing = SummonAssistantDB.blacklist[key]
    if existing then
        existing.reporters = existing.reporters or { [existing.addedBy or addedBy] = true }
        existing.reporters[addedBy] = true
        if timestamp > (existing.timestamp or 0) then
            existing.reason = reason
            existing.timestamp = timestamp
        end
    else
        SummonAssistantDB.blacklist[key] = {
            name = short,
            reason = reason,
            addedBy = addedBy,
            timestamp = timestamp,
            reporters = { [addedBy] = true },
        }
        if isRemote then
            NS.Print("|cffff9900[Community Blacklist]|r Added |cffff4444" .. short .. "|r (" .. reason .. ") reported by " .. addedBy)
        else
            NS.Print("Added |cffff4444" .. short .. "|r to Blacklist: " .. reason)
        end
    end

    if not isRemote and NS.BroadcastBlacklistAdd then
        NS.BroadcastBlacklistAdd(short, reason, addedBy, timestamp)
    end
    if NS.RefreshUI then NS.RefreshUI() end
    return true
end

function NS.RemoveBlacklistEntry(name, isRemote)
    local key, short = NS.NormalizeName(name)
    if not key or not SummonAssistantDB.blacklist[key] then return false end
    SummonAssistantDB.blacklist[key] = nil
    if not isRemote then
        NS.Print("Removed |cff00ff00" .. (short or name) .. "|r from Blacklist.")
        if NS.BroadcastBlacklistRemove then
            NS.BroadcastBlacklistRemove(short or name)
        end
    end
    if NS.RefreshUI then NS.RefreshUI() end
    return true
end

-- Queue management with chat excerpt & detected destination support
function NS.AddToQueue(fullName, source, msgText, meta)
    local key, short, trimmed = NS.NormalizeName(fullName)
    if not key then return nil end
    if NS.IsBlacklisted(key) then return nil end

    local cleanMsg = NS.IsSafeString(msgText) and strtrim(msgText) or ""
    local excerpt = cleanMsg
    if #excerpt > 42 then
        excerpt = excerpt:sub(1, 39) .. "..."
    end
    local destTag = (meta and meta.destTag) or NS.DetectSummonDestination(cleanMsg)

    for _, item in ipairs(NS.queue) do
        if item.key == key then
            item.time = GetTime()
            item.source = source or item.source
            if cleanMsg ~= "" then
                item.msg = cleanMsg
                item.excerpt = excerpt
            end
            if destTag then
                item.destTag = destTag
            end
            if meta then
                item.channelName = meta.channelName or item.channelName
                item.bnSenderID = meta.bnSenderID or item.bnSenderID
                item.bnetGameAccountID = meta.bnetGameAccountID or item.bnetGameAccountID
            end
            if NS.RefreshUI then NS.RefreshUI() end
            return item
        end
    end

    local entry = {
        key = key,
        name = trimmed,
        shortName = short,
        source = source or "Whisper",
        status = "Waiting",
        time = GetTime(),
        msg = cleanMsg,
        excerpt = excerpt,
        destTag = destTag,
        channelName = meta and meta.channelName or nil,
        bnSenderID = meta and meta.bnSenderID or nil,
        bnetGameAccountID = meta and meta.bnetGameAccountID or nil,
    }
    table.insert(NS.queue, entry)
    if NS.RefreshUI then NS.RefreshUI() end
    return entry
end

function NS.RemoveFromQueue(nameOrKey)
    local key = NS.NormalizeName(nameOrKey)
    if not key then return end
    for i = #NS.queue, 1, -1 do
        if NS.queue[i].key == key then
            table.remove(NS.queue, i)
        end
    end
    if NS.RefreshUI then NS.RefreshUI() end
end

function NS.RemoveQueueIndex(idx)
    if NS.queue[idx] then
        table.remove(NS.queue, idx)
        if NS.RefreshUI then NS.RefreshUI() end
    end
end

-- Record peer telemetry persistently so it survives roster rescans regardless of event order
function NS.RecordAddonPeer(senderName, shards, summonsDone, version, serviceArea)
    local key, short = NS.NormalizeName(senderName)
    if not key or not short then return end
    local peer = NS.addonPeers[key] or {}
    peer.name = short
    peer.hasAddon = true
    if shards ~= nil and shards >= 0 then
        peer.shards = shards
    end
    if summonsDone ~= nil and summonsDone >= 0 then
        peer.summonsDone = summonsDone
    end
    if NS.IsSafeString(version) and version ~= "" then
        peer.version = version
    end
    if NS.IsSafeString(serviceArea) and strtrim(serviceArea) ~= "" then
        peer.serviceArea = strtrim(serviceArea)
    end
    peer.lastSeen = GetTime()
    NS.addonPeers[key] = peer

    if NS.warlocks[short] then
        NS.warlocks[short].hasAddon = true
        if peer.shards ~= nil then NS.warlocks[short].shards = peer.shards end
        if peer.summonsDone ~= nil then NS.warlocks[short].summonsDone = peer.summonsDone end
        if peer.version then NS.warlocks[short].version = peer.version end
        if peer.serviceArea then NS.warlocks[short].serviceArea = peer.serviceArea end
    end
end

-- Group & Warlock Rotation management
function NS.ScanGroup()
    local seenWarlocks = {}
    local groupMembers = {}

    local function inspectUnit(unit)
        if not UnitExists(unit) then return end
        local rawName, rawRealm = UnitName(unit)
        if not NS.IsSafeString(rawName) then return end
        local fullUnitName = rawName
        if NS.IsSafeString(rawRealm) and rawRealm ~= "" and not rawName:find("-", 1, true) then
            fullUnitName = rawName .. "-" .. rawRealm
        end
        local key, short = NS.NormalizeName(fullUnitName)
        if not key then return end
        groupMembers[key] = true

        local _, classFile = UnitClass(unit)
        if classFile == "WARLOCK" then
            seenWarlocks[short] = true
            local existing = NS.warlocks[short]
            local peer = NS.addonPeers[key]
            local isSelf = UnitIsUnit(unit, "player")

            local shards = -1
            if isSelf then
                shards = NS.GetMyShards()
            elseif peer and peer.shards ~= nil then
                shards = peer.shards
            elseif existing and existing.shards ~= nil then
                shards = existing.shards
            end

            local summonsDone = (existing and existing.summonsDone) or 0
            if not isSelf and peer and peer.summonsDone ~= nil and peer.summonsDone > summonsDone then
                summonsDone = peer.summonsDone
            end

            local area = nil
            if isSelf then
                area = NS.GetMyServiceArea()
            elseif peer and peer.serviceArea then
                area = peer.serviceArea
            elseif existing and existing.serviceArea then
                area = existing.serviceArea
            end

            NS.warlocks[short] = {
                name = short,
                fullName = fullUnitName,
                shards = shards,
                summonsDone = summonsDone,
                online = UnitIsConnected(unit) and true or false,
                hasAddon = isSelf or (peer and peer.hasAddon) or (existing and existing.hasAddon) or false,
                version = isSelf and NS.VERSION or (peer and peer.version) or (existing and existing.version) or nil,
                serviceArea = area,
            }

            local foundInOrder = false
            for _, wName in ipairs(NS.rotationOrder) do
                if wName == short then foundInOrder = true break end
            end
            if not foundInOrder then
                table.insert(NS.rotationOrder, short)
            end
        end
    end

    inspectUnit("player")
    if IsInRaid() then
        for i = 1, 40 do inspectUnit("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, 4 do inspectUnit("party" .. i) end
    end

    -- Prune warlocks who left the group
    for i = #NS.rotationOrder, 1, -1 do
        local wName = NS.rotationOrder[i]
        if not seenWarlocks[wName] then
            table.remove(NS.rotationOrder, i)
            NS.warlocks[wName] = nil
        end
    end

    if NS.rotationIndex > #NS.rotationOrder then
        NS.rotationIndex = 1
    end

    -- Update customer queue statuses
    for i = #NS.queue, 1, -1 do
        local q = NS.queue[i]
        if groupMembers[q.key] then
            q.status = "In Group"
        elseif q.status == "In Group" then
            table.remove(NS.queue, i)
        elseif (GetTime() - q.time) > 300 and q.status == "Waiting" then
            table.remove(NS.queue, i)
        end
    end

    if NS.RefreshUI then NS.RefreshUI() end
end

function NS.GetNextWarlock()
    local count = #NS.rotationOrder
    if count == 0 then return nil end

    for offset = 0, count - 1 do
        local idx = ((NS.rotationIndex - 1 + offset) % count) + 1
        local wName = NS.rotationOrder[idx]
        local info = NS.warlocks[wName]
        if info and info.online and (info.shards == -1 or info.shards > 0) then
            NS.rotationIndex = idx
            return info, idx
        end
    end

    local fallbackName = NS.rotationOrder[NS.rotationIndex]
    return NS.warlocks[fallbackName], NS.rotationIndex
end

function NS.SetCurrentTurn(warlockName, broadcast)
    for idx, wName in ipairs(NS.rotationOrder) do
        if wName:lower() == warlockName:lower() then
            NS.rotationIndex = idx
            if broadcast and NS.BroadcastTurn then
                NS.BroadcastTurn(wName, "")
            end
            if NS.RefreshUI then NS.RefreshUI() end
            return true
        end
    end
    return false
end

function NS.AnnounceAndAdvanceRotation(customerName, skipOnly)
    local current = NS.GetNextWarlock()
    if not current then
        NS.Print("No Warlocks found in your group to announce.")
        return
    end

    if not skipOnly then
        current.summonsDone = (current.summonsDone or 0) + 1
    end

    if #NS.rotationOrder > 0 then
        NS.rotationIndex = (NS.rotationIndex % #NS.rotationOrder) + 1
    end
    local nextLock = NS.GetNextWarlock()

    local chatType = NS.GetGroupChatChannel()
    if SummonAssistantDB.announceRotation and chatType then
        local targetStr = (NS.IsSafeString(customerName) and customerName ~= "") and (" -> Summoning: " .. customerName) or ""
        local shardStr = (nextLock and nextLock.shards >= 0) and (" (" .. nextLock.shards .. " shards)") or ""
        if nextLock then
            NS.SendChatSafe("[Summon Assistant] Next Summon: " .. nextLock.name .. shardStr .. targetStr, chatType)
        end
    elseif nextLock then
        NS.Print("Next Summon: |cff9482c9" .. nextLock.name .. "|r")
    end

    if nextLock and NS.BroadcastTurn then
        NS.BroadcastTurn(nextLock.name, customerName or "")
    end
    if NS.RefreshUI then NS.RefreshUI() end
end

-- Core event frame
local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
coreFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
coreFrame:RegisterEvent("BAG_UPDATE")
coreFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

local lastShardCount = -1
local lastGroupCount = 0

coreFrame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" and arg1 == addonName then
        SummonAssistantDB = SummonAssistantDB or {}

        for k, v in pairs(defaults) do
            if SummonAssistantDB[k] == nil then
                if type(v) == "table" then
                    SummonAssistantDB[k] = CopyTable(v)
                else
                    SummonAssistantDB[k] = v
                end
            end
        end

        if NS.InitComms then NS.InitComms() end
        if NS.InitUI then NS.InitUI() end
        NS.Print("v" .. NS.VERSION .. " loaded. Type |cff00ff00/sa|r or click the minimap icon.")

    elseif event == "PLAYER_ENTERING_WORLD" then
        lastShardCount = NS.GetMyShards()
        NS.ScanGroup()
        if NS.BroadcastHello then
            NS.BroadcastHello()
            C_Timer.After(2.5, function()
                NS.ScanGroup()
                NS.BroadcastHello()
            end)
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        NS.ScanGroup()
        local currentCount = GetNumGroupMembers()
        local myDone = NS.warlocks[NS.GetMyShortName()] and NS.warlocks[NS.GetMyShortName()].summonsDone or 0
        if currentCount ~= lastGroupCount then
            lastGroupCount = currentCount
            if NS.BroadcastHello then
                NS.BroadcastHello()
            end
        elseif NS.BroadcastShards then
            NS.BroadcastShards(NS.GetMyShards(), myDone)
        end

    elseif event == "BAG_UPDATE" then
        local currentShards = NS.GetMyShards()
        if currentShards ~= lastShardCount then
            lastShardCount = currentShards
            local me = NS.GetMyShortName()
            if NS.warlocks[me] then
                NS.warlocks[me].shards = currentShards
            end
            if NS.BroadcastShards then
                NS.BroadcastShards(currentShards, NS.warlocks[me] and NS.warlocks[me].summonsDone or 0)
            end
            if NS.RefreshUI then NS.RefreshUI() end
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not NS.IsSafeString(arg1) then return end
        local isRitual = (arg3 == NS.RITUAL_OF_SUMMONING_ID)
        if not isRitual and type(arg3) == "number" and C_Spell and C_Spell.GetSpellName then
            local sName = C_Spell.GetSpellName(arg3)
            if NS.IsSafeString(sName) and sName == "Ritual of Summoning" then
                isRitual = true
            end
        end

        if isRitual then
            local casterRaw = UnitName(arg1)
            if NS.IsSafeString(casterRaw) then
                local _, casterShort = NS.NormalizeName(casterRaw)
                if casterShort and NS.warlocks[casterShort] then
                    NS.warlocks[casterShort].summonsDone = (NS.warlocks[casterShort].summonsDone or 0) + 1
                    for idx, wName in ipairs(NS.rotationOrder) do
                        if wName == casterShort then
                            NS.rotationIndex = (idx % #NS.rotationOrder) + 1
                            break
                        end
                    end
                    local nextLock = NS.GetNextWarlock()
                    local chatType = NS.GetGroupChatChannel()
                    if SummonAssistantDB.announceRotation and chatType and UnitIsUnit(arg1, "player") and nextLock then
                        local shardStr = nextLock.shards >= 0 and (" (" .. nextLock.shards .. " shards)") or ""
                        NS.SendChatSafe("[Summon Assistant] Ritual cast! Next up: " .. nextLock.name .. shardStr, chatType)
                    end
                    if NS.RefreshUI then NS.RefreshUI() end
                end
            end
        end
    end
end)
