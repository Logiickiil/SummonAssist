local addonName, NS = ...

local recentAutoInvites = {} -- throttle duplicate whispers within 10s
local recentPublicLogs = {}  -- deduplicate identical public chat captures across multiple chat frames

-- Resolve a Battle.net friend account ID (bnSenderID) into character name, full name, and gameAccountID
function NS.ResolveBNetSender(bnSenderID, fallbackDisplayName)
    if not bnSenderID or type(bnSenderID) ~= "number" then
        return nil, nil, nil
    end

    local charName, realmName, gameAccountID

    if C_BattleNet and C_BattleNet.GetAccountInfoByID then
        local ok, accountInfo = pcall(C_BattleNet.GetAccountInfoByID, bnSenderID)
        if ok and type(accountInfo) == "table" and type(accountInfo.gameAccountInfo) == "table" then
            local ga = accountInfo.gameAccountInfo
            if NS.IsSafeString(ga.characterName) and ga.characterName ~= "" then
                charName = ga.characterName
            end
            if NS.IsSafeString(ga.realmName) and ga.realmName ~= "" then
                realmName = ga.realmName
            end
            if type(ga.gameAccountID) == "number" then
                gameAccountID = ga.gameAccountID
            end
        end
    end

    if not charName and BNGetFriendInfoByID then
        local ok, _, _, _, _, toonName, toonID = pcall(BNGetFriendInfoByID, bnSenderID)
        if ok then
            if NS.IsSafeString(toonName) and toonName ~= "" then
                charName = toonName
            end
            if type(toonID) == "number" and not gameAccountID then
                gameAccountID = toonID
            end
        end
    end

    if not charName and NS.IsSafeString(fallbackDisplayName) and fallbackDisplayName ~= "" then
        charName = fallbackDisplayName
    end

    if not charName then
        return nil, nil, gameAccountID
    end

    local fullName = charName
    if realmName and realmName ~= "" and not charName:find("-", 1, true) then
        fullName = charName .. "-" .. realmName:gsub("%s+", "")
    end

    return charName, fullName, gameAccountID
end

-- Exact standalone keyword check (e.g. "inv" or "123" alone, NOT "Inv please I really want to come")
function NS.MatchesKeyword(msg)
    if not NS.IsSafeString(msg) then return false end
    local cleanMsg = strtrim(msg):lower()
    if cleanMsg == "" then return false end

    local strippedMsg = cleanMsg:gsub("^[%s%p]+", ""):gsub("[%s%p]+$", "")

    for _, kw in ipairs(SummonAssistantDB.keywords or {}) do
        if NS.IsSafeString(kw) and kw ~= "" then
            local cleanKw = strtrim(kw):lower()
            if cleanKw ~= "" then
                if cleanMsg == cleanKw or (strippedMsg ~= "" and strippedMsg == cleanKw) then
                    return true
                end
            end
        end
    end
    return false
end

-- Check public chat (Trade/World/LFG/Say/Yell) for summon requests
function NS.IsPublicSummonRequest(msg)
    if not NS.IsSafeString(msg) then return false end
    local lowerMsg = msg:lower()
    -- Ignore our own addon ads
    if lowerMsg:find("wts summon", 1, true) or lowerMsg:find("whisper '", 1, true) then
        return false
    end

    if lowerMsg:find("wtb sum", 1, true)
        or lowerMsg:find("lf sum", 1, true)
        or lowerMsg:find("need sum", 1, true)
        or lowerMsg:find("looking for sum", 1, true)
        or lowerMsg:find("buy sum", 1, true)
        or lowerMsg:find("buying sum", 1, true)
        or lowerMsg:find("anyone summoning", 1, true)
        or lowerMsg:find("sum to ", 1, true)
        or lowerMsg:find("summon to ", 1, true)
        or lowerMsg:find("summons to ", 1, true) then
        return true
    end
    return false
end

