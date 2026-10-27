-- Published talent references are read-only. Importing is left to WoW's
-- talent window; opening this browser never changes a loadout or action bar.
local A = TheOneToRuleThemAll

local function character()
    local className, class = UnitClass("player")
    local index = C_SpecializationInfo.GetSpecialization()
    local spec, specName
    if index then spec, specName = C_SpecializationInfo.GetSpecializationInfo(index) end
    return class, spec, className, specName
end

local function reference(profileId)
    local class, spec = character()
    local requested = profileId and A.profiles[profileId]
    if requested and (requested.class ~= class or requested.spec ~= spec) then
        return nil, "Select a profile for your current specialization."
    end
    local fallback
    for _, entry in ipairs(A.standardDefinitions or {}) do
        if entry.class == class and entry.spec == spec then
            if entry.id == profileId then return entry end
            fallback = fallback or entry
        end
    end
    -- A custom profile may browse the published reference for its own spec.
    -- An unknown explicit ID must not silently select a different profile.
    if profileId and not requested then
        return nil, "No Method reference is included for that profile."
    end
    return fallback, "No Method reference is included for this specialization yet."
end

function A.HasTalentReference(profileId)
    return reference(profileId) ~= nil
end

local function label(parent, font, width)
    local text = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    return text
end

local function button(parent, text, width)
    local result = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    result:SetSize(width, 28)
    result:SetText(text)
    return result
end

