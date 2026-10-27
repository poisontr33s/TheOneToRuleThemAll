-- The One To Rule Them All: profile registration and transactional setup.
-- Only explicit setup/undo commands or panel clicks write macros/action slots,
-- out of combat. No rotation decisions, timed casting or keybinding writes.
TheOneToRuleThemAll = { version = "0.3.1-combined", profiles = {} }
local A = TheOneToRuleThemAll
local PREFIX = "|cff91c7adThe One:|r "
local function say(s) print(PREFIX .. s) end
local function check(ok, message) if not ok then error(message, 0) end end
local function db()
    TheOneToRuleThemAllDB = TheOneToRuleThemAllDB or { version = 1 }
    check(TheOneToRuleThemAllDB.version == 1, "Unknown saved-data version; nothing changed.")
    return TheOneToRuleThemAllDB
end
local function classID() return select(2, UnitClass("player")) end
local function className(token)
    local name, current = UnitClass("player")
    if not token or token == current then return name or "Unknown class" end
    local names = LOCALIZED_CLASS_NAMES_MALE or {}
    return names[token] or "another class"
end
local function specID()
    local s = C_SpecializationInfo.GetSpecialization()
    return s and C_SpecializationInfo.GetSpecializationInfo(s)
end
local function specText()
    local _, name = C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization())
    return name or "unknown specialization"
end
local KIND_TEXT = {spell="a spell", item="an item", macro="a macro", flyout="a spell flyout",
    summonmount="a mount", summonpet="a battle pet", equipmentset="an equipment set",
    outfit="a transmog outfit", companion="a companion"}
local function kindText(kind) return KIND_TEXT[kind] or "an action the addon cannot restore" end
-- Players see bar positions, not raw action-slot numbers.
local function slotText(slot)
    if slot >= 1 and slot <= 12 then return "main bar slot " .. slot end
    if slot >= 61 and slot <= 72 then return "Action Bar 2 slot " .. (slot - 60) end
    if slot >= 73 and slot <= 84 and classID() == "ROGUE" then return "Stealth bar slot " .. (slot - 72) end
    return "action slot " .. slot
end
local function capitalized(text) return (text:gsub("^%l", string.upper)) end
local function configID()
    return C_ClassTalents and C_ClassTalents.GetActiveConfigID() or 0
end
-- The active config belongs to the specialization; loading another saved
-- loadout can leave that ID unchanged. Record the selected saved loadout and
-- starter-build state separately when the client exposes those APIs.
local function loadoutIdentity()
    local identity, spec = {}, specID()
    if spec and C_ClassTalents and type(C_ClassTalents.GetLastSelectedSavedConfigID) == "function" then
        identity.savedConfig = C_ClassTalents.GetLastSelectedSavedConfigID(spec) or false
    end
    if C_ClassTalents and type(C_ClassTalents.GetStarterBuildActive) == "function" then
        identity.starter = not not C_ClassTalents.GetStarterBuildActive()
    end
    if next(identity) then return identity end
end
local function fullLoadoutIdentity(backup)
    local identity = backup and backup.loadout
    return identity and identity.savedConfig ~= nil and identity.starter ~= nil
end
local LEGACY_UNDO = "This previous setup was saved without full loadout information. Select the original talent loadout before Undo; the addon cannot fully check it."
local function page() return C_ActionBar.GetActionBarPage() end
local function guard(context)
    check(not InCombatLockdown(), "Leave combat first; nothing changed.")
    check(not GetCursorInfo(), "Put down the item/spell on your cursor first; nothing changed.")
    if context then
        check(classID() == context.class, "This profile is for " .. className(context.class) .. "; nothing changed.")
        if context.spec then
            check(specID() == context.spec, "Select " .. (context.specName or tostring(context.spec)) .. " first; nothing changed.")
        end
        if context.blockedWhileStealthed then
            check(not IsStealthed(), "Leave Stealth first; nothing changed.")
        end
        if context.requiredPage then
            check(page() == context.requiredPage, "Switch the main bar to page " .. context.requiredPage .. " (normally Shift+1 for page 1), then try again.")
        end
    end
end
local function spellName(id)
    local n = C_Spell.GetSpellName(id)
    check(n and n ~= "", "Spell data not ready for ID " .. id .. "; try again after opening your spellbook.")
    return n