function NS.BuildCustomerWhisperMessage(playerName)
    local tpl = SummonAssistantDB.whisperTemplate
    if not NS.IsSafeString(tpl) or strtrim(tpl) == "" then
        tpl = NS.DEFAULT_WHISPER_TEMPLATE
    end
    return NS.FormatCustomTemplate(tpl, playerName)
end

function NS.BuildCustomAdMessage()
    local tpl = SummonAssistantDB.adTemplate
    if not NS.IsSafeString(tpl) or strtrim(tpl) == "" then
        tpl = NS.DEFAULT_AD_TEMPLATE
    end
    return NS.FormatCustomTemplate(tpl)
end

local function SendCustomerConfirmWhisper(targetName, bnSenderID)
    if not SummonAssistantDB.whisperCustomer then return end

    local infoMsg = NS.BuildCustomerWhisperMessage(targetName)
    if infoMsg == "" then return end

    if bnSenderID then
        if C_BattleNet and C_BattleNet.SendWhisper then
            local ok = pcall(C_BattleNet.SendWhisper, bnSenderID, infoMsg)
            if ok then return end
        end
        if BNSendWhisper then
            local ok = pcall(BNSendWhisper, bnSenderID, infoMsg)
            if ok then return end
        end
    end

    local whisperTarget = NS.GetWhisperTarget(targetName)
    if whisperTarget and whisperTarget ~= "" then
        NS.SendChatSafe(infoMsg, "WHISPER", nil, whisperTarget)
    end
end

-- Shared processor for both standard whispers and Battle.net whispers (standalone keyword only)
local function ProcessIncomingWhisper(msg, targetFullName, sourceLabel, bnSenderID, bnetGameAccountID)
    if not SummonAssistantDB.enabled then return end
    if not NS.IsSafeString(msg) then return end
    if not NS.MatchesKeyword(msg) then return end

    local key, short, trimmed
    if NS.IsSafeString(targetFullName) and targetFullName ~= "" then
        key, short, trimmed = NS.NormalizeName(targetFullName)
    end

    if short and short == NS.GetMyShortName() then return end

    if key and NS.IsBlacklisted(key) then
        local entry = SummonAssistantDB.blacklist[key]
        local reason = entry and entry.reason or "Community Blacklist"
        NS.Print("|cffff3333[BLACKLIST ALERT]|r Blacklisted player |cffff4444" .. short .. "|r whispered for a summon! Reason: " .. reason)
        local grp = NS.GetGroupChatChannel()
        if grp then
            NS.SendChatSafe("[Summon Assistant] WARNING: Blacklisted player " .. short .. " tried to get a summon (" .. reason .. ")!", grp)
        end
        return
    end

    local queueName = trimmed or (bnSenderID and ("BNet#" .. tostring(bnSenderID))) or nil
    local qEntry = nil
    if queueName then
        qEntry = NS.AddToQueue(queueName, sourceLabel, msg, {
            bnSenderID = bnSenderID,
            bnetGameAccountID = bnetGameAccountID,
        })
    end

    if SummonAssistantDB.autoInvite then
        local throttleKey = key or (bnSenderID and ("bn:" .. tostring(bnSenderID)))
        if throttleKey then
            local now = GetTime()
            if not recentAutoInvites[throttleKey] or (now - recentAutoInvites[throttleKey]) > 10 then
                recentAutoInvites[throttleKey] = now
                if NS.InvitePlayer(trimmed, bnetGameAccountID) then
                    if qEntry then qEntry.status = "Invited" end
                    NS.Print("Auto-invited |cff00ff00" .. (short or queueName) .. "|r (" .. sourceLabel .. " keyword matched).")
                    SendCustomerConfirmWhisper(trimmed, bnSenderID)
                    if NS.RefreshUI then NS.RefreshUI() end
                end
            end
        end
    end
end