local function copyField(parent, width, height, multiline)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, height)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetAutoFocus(false)
    box:SetMultiLine(multiline)
    box:SetMaxLetters(0)
    box:SetTextInsets(8, 8, 8, 8)
    local background = box:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.08, 0.12, 0.10, 1)
    box.sourceText = ""
    box:SetScript("OnTextChanged", function(self)
        if self.restoring or self:GetText() == self.sourceText then return end
        self.restoring = true
        self:SetText(self.sourceText)
        self:SetCursorPosition(0)
        self.restoring = false
    end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function setCopyText(box, text)
    box:ClearFocus()
    box.sourceText = text or ""
    box:SetText(box.sourceText)
    box:SetCursorPosition(0)
end

local function refresh(panel)
    local class, spec, className, specName = character()
    if panel.class and (panel.class ~= class or panel.spec ~= spec) then
        panel.profileId, panel.buildIndex = nil, 1
    end
    panel.class, panel.spec = class, spec
    panel.characterText:SetText(tostring(className or class or "Unknown class") .. " / " ..
        tostring(specName or spec or "No specialization"))
    local entry, problem = reference(panel.profileId)
    panel.reference = entry
    panel.builds = {}
    for _, build in ipairs(entry and entry.builds or {}) do
        if type(build) == "table" and type(build.code) == "string" and build.code:find("%S") then
            panel.builds[#panel.builds + 1] = build
        end
    end
    panel.buildIndex = math.min(math.max(panel.buildIndex or 1, 1), math.max(#panel.builds, 1))
    local build = panel.builds[panel.buildIndex]
    panel.previousButton:SetEnabled(#panel.builds > 1)
    panel.nextButton:SetEnabled(#panel.builds > 1)
    panel.selectButton:SetEnabled(build ~= nil)
    setCopyText(panel.codeBox, build and build.code or "")
    local guide = entry and entry.guide or ""
    setCopyText(panel.sourceBox, guide)
    if not entry then
        panel.buildText:SetText(problem)
        panel.metadataText:SetText("")
        panel.hint:SetText("Your current talents and setup are unchanged.")
        return
    end
    local metadata = {}
    if build and build.hero and build.hero ~= "" then metadata[#metadata + 1] = build.hero end
    if build and build.content and build.content ~= "" then metadata[#metadata + 1] = build.content end
    if entry.patch and entry.patch ~= "" then metadata[#metadata + 1] = "Guide patch " .. entry.patch end
    if entry.updated and entry.updated ~= "" then metadata[#metadata + 1] = "Updated " .. entry.updated end
    panel.metadataText:SetText(table.concat(metadata, " · "))
    if build then
        panel.buildText:SetText((build.label or entry.specName .. " reference") ..
            "  (" .. panel.buildIndex .. "/" .. #panel.builds .. ")")
        panel.hint:SetText("Select the code, press Ctrl+C, then import it in WoW's talent window.")
    else
        panel.buildText:SetText("No verified import code is included yet.")
        panel.hint:SetText("Select the guide address below to find its published builds.")
    end
end

local function createBrowser()
    local panel = CreateFrame("Frame", "TheOneToRuleThemAllTalentBrowser", UIParent)
    panel:Hide()
    panel:SetSize(680, 540)
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
    local title = label(panel, "GameFontNormalLarge", 640)
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText("Method talent reference")
    local description = label(panel, "GameFontHighlight", 640)
    description:SetPoint("TOPLEFT", 20, -50)
    description:SetHeight(38)
    description:SetText("Browse published standard builds for this specialization. Importing a code is your choice; custom setups are kept until you change them.")
    panel.characterText = label(panel, "GameFontNormal", 640)
    panel.characterText:SetPoint("TOPLEFT", 20, -100)
    panel.previousButton = button(panel, "<", 32)
    panel.previousButton:SetPoint("TOPLEFT", 20, -130)
    panel.nextButton = button(panel, ">", 32)
    panel.nextButton:SetPoint("TOPRIGHT", -20, -130)
    panel.buildText = label(panel, "GameFontHighlight", 552)
    panel.buildText:SetPoint("TOPLEFT", 64, -132)
    panel.buildText:SetHeight(38)
    panel.metadataText = label(panel, "GameFontHighlightSmall", 640)
    panel.metadataText:SetPoint("TOPLEFT", 20, -180)
    panel.metadataText:SetHeight(34)
    local codeLabel = label(panel, "GameFontNormal", 640)
    codeLabel:SetPoint("TOPLEFT", 20, -224)
    codeLabel:SetText("Talent import code")
    panel.codeBox = copyField(panel, 640, 112, true)
    panel.codeBox:SetPoint("TOPLEFT", 20, -246)
    panel.selectButton = button(panel, "Select code", 150)
    panel.selectButton:SetPoint("TOPLEFT", 20, -370)
    panel.hint = label(panel, "GameFontHighlightSmall", 470)
    panel.hint:SetPoint("TOPLEFT", 186, -371)
    panel.hint:SetHeight(38)
    local sourceLabel = label(panel, "GameFontNormal", 640)
    sourceLabel:SetPoint("TOPLEFT", 20, -418)
    sourceLabel:SetText("Source guide — click the address to select it")
    panel.sourceBox = copyField(panel, 640, 32, false)
    panel.sourceBox:SetPoint("TOPLEFT", 20, -440)
    panel.closeButton = button(panel, "Close", 100)
    panel.closeButton:SetPoint("BOTTOMRIGHT", -20, 18)
    panel.Refresh = refresh
    panel.previousButton:SetScript("OnClick", function()
        if #panel.builds > 1 then panel.buildIndex = (panel.buildIndex - 2) % #panel.builds + 1 end
        refresh(panel)
    end)
    panel.nextButton:SetScript("OnClick", function()
        if #panel.builds > 1 then panel.buildIndex = panel.buildIndex % #panel.builds + 1 end
        refresh(panel)
    end)
    panel.selectButton:SetScript("OnClick", function()
        if panel.codeBox.sourceText ~= "" then
            panel.codeBox:SetFocus()
            panel.codeBox:HighlightText()
        end
    end)
    panel.closeButton:SetScript("OnClick", function() panel:Hide() end)
    panel:SetScript("OnShow", function()
        panel:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        panel:RegisterEvent("PLAYER_TALENT_UPDATE")
        refresh(panel)
    end)
    panel:SetScript("OnHide", function()
        panel:UnregisterAllEvents()
        panel.codeBox:ClearFocus()
        panel.sourceBox:ClearFocus()
        panel:StopMovingOrSizing()
    end)
    panel:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
        refresh(panel)
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "TheOneToRuleThemAllTalentBrowser" end
    return panel
end

function A.ShowTalentBuilds(profileId)
    if not A.talentBrowser then A.talentBrowser = createBrowser() end
    local panel = A.talentBrowser
    panel.profileId, panel.buildIndex = profileId, 1
    if panel:IsShown() then refresh(panel) else panel:Show() end
end