end
local function resolved(id)
    return C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(id) or id
end
local function learned(id)
    return C_SpellBook.IsSpellKnown(id) or C_SpellBook.IsSpellKnown(resolved(id))
end
A.api = {
    check = check, spellName = spellName, learned = learned, resolved = resolved,
    spell = function(id) return {kind="spell", id=resolved(id)} end,
    macro = function(name, body)
        return {kind="macro", character=true, name=name, icon=134400, body=body}
    end,
}

-- Modules register one profile per supported policy, with separate layouts.
-- Nothing is selected by class automatically; users choose the named profile.
function A.RegisterProfile(profile)
    check(type(profile) == "table" and type(profile.id) == "string" and profile.id:match("^[a-z][a-z0-9_-]*$"), "Invalid profile ID.")
    check(not A.profiles[profile.id], "Duplicate profile ID: " .. profile.id)
    check(type(profile.class) == "string" and type(profile.spec) == "number" and type(profile.label) == "string", "Profile needs class/spec/label.")
    check(type(profile.build) == "function" and type(profile.layouts) == "table", "Profile needs layouts and a plan builder.")
    A.profiles[profile.id] = profile
end
local function profileFor(id)
    local p = A.profiles[id]
    check(p, "No tested profile named '" .. tostring(id) .. "'. Use /tor list. Nothing changed.")
    return p
end
local function capacities()
    local m = Constants and Constants.MacroConsts
    return m and m.MAX_ACCOUNT_MACROS or 120, m and m.MAX_CHARACTER_MACROS or 30
end
local function macroRecord(index)
    local name, icon, body = GetMacroInfo(index)
    check(name and body, "Cannot read an existing macro; nothing will be overwritten.")
    local accountMax = capacities()
    return {kind="macro", name=name, icon=icon, body=body, character=index > accountMax}
end
local function findMacro(record)
    local a, c = capacities()
    local first, last = 1, a
    if record.character then first, last = a + 1, a + c end
    for i=first,last do
        local name, _, body = GetMacroInfo(i)
        if name == record.name and body == record.body then return i end
    end
