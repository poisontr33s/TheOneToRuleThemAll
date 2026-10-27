-- Optional setup window. It is created only when /tor or /tor ui is used.
-- Preview and events inspect state; only explicit Apply/Undo clicks write it.
local A = TheOneToRuleThemAll
local EVENTS = {
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE", "ACTIONBAR_PAGE_CHANGED", "UPDATE_STEALTH", "UPDATE_MACROS",
    "UPDATE_BINDINGS", "CURSOR_CHANGED", "UPDATE_SHAPESHIFT_FORM",
}
local function heading(text) return "|cff91c7ad" .. text .. "|r" end
local function label(parent, font, width)
    local text = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    return text
end
local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 28)
    b:SetNormalFontObject("GameFontNormal")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetDisabledFontObject("GameFontDisable")
    b:SetText(text)
    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.10, 0.17, 0.14, 1)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    b:GetHighlightTexture():SetVertexColor(0.15, 0.30, 0.24, 0.45)
    return b
end
local function ranges(slots)
    table.sort(slots)
    local result, first, last = {}, nil, nil
    local function finish()
        if first then result[#result+1] = first == last and tostring(first) or (first .. "-" .. last) end
    end
    for _, slot in ipairs(slots) do
        if not first then first, last = slot, slot
        elseif slot == last + 1 then last = slot
        else finish(); first, last = slot, slot end
    end
    finish()
    return table.concat(result, ", ")
end
local function appendControl(lines, row, profile, number)
    local info = A.ControlInfo(row, profile)
    lines[#lines+1] = "Slot " .. number .. "   " .. info.actionText
    lines[#lines+1] = "    Keys: " .. info.keysText
    if info.altKeysText then lines[#lines+1] = "    Alt: " .. info.altKeysText end
end
function A.GetPlayGuide(id)
    local source = A.playGuideSource
    if type(source) ~= "string" then return end
    local start, finish
    if id == "subburst" then
        start = source:find("BEGYNN HER\n", 1, true)
        finish = source:find("ASSASSINATION: NÅR ROLIGERE TEMPO BETYR MEST\n", 1, true)
    elseif id == "assa" then
        start = source:find("ASSASSINATION: NÅR ROLIGERE TEMPO BETYR MEST\n", 1, true)
        finish = source:find("FELLES\n", 1, true)
    end
    local common = source:find("FELLES\n", 1, true)
    local legacy = source:find("De gamle sub/sublite-layoutene", 1, true)
    if start and finish and common and legacy then
        return source:sub(start, finish - 1) .. source:sub(common, legacy - 1)
    end
end
local function guideText(panel, snapshot)
    local lines = {
        heading("Play guide — " .. snapshot.profile.label),
        "Read-only notes for the selected preview. Return to setup to apply a layout.",
    }
    if panel.lastError then lines[#lines+1] = "\n|cffff8888Last action stopped|r\n" .. panel.lastError end
    if not snapshot.canApply then lines[#lines+1] = "\nSetup: " .. tostring(snapshot.applyReason) end
    lines[#lines+1] = "\n" .. heading("Previewed keys")
    lines[#lines+1] = "These are the selected layout's actions on your existing WoW bindings. Your bars may differ until you apply it."
    local rows = {}
    for _, row in ipairs(snapshot.plan.rows) do
        if row.slot >= 1 and row.slot <= 12 then rows[#rows+1] = row end
    end
    table.sort(rows, function(a,b) return a.slot < b.slot end)
    for _, row in ipairs(rows) do appendControl(lines, row, snapshot.profile, row.slot) end
    lines[#lines+1] = "\n" .. heading("Original playing guide · 25 October 2026")
    lines[#lines+1] = "The comparisons below describe the original reference model, not a current-live measurement. Slot numbers in the notes refer to the named layout; use the keys above."
    lines[#lines+1] = "\n" .. A.GetPlayGuide(snapshot.selectedId)
    return table.concat(lines, "\n")
end
local function previewText(panel, snapshot)
    local lines = {}
    if panel.lastError then
        lines[#lines+1] = "|cffff8888Last action stopped|r\n" .. panel.lastError .. "\n"
    end
    if not snapshot.plan then
        lines[#lines+1] = snapshot.applyReason or "No compatible profile is included for this class and specialization."
        lines[#lines+1] = "\nThe addon does not change your bars automatically."
        if snapshot.backup then lines[#lines+1] = "\nUndo: " .. (snapshot.undoReason or "Available for the saved setup.") end
        return table.concat(lines, "\n")
    end
    local plan, profile = snapshot.plan, snapshot.profile
    lines[#lines+1] = heading("Status")
    lines[#lines+1] = snapshot.canApply and "Ready to apply this layout." or ("Apply: " .. tostring(snapshot.applyReason))
    if snapshot.backup and snapshot.backup.state ~= "restored" then
        lines[#lines+1] = "Saved setup: " .. tostring(snapshot.backup.mode) .. " / " .. tostring(snapshot.backup.layout) .. "."
        lines[#lines+1] = snapshot.canUndo and "Undo is available." or ("Undo: " .. tostring(snapshot.undoReason))
    end
    if snapshot.legacyUndo then lines[#lines+1] = snapshot.legacyUndo end
    lines[#lines+1] = "\n" .. heading("Main bar - keys for this preview")
    lines[#lines+1] = "Keys shown use WoW's built-in action bars. Custom action-bar addons may use other bindings."
    local main, bar2, bar3, bar2Slots, bar3Slots, stealth, other = {}, {}, {}, {}, {}, {}, {}
    local formMain = false
    for _, row in ipairs(plan.rows or {}) do
        if row.mainButton or (row.slot >= 1 and row.slot <= 12) then
            main[#main+1] = row
            if row.mainButton and row.slot > 12 then formMain = true end
        elseif row.slot >= 61 and row.slot <= 72 then
            bar2[#bar2+1] = row
            bar2Slots[#bar2Slots+1] = row.slot - 60
        elseif row.slot >= 49 and row.slot <= 60 then
            bar3[#bar3+1] = row
            bar3Slots[#bar3Slots+1] = row.slot - 48
        elseif snapshot.class == "ROGUE" and row.slot >= 73 and row.slot <= 84 then
            stealth[#stealth+1] = row.slot - 72
        else
            other[#other+1] = row.slot
        end
    end
    table.sort(main, function(a,b) return (a.mainButton or a.slot) < (b.mainButton or b.slot) end)
    for _, row in ipairs(main) do appendControl(lines, row, profile, row.mainButton or row.slot) end
    if formMain then lines[#lines+1] = "Apply changes the main buttons in your selected form only." end
    lines[#lines+1] = "Key assignments stay the same; Apply replaces the abilities in the listed slots."
    if #bar2 > 0 then
        lines[#lines+1] = "\n" .. heading("Action Bar 2")
        lines[#lines+1] = "Your existing keys for these Action Bar 2 slots will cast the abilities listed below after Apply."
        table.sort(bar2, function(a,b) return a.slot < b.slot end)
        for _, row in ipairs(bar2) do
            appendControl(lines, row, profile, row.slot - 60)
        end
    end
    if #bar3 > 0 then
        lines[#lines+1] = "\n" .. heading("Action Bar 3")
        lines[#lines+1] = "Your existing keys for these Action Bar 3 slots will cast the abilities listed below after Apply."
        table.sort(bar3, function(a,b) return a.slot < b.slot end)
        for _, row in ipairs(bar3) do appendControl(lines, row, profile, row.slot - 48) end
    end
    lines[#lines+1] = "\n" .. heading("Using this layout")
    lines[#lines+1] = "Numbers in these notes identify slots. Use each slot's bound key."
    if profile.layouts[snapshot.layout].altSlots then
        lines[#lines+1] = "Hold Alt with that key for an alternate action."
    end
    if snapshot.layout == "mouseover" then
        lines[#lines+1] = "Friendly spells use a valid friendly mouseover; otherwise they keep normal targeting."
    end
    for _, line in ipairs(plan.lines or {}) do lines[#lines+1] = line end
    lines[#lines+1] = "\n" .. heading("Other affected bars")
    if #bar2 > 0 then lines[#lines+1] = "Action Bar 2: slots " .. ranges(bar2Slots) .. ". Enable it in WoW Options if hidden." end
    if #bar3 > 0 then lines[#lines+1] = "Action Bar 3: slots " .. ranges(bar3Slots) .. ". Enable it in WoW Options if hidden." end
    if #stealth > 0 then lines[#lines+1] = "Rogue Stealth / Dance bar: slots " .. ranges(stealth) .. "." end
    if #other > 0 then lines[#lines+1] = "Additional action slots: " .. ranges(other) .. "." end
    if #bar2 + #bar3 + #stealth + #other == 0 then lines[#lines+1] = "No additional bars." end
    if #(plan.skipped or {}) > 0 then
        lines[#lines+1] = "Unlearned utilities left untouched: " .. table.concat(plan.skipped, ", ") .. "."
    end
    if panel.details then
        local evidence = profile and profile.evidence
        if evidence then
            lines[#lines+1] = "\n" .. heading("Reference model")
            for _, key in ipairs({"patch", "gear", "tuning", "validation"}) do
                if evidence[key] then lines[#lines+1] = evidence[key] end
            end
            lines[#lines+1] = "Setup checks required spells, not your complete talent code, equipment or set bonuses."
        end
        if #(plan.macros or {}) > 0 then
            lines[#lines+1] = "\n" .. heading("Generated macros")
            for _, macro in ipairs(plan.macros) do
                lines[#lines+1] = "\n" .. macro.name .. "\n" .. macro.body
            end
        end
    end
    return table.concat(lines, "\n")
end
local function scrollTo(panel, offset)
    local maximum = math.max(0, panel.content:GetHeight() - panel.scroll:GetHeight())
    local value = math.min(maximum, math.max(0, offset))
    panel.scroll:SetVerticalScroll(value)
    panel.scrollUp:SetEnabled(value > 0)
    panel.scrollDown:SetEnabled(value < maximum)
end
local function refresh(panel, resetScroll)
    if panel.busy then return end
    -- An explicit stale profile must not silently select a different policy.
    -- Clear UI selection only when the character's class/spec actually changed.
    if panel.snapshot then
        local currentClass = select(2, UnitClass("player"))
        local index = C_SpecializationInfo.GetSpecialization()
        local currentSpec = index and C_SpecializationInfo.GetSpecializationInfo(index)
        if currentClass ~= panel.snapshot.class or currentSpec ~= panel.snapshot.spec then
            panel.selectedId, panel.layout, panel.details = nil, "standard", false
            panel.guide = false
            panel.lastError, panel.lastMessage = nil, nil
            resetScroll = true
        end
    end
    local ok, snapshot = pcall(A.Inspect, panel.selectedId, panel.layout)
    panel.talentsButton:SetEnabled(type(A.HasTalentReference) == "function" and A.HasTalentReference(panel.selectedId) or false)
    if not ok then
        panel.applyButton:SetEnabled(false)
        panel.undoButton:SetEnabled(false)
        panel.guideButton:SetEnabled(false)
        panel.statusText:SetText("Preview unavailable. Use Refresh to try again.")
        panel.statusText:SetTextColor(1, 0.5, 0.5)
        panel.previewText:SetText(tostring(snapshot))
    else
        panel.snapshot = snapshot
        panel.selectedId, panel.layout = snapshot.selectedId, snapshot.layout or "standard"
        local profile = snapshot.profile
        local hasGuide = snapshot.plan ~= nil and A.GetPlayGuide(snapshot.selectedId) ~= nil
        if not hasGuide then panel.guide = false end
        local className = UnitClass("player")
        panel.characterText:SetText(tostring(className or "Unknown class") .. " / " .. (profile and profile.specName or ("specialization " .. tostring(snapshot.spec or "unavailable"))))
        panel.profileText:SetText(profile and profile.label or "No supported profile for this specialization")
        panel.profilePrev:SetEnabled(#(snapshot.profiles or {}) > 1)
        panel.profileNext:SetEnabled(#(snapshot.profiles or {}) > 1)
        panel.standardButton:SetText(panel.layout == "standard" and "Standard (selected)" or "Standard")
        panel.alternateLayout = profile and profile.layouts.mouseover and "mouseover" or "compact"
        local alternateName = panel.alternateLayout == "mouseover" and "Mouseover" or "Compact"
        panel.compactButton:SetText(alternateName .. (panel.layout == panel.alternateLayout and " (selected)" or ""))
        panel.standardButton:SetEnabled(profile and profile.layouts and profile.layouts.standard ~= nil or false)
        panel.compactButton:SetEnabled(profile and profile.layouts and profile.layouts[panel.alternateLayout] ~= nil or false)
        panel.detailsButton:SetText(panel.details and "Hide details" or "Show details")
        panel.detailsButton:SetEnabled(snapshot.plan ~= nil and not panel.guide)
        panel.guideButton:SetText(panel.guide and "Back to setup" or "Play guide")
        panel.guideButton:SetEnabled(hasGuide)
        panel.applyButton:SetEnabled(snapshot.canApply == true and not panel.guide)
        panel.undoButton:SetEnabled(snapshot.canUndo == true and not panel.guide)
        panel.previewText:SetText(panel.guide and guideText(panel, snapshot) or previewText(panel, snapshot))
        if panel.lastError then
            panel.statusText:SetText("Action stopped. Read the message at the top of the preview.")
            panel.statusText:SetTextColor(1, 0.5, 0.5)
        elseif panel.guide then
            panel.statusText:SetText("Play guide: read at your own pace. Return to setup to change bars.")
            panel.statusText:SetTextColor(0.65, 0.88, 0.72)
        elseif panel.lastMessage then
            panel.statusText:SetText(panel.lastMessage)
            if snapshot.backup and snapshot.backup.state == "needs-undo" then
                panel.statusText:SetTextColor(0.92, 0.78, 0.53)
            else
                panel.statusText:SetTextColor(0.65, 0.88, 0.72)
            end
        elseif snapshot.canApply then
            panel.statusText:SetText("Ready to apply the previewed layout.")
            panel.statusText:SetTextColor(0.65, 0.88, 0.72)
        else
            panel.statusText:SetText(snapshot.plan and "Apply unavailable. Read the reason at the top of the preview." or "No profile for this specialization. The addon will not change anything on this character.")
            panel.statusText:SetTextColor(0.92, 0.78, 0.53)
        end
        local activeBackup = snapshot.backup and snapshot.backup.state ~= "restored"
        panel.undoWarning:SetText(panel.guide and "Reading this guide does not apply or undo a layout." or
            (activeBackup and "Undo replaces your current actions in the saved slots." or "Apply replaces the previewed slots and saves your previous setup."))
    end
    panel.content:SetHeight(math.max(panel.scroll:GetHeight(), panel.previewText:GetStringHeight() + 12))
    scrollTo(panel, resetScroll and 0 or panel.scroll:GetVerticalScroll())
end
local function execute(panel, command)
    if panel.busy then return end
    panel.busy = true
    local called, success, problem, note = pcall(A.Execute, command)
    panel.busy = false
    if not called or success ~= true then
        panel.lastError = tostring(not called and success or problem or "Command did not complete; see chat for details.")
        panel.lastMessage = nil
    else
        panel.lastError = nil
        panel.lastMessage = note or (command == "undo" and "Original bars restored. Generated macros were kept." or "Setup verified. Use /reload to save your previous setup.")
    end
    refresh(panel, true)
end
local function createPanel()
    local panel = CreateFrame("Frame", "TheOneToRuleThemAllPanel", UIParent)
    panel:Hide()
    panel:SetSize(720, 660)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.035, 0.055, 0.05, 0.98)
    local title = label(panel, "GameFontNormalLarge", 580)
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText("The One To Rule Them All")
    local version = label(panel, "GameFontHighlightSmall", 110)
    version:SetPoint("TOPRIGHT", -20, -21)
    version:SetText("v" .. A.version)
    panel.characterText = label(panel, "GameFontHighlightSmall", 660)
    panel.characterText:SetPoint("TOPLEFT", 20, -44)
    panel.profilePrev = button(panel, "<", 32)
    panel.profilePrev:SetPoint("TOPLEFT", 20, -76)
    panel.profileNext = button(panel, ">", 32)
    panel.profileNext:SetPoint("TOPRIGHT", -20, -76)
    panel.profileText = label(panel, "GameFontNormal", 590)
    panel.profileText:SetPoint("TOPLEFT", 64, -77)
    panel.profileText:SetHeight(38)
    panel.standardButton = button(panel, "Standard", 155)
    panel.standardButton:SetPoint("TOPLEFT", 20, -123)
    panel.compactButton = button(panel, "Compact", 155)
    panel.compactButton:SetPoint("LEFT", panel.standardButton, "RIGHT", 8, 0)
    panel.detailsButton = button(panel, "Show details", 125)
    panel.detailsButton:SetPoint("LEFT", panel.compactButton, "RIGHT", 8, 0)
    panel.refreshButton = button(panel, "Refresh", 100)
    panel.refreshButton:SetPoint("TOPRIGHT", -20, -123)
    panel.scroll = CreateFrame("ScrollFrame", nil, panel)
    panel.scroll:SetPoint("TOPLEFT", 20, -169)
    panel.scroll:SetPoint("BOTTOMRIGHT", -62, 155)
    panel.scroll:EnableMouseWheel(true)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(638, 1)
    panel.previewText = label(panel.content, "GameFontHighlight", 626)
    panel.previewText:SetPoint("TOPLEFT", 0, -2)
    panel.previewText:SetSpacing(4)
    panel.scroll:SetScrollChild(panel.content)
    panel.scrollUp = button(panel, "^", 30)
    panel.scrollUp:SetPoint("TOPRIGHT", -20, -169)
    panel.scrollDown = button(panel, "v", 30)
    panel.scrollDown:SetPoint("BOTTOMRIGHT", -20, 155)
    local scrollHint = label(panel, "GameFontHighlightSmall", 650)
    scrollHint:SetPoint("BOTTOMLEFT", 20, 131)
    scrollHint:SetText("Mouse wheel or arrow buttons to scroll the preview.")
    panel.statusText = label(panel, "GameFontHighlight", 670)
    panel.statusText:SetPoint("BOTTOMLEFT", 20, 82)
    panel.statusText:SetHeight(36)
    panel.undoWarning = label(panel, "GameFontHighlightSmall", 670)
    panel.undoWarning:SetPoint("BOTTOMLEFT", 20, 54)
    panel.undoWarning:SetHeight(24)
    panel.applyButton = button(panel, "Apply layout", 140)
    panel.applyButton:SetPoint("BOTTOMLEFT", 20, 18)
    panel.undoButton = button(panel, "Undo setup", 130)
    panel.undoButton:SetPoint("LEFT", panel.applyButton, "RIGHT", 10, 0)
    panel.guideButton = button(panel, "Play guide", 130)
    panel.guideButton:SetPoint("LEFT", panel.undoButton, "RIGHT", 10, 0)
    panel.talentsButton = button(panel, "Talent builds", 130)
    panel.talentsButton:SetPoint("LEFT", panel.guideButton, "RIGHT", 10, 0)
    panel.closeButton = button(panel, "Close", 100)
    panel.closeButton:SetPoint("BOTTOMRIGHT", -20, 18)
    panel.layout, panel.details = "standard", false
    panel.Refresh = refresh
    local function choose(direction)
        local profiles = panel.snapshot and panel.snapshot.profiles or {}
        if #profiles == 0 then return end
        local current = 1
        for i, profile in ipairs(profiles) do if profile.id == panel.selectedId then current = i; break end end
        local selected = profiles[((current - 1 + direction) % #profiles) + 1]
        panel.selectedId = selected.id
        if not selected.layouts[panel.layout] then panel.layout = "standard" end
        panel.lastError, panel.lastMessage = nil, nil
        refresh(panel, true)
    end
    panel.profilePrev:SetScript("OnClick", function() choose(-1) end)
    panel.profileNext:SetScript("OnClick", function() choose(1) end)
    panel.standardButton:SetScript("OnClick", function()
        panel.layout, panel.lastError, panel.lastMessage = "standard", nil, nil
        refresh(panel, true)
    end)
    panel.compactButton:SetScript("OnClick", function()
        panel.layout, panel.lastError, panel.lastMessage = panel.alternateLayout or "compact", nil, nil
        refresh(panel, true)
    end)
    panel.detailsButton:SetScript("OnClick", function() panel.details = not panel.details; refresh(panel) end)
    panel.guideButton:SetScript("OnClick", function()
        panel.guide = not panel.guide
        refresh(panel, true)
    end)
    panel.talentsButton:SetScript("OnClick", function()
        if type(A.ShowTalentBuilds) == "function" then A.ShowTalentBuilds(panel.selectedId) end
    end)
    panel.refreshButton:SetScript("OnClick", function() panel.lastError, panel.lastMessage = nil, nil; refresh(panel) end)
    panel.applyButton:SetScript("OnClick", function()
        if panel.selectedId and not panel.guide then execute(panel, "apply " .. panel.selectedId .. " " .. panel.layout) end
    end)
    panel.undoButton:SetScript("OnClick", function() if not panel.guide then execute(panel, "undo") end end)
    panel.closeButton:SetScript("OnClick", function() panel:Hide() end)
    panel.scrollUp:SetScript("OnClick", function() scrollTo(panel, panel.scroll:GetVerticalScroll() - 90) end)
    panel.scrollDown:SetScript("OnClick", function() scrollTo(panel, panel.scroll:GetVerticalScroll() + 90) end)
    panel.scroll:SetScript("OnMouseWheel", function(_, delta) scrollTo(panel, panel.scroll:GetVerticalScroll() - delta * 42) end)
    panel:SetScript("OnShow", function()
        for _, event in ipairs(EVENTS) do panel:RegisterEvent(event) end
        refresh(panel, true)
    end)
    panel:SetScript("OnHide", function() panel:UnregisterAllEvents(); panel:StopMovingOrSizing() end)
    panel:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
        refresh(panel)
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1] = "TheOneToRuleThemAllPanel" end
    return panel
end
function A.TogglePanel()
    if not A.panel then A.panel = createPanel() end
    if A.panel:IsShown() then A.panel:Hide() else A.panel:Show() end
end
function A.ShowGuide()
    if not A.panel then
        A.panel = createPanel()
        local backup = TheOneToRuleThemAllDB and TheOneToRuleThemAllDB.backup
        local index = C_SpecializationInfo.GetSpecialization()
        local spec = index and C_SpecializationInfo.GetSpecializationInfo(index)
        if backup and backup.state == "applied" and backup.class == select(2, UnitClass("player"))
            and backup.spec == spec and A.GetPlayGuide(backup.mode) then
            A.panel.selectedId, A.panel.layout = backup.mode, backup.layout
        end
    end
    local panel = A.panel
    refresh(panel, true)
    if not panel.snapshot or not panel.snapshot.plan or not panel.guideButton:IsEnabled() then
        error("A playing guide is included for SubBurst and Fatebound Assassination. Select one of those profiles in /tor.", 0)
    end
    panel.guide = true
    if panel:IsShown() then refresh(panel, true) else panel:Show() end
end