-- Public chat watcher: captures summon requests, extracts destination & chat excerpt, and applies Chat Watch Filter
local function ProcessPublicChatMessage(event, msg, sender, channelString)
    if not SummonAssistantDB or not SummonAssistantDB.enabled or not SummonAssistantDB.scanPublicChat then
        return
    end
    if not NS.IsSafeString(msg) or not NS.IsSafeString(sender) then
        return
    end
    if not NS.IsPublicSummonRequest(msg) then
        return
    end

    local key, short, trimmed = NS.NormalizeName(sender)
    if not key or short == NS.GetMyShortName() then return end
    if NS.IsBlacklisted(key) then return end

    local detectedDest = NS.DetectSummonDestination(msg)
    if not NS.MatchesChatWatchFilter(msg, detectedDest) then
        return
    end

    -- Deduplicate identical messages from the same player within 3 seconds (e.g. multi-channel spam)
    local dedupKey = key .. ":" .. msg:lower()
    local now = GetTime()
    if recentPublicLogs[dedupKey] and (now - recentPublicLogs[dedupKey]) < 3.0 then
        return
    end
    recentPublicLogs[dedupKey] = now

    local sourceLabel = "Public"
    local cleanChannel = nil
    if event == "CHAT_MSG_CHANNEL" and NS.IsSafeString(channelString) and channelString ~= "" then
        cleanChannel = channelString
        local chNameOnly = channelString:match("^%d+%.%s*(.+)$") or channelString
        sourceLabel = chNameOnly
    elseif event == "CHAT_MSG_YELL" then
        sourceLabel = "Yell"
    elseif event == "CHAT_MSG_SAY" then
        sourceLabel = "Say"
    end

    NS.AddToQueue(trimmed, sourceLabel, msg, {
        destTag = detectedDest,
        channelName = cleanChannel or sourceLabel,
    })
end

-- Clickable [+Invite] hyperlink handler in chat frames
hooksecurefunc("SetItemRef", function(link, text, button)
    if not NS.IsSafeString(link) then return end
    local action, payload = link:match("^addon:SummonAssistant:([^:]+):(.+)$")
    if action == "inv" and payload then
        NS.InvitePlayer(payload, nil)
    elseif action == "bninv" and payload then
        local gaID, charTarget = payload:match("^([^:]+):(.*)$")
        NS.InvitePlayer(charTarget ~= "" and charTarget or nil, tonumber(gaID))
    end
end)

-- Chat filter to inject clickable [+Invite] or [BLACKLISTED] tags in chat frames
local function ChatScanFilter(self, event, msg, sender, ...)
    if not SummonAssistantDB or not SummonAssistantDB.enabled then
        return false, msg, sender, ...
    end
    if not NS.IsSafeString(msg) then
        return false, msg, sender, ...
    end

    local isBNet = (event == "CHAT_MSG_BN_WHISPER")
    local isWhisper = (event == "CHAT_MSG_WHISPER") or isBNet
    local isMatch = (isWhisper and NS.MatchesKeyword(msg))
                    or (SummonAssistantDB.scanPublicChat and NS.IsPublicSummonRequest(msg))

    if not isMatch then
        return false, msg, sender, ...
    end

    if isBNet then
        local bnSenderID = select(11, ...)
        local _, fullName, gameAccountID = NS.ResolveBNetSender(bnSenderID, sender)
        local key, short, trimmed = NS.NormalizeName(fullName or "")
        if key and NS.IsBlacklisted(key) then
            return false, "|cffff3333[BLACKLISTED]|r " .. msg, sender, ...
        elseif gameAccountID or trimmed then
            local linkData = tostring(gameAccountID or 0) .. ":" .. (trimmed or "")
            local invLink = "|Haddon:SummonAssistant:bninv:" .. linkData .. "|h|cff00ff00[+Invite]|r|h "
            return false, invLink .. msg, sender, ...
        end
        return false, msg, sender, ...
    end

    if not NS.IsSafeString(sender) then
        return false, msg, sender, ...
    end

    local key, short, trimmed = NS.NormalizeName(sender)
    if not key or short == NS.GetMyShortName() then
        return false, msg, sender, ...
    end

    if NS.IsBlacklisted(key) then
        return false, "|cffff3333[BLACKLISTED]|r " .. msg, sender, ...
    else
        local invLink = "|Haddon:SummonAssistant:inv:" .. trimmed .. "|h|cff00ff00[+Invite]|r|h "
        return false, invLink .. msg, sender, ...
    end
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", ChatScanFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_BN_WHISPER", ChatScanFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatScanFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", ChatScanFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_YELL", ChatScanFilter)