end
local function preflightMacros(plans)
    local needed, names = 0, {}
    local accountMax, characterMax = capacities()
    for _, m in ipairs(plans) do
        check(type(m.name) == "string" and #m.name <= 16, "A macro name exceeds WoW's 16-byte limit.")
        check(not names[m.name], "Duplicate generated macro name: " .. m.name)
        names[m.name] = true
        check(type(m.body) == "string" and #m.body <= 255, "A localized macro exceeds WoW's 255-byte limit.")
        for i=1,accountMax+characterMax do
            local n, _, b = GetMacroInfo(i)
            if n == m.name then
                check(i > accountMax and b == m.body, "A different macro already uses '" .. m.name .. "'. Rename it before setup.")
            end
        end
        if not findMacro(m) then needed = needed + 1 end
    end
    local _, current = GetNumMacros()
    check(current + needed <= characterMax, "Need " .. needed .. " free character macro slots. Free some in /macro, then retry.")
end
local function validatePlan(plan)
    check(type(plan) == "table" and type(plan.rows) == "table" and #plan.rows > 0, "Profile produced no action slots.")
    local seen, declaredMacros = {}, {}
    for _, macro in ipairs(plan.macros or {}) do declaredMacros[macro] = true end
    for _, row in ipairs(plan.rows) do
        check(type(row.slot) == "number" and row.slot >= 1 and row.slot % 1 == 0 and not seen[row.slot], "Profile produced an invalid or duplicate action slot.")
        seen[row.slot] = true
        check(type(row.action) == "table" and (row.action.kind == "spell" or row.action.kind == "macro"), "Profiles may place only declared spells or macros.")
        if row.action.kind == "macro" then
            check(declaredMacros[row.action], "Profile references a macro it did not declare; nothing changed.")
        else
            check(type(row.action.id) == "number" and row.action.id > 0, "Profile references an invalid spell; nothing changed.")
        end
    end
end
local function checkBindings(profile, layout)
    local slots = profile.layouts[layout].altSlots
    if not slots then return end
    check(type(GetBindingAction) == "function" and type(GetBindingKey) == "function", "Cannot inspect Alt bindings; use the standard layout.")
    for _, slot in ipairs(slots) do
        local action = "ACTIONBUTTON" .. slot
        local keys = {GetBindingKey(action)}
        local hasBaseKey = false
        for _, key in ipairs(keys) do
            if not key:find("ALT-",1,true) then hasBaseKey = true end
        end
        check(hasBaseKey, "Action button " .. slot .. " needs a key without Alt for its ordinary action. Bind one in WoW or use the standard layout; no bindings were changed.")
        -- Numeric defaults must also be free, even if the user uses a second key.
        keys[#keys+1] = tostring(slot)
        for _, key in ipairs(keys) do
            -- The player's existing key may already include Shift or Ctrl.
            -- Also accept an Alt chord explicitly bound to the same button.
            if not key:find("ALT-",1,true) then
                local chord = "ALT-" .. key
                local bound = GetBindingAction(chord, true)
                check(not bound or bound == "" or bound == action,
                    chord .. " is bound to " .. tostring(_G["BINDING_NAME_" .. tostring(bound)] or bound) .. ". Clear that conflicting binding or use the standard layout; no bindings were changed.")
            end
        end
    end
end
local function migrationGuard()
    for _, old in ipairs({
        {db=AstraRogueSetupDB, command="/astrarogue undo"},
        {db=AstraSubSetupDB, command="/astrasub undo"},
    }) do
        local b = old.db and old.db.backup
        check(not b or b.state == "restored", "An earlier Astra addon still has a previous setup to restore. Run " .. old.command .. " in that addon before applying The One; its backup was not modified.")
    end
end
local function isAssisted(slot, id, subtype)
    return (C_ActionBar and C_ActionBar.IsAssistedCombatAction and C_ActionBar.IsAssistedCombatAction(slot)) or subtype == "assistedcombat" or id == "assistedcombat"
end
local function assistedSpell()
    local id = C_AssistedCombat and C_AssistedCombat.GetActionSpell and C_AssistedCombat.GetActionSpell()
    check(type(id) == "number", "Assisted Combat spell is unavailable; move that button to an untouched bar before setup.")
    return id
end
local function supportedStoredAction(kind)
    return kind == "spell" or kind == "item"
        or (kind == "equipmentset" and C_EquipmentSet and C_EquipmentSet.PickupEquipmentSet)
        or (kind == "summonpet" and C_PetJournal and C_PetJournal.PickupPet)
end
local function unsupportedText(slot, kind)
    return capitalized(slotText(slot)) .. " holds " .. kindText(kind) .. ", which Undo cannot put back. Move it to a bar this layout does not change, then try again."
end
local function checkExistingAction(slot)
    local kind, id, subtype = GetActionInfo(slot)
    if not kind then return end
    if isAssisted(slot,id,subtype) then assistedSpell(); return end
    check(kind == "macro" or supportedStoredAction(kind), unsupportedText(slot, kind))
end
local function capture(slot)
    local kind, id, subtype = GetActionInfo(slot)
    if not kind then return {kind="empty"} end
    if isAssisted(slot, id, subtype) then assistedSpell(); return {kind="assisted"} end
    if kind == "macro" then
        -- GetActionInfo can return the resolved spell, not the macro index.
        check(not InCombatLockdown(), "Combat started; saving the previous setup stopped before picking up an action.")
        PickupAction(slot)
        local cursorKind, index = GetCursorInfo()
        if cursorKind then
            local ok = false
            if not InCombatLockdown() then ok = pcall(PlaceAction,slot) end
            if not ok then
                local currentKind, currentIndex = GetCursorInfo()
                -- Retry a failed native placement only while the exact action
                -- we picked up remains on the cursor and combat has not begun.
                if currentKind == cursorKind and currentIndex == index and not InCombatLockdown() then
                    ok = pcall(PlaceAction,slot)
                end
                if not ok then
                    local guidance = GetCursorInfo() and "Preserve the action on your cursor and put it back in that slot out of combat." or "Inspect that slot out of combat before retrying."
                    error("Macro inspection stopped at slot " .. slot .. ". " .. guidance .. " If the previous setup was already saved, /tor undo remains available.",0)
                end
            end
        end
        check(cursorKind == "macro" and not GetCursorInfo(), "Could not safely save the previous macro in slot " .. slot)
        return macroRecord(index)
    end
    check(supportedStoredAction(kind), unsupportedText(slot, kind))
    return {kind=kind, id=id, subtype=subtype}
end
local function matches(slot, action)
    local kind, id, subtype = GetActionInfo(slot)
    if action.kind == "empty" then return not kind end
    if action.kind == "assisted" then return isAssisted(slot,id,subtype) end
    if action.kind == "macro" then
        if kind ~= "macro" then return false end
        local r = capture(slot)
        return r.name == action.name and r.body == action.body and r.character == action.character
    end
    if action.kind == "spell" then return kind == "spell" and (id == action.id or resolved(id) == resolved(action.id)) end
    return kind == action.kind and id == action.id
end
-- Items, battle pets and equipment sets can disappear after setup. During Undo
-- such a slot is cleared and reported instead of stopping Undo half-way.
local MAY_BE_GONE = {item=true, equipmentset=true, summonpet=true}
local function place(slot, action, allowGone)
    check(not InCombatLockdown(), "Combat started; try /tor undo when it ends.")
    check(not GetCursorInfo(), "Cursor is occupied; setup stopped to preserve it.")
    if action.kind == "empty" then
        if GetActionInfo(slot) then PickupAction(slot); ClearCursor() end
    else
        if action.kind == "assisted" then C_Spell.PickupSpell(assistedSpell())
        elseif action.kind == "spell" then C_Spell.PickupSpell(action.id)
        elseif action.kind == "macro" then
            local i = findMacro(action)
            check(i, "Saved macro '" .. action.name .. "' was removed or edited. Restore that macro before undo.")
            PickupMacro(i)
        elseif action.kind == "item" then
            C_Item.PickupItem(action.id)
            -- Toys are not in the bags; the toy box can still pick them up.
            if not GetCursorInfo() and PlayerHasToy(action.id) then C_ToyBox.PickupToyBoxItem(action.id) end
        elseif action.kind == "equipmentset" then C_EquipmentSet.PickupEquipmentSet(action.id)
        elseif action.kind == "summonpet" then C_PetJournal.PickupPet(action.id)
        else error("Cannot restore action type " .. tostring(action.kind),0) end
        if not GetCursorInfo() and allowGone and MAY_BE_GONE[action.kind] then
            if GetActionInfo(slot) then PickupAction(slot); ClearCursor() end
            check(not GetActionInfo(slot), "Could not clear " .. slotText(slot) .. ".")
            return false
        end
        check(GetCursorInfo(), "Could not pick up " .. kindText(action.kind) .. " for " .. slotText(slot) .. ".")
        PlaceAction(slot); ClearCursor()
    end
    check(matches(slot,action), "Could not confirm the new action in " .. slotText(slot) .. ".")
end
local function checkContext(backup)
    check(backup and backup.version == 1, "No previous setup is available to restore.")
    check(backup.state ~= "restored", "This previous setup has already been restored; nothing changed.")
    check(backup.class == classID() and backup.spec == specID() and backup.config == configID(), "Select the same class, specialization and talent loadout used for setup before undo.")
    if backup.loadout then
        local current = loadoutIdentity() or {}
        for _, field in ipairs({"savedConfig","starter"}) do
            if backup.loadout[field] ~= nil then
                check(current[field] == backup.loadout[field], "Select the same saved talent loadout and starter-build state used for setup before undo.")
            end
        end
    end
end
local function checkRestore(backup)
    checkContext(backup)
    for _, row in ipairs(backup.rows) do
        check(row.action.kind == "macro" or row.action.kind == "empty" or row.action.kind == "assisted" or supportedStoredAction(row.action.kind),
            "The saved setup has " .. kindText(row.action.kind) .. " in " .. slotText(row.slot) .. ", which this version cannot restore; nothing changed.")
        if row.action.kind == "macro" then check(findMacro(row.action), "Original macro '" .. row.action.name .. "' has changed. Restore it before undo.") end
    end
end
-- Only an explicit Undo may clear unavailable originals. Automatic rollback
-- must keep the backup open if it cannot put every original button back.
local function restore(backup, allowGone)
    checkRestore(backup)
    local gone = {}
    for _, row in ipairs(backup.rows) do
        -- A failed Apply may not have touched this slot. Keep an original
        -- item/pet/set button that is still there, even if pickup now fails.
        if not (MAY_BE_GONE[row.action.kind] and matches(row.slot,row.action)) then
            if place(row.slot,row.action,allowGone) == false then gone[#gone+1] = row end
        end
    end
    backup.state = "restored"
    return gone
end
local function storedText(action)
    if action.kind == "item" then
        return C_Item.GetItemNameByID(action.id) or ("item " .. tostring(action.id))
    elseif action.kind == "equipmentset" then
        local ok, name = pcall(C_EquipmentSet.GetEquipmentSetInfo, action.id)
        return ok and name or kindText(action.kind)
    end
    return kindText(action.kind)
end
-- Returns the full chat message and a short version for the panel's status line.
local function undoNote(gone)
    if #gone == 0 then
        local done = "Original bars restored. Generated macros kept."
        return done, done
    end
    local parts = {}
    for _, row in ipairs(gone) do parts[#parts+1] = slotText(row.slot) .. " (" .. storedText(row.action) .. ")" end
    return "Original bars restored, except " .. table.concat(parts, ", ") .. ": no longer available, so "
        .. (#gone == 1 and "that slot is" or "those slots are") .. " now empty. Generated macros kept.",
        "Original bars restored, except " .. #gone .. (#gone == 1 and " slot that is" or " slots that are") .. " now empty. See chat."
end
local function layoutNames(profile)
    local names = {}
    for name in pairs(profile.layouts) do names[#names+1] = name end
    table.sort(names, function(a,b)
        if a == "standard" then return b ~= "standard" end
        if b == "standard" then return false end
        return a < b
    end)
    return names
end
local function layoutFor(profile, layout)
    layout = layout or "standard"
    check(profile.layouts[layout], "Unknown layout '" .. layout .. "'. Available for this profile: " .. table.concat(layoutNames(profile), ", ") .. ".")
    return layout
end
local function describe(profile, layout, plan)
    say(profile.label .. " / " .. layout .. ": " .. profile.layouts[layout].description)
    for _, line in ipairs(plan.lines or {}) do say(line) end
    local bar2 = {}
    for _, row in ipairs(plan.rows) do
        if row.slot >= 61 and row.slot <= 72 then bar2[#bar2+1] = row end
    end
    if #bar2 > 0 then
        table.sort(bar2,function(a,b) return a.slot < b.slot end)
        local parts = {}
        for _, row in ipairs(bar2) do
            local name = row.action.kind == "macro" and row.action.name .. " (macro)" or spellName(row.action.id)
            parts[#parts+1] = (row.slot - 60) .. " " .. name
        end
        say("Action Bar 2 after Apply: " .. table.concat(parts, ", ") .. ". Keys you have bound to these slots will cast them.")
    end
end
local function preview(id, requestedLayout)
    local p = profileFor(id)
    local layout = layoutFor(p,requestedLayout)
    local plan = p.build(A.api,layout,false)
    validatePlan(plan)
    describe(p,layout,plan)
    say("Preview only: no bars, macros, bindings, gear or talents changed.")
end
-- Shared preflight for setup and the read-only panel/check command. Do not
-- initialize saved variables or inspect a macro by picking up an action here.
local function preparePlan(p, layout)
    guard(p); migrationGuard()
    local state = TheOneToRuleThemAllDB
    check(not state or state.version == 1, "Unknown saved-data version; nothing changed.")
    check(not state or not state.backup or state.backup.state == "restored", "A previous setup is already saved. Run /tor undo before another setup.")
    local plan = p.build(A.api,layout,true)
    validatePlan(plan)
    checkBindings(p,layout)
    preflightMacros(plan.macros or {})
    -- Reject unsupported slots before inspecting any macro through the cursor.
    for _, row in ipairs(plan.rows) do checkExistingAction(row.slot) end
    return plan
end
local function apply(id, requestedLayout)
    local p = profileFor(id)
    local layout = layoutFor(p,requestedLayout)
    local plan = preparePlan(p,layout)
    local state = db()
    local backup = {version=1,mode=id,layout=layout,class=p.class,spec=specID(),config=configID(),loadout=loadoutIdentity(),requiredPage=p.requiredPage,
        blockedWhileStealthed=p.blockedWhileStealthed,state="pending",rows={}}
    for _, row in ipairs(plan.rows) do backup.rows[#backup.rows+1] = {slot=row.slot,action=capture(row.slot)} end
    state.backup = backup
    local ok, problem = pcall(function()
        for _, m in ipairs(plan.macros or {}) do
            if not findMacro(m) then
                check(not InCombatLockdown(), "Combat started; macro creation stopped. Try /tor undo when it ends.")
                CreateMacro(m.name,m.icon,m.body,true)
                check(findMacro(m),"WoW did not create " .. m.name)
            end
        end
        for _, row in ipairs(plan.rows) do place(row.slot,row.action) end
    end)
    if not ok then
        local restored, restoreError = pcall(restore,backup)
        if restored then error(tostring(problem) .. ". Original bars restored; generated macros were kept.",0) end
        backup.state = "needs-undo"
        error(tostring(problem) .. ". Undo is still saved: run /tor undo after resolving: " .. tostring(restoreError),0)
    end
    backup.state = "applied"
    say("Setup verified: " .. #plan.rows .. " action slots. Existing keybindings preserved.")
    describe(p,layout,plan)
    if #(plan.skipped or {}) > 0 then say("Unlearned utilities left untouched: " .. table.concat(plan.skipped,", ")) end
    say("/tor undo restores your previous setup. Generated macros are kept. Enable Action Bar 2 if hidden; /reload saves your previous setup to disk.")
end
local function listProfiles()
    local ids = {}; for id in pairs(A.profiles) do ids[#ids+1]=id end; table.sort(ids)
    local matched = false
    for _, id in ipairs(ids) do
        local p = A.profiles[id]
        say(id .. " - " .. p.label .. " (" .. className(p.class) .. "; " .. table.concat(layoutNames(p), "/") .. ")")
        if p.class == classID() and p.spec == specID() then matched = true end
    end
    if not matched then say("No profile is included for your class and specialization yet.") end
end
local STATE_TEXT = {applied="active", restored="already restored", pending="not finished", ["needs-undo"]="needs Undo"}
local function status()
    say("The One To Rule Them All " .. A.version .. " - " .. className() .. ", " .. specText())
    local b = TheOneToRuleThemAllDB and TheOneToRuleThemAllDB.backup
    if b then say("Previous setup from " .. tostring(b.mode) .. " (" .. tostring(b.layout) .. "): " .. (STATE_TEXT[b.state] or tostring(b.state)) .. ". /tor undo needs the original specialization and talent loadout.")
    else say("No previous setup is saved. Use /tor list and /tor preview <profile> [standard|compact].") end
    if b and b.state ~= "restored" and not fullLoadoutIdentity(b) then say(LEGACY_UNDO) end
    say("Setup checks that the required abilities are learned. It does not check your full talent build, gear or set bonuses.")
end

-- Returns a fresh view of the current character without changing saved data,
-- the cursor, action slots, macros or keybindings. Applying still performs its
-- own preflight and transactional snapshot; this is not a placement test.
function A.Inspect(id, requestedLayout)
    local view = {version=A.version,class=classID(),className=className(),spec=specID(),profiles={},
        selectedId=id,layout=requestedLayout or "standard",canApply=false,canUndo=false}
    for profileId,p in pairs(A.profiles) do
        if p.class == view.class and p.spec == view.spec then
            local recommended = false
            if type(p.recommendedWhen) == "function" then
                local ok, value = pcall(p.recommendedWhen,A.api)
                recommended = ok and not not value
            end
            view.profiles[#view.profiles+1] = {id=profileId,label=p.label,specName=p.specName,
                layouts=p.layouts,evidence=p.evidence,recommended=recommended}
        end
    end
    table.sort(view.profiles,function(a,b)
        if a.recommended ~= b.recommended then return a.recommended end
        return a.id < b.id
    end)
    if not id then view.selectedId = view.profiles[1] and view.profiles[1].id end
    local ok, problem = pcall(function()
        check(view.selectedId, "No profile is included for your class and specialization yet.")
        local p = profileFor(view.selectedId)
        view.profile = p
        view.layout = layoutFor(p,requestedLayout)
        check(p.class == view.class and p.spec == view.spec, "The selected profile does not match your current class and specialization; nothing changed.")
        view.plan = p.build(A.api,view.layout,false)
        validatePlan(view.plan)
        preparePlan(p,view.layout)
    end)
    view.canApply = ok
    if not ok then view.applyReason = tostring(problem) end

    local state = TheOneToRuleThemAllDB
    local b = state and state.backup
    if b then view.backup = {mode=b.mode,layout=b.layout,state=b.state} end
    if b and b.state ~= "restored" and not fullLoadoutIdentity(b) then view.legacyUndo = LEGACY_UNDO end
    local undoOK, undoProblem = pcall(function()
        check(not state or state.version == 1, "Unknown saved-data version; nothing changed.")
        check(b, "No previous setup is available to restore.")
        checkContext(b)
        guard(b)
        checkRestore(b)
    end)
    view.canUndo = undoOK
    if not undoOK then view.undoReason = tostring(undoProblem) end
    return view
end

local function help()
    say("/tor opens the panel; /tor list; /tor status; /tor check [profile] [standard|compact]; /tor preview <profile> [standard|compact]; /tor apply <profile> [standard|compact]; /tor undo.")
    for id,p in pairs(A.profiles) do
        if p.class == classID() and p.spec == specID() and type(p.recommendedWhen) == "function" then
            local valid, compatible = pcall(p.recommendedWhen,A.api)
            if valid and compatible then
                say("Compatible starting profile: /tor " .. id .. "." .. (p.layouts.compact and " Add compact for the optional Alt layout." or ""))
            end
        end
    end
    say("Setup places abilities and standard WoW macros on your bars. You choose and press every combat action; talents, keybindings and gear are untouched.")
end

SLASH_THEONETORULETHEMALL1 = "/tor"
SLASH_THEONETORULETHEMALL2 = "/theone"
-- Returns ok, problem and, after Undo, a short result line for the panel.
function A.Execute(message)
    local args = {}; for word in (message or ""):lower():gmatch("%S+") do args[#args+1]=word end
    local note
    local ok, problem = pcall(function()
        local cmd = args[1]
        if not cmd or cmd == "ui" then
            check(#args<=1,"Use /tor ui.")
            if type(A.TogglePanel) == "function" then A.TogglePanel() else help() end
        elseif cmd == "help" then check(#args==1,"Use /tor help."); help()
        elseif cmd == "list" then check(#args==1,"Use /tor list."); listProfiles()
        elseif cmd == "status" then check(#args==1,"Use /tor status."); status()
        elseif cmd == "check" then
            check(#args<=3,"Use /tor check [profile] [standard|compact].")
            local view = A.Inspect(args[2],args[3])
            say("Check: " .. tostring(view.selectedId or "no matching profile") .. " / " .. view.layout)
            say(view.canApply and "Ready to apply. Each slot is checked again when you apply." or "Cannot apply: " .. view.applyReason)
            say(view.canUndo and "Undo ready: your previous setup can be restored." or "Undo unavailable: " .. view.undoReason)
            if view.legacyUndo then say(view.legacyUndo) end
            say("Check only: nothing was changed.")
        elseif cmd == "preview" or cmd == "apply" then
            check(args[2] and #args<=3,"Use /tor " .. cmd .. " <profile> [standard|compact].")
            if cmd == "preview" then preview(args[2],args[3]) else apply(args[2],args[3]) end
        elseif cmd == "undo" then
            check(#args==1,"Use /tor undo.")
            local state = TheOneToRuleThemAllDB
            check(not state or state.version == 1,"Unknown saved-data version; nothing changed.")
            local b = state and state.backup
            checkContext(b); guard(b)
            local full
            full, note = undoNote(restore(b,true))
            say(full)
        elseif cmd and A.profiles[cmd] then check(#args<=2,"Use /tor <profile> [standard|compact]."); apply(cmd,args[2])
        else help() end
    end)
    if not ok then say(tostring(problem)) end
    return ok, problem, note
end
SlashCmdList.THEONETORULETHEMALL = A.Execute
