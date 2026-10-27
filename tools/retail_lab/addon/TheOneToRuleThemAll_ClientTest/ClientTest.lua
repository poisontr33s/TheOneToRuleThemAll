-- Optional real-client exercise. No action-bar writes occur on load or events.
-- Only the Apply and Undo buttons call the main addon's guarded commands.
local A = TheOneToRuleThemAll
local addonName = ...
local panel, db, sessionID
local deployment = TheOneToRuleThemAllClientTestDeployment or {}
local deploymentID = deployment.id or "manual"
local sourceSHA = deployment.source_sha256 or "untracked"
local requestedProfile, requestedLayout
local function isRetail()
    return type(WOW_PROJECT_ID) == "number" and type(WOW_PROJECT_MAINLINE) == "number"
        and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
end

local function secret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end
local function readable(value)
    if secret(value) then error("WoW has restricted this value; no result was inferred.", 0) end
    return value
end
local function quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
        if c == '"' then return '\\"' end
        if c == '\\' then return '\\\\' end
        return string.format("\\u%04x", string.byte(c))
    end) .. '"'
end
local function json(value)
    readable(value)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "string" then return quote(value) end
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return "null" end
        return tostring(value)
    end
    if kind ~= "table" then error("Unsupported report value", 0) end
    local count, array = 0, true
    for key in pairs(value) do
        count = count + 1
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then array = false end
    end
    array = array and count == #value
    local parts = {}
    if array then
        for _, entry in ipairs(value) do parts[#parts+1] = json(entry) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys+1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts+1] = quote(tostring(key)) .. ":" .. json(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function base64(value)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local parts = {}
    for i = 1, #value, 3 do
        local a, b, c = value:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local function digit(shift) local index = math.floor(n / shift) % 64 + 1; return alphabet:sub(index,index) end
        parts[#parts+1] = digit(262144) .. digit(4096) .. (b and digit(64) or "=") .. (c and digit(1) or "=")
    end
    return table.concat(parts)
end
local function publish()
    db.report.updated_at = GetServerTime()
    TheOneToRuleThemAllClientTestReport = base64(json(db.report))
end
local function newReport(phase)
    local version, build, buildDate, interface = GetBuildInfo()
    return {
        schema=1, loaded=true, runtime="WoW Retail APIs", phase=phase or "ready",
        session_id=sessionID, started_session=sessionID,
        deployment_id=deploymentID, source_sha256=sourceSHA,
        addon_version=A and A.version or "unavailable",
        build={version=version,build=build,date=buildDate,interface=interface},
        checks={client_loaded={status="observed"}}, errors={},
        observations={visuals="not_verified",casts="not_verified"},
    }
end
local function backup()
    return TheOneToRuleThemAllDB and TheOneToRuleThemAllDB.backup
end
local function activeBackup()
    local b = backup()
    return b and b.state ~= "restored" and b
end
local function guard()
    if not isRetail() then error("This companion requires WoW Retail.",0) end
    if not A or type(A.Execute) ~= "function" or type(A.Inspect) ~= "function" then
        error("The One is not loaded.",0)
    end
    if InCombatLockdown() then error("Gå ut av kamp først.",0) end
    if GetCursorInfo() then error("Legg ned det du holder på musepekeren først.",0) end
end
local function actionAt(slot)
    local kind, id, subtype = GetActionInfo(slot)
    readable(kind); readable(id); readable(subtype)
    local record = {slot=slot,kind=kind or "empty",id=id,subtype=subtype}
    if kind == "macro" then
        record.verification = "core_confirmed_only"
        if type(GetActionText) == "function" then record.name = readable(GetActionText(slot)) end
    elseif kind == "spell" then
        if C_ActionBar.IsAssistedCombatAction and readable(C_ActionBar.IsAssistedCombatAction(slot)) then
            record.assisted = true
        elseif type(id) == "number" and C_Spell.GetBaseSpell then
            record.base_id = readable(C_Spell.GetBaseSpell(id))
        end
    end
    return record
end
local function actions(rows)
    local result = {}
    for _, row in ipairs(rows) do result[#result+1] = actionAt(row.slot) end
    return result
end
local function macroRecords()
    local result = {}
    local m = Constants and Constants.MacroConsts
    local accountMax = m and m.MAX_ACCOUNT_MACROS or 120
    local characterMax = m and m.MAX_CHARACTER_MACROS or 30
    for index = 1, accountMax + characterMax do
        local name, icon, body = GetMacroInfo(index)
        readable(name); readable(icon); readable(body)
        if name then result[#result+1] = {index=index,name=name,icon=icon,body=body} end
    end
    return result
end
local function compare(expected, actual)
    local differences, macroCount = {}, 0
    for i, original in ipairs(expected) do
        local current = actual[i]
        local same = current and current.slot == original.slot and current.kind == original.kind
        if same and original.kind == "macro" then
            macroCount = macroCount + 1
            -- GetActionInfo's macro ID is not a stable macro identity. The main
            -- addon verifies the exact saved body through its guarded path.
            same = not original.name or not current.name or original.name == current.name
        elseif same and original.kind == "spell" then
            same = original.assisted and current.assisted or
                (not original.assisted and not current.assisted and
                 (original.base_id or original.id) == (current.base_id or current.id))
        elseif same then
            same = original.id == current.id and original.subtype == current.subtype
        end
        if not same then differences[#differences+1] = original.slot end
    end
    return {status=#differences == 0 and "passed" or "failed",different_slots=differences,
        macros=macroCount > 0 and "core_confirmed_only" or "none",macro_slots=macroCount}
end
local function selectedView()
    local p = A.panel
    return A.Inspect(requestedProfile or (p and p.selectedId), requestedLayout or (p and p.layout))
end
local function begin()
    guard()
    if activeBackup() then error("Et oppsett venter allerede på Angre. Gjør det ferdig først.",0) end
    local view = selectedView()
    if not view.canApply then error(view.applyReason or "Ingen kompatibel profil.",0) end
    db.counter = (db.counter or 0) + 1
    db.report = newReport("preparing")
    local r = db.report
    r.run_id = tostring(GetServerTime()) .. "-" .. db.counter
    r.profile, r.layout, r.class, r.spec = view.selectedId, view.layout, view.class, view.spec
    r.original_actions = actions(view.plan.rows)
    local originalMacros = json(macroRecords())
    local originalDB = json(TheOneToRuleThemAllDB)
    if not A.panel or not A.panel:IsShown() then A.TogglePanel() end
    A.panel.selectedId, A.panel.layout = r.profile, r.layout
    A.panel:Refresh(true)
    r.checks.panel = {status=A.panel:IsShown() and A.panel:GetWidth() > 0 and A.panel:GetHeight() > 0 and "observed" or "failed",
        basis="Native frame exists, is shown and has nonzero dimensions; appearance is not verified."}
    r.checks.read_only = {
        status=json(actions(view.plan.rows)) == json(r.original_actions)
            and originalMacros == json(macroRecords()) and originalDB == json(TheOneToRuleThemAllDB)
            and not GetCursorInfo() and "passed" or "failed",
    }
    if r.checks.read_only.status ~= "passed" then error("Forhåndsvisningen endret uventet tilstand. Prøven er stoppet.",0) end
    r.phase = "prepared"
    r.note = "Se over oppsettet i hovedvinduet. Prøv oppsett når du er klar."
end
local function apply()
    guard()
    local r = db.report
    if r.phase ~= "prepared" then error("Start prøven først.",0) end
    if not r.checks.read_only or r.checks.read_only.status ~= "passed" then error("Start prøven på nytt.",0) end
    if activeBackup() then error("Et annet oppsett har en aktiv backup. Angre det først.",0) end
    local view = A.Inspect(r.profile,r.layout)
    if not view.canApply then error(view.applyReason,0) end
    if json(actions(view.plan.rows)) ~= json(r.original_actions) then
        error("Knappene er endret siden prøven startet. Start på nytt.",0)
    end
    -- This call is reached only from the player's Apply button click.
    r.phase = "applying"
    local ok, problem = A.Execute("apply " .. r.profile .. " " .. r.layout)
    local b = backup()
    r.applied_actions = actions(view.plan.rows)
    r.checks.apply = {status=ok and b and b.state == "applied" and "passed" or "failed",
        basis="Main addon command and native placement verification executed in this client."}
    if not ok or not b or b.state ~= "applied" then
        r.phase = activeBackup() and "needs_undo" or "failed"
        error(problem or "Oppsettet ble ikke fullført.",0)
    end
    local expected = {}
    for _, row in ipairs(view.plan.rows) do
        local action = row.action
        local entry = {slot=row.slot,kind=action.kind,id=action.id,name=action.name}
        if action.kind == "spell" and C_Spell.GetBaseSpell then entry.base_id=readable(C_Spell.GetBaseSpell(action.id)) end
        expected[#expected+1] = entry
    end
    r.checks.placed_actions = compare(expected,r.applied_actions)
    r.phase = "applied"
    r.note = "Oppsettet er lagt inn. Last på nytt for å prøve den lagrede backupen."
end
local function reload()
    guard()
    if db.report.phase == "applied" then db.report.phase = "awaiting_reload" end
    publish()
    ReloadUI()
end
local function undo()
    guard()
    local r, b = db.report, activeBackup()
    if not b then error("Ingen aktiv backup å angre.",0) end
    -- An older deployment may need recovery, but its observations never count
    -- as a completed run for the current source/deployment.
    local stale = r.phase == "stale_run"
    local tracked = r.run_id and r.checks.apply and r.checks.apply.status == "passed"
        and r.profile == b.mode and r.layout == b.layout and not stale
    local expected = tracked and r.original_actions
    r.phase = stale and "stale_run" or "undoing"
    local ok, problem, note = A.Execute("undo")
    b = backup()
    r.checks.undo = {status=ok and b and b.state == "restored" and "passed" or "failed",
        basis="Main addon restored its saved originals in this client."}
    r.phase = stale and "stale_run" or (ok and b and b.state == "restored" and (tracked and "restored" or "recovery_only") or "needs_undo")
    if expected then
        r.restored_actions = actions(expected)
        r.checks.restored_actions = compare(expected,r.restored_actions)
    else
        r.checks.restored_actions = {status="not_verified",basis="No original capture from this deployment."}
    end
    if not ok or not b or b.state ~= "restored" then
        r.phase = stale and "stale_run" or "needs_undo"
        error(problem or note or "Angre er ikke ferdig. Backupen er beholdt.",0)
    end
    r.phase = stale and "stale_run" or (tracked and "restored" or "recovery_only")
    r.note = "Det opprinnelige oppsettet er tilbake. Last på nytt for å lagre resultatet."
end
local function refresh()
    if not panel or not db then return end
    local r = db.report
    panel.status:SetText(r.note or "Åpne prøven utenfor kamp. Start viser oppsettet uten å endre knappene.")
    local available = isRetail() and not InCombatLockdown() and not GetCursorInfo()
    panel.beginButton:SetEnabled(available and not activeBackup())
    panel.applyButton:SetEnabled(available and r.phase == "prepared")
    panel.reloadButton:SetEnabled(available)
    panel.undoButton:SetEnabled(available and activeBackup() ~= nil)
end
local function run(action)
    if not db then return end
    local ok, problem = pcall(action)
    if not ok then
        if db.report.phase == "preparing" then db.report.phase = "failed" end
        if db.report.phase == "applying" then db.report.phase = activeBackup() and "needs_undo" or "failed" end
        local message = secret(problem) and "WoW restricted an error value." or tostring(problem)
        db.report.errors[#db.report.errors+1] = {phase=db.report.phase,message=message}
        db.report.note = message
    end
    publish()
    refresh()
end
local function makePanel()
    local f = CreateFrame("Frame","TheOneToRuleThemAllClientTestPanel",UIParent)
    f:SetSize(260,345); f:SetPoint("TOPLEFT",UIParent,"TOPLEFT",20,-120)
    f:SetFrameStrata("DIALOG"); f:SetFrameLevel(150); f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    local bg=f:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.035,0.055,0.05,0.98)
    local title=f:CreateFontString(nil,"ARTWORK","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",14,-14); title:SetText("The One — prøvekjøring")
    f.status=f:CreateFontString(nil,"ARTWORK","GameFontHighlight")
    f.status:SetPoint("TOPLEFT",14,-45); f.status:SetSize(232,92); f.status:SetJustifyH("LEFT"); f.status:SetJustifyV("TOP")
    local function button(name,text,y,action)
        local b=CreateFrame("Button",name,f,"UIPanelButtonTemplate")
        b:SetSize(232,28); b:SetPoint("TOPLEFT",14,y); b:SetText(text)
        b:SetScript("OnClick",function() run(action) end)
        return b
    end
    f.beginButton=button("TORClientTestBegin","Start",-142,begin)
    f.applyButton=button("TORClientTestApply","Prøv oppsett",-178,apply)
    f.reloadButton=button("TORClientTestReload","Last på nytt / lagre",-214,reload)
    f.undoButton=button("TORClientTestUndo","Angre",-250,undo)
    f.closeButton=button("TORClientTestClose","Lukk",-295,function() f:Hide() end)
    f:SetScript("OnShow",refresh)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]="TheOneToRuleThemAllClientTestPanel" end
    return f
end
local function initialize()
    sessionID=tostring(GetServerTime()) .. ":" .. tostring(GetTimePreciseSec())
    db = TheOneToRuleThemAllClientTestDB
    if type(db) ~= "table" or db.schema ~= 1 then db={schema=1,counter=0} end
    TheOneToRuleThemAllClientTestDB=db
    local old=db.report
    local current=newReport()
    if not old then
        db.report=current
    elseif old.deployment_id ~= deploymentID or old.source_sha256 ~= sourceSHA
        or old.addon_version ~= current.addon_version or json(old.build) ~= json(current.build) then
        db.previous_report=old
        db.report=current
        db.report.phase="stale_run"
        db.report.previous_run_id=old.run_id
        db.report.note="WoW eller The One er endret. En eldre prøve teller ikke her. Angre et aktivt oppsett før du starter på nytt."
    else
        old.loaded=true
        old.session_id=sessionID
        old.current_addon_version=A and A.version or "unavailable"
        if old.phase=="awaiting_reload" or old.phase=="applied" then
            local b=backup()
            local valid=b and b.state=="applied" and b.mode==old.profile and b.layout==old.layout and old.addon_version==old.current_addon_version
            old.checks.reload={status=valid and "passed" or "failed",basis="SavedVariables were loaded in a new addon session."}
            old.phase=valid and "reloaded" or "needs_undo"
            old.note=valid and "Backupen overlevde ny innlasting. Trykk Angre for å få knappene tilbake." or "Den lagrede prøven stemmer ikke med oppsettet. Undersøk backupen før du fortsetter."
        end
    end
    if not isRetail() then
        db.report.phase="unsupported_client"; db.report.note="Denne prøven krever WoW Retail."
    end
    publish()
end
SLASH_TORCLIENTTEST1="/tortest"
SlashCmdList.TORCLIENTTEST=function(message)
    local args={}; for word in (message or ""):gmatch("%S+") do args[#args+1]=word end
    if #args>2 then print("/tortest [profil] [standard|compact]"); return end
    requestedProfile,requestedLayout=args[1],args[2]
    if not db then print("The One-prøven er ikke ferdig lastet."); return end
    if not panel then panel=makePanel() end
    panel:Show(); refresh()
end
local events=CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("CURSOR_CHANGED")
events:SetScript("OnEvent",function(_,event,name)
    if event=="ADDON_LOADED" then
        if name==addonName then initialize() end
    elseif db then refresh() end
end)
