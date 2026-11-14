local addonName, NS = ...

local mainFrame
local minimapBtn
local areaMenuFrame
local activeTab = 1
local tabPanels = {}
local tabButtons = {}
local warlockRows = {}
local queueRows = {}
local blRows = {}
local blSearchQuery = ""

-- Solid opaque card helper using an explicit BACKGROUND ColorTexture so backgrounds are 100% solid
local function CreateSolidPanel(parent, r, g, b, borderR, borderG, borderB)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropBorderColor(borderR or 0.36, borderG or 0.30, borderB or 0.52, 1.0)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(r or 0.07, g or 0.07, b or 0.10, 1.0)
    f.solidBg = bg
    return f
end

local function CreateActionButton(parent, width, height, text)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, height)
    btn:SetText(text)
    return btn
end

local function SetInputPlaceholder(editBox, placeholderText)
    editBox.placeholder = placeholderText
    editBox.isPlaceholder = true
    editBox:SetText(placeholderText)
    editBox:SetTextColor(0.55, 0.55, 0.62, 1.0)

    editBox:SetScript("OnEditFocusGained", function(self)
        if self.isPlaceholder then
            self.isPlaceholder = false
            self:SetText("")
            self:SetTextColor(1.0, 1.0, 1.0, 1.0)
        end
    end)

    editBox:SetScript("OnEditFocusLost", function(self)
        if strtrim(self:GetText() or "") == "" then
            self.isPlaceholder = true
            self:SetText(self.placeholder)
            self:SetTextColor(0.55, 0.55, 0.62, 1.0)
        end
    end)
end

local function GetRealInputText(editBox)
    if editBox.isPlaceholder then return "" end
    return strtrim(editBox:GetText() or "")
end

local function SelectTab(idx)
    activeTab = idx
    if areaMenuFrame then areaMenuFrame:Hide() end
    for i, panel in ipairs(tabPanels) do
        local tb = tabButtons[i]
        if i == idx then
            panel:Show()
            tb.solidBg:SetColorTexture(0.24, 0.18, 0.38, 1.0)
            tb:SetBackdropBorderColor(0.68, 0.56, 0.94, 1.0)
            tb.label:SetTextColor(1.0, 0.92, 0.60, 1.0)
        else
            panel:Hide()
            tb.solidBg:SetColorTexture(0.11, 0.11, 0.16, 1.0)
            tb:SetBackdropBorderColor(0.28, 0.25, 0.38, 1.0)
            tb.label:SetTextColor(0.75, 0.75, 0.82, 1.0)
        end
    end
    if NS.RefreshUI then NS.RefreshUI() end
end

