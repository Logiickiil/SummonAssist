local addonName, NS = ...

local sendQueue = {}
local lastSendTime = 0
local SEND_INTERVAL = 0.20
local lastReplyToPeer = {}
NS.debugComms = false

local function SendAddonRaw(prefix, msg, chatType, target)
    local ok, res
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        ok, res = pcall(C_ChatInfo.SendAddonMessage, prefix, msg, chatType, target)
        if NS.debugComms then
            NS.Print(string.format("[Comms TX] %s -> %s (ok=%s, res=%s)", chatType, tostring(target or ""), tostring(ok), tostring(res)))
        end
        if ok then return true, res end
    end
    if SendAddonMessage then
        ok, res = pcall(SendAddonMessage, prefix, msg, chatType, target)
        if ok then return true, res end
    end
    return false, nil
end

local function EnqueueMessage(msg, chatType, target, highPriority)
    if not NS.IsSafeString(msg) then return end
    local item = { msg = msg, chatType = chatType, target = target }
    if highPriority then
        table.insert(sendQueue, 1, item)
    else
        table.insert(sendQueue, item)
    end
end

local throttleFrame = CreateFrame("Frame")
throttleFrame:SetScript("OnUpdate", function(self, elapsed)
    if #sendQueue == 0 then return end
    local now = GetTime()
    if (now - lastSendTime) >= SEND_INTERVAL then
        lastSendTime = now
        local item = table.remove(sendQueue, 1)
        if item then
            if item.chatType == "CHANNEL" then
                local chId = GetChannelName(NS.CHANNEL_NAME)
                if chId and chId > 0 then
                    SendAddonRaw(NS.PREFIX, item.msg, "CHANNEL", chId)
                end
            elseif item.chatType == "GUILD" then
                if IsInGuild() then
                    SendAddonRaw(NS.PREFIX, item.msg, "GUILD")
                end
            elseif item.chatType == "RAID" or item.chatType == "PARTY" or item.chatType == "INSTANCE_CHAT" then
                local grp = NS.GetGroupChatChannel()
                if grp then
                    SendAddonRaw(NS.PREFIX, item.msg, grp)
                end
            elseif item.chatType == "WHISPER" and item.target then
                local wTarget = NS.GetWhisperTarget(item.target)
                if wTarget then
                    SendAddonRaw(NS.PREFIX, item.msg, "WHISPER", wTarget)
                end
            end
        end
    end
end)

-- Also send direct WHISPER addon messages to every other Warlock in the group
-- so comms work reliably across any zone/continent even if group chat types differ
local function WhisperGroupWarlocks(payload)
    local me = NS.GetMyShortName()
    for wShort, info in pairs(NS.warlocks) do
        if wShort ~= me and info.online then
            local target = info.fullName or info.name
            if target and target ~= "" then
                EnqueueMessage(payload, "WHISPER", target, true)
            end
        end
    end
end

-- Broadcast presence, shard count, summon tally, version, and servicing area
function NS.BroadcastHello()
    local me = NS.GetMyShortName()
    local shards = NS.GetMyShards()
    local done = (NS.warlocks[me] and NS.warlocks[me].summonsDone) or 0
    local cleanArea = NS.GetMyServiceArea():gsub("|", "/")
    local payload = string.format("HELLO|%d|%d|%s|%s", tonumber(shards) or 0, tonumber(done) or 0, NS.VERSION, cleanArea)

    local grp = NS.GetGroupChatChannel()
    if grp then
        EnqueueMessage(payload, grp, nil, true)
    end
    WhisperGroupWarlocks(payload)
    if IsInGuild() then
        EnqueueMessage(payload, "GUILD", nil, false)
    end
end

function NS.BroadcastShards(shards, summonsDone)
    local me = NS.GetMyShortName()
    local cleanArea = NS.GetMyServiceArea():gsub("|", "/")
    local payload = string.format("SHARD|%d|%d|%s|%s", tonumber(shards) or 0, tonumber(summonsDone) or 0, NS.VERSION, cleanArea)

    local grp = NS.GetGroupChatChannel()
    if grp then
        EnqueueMessage(payload, grp, nil, true)
    end
    WhisperGroupWarlocks(payload)
end

function NS.BroadcastTurn(nextWarlockName, customerName)
    local grp = NS.GetGroupChatChannel()
    if not grp or not NS.IsSafeString(nextWarlockName) then return end
    local payload = string.format("TURN|%s|%s", nextWarlockName, customerName or "")
    EnqueueMessage(payload, grp, nil, true)
    WhisperGroupWarlocks(payload)
end

function NS.BroadcastBlacklistAdd(name, reason, addedBy, timestamp)
    if not SummonAssistantDB.autoSyncBlacklist then return end
    local cleanReason = (reason or "Scammer"):gsub("|", "/"):gsub(";", ","):sub(1, 80)
    local payload = string.format("BL_ADD|%s|%s|%s|%d", name, cleanReason, addedBy or NS.GetMyShortName(), timestamp or time())
    EnqueueMessage(payload, "PARTY")
    EnqueueMessage(payload, "GUILD")
    EnqueueMessage(payload, "CHANNEL")
end

function NS.BroadcastBlacklistRemove(name)
    if not SummonAssistantDB.autoSyncBlacklist then return end
    local payload = "BL_DEL|" .. name
    EnqueueMessage(payload, "PARTY")
    EnqueueMessage(payload, "GUILD")
    EnqueueMessage(payload, "CHANNEL")
end

function NS.RequestCommunityBlacklistSync()
    if not SummonAssistantDB.autoSyncBlacklist then return end
    EnqueueMessage("BL_REQ|" .. NS.VERSION, "PARTY")
    EnqueueMessage("BL_REQ|" .. NS.VERSION, "GUILD")
    EnqueueMessage("BL_REQ|" .. NS.VERSION, "CHANNEL")
    NS.Print("Requested community blacklist sync from nearby/guild/channel Warlocks...")