local chatWatcherFrame = CreateFrame("Frame")
chatWatcherFrame:RegisterEvent("CHAT_MSG_WHISPER")
chatWatcherFrame:RegisterEvent("CHAT_MSG_BN_WHISPER")
chatWatcherFrame:RegisterEvent("CHAT_MSG_CHANNEL")
chatWatcherFrame:RegisterEvent("CHAT_MSG_SAY")
chatWatcherFrame:RegisterEvent("CHAT_MSG_YELL")
chatWatcherFrame:SetScript("OnEvent", function(_, event, msg, sender, _, channelString, _, _, _, _, _, _, _, _, bnSenderID)
    if event == "CHAT_MSG_WHISPER" then
        ProcessIncomingWhisper(msg, sender, "Whisper", nil, nil)
    elseif event == "CHAT_MSG_BN_WHISPER" then
        local _, fullName, gameAccountID = NS.ResolveBNetSender(bnSenderID, sender)
        ProcessIncomingWhisper(msg, fullName, "BNet Friend", bnSenderID, gameAccountID)
    else
        ProcessPublicChatMessage(event, msg, sender, channelString)
    end
end)

-- Multi-channel advertisement broadcaster using customizable adTemplate
function NS.PostSummonAd()
    local ad = NS.BuildCustomAdMessage()
    if ad == "" then
        NS.Print("|cffff4444Ad message is empty.|r Configure it in Settings -> Custom Ad Message.")
        return
    end

    local rawChannels = tostring(SummonAssistantDB.adChannels or "2")
    local sentTargets = {}
    local skippedTargets = {}
    local seen = {}

    for token in rawChannels:gmatch("[^,%s;]+") do
        local clean = strtrim(token)
        if clean ~= "" then
            local upper = clean:upper()
            local chNum = tonumber(clean)
            if chNum then
                if not seen["CH:" .. chNum] then
                    seen["CH:" .. chNum] = true
                    local id = GetChannelName(chNum)
                    if id and id > 0 then
                        NS.SendChatSafe(ad, "CHANNEL", nil, chNum)
                        table.insert(sentTargets, tostring(chNum))
                    else
                        table.insert(skippedTargets, tostring(chNum))
                    end
                end
            elseif upper == "YELL" then
                if not seen["YELL"] then
                    seen["YELL"] = true
                    NS.SendChatSafe(ad, "YELL")
                    table.insert(sentTargets, "Yell")
                end
            elseif upper == "SAY" then
                if not seen["SAY"] then
                    seen["SAY"] = true
                    NS.SendChatSafe(ad, "SAY")
                    table.insert(sentTargets, "Say")
                end
            else
                local id = GetChannelName(clean)
                if id and id > 0 then
                    if not seen["CH:" .. id] then
                        seen["CH:" .. id] = true
                        NS.SendChatSafe(ad, "CHANNEL", nil, id)
                        table.insert(sentTargets, clean .. " (#" .. id .. ")")
                    end
                else
                    table.insert(skippedTargets, clean)
                end
            end
        end
    end

    if #sentTargets > 0 then
        NS.Print("Posted summon ad to: |cff00ff00" .. table.concat(sentTargets, ", ") .. "|r")
    else
        NS.Print("|cffff4444No active channels matched|r (" .. rawChannels .. "). Check Settings -> Ad Channels.")
    end

    if #skippedTargets > 0 then
        NS.Print("|cffffaa00Skipped unjoined channels:|r " .. table.concat(skippedTargets, ", "))
    end
end
