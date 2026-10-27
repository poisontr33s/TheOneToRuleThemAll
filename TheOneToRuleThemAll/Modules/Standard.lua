-- Published talent builds are references, not commands to change talents.
-- Every action remains a normal player-pressed WoW button.
local A = TheOneToRuleThemAll

local function gearText(definition)
    local gear = A.gearTemplate
    local lines = {gear.quality .. ".", "Gems: " .. gear.gems}
    for _, slot in ipairs({"head", "shoulders", "chest", "boots", "rings"}) do
        lines[#lines+1] = slot:gsub("^%l", string.upper) .. ": " .. gear[slot]
    end
    lines[#lines+1] = "Legs: " .. gear.legs[definition.primaryStat]
    lines[#lines+1] = "Fixed reference template. Equipment is not changed."
    return table.concat(lines, "\n")
end

local function activeSpell(api, entry)
    local candidates = {entry.id}
    for _, id in ipairs(entry.alternatives or {}) do candidates[#candidates+1] = id end
    for _, id in ipairs(candidates) do
        local replacement = api.resolved(id)
        local passive = C_Spell.IsSpellPassive and
            (C_Spell.IsSpellPassive(id) or C_Spell.IsSpellPassive(replacement))
        if api.learned(id) and not passive then
            -- Do not resolve a proc here. The native base button must survive
            -- the end of Shadow Dance, Metamorphosis, a hero proc, etc.
            return id
        end
    end
end

local function build(definition, api, layout, enforce)
    local nativeOK, native = pcall(A.CheckNativeContext, definition)
    if enforce then
        api.check(nativeOK, native)
        api.check(type(C_Spell.IsSpellPassive) == "function", "Spellbook data is unavailable; reopen your spellbook and try again.")
    end
    local first = nativeOK and native.first or 1
    local plan = {rows={},macros={},skipped={},lines={}}
    if not nativeOK then plan.lines[#plan.lines+1] = tostring(native) end
    for _, note in ipairs(definition.notes or {}) do plan.lines[#plan.lines+1] = note end

    local function add(entry, slot, position, mainButton)
        local id = activeSpell(api, entry)
        if not id then
            if enforce and entry.required then
                api.check(false, "Learn " .. entry.name .. " or its talent replacement before applying this profile; nothing changed.")
            end
            plan.skipped[#plan.skipped+1] = entry.name .. " (" .. position .. " unchanged)"
            return
        end
        local action = {kind="spell",id=id}
        if layout == "mouseover" and entry.helpful then
            local condition = entry.targetDead and "dead" or "nodead"
            action = api.macro("TOR" .. definition.spec .. "H" .. slot,
                "#showtooltip\n/cast [@mouseover,help," .. condition .. "] [] " .. api.spellName(id))
            action.displayText = api.spellName(id) .. " (mouseover)"
            plan.macros[#plan.macros+1] = action
        end
        plan.rows[#plan.rows+1] = {slot=slot,mainButton=mainButton,action=action}
    end

    for index, entry in ipairs(definition.main) do add(entry, first+index-1, "main slot " .. index, index) end
    for index, entry in ipairs(definition.utility) do add(entry, 60+index, "Bar 2 slot " .. index) end
    for index, entry in ipairs(definition.extra) do add(entry, 48+index, "Bar 3 slot " .. index) end

    local racialCount = 0
    for _, racial in ipairs(A.racialDefinitions) do
        local entry = {id=racial.ids[1],name=racial.name,alternatives={}}
        for index=2,#racial.ids do entry.alternatives[#entry.alternatives+1] = racial.ids[index] end
        if activeSpell(api, entry) then
            racialCount = racialCount + 1
            api.check(racialCount <= 3, "More racial abilities are available than this layout can place. Nothing changed.")
            add(entry,57+racialCount,"Bar 3 slot " .. (9+racialCount))
        end
    end
    table.sort(plan.rows, function(a,b) return a.slot < b.slot end)
    return plan
end

for _, definition in ipairs(A.standardDefinitions) do
    local layouts = {standard={description="Native spell buttons; fixed core, utility and racial positions"}}
    if definition.role == "HEALER" then
        layouts.mouseover = {description="Friendly spells use your mouseover when valid, otherwise their normal target"}
    end
    A.RegisterProfile({
        id=definition.id,class=definition.class,spec=definition.spec,specName=definition.specName,
        label="Method Mythic+ — " .. definition.specName,requiredPage=1,nativeMainBar=true,
        requiredForm=definition.requiredForm,blockedWhileStealthed=definition.blockedWhileStealthed,
        evidence={
            patch=definition.patch .. "; Method guide updated " .. definition.updated,
            gear=gearText(definition),
            tuning="Method Mythic+ talents; fixed button layout.",
            validation="WoW client testing pending.",
        },
        layouts=layouts,
        build=function(api,layout,enforce) return build(definition,api,layout,enforce) end,
    })
end