end

function NS.SendBlacklistBatch(targetChannel, whisperTarget)
    if not SummonAssistantDB.autoSyncBlacklist then return end
    local count = 0
    for _, entry in pairs(SummonAssistantDB.blacklist) do
        local cleanReason = (entry.reason or "Scammer"):gsub("|", "/"):sub(1, 60)
        local payload = string.format("BL_ADD|%s|%s|%s|%d", entry.name, cleanReason, entry.addedBy or "Community", entry.timestamp or time())
        EnqueueMessage(payload, targetChannel, whisperTarget)
        count = count + 1
        if count >= 25 then break end
    end
end

-- Export / Import Serializer for Discord / Guild sharing
function NS.ExportBlacklistString()
    local lines = { "SABL1" }
    for _, entry in pairs(SummonAssistantDB.blacklist) do
        local r = (entry.reason or "Scammer"):gsub("|", "/"):gsub("\r", " "):gsub("\n", " ")
        table.insert(lines, string.format("%s|%s|%s|%d", entry.name, r, entry.addedBy or "Community", entry.timestamp or time()))
    end
    return table.concat(lines, "\n")
end

function NS.ImportBlacklistString(rawText)
    if not NS.IsSafeString(rawText) then return 0 end
    local imported = 0
    for line in rawText:gmatch("[^\r\n]+") do
        if line ~= "SABL1" and line ~= "SSBL1" then
            local name, reason, addedBy, ts = strsplit("|", line)
            if name and name ~= "" then
                if NS.AddBlacklistEntry(name, reason, addedBy, tonumber(ts), true) then
                    imported = imported + 1
                end
            end
        end
    end
    NS.Print("Imported/updated |cff00ff00" .. imported .. "|r blacklist entries.")
    return imported
end

local function OnAddonMessage(prefix, msg, dist, sender)
    if not NS.IsSafeString(prefix) or prefix ~= NS.PREFIX then return end
    if not NS.IsSafeString(msg) or not NS.IsSafeString(sender) then return end

    local senderKey, senderShort = NS.NormalizeName(sender)
    if not senderShort or senderShort == NS.GetMyShortName() then return end

    if NS.debugComms then
        NS.Print(string.format("[Comms RX] %s from %s (%s): %s", tostring(dist), senderShort, tostring(sender), msg))
    end

    local cmd, a1, a2, a3, a4 = strsplit("|", msg)

    if cmd == "HELLO" or cmd == "SHARD" then
        local shards = tonumber(a1)
        local done = tonumber(a2)
        local ver = a3
        local area = a4

        NS.RecordAddonPeer(senderShort, shards, done, ver, area)
        if not NS.warlocks[senderShort] then
            NS.ScanGroup()
        end
        if NS.RefreshUI then NS.RefreshUI() end

        if cmd == "HELLO" then
            local now = GetTime()
            if not lastReplyToPeer[senderKey] or (now - lastReplyToPeer[senderKey]) > 2.0 then
                lastReplyToPeer[senderKey] = now
                local me = NS.GetMyShortName()
                local myDone = (NS.warlocks[me] and NS.warlocks[me].summonsDone) or 0
                local cleanArea = NS.GetMyServiceArea():gsub("|", "/")
                local replyPayload = string.format("SHARD|%d|%d|%s|%s", NS.GetMyShards(), myDone, NS.VERSION, cleanArea)
                EnqueueMessage(replyPayload, "WHISPER", sender, true)
                local grp = NS.GetGroupChatChannel()
                if grp then
                    EnqueueMessage(replyPayload, grp, nil, true)
                end
            end
        end

    elseif cmd == "TURN" then
        NS.RecordAddonPeer(senderShort, nil, nil, nil, nil)
        if a1 and a1 ~= "" then
            NS.SetCurrentTurn(a1, false)
        end

    elseif cmd == "BL_ADD" then
        NS.RecordAddonPeer(senderShort, nil, nil, nil, nil)
        if SummonAssistantDB.autoSyncBlacklist and a1 and a1 ~= "" then
            NS.AddBlacklistEntry(a1, a2, a3 or senderShort, tonumber(a4), true)
        end

    elseif cmd == "BL_DEL" then
        NS.RecordAddonPeer(senderShort, nil, nil, nil, nil)
        if SummonAssistantDB.autoSyncBlacklist and a1 and a1 ~= "" then
            NS.RemoveBlacklistEntry(a1, true)
        end

    elseif cmd == "BL_REQ" then
        NS.RecordAddonPeer(senderShort, nil, nil, nil, nil)
        if SummonAssistantDB.autoSyncBlacklist then
            NS.SendBlacklistBatch("WHISPER", sender)
        end
    end
end

function NS.InitComms()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, NS.PREFIX)
    end
    if RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, NS.PREFIX)
    end

    local commFrame = CreateFrame("Frame")
    commFrame:RegisterEvent("CHAT_MSG_ADDON")
    commFrame:SetScript("OnEvent", function(_, event, prefix, msg, dist, sender)
        if event == "CHAT_MSG_ADDON" then
            OnAddonMessage(prefix, msg, dist, sender)
        end
    end)

    -- Delay custom channel join by 6 seconds so /1 General and /2 Trade keep their standard channel numbers
    C_Timer.After(6, function()
        if JoinTemporaryChannel then
            pcall(JoinTemporaryChannel, NS.CHANNEL_NAME)
        end
        C_Timer.After(2, function()
            NS.RequestCommunityBlacklistSync()
        end)
    end)
end