-- Servicing Area quick-selector popup menu
local function ToggleServiceAreaMenu(anchorBtn)
    if not areaMenuFrame then
        local m = CreateSolidPanel(mainFrame, 0.07, 0.07, 0.11, 0.58, 0.50, 0.82)
        m:SetWidth(195)
        m:SetFrameStrata("DIALOG")
        m:EnableMouse(true)
        m:Hide()

        local y = -6
        local function AddMenuChoice(labelText, onPick)
            local itemBtn = CreateFrame("Button", nil, m, "BackdropTemplate")
            itemBtn:SetSize(183, 20)
            itemBtn:SetPoint("TOPLEFT", 6, y)
            itemBtn:SetBackdrop({ edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
            itemBtn:SetBackdropBorderColor(0.22, 0.20, 0.32, 1.0)
            local bg = itemBtn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(itemBtn)
            bg:SetColorTexture(0.12, 0.11, 0.18, 1.0)

            local txt = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            txt:SetPoint("LEFT", 8, 0)
            txt:SetText(labelText)

            itemBtn:SetScript("OnEnter", function()
                bg:SetColorTexture(0.24, 0.19, 0.38, 1.0)
            end)
            itemBtn:SetScript("OnLeave", function()
                bg:SetColorTexture(0.12, 0.11, 0.18, 1.0)
            end)
            itemBtn:SetScript("OnClick", function()
                onPick()
                m:Hide()
            end)
            y = y - 22
        end

        AddMenuChoice("|cff4ce87aUse My Current Zone|r", function()
            local z = GetRealZoneText and GetRealZoneText()
            if NS.IsSafeString(z) and z ~= "" then
                NS.SetMyServiceArea(z, true)
                NS.Print("Servicing Area set to current zone: |cff66d9ff" .. z .. "|r")
            end
        end)

        for _, preset in ipairs(NS.SERVICE_AREA_PRESETS) do
            AddMenuChoice(preset, function()
                NS.SetMyServiceArea(preset, true)
                NS.Print("Servicing Area set to: |cff66d9ff" .. preset .. "|r")
            end)
        end

        m:SetHeight(math.abs(y) + 6)
        areaMenuFrame = m
    end

    if areaMenuFrame:IsShown() then
        areaMenuFrame:Hide()
    else
        areaMenuFrame:ClearAllPoints()
        areaMenuFrame:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 0, -2)
        areaMenuFrame:Show()
    end
end

local function ShowExportImportModal(mode)
    if not NS.ioModal then
        local m = CreateSolidPanel(UIParent, 0.06, 0.06, 0.09, 0.58, 0.51, 0.79)
        m:SetSize(440, 270)
        m:SetPoint("CENTER")
        m:SetFrameStrata("DIALOG")
        m:EnableMouse(true)

        local title = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        m.title = title

        local close = CreateActionButton(m, 24, 22, "X")
        close:SetPoint("TOPRIGHT", -10, -10)
        close:SetScript("OnClick", function() m:Hide() end)

        local boxFrame = CreateSolidPanel(m, 0.03, 0.03, 0.05, 0.30, 0.26, 0.42)
        boxFrame:SetPoint("TOPLEFT", 12, -40)
        boxFrame:SetPoint("BOTTOMRIGHT", -12, 44)

        local sf = CreateFrame("ScrollFrame", nil, boxFrame, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 8, -8)
        sf:SetPoint("BOTTOMRIGHT", -28, 8)

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(375)
        eb:SetAutoFocus(true)
        sf:SetScrollChild(eb)
        m.editBox = eb

        local actionBtn = CreateActionButton(m, 120, 26, "Import")
        actionBtn:SetPoint("BOTTOMRIGHT", -12, 10)
        m.actionBtn = actionBtn

        NS.ioModal = m
    end

    local m = NS.ioModal
    if mode == "EXPORT" then
        m.title:SetText("Export Community Blacklist (Ctrl+C)")
        m.editBox:SetText(NS.ExportBlacklistString())
        m.editBox:HighlightText()
        m.actionBtn:SetText("Select All")
        m.actionBtn:SetScript("OnClick", function()
            m.editBox:SetFocus()
            m.editBox:HighlightText()
        end)
    else
        m.title:SetText("Paste Community Blacklist String")
        m.editBox:SetText("")
        m.actionBtn:SetText("Import Now")
        m.actionBtn:SetScript("OnClick", function()
            NS.ImportBlacklistString(m.editBox:GetText())
            m:Hide()
        end)
    end
    m:Show()
end

-- Minimap toggle button
local function CreateMinimapButton()
    if minimapBtn then return end
    local btn = CreateFrame("Button", "SummonAssistantMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface/Icons/Spell_Shadow_Twilight")
    icon:SetPoint("CENTER", 0, 1)

    local function UpdatePosition()
        local angle = math.rad(SummonAssistantDB.minimapAngle or 220)
        local x = math.cos(angle) * 80
        local y = math.sin(angle) * 80
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            SummonAssistantDB.minimapAngle = angle
            UpdatePosition()
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            SummonAssistantDB.autoInvite = not SummonAssistantDB.autoInvite
            NS.Print("Auto-Invite is now " .. (SummonAssistantDB.autoInvite and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
            NS.RefreshUI()
        else
            if mainFrame:IsShown() then
                mainFrame:Hide()
            else
                NS.ScanGroup()
                if NS.BroadcastHello then NS.BroadcastHello() end
                mainFrame:Show()
                NS.RefreshUI()
            end
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff9482c9Summon Assistant|r")
        GameTooltip:AddLine("Left-Click: Open / Close Window", 1, 1, 1)
        GameTooltip:AddLine("Right-Click: Toggle Auto-Invite (" .. (SummonAssistantDB.autoInvite and "|cff00ff00ON|r" or "|cffff4444OFF|r") .. ")", 1, 1, 1)
        GameTooltip:AddLine("Area: |cff66d9ff" .. NS.GetMyServiceArea() .. "|r", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Soul Shards: |cff00ff00" .. NS.GetMyShards() .. "|r | Queue: |cffffff00" .. #NS.queue .. "|r", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdatePosition()
    minimapBtn = btn
end

function NS.InitUI()
    if mainFrame then return end

    mainFrame = CreateSolidPanel(UIParent, 0.055, 0.055, 0.085, 0.50, 0.40, 0.72)
    mainFrame:SetSize(610, 585)
    mainFrame:SetFrameStrata("HIGH")
    if SummonAssistantDB.windowPos then
        local p = SummonAssistantDB.windowPos
        mainFrame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else
        mainFrame:SetPoint("CENTER")
    end
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        SummonAssistantDB.windowPos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    mainFrame:Hide()

    tinsert(UISpecialFrames, "SummonAssistantMainFrame")
    _G["SummonAssistantMainFrame"] = mainFrame

    -- Solid Header Bar
    local header = CreateSolidPanel(mainFrame, 0.13, 0.10, 0.21, 0.50, 0.40, 0.72)
    header:SetHeight(36)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)

    local headerIcon = header:CreateTexture(nil, "ARTWORK")
    headerIcon:SetSize(22, 22)
    headerIcon:SetTexture("Interface/Icons/Spell_Shadow_Twilight")
    headerIcon:SetPoint("LEFT", 10, 0)

    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", headerIcon, "RIGHT", 8, 0)
    titleText:SetText("|cffa68ef2Summon Assistant|r |cff8a869e(v" .. NS.VERSION .. ")|r")

    local shardPill = CreateSolidPanel(header, 0.08, 0.07, 0.13, 0.38, 0.31, 0.55)
    shardPill:SetSize(110, 22)
    shardPill:SetPoint("RIGHT", -40, 0)

    local shardBadge = shardPill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    shardBadge:SetPoint("CENTER", 0, 0)
    mainFrame.shardBadge = shardBadge

    local closeBtn = CreateActionButton(header, 24, 22, "X")
    closeBtn:SetPoint("RIGHT", -8, 0)
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

    -- Quick Control Bar (Solid Strip)
    local ctrlBar = CreateSolidPanel(mainFrame, 0.09, 0.08, 0.14, 0.28, 0.24, 0.40)
    ctrlBar:SetHeight(36)
    ctrlBar:SetPoint("TOPLEFT", 10, -44)
    ctrlBar:SetPoint("TOPRIGHT", -10, -44)

    local autoInvBtn = CreateActionButton(ctrlBar, 155, 24, "Auto-Invite: ON")
    autoInvBtn:SetPoint("LEFT", 8, 0)
    autoInvBtn:SetScript("OnClick", function()
        SummonAssistantDB.autoInvite = not SummonAssistantDB.autoInvite
        NS.RefreshUI()
    end)
    mainFrame.autoInvBtn = autoInvBtn

    local nextBtn = CreateActionButton(ctrlBar, 175, 24, "Announce Next Summon")
    nextBtn:SetPoint("LEFT", autoInvBtn, "RIGHT", 8, 0)
    nextBtn:SetScript("OnClick", function()
        local firstCustomer = NS.queue[1] and NS.queue[1].shortName or ""
        NS.AnnounceAndAdvanceRotation(firstCustomer, false)
    end)

    local adBtn = CreateActionButton(ctrlBar, 225, 24, "Post Ad")
    adBtn:SetPoint("RIGHT", -8, 0)
    adBtn:SetScript("OnClick", function()
        NS.PostSummonAd()
    end)
    mainFrame.adBtn = adBtn

    -- Custom Styled Solid Tabs (3 tabs across 590px inner width -> 192px each)
    local tabNames = { "Queue & Rotation", "Community Blacklist", "Settings" }
    local tabWidth = 192
    for i, name in ipairs(tabNames) do
        local tb = CreateFrame("Button", nil, mainFrame, "BackdropTemplate")
        tb:SetSize(tabWidth, 26)
        tb:SetPoint("TOPLEFT", 10 + (i - 1) * (tabWidth + 7), -88)
        tb:SetBackdrop({
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        local bg = tb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(tb)
        tb.solidBg = bg

        local lbl = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("CENTER")
        lbl:SetText(name)
        tb.label = lbl

        tb:SetScript("OnClick", function() SelectTab(i) end)
        tabButtons[i] = tb

        local panel = CreateSolidPanel(mainFrame, 0.08, 0.08, 0.12, 0.34, 0.28, 0.48)
        panel:SetPoint("TOPLEFT", 10, -116)
        panel:SetPoint("BOTTOMRIGHT", -10, 10)
        tabPanels[i] = panel
    end

    -- =========================================================================
    -- TAB 1: Queue & Rotation
    -- =========================================================================
    local p1 = tabPanels[1]

    local rotSection = CreateSolidPanel(p1, 0.10, 0.09, 0.15, 0.30, 0.25, 0.44)
    rotSection:SetPoint("TOPLEFT", 8, -8)
    rotSection:SetPoint("TOPRIGHT", -8, -8)
    rotSection:SetHeight(192)

    local rotHeader = rotSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rotHeader:SetPoint("TOPLEFT", 10, -8)
    rotHeader:SetText("|cffa68ef2Warlock Rotation & Servicing Areas|r")

    local skipTurnBtn = CreateActionButton(rotSection, 82, 20, "Skip Turn")
    skipTurnBtn:SetPoint("TOPRIGHT", -8, -6)
    skipTurnBtn:SetScript("OnClick", function()
        NS.AnnounceAndAdvanceRotation("", true)
    end)

    local syncGroupBtn = CreateActionButton(rotSection, 58, 20, "Sync")
    syncGroupBtn:SetPoint("RIGHT", skipTurnBtn, "LEFT", -4, 0)
    syncGroupBtn:SetScript("OnClick", function()
        NS.ScanGroup()
        if NS.BroadcastHello then NS.BroadcastHello() end
        NS.Print("Synced Warlock shard counts and servicing areas with group.")
    end)

    local myAreaBtn = CreateActionButton(rotSection, 155, 20, "Area: Felwood")
    myAreaBtn:SetPoint("RIGHT", syncGroupBtn, "LEFT", -4, 0)
    myAreaBtn:SetScript("OnClick", function(self)
        ToggleServiceAreaMenu(self)
    end)
    mainFrame.myAreaBtn = myAreaBtn

    for i = 1, 6 do
        local row = CreateSolidPanel(rotSection, 0.13, 0.12, 0.19, 0.25, 0.22, 0.36)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", 8, -32 - (i - 1) * 25)
        row:SetPoint("TOPRIGHT", -8, -32 - (i - 1) * 25)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetWidth(385)
        row.label:SetJustifyH("LEFT")

        row.setBtn = CreateActionButton(row, 74, 18, "Set Turn")
        row.setBtn:SetPoint("RIGHT", -6, 0)

        row.shards = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.shards:SetPoint("RIGHT", row.setBtn, "LEFT", -10, 0)

        warlockRows[i] = row
    end

    local qSection = CreateSolidPanel(p1, 0.10, 0.09, 0.15, 0.24, 0.36, 0.28)
    qSection:SetPoint("TOPLEFT", rotSection, "BOTTOMLEFT", 0, -8)
    qSection:SetPoint("BOTTOMRIGHT", -8, 8)

    local qHeader = qSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qHeader:SetPoint("TOPLEFT", 10, -8)
    qHeader:SetText("|cff4ce87aCustomer Summon Queue|r")

    local clearQBtn = CreateActionButton(qSection, 78, 20, "Clear All")
    clearQBtn:SetPoint("TOPRIGHT", -8, -6)
    clearQBtn:SetScript("OnClick", function()
        wipe(NS.queue)
        NS.RefreshUI()
    end)

    local areaFilterBtn = CreateActionButton(qSection, 155, 20, "Queue Filter: All")
    areaFilterBtn:SetPoint("RIGHT", clearQBtn, "LEFT", -6, 0)
    areaFilterBtn:SetScript("OnClick", function()
        SummonAssistantDB.filterQueueByMyArea = not SummonAssistantDB.filterQueueByMyArea
        NS.RefreshUI()
    end)
    mainFrame.areaFilterBtn = areaFilterBtn

    for i = 1, 7 do
        local row = CreateSolidPanel(qSection, 0.12, 0.14, 0.17, 0.22, 0.30, 0.28)
        row:SetHeight(25)
        row:SetPoint("TOPLEFT", 8, -32 - (i - 1) * 26)
        row:SetPoint("TOPRIGHT", -8, -32 - (i - 1) * 26)
        row:EnableMouse(true)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 8, 0)
        row.label:SetWidth(330)
        row.label:SetJustifyH("LEFT")

        row.removeBtn = CreateActionButton(row, 58, 19, "Remove")
        row.removeBtn:SetPoint("RIGHT", -6, 0)

        row.kickBtn = CreateActionButton(row, 44, 19, "Kick")
        row.kickBtn:SetPoint("RIGHT", row.removeBtn, "LEFT", -4, 0)

        row.invBtn = CreateActionButton(row, 50, 19, "Invite")
        row.invBtn:SetPoint("RIGHT", row.kickBtn, "LEFT", -4, 0)

        row.blBtn = CreateActionButton(row, 40, 19, "Ban")
        row.blBtn:SetPoint("RIGHT", row.invBtn, "LEFT", -4, 0)

        queueRows[i] = row
    end

    -- =========================================================================
    -- TAB 2: Community Blacklist
    -- =========================================================================
    local p2 = tabPanels[2]

    local addBoxPanel = CreateSolidPanel(p2, 0.11, 0.10, 0.16, 0.36, 0.24, 0.28)
    addBoxPanel:SetPoint("TOPLEFT", 8, -8)
    addBoxPanel:SetPoint("TOPRIGHT", -8, -8)
    addBoxPanel:SetHeight(68)

    local addNameBox = CreateFrame("EditBox", nil, addBoxPanel, "InputBoxTemplate")
    addNameBox:SetSize(135, 22)
    addNameBox:SetPoint("TOPLEFT", 12, -10)
    addNameBox:SetAutoFocus(false)
    SetInputPlaceholder(addNameBox, "PlayerName")

    local addReasonBox = CreateFrame("EditBox", nil, addBoxPanel, "InputBoxTemplate")
    addReasonBox:SetSize(295, 22)
    addReasonBox:SetPoint("LEFT", addNameBox, "RIGHT", 8, 0)
    addReasonBox:SetAutoFocus(false)
    SetInputPlaceholder(addReasonBox, "Reason (e.g. Did not pay gold)")

    local function SubmitBlacklistInput()
        local n = GetRealInputText(addNameBox)
        local r = GetRealInputText(addReasonBox)
        if n ~= "" then
            NS.AddBlacklistEntry(n, r ~= "" and r or "Did not pay gold", NS.GetMyShortName(), time(), false)
            addNameBox:SetText("")
            addNameBox:ClearFocus()
            addReasonBox:SetText("")
            addReasonBox:ClearFocus()
        end
    end

    addNameBox:SetScript("OnEnterPressed", SubmitBlacklistInput)
    addReasonBox:SetScript("OnEnterPressed", SubmitBlacklistInput)

    local addBlBtn = CreateActionButton(addBoxPanel, 102, 22, "+ Blacklist")
    addBlBtn:SetPoint("LEFT", addReasonBox, "RIGHT", 8, 0)
    addBlBtn:SetScript("OnClick", SubmitBlacklistInput)

    local searchBox = CreateFrame("EditBox", nil, addBoxPanel, "InputBoxTemplate")
    searchBox:SetSize(230, 20)
    searchBox:SetPoint("TOPLEFT", 12, -38)
    searchBox:SetAutoFocus(false)
    SetInputPlaceholder(searchBox, "Filter blacklist...")
    searchBox:SetScript("OnTextChanged", function(self)
        if self.isPlaceholder then
            blSearchQuery = ""
        else
            blSearchQuery = (self:GetText() or ""):lower()
        end
        NS.RefreshUI()
    end)

    local syncBtn = CreateActionButton(addBoxPanel, 86, 22, "Sync Now")
    syncBtn:SetPoint("TOPRIGHT", -176, -37)
    syncBtn:SetScript("OnClick", function() NS.RequestCommunityBlacklistSync() end)

    local exportBtn = CreateActionButton(addBoxPanel, 78, 22, "Export")
    exportBtn:SetPoint("TOPRIGHT", -92, -37)
    exportBtn:SetScript("OnClick", function() ShowExportImportModal("EXPORT") end)

    local importBtn = CreateActionButton(addBoxPanel, 78, 22, "Import")
    importBtn:SetPoint("TOPRIGHT", -8, -37)
    importBtn:SetScript("OnClick", function() ShowExportImportModal("IMPORT") end)

    for i = 1, 12 do
        local row = CreateSolidPanel(p2, 0.14, 0.09, 0.11, 0.42, 0.18, 0.20)
        row:SetHeight(25)
        row:SetPoint("TOPLEFT", 8, -84 - (i - 1) * 26)
        row:SetPoint("TOPRIGHT", -8, -84 - (i - 1) * 26)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 8, 0)

        row.delBtn = CreateActionButton(row, 64, 19, "Remove")
        row.delBtn:SetPoint("RIGHT", -6, 0)
        blRows[i] = row
    end

    -- =========================================================================
    -- TAB 3: Settings
    -- =========================================================================
    local p3 = tabPanels[3]

    local settingsCard = CreateSolidPanel(p3, 0.10, 0.09, 0.15, 0.30, 0.25, 0.44)
    settingsCard:SetPoint("TOPLEFT", 8, -8)
    settingsCard:SetPoint("BOTTOMRIGHT", -8, 8)

    local function CreateLabeledInput(yOffset, labelStr, hintStr, initialVal, boxWidth, onSave, onReset)
        local lbl = settingsCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", 12, yOffset)
        lbl:SetText(labelStr)

        local eb = CreateFrame("EditBox", nil, settingsCard, "InputBoxTemplate")
        eb:SetSize(boxWidth or 340, 20)
        eb:SetPoint("TOPLEFT", 175, yOffset + 4)
        eb:SetAutoFocus(false)
        eb:SetText(initialVal or "")
        eb:SetScript("OnEnterPressed", function(self)
            onSave(self:GetText())
            self:ClearFocus()
            NS.Print("Saved: " .. labelStr)
            NS.RefreshUI()
        end)
        eb:SetScript("OnEditFocusLost", function(self)
            onSave(self:GetText())
            NS.RefreshUI()
        end)

        if onReset then
            local rst = CreateActionButton(settingsCard, 46, 20, "Reset")
            rst:SetPoint("LEFT", eb, "RIGHT", 4, 0)
            rst:SetScript("OnClick", function()
                local def = onReset()
                eb:SetText(def)
                NS.Print("Reset " .. labelStr .. " to default.")
                NS.RefreshUI()
            end)
        end

        if hintStr then
            local hint = settingsCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            hint:SetPoint("TOPLEFT", 175, yOffset - 15)
            hint:SetText(hintStr)
        end
        return eb
    end

    CreateLabeledInput(-12, "Auto-Invite Keywords:", "Standalone whisper match only (e.g. 123, sum, inv)", table.concat(SummonAssistantDB.keywords, ", "), 380, function(val)
        local list = {}
        for word in val:gmatch("[^,]+") do
            local clean = strtrim(word)
            if clean ~= "" then table.insert(list, clean) end
        end
        SummonAssistantDB.keywords = list
    end)

    mainFrame.locInput = CreateLabeledInput(-48, "My Servicing Area:", "Shown to group Warlocks & used by {loc} token", SummonAssistantDB.locationText, 380, function(val)
        NS.SetMyServiceArea(val, true)
    end)

    CreateLabeledInput(-84, "Price (Gold/Silver):", "Used by {price} token (e.g. 2g or 50s)", SummonAssistantDB.priceText, 380, function(val)
        SummonAssistantDB.priceText = strtrim(val)
    end)

    CreateLabeledInput(-120, "Ad Channels (Multi):", "Comma-separated: e.g. 2, 8, 10 or 2, 8, YELL", SummonAssistantDB.adChannels, 380, function(val)
        SummonAssistantDB.adChannels = strtrim(val)
    end)

    CreateLabeledInput(-156, "Chat Watch Filter:", "Optional public queue filter (e.g. uc, undercity) or blank for all", SummonAssistantDB.chatWatchFilter, 380, function(val)
        SummonAssistantDB.chatWatchFilter = strtrim(val)
    end)

    CreateLabeledInput(-192, "Custom Ad Message:", "Tokens: {loc}, {price}, {kw}, {shards}, {summoner}", SummonAssistantDB.adTemplate, 330, function(val)
        SummonAssistantDB.adTemplate = strtrim(val)
    end, function()
        SummonAssistantDB.adTemplate = NS.DEFAULT_AD_TEMPLATE
        return NS.DEFAULT_AD_TEMPLATE
    end)

    CreateLabeledInput(-228, "Auto-Invite Whisper:", "Tokens: {player}, {loc}, {price}, {summoner}, {shards}", SummonAssistantDB.whisperTemplate, 330, function(val)
        SummonAssistantDB.whisperTemplate = strtrim(val)
    end, function()
        SummonAssistantDB.whisperTemplate = NS.DEFAULT_WHISPER_TEMPLATE
        return NS.DEFAULT_WHISPER_TEMPLATE
    end)

    local divider = settingsCard:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 12, -264)
    divider:SetPoint("TOPRIGHT", -12, -264)
    divider:SetColorTexture(0.32, 0.27, 0.46, 1.0)

    local function CreateCheckOption(yOffset, text, dbKey)
        local cb = CreateFrame("CheckButton", nil, settingsCard, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 10, yOffset)
        cb:SetChecked(SummonAssistantDB[dbKey])
        cb.text:SetText(" " .. text)
        cb:SetScript("OnClick", function(self)
            SummonAssistantDB[dbKey] = self:GetChecked() and true or false
            NS.RefreshUI()
        end)
        return cb
    end

    CreateCheckOption(-270, "Auto-Convert Party to Raid at 5 Players", "autoConvertRaid")
    CreateCheckOption(-294, "Announce Next Summoner in Party/Raid Chat", "announceRotation")
    CreateCheckOption(-318, "Whisper Customer on Auto-Invite (incl. BNet)", "whisperCustomer")
    CreateCheckOption(-342, "Watch Public Chat & Grab Summon Requests into Queue", "scanPublicChat")
    CreateCheckOption(-366, "Only Queue Public Requests Matching My Servicing Area", "filterQueueByMyArea")
    CreateCheckOption(-390, "Auto-Sync Community Blacklist Over Network", "autoSyncBlacklist")

    CreateMinimapButton()
    SelectTab(1)
end

function NS.RefreshUI()
    if not mainFrame or not mainFrame:IsShown() then return end

    local shards = NS.GetMyShards()
    local shardColor = shards > 10 and "|cff00ff00" or (shards > 3 and "|cffffff00" or "|cffff3333")
    mainFrame.shardBadge:SetText("Shards: " .. shardColor .. shards .. "|r")

    if SummonAssistantDB.autoInvite then
        mainFrame.autoInvBtn:SetText("|cff00ff00Auto-Invite: ON|r")
    else
        mainFrame.autoInvBtn:SetText("|cffff4444Auto-Invite: OFF|r")
    end

    local chLabel = strtrim(SummonAssistantDB.adChannels or "2")
    if #chLabel > 14 then chLabel = chLabel:sub(1, 12) .. ".." end
    mainFrame.adBtn:SetText("Post Ad (Ch: " .. chLabel .. ")")

    local myArea = NS.GetMyServiceArea()
    if mainFrame.myAreaBtn then
        local shortArea = #myArea > 18 and (myArea:sub(1, 16) .. "..") or myArea
        mainFrame.myAreaBtn:SetText("Area: " .. shortArea)
    end
    if mainFrame.locInput and not mainFrame.locInput:HasFocus() then
        mainFrame.locInput:SetText(myArea)
    end

    if mainFrame.areaFilterBtn then
        if SummonAssistantDB.filterQueueByMyArea then
            mainFrame.areaFilterBtn:SetText("|cff66d9ffFilter: My Area|r")
        elseif NS.IsSafeString(SummonAssistantDB.chatWatchFilter) and strtrim(SummonAssistantDB.chatWatchFilter) ~= "" then
            mainFrame.areaFilterBtn:SetText("|cff66d9ffFilter: Custom|r")
        else
            mainFrame.areaFilterBtn:SetText("Queue Filter: All")
        end
    end

    if activeTab == 1 then
        local nextLock = NS.GetNextWarlock()
        local me = NS.GetMyShortName()
        for i = 1, 6 do
            local row = warlockRows[i]
            local wName = NS.rotationOrder[i]
            local info = wName and NS.warlocks[wName]
            if info then
                local isNext = (nextLock and nextLock.name == info.name)
                if isNext then
                    row.solidBg:SetColorTexture(0.08, 0.21, 0.13, 1.0)
                    row:SetBackdropBorderColor(0.25, 0.72, 0.42, 1.0)
                else
                    row.solidBg:SetColorTexture(0.13, 0.12, 0.19, 1.0)
                    row:SetBackdropBorderColor(0.25, 0.22, 0.36, 1.0)
                end

                local prefix = isNext and "|cff00ff00>> NEXT << |r" or ("#" .. i .. " ")
                local addonTag = ""
                if info.name == me then
                    addonTag = " |cff66ccff(You)|r"
                elseif info.hasAddon then
                    local vStr = info.version and (" v" .. info.version) or ""
                    addonTag = " |cff4ce87a(Synced" .. vStr .. ")|r"
                else
                    addonTag = " |cff888888(No Addon)|r"
                end

                local areaBadge = ""
                if info.serviceArea and info.serviceArea ~= "" then
                    areaBadge = " |cff66d9ff[" .. info.serviceArea .. "]|r"
                end

                row.label:SetText(prefix .. "|cffa68ef2" .. info.name .. "|r" .. addonTag .. areaBadge .. " |cffb0b0c0(" .. (info.summonsDone or 0) .. ")|r")

                if info.shards >= 0 then
                    local c = info.shards > 10 and "|cff00ff00" or (info.shards > 3 and "|cffffff00" or "|cffff3333")
                    row.shards:SetText(c .. info.shards .. " Shards|r")
                else
                    row.shards:SetText("|cff888888? Shards|r")
                end

                row.setBtn:SetScript("OnClick", function()
                    NS.SetCurrentTurn(info.name, true)
                end)
                row:Show()
            else
                row:Hide()
            end
        end

        for i = 1, 7 do
            local row = queueRows[i]
            local item = NS.queue[i]
            if item then
                local statusColor = item.status == "In Group" and "|cff00ff00" or (item.status == "Invited" and "|cffffff00" or "|cffcccccc")
                local destPart = item.destTag and (" |cff66d9ff[" .. item.destTag .. "]|r") or ""
                local excerptPart = ""
                if item.excerpt and item.excerpt ~= "" then
                    local maxLen = item.destTag and 22 or 34
                    local shortSnippet = #item.excerpt > maxLen and (item.excerpt:sub(1, maxLen - 3) .. "...") or item.excerpt
                    excerptPart = " |cffb8b8c8\"" .. shortSnippet .. "\"|r"
                end

                row.label:SetText(string.format("%s |cff8f8fa3[%s]|r%s%s - %s%s|r",
                    item.shortName, item.source, destPart, excerptPart, statusColor, item.status))

                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                    GameTooltip:AddLine("|cff9482c9" .. item.shortName .. "|r (" .. (item.channelName or item.source) .. ")")
                    if item.destTag then
                        GameTooltip:AddLine("Detected Destination: |cff66d9ff" .. item.destTag .. "|r", 1, 1, 1)
                    end
                    if item.msg and item.msg ~= "" then
                        GameTooltip:AddLine("Message: \"" .. item.msg .. "\"", 0.9, 0.9, 0.7, true)
                    end
                    GameTooltip:AddLine("Status: " .. item.status, 0.7, 0.7, 0.7)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)

                row.invBtn:SetScript("OnClick", function()
                    if NS.InvitePlayer(item.name, item.bnetGameAccountID) then
                        item.status = "Invited"
                        NS.RefreshUI()
                    end
                end)

                row.kickBtn:SetScript("OnClick", function()
                    NS.KickPlayer(item.name)
                    NS.RemoveQueueIndex(i)
                end)

                row.removeBtn:SetScript("OnClick", function()
                    NS.RemoveQueueIndex(i)
                end)

                row.blBtn:SetScript("OnClick", function()
                    NS.AddBlacklistEntry(item.shortName, "Summon scam / no pay", NS.GetMyShortName(), time(), false)
                    NS.KickPlayer(item.name)
                    NS.RemoveQueueIndex(i)
                end)
                row:Show()
            else
                row:Hide()
            end
        end

    elseif activeTab == 2 then
        local list = {}
        for _, entry in pairs(SummonAssistantDB.blacklist) do
            if blSearchQuery == ""
                or entry.name:lower():find(blSearchQuery, 1, true)
                or (entry.reason and entry.reason:lower():find(blSearchQuery, 1, true)) then
                table.insert(list, entry)
            end
        end
        table.sort(list, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)

        for i = 1, 12 do
            local row = blRows[i]
            local entry = list[i]
            if entry then
                local repCount = 0
                if entry.reporters then
                    for _ in pairs(entry.reporters) do repCount = repCount + 1 end
                end
                row.label:SetText(string.format("|cffff4444%s|r - %s |cff888888(by %s, %d reports)|r",
                    entry.name, entry.reason or "Blacklisted", entry.addedBy or "?", math.max(1, repCount)))
                row.delBtn:SetScript("OnClick", function()
                    NS.RemoveBlacklistEntry(entry.name, false)
                end)
                row:Show()
            else
                row:Hide()
            end
        end
    end
end

-- Slash commands (/sa primary, /summonassistant full, /ss legacy alias)
SLASH_SUMMONASSISTANT1 = "/sa"
SLASH_SUMMONASSISTANT2 = "/summonassistant"
SLASH_SUMMONASSISTANT3 = "/ss"
SlashCmdList["SUMMONASSISTANT"] = function(msg)
    local raw = strtrim(msg or "")
    local cmd, rest = raw:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "" then
        if mainFrame:IsShown() then
            mainFrame:Hide()
        else
            NS.ScanGroup()
            if NS.BroadcastHello then NS.BroadcastHello() end
            mainFrame:Show()
            NS.RefreshUI()
        end
    elseif cmd == "inv" or cmd == "autoinv" then
        SummonAssistantDB.autoInvite = not SummonAssistantDB.autoInvite
        NS.Print("Auto-Invite is now " .. (SummonAssistantDB.autoInvite and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
        NS.RefreshUI()
    elseif cmd == "area" then
        if rest ~= "" then
            NS.SetMyServiceArea(rest, true)
            NS.Print("Servicing Area set to: |cff66d9ff" .. rest .. "|r")
        else
            NS.Print("Current Servicing Area: |cff66d9ff" .. NS.GetMyServiceArea() .. "|r (Usage: /sa area <Location>)")
        end
    elseif cmd == "next" then
        NS.AnnounceAndAdvanceRotation(rest, false)
    elseif cmd == "sync" then
        NS.ScanGroup()
        if NS.BroadcastHello then NS.BroadcastHello() end
        NS.RequestCommunityBlacklistSync()
    elseif cmd == "debug" then
        NS.debugComms = not NS.debugComms
        NS.Print("Comms debug logging is now " .. (NS.debugComms and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
    elseif cmd == "bl" or cmd == "blacklist" then
        local target, reason = rest:match("^(%S+)%s*(.*)$")
        if target then
            NS.AddBlacklistEntry(target, reason, NS.GetMyShortName(), time(), false)
        else
            NS.Print("Usage: /sa bl <PlayerName> [Reason]")
        end
    elseif cmd == "unbl" then
        if rest ~= "" then
            NS.RemoveBlacklistEntry(rest, false)
        else
            NS.Print("Usage: /sa unbl <PlayerName>")
        end
    elseif cmd == "ad" then
        NS.PostSummonAd()
    elseif cmd == "testad" then
        NS.Print("Ad Preview: " .. NS.BuildCustomAdMessage())
    elseif cmd == "testwhisper" then
        NS.Print("Whisper Preview: " .. NS.BuildCustomerWhisperMessage(rest ~= "" and rest or "Customer"))
    else
        NS.Print("Commands: |cff00ff00/sa|r (UI), |cff00ff00/sa area <loc>|r, |cff00ff00/sa sync|r, |cff00ff00/sa inv|r, |cff00ff00/sa next|r, |cff00ff00/sa bl <name> [reason]|r, |cff00ff00/sa ad|r")
    end
end
