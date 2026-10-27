-- Transaction and routing checks with mocked native APIs. These do not prove
-- that an action can be cast or that a Method build performs well in Retail.
return function(c)
    local test, expect, copy, equal = c.test, c.expect, c.copy, c.equal
    local function A() return c.addon() end
    local function S() return c.state() end
    local function definition(id)
        for _, entry in ipairs(A().standardDefinitions) do
            if entry.id == id then return entry end
        end
        error("Missing standard definition: " .. id)
    end
    local function entries(def)
        local result = {}
        for _, bar in ipairs({"main", "utility", "extra"}) do
            for index, entry in ipairs(def[bar]) do
                result[#result+1] = {bar=bar,index=index,entry=entry}
            end
        end
        return result
    end
    local function fixture(def, racial)
        local state = S()
        state.class, state.localizedClass, state.spec = def.class, def.class, def.spec
        state.known, state.passive, state.book = {}, {}, {}
        state.formSpell = def.requiredForm or 0
        state.formIndex = state.formSpell ~= 0 and 3 or 0
        -- Deliberately separate the form's list position from its native page.
        state.nativePage = state.formSpell ~= 0 and 9 or 1
        for _, item in ipairs(entries(def)) do
            state.known[item.entry.id] = true
            state.names[item.entry.id] = "Local " .. item.entry.name
        end
        if racial then state.known[racial] = true end
        C_SpellBook.IsSpellKnown = function(id) return state.known[id] == true end
        C_SpellBook.IsSpellKnownOrInSpellBook = function(id)
            return state.known[id] == true or state.book[id] == true
        end
        C_Spell.IsSpellPassive = function(id) return state.passive[id] == true end
        NUM_ACTIONBAR_BUTTONS = 12
        C_ActionBar.HasVehicleActionBar = function() return state.vehicle == true end
        C_ActionBar.HasOverrideActionBar = function() return state.overrideBar == true end
        C_ActionBar.HasTempShapeshiftActionBar = function() return state.temporaryForm == true end
        C_ActionBar.IsPossessBarVisible = function() return state.possess == true end
        C_ActionBar.HasBonusActionBar = function() return state.nativePage ~= 1 end
        C_ActionBar.GetBonusBarIndex = function() return state.nativePage end
        C_PetBattles = {IsInBattle=function() return state.petBattle == true end}
        GetShapeshiftForm = function() return state.formIndex end
        GetNumShapeshiftForms = function() return 4 end
        GetShapeshiftFormInfo = function(index)
            return 134400, index == state.formIndex, true,
                index == state.formIndex and state.formSpell or 999999
        end
        for button=1,9 do
            local buttonID = button
            _G["ActionButton" .. button] = {CalculateAction=function()
                return (state.nativePage-1)*12+buttonID
            end}
        end
        state.talentWrites = 0
        local function noTalentWrite()
            state.talentWrites = state.talentWrites+1
            error("A button setup attempted to change talents")
        end
        C_ClassTalents.ImportLoadout = noTalentWrite
        C_ClassTalents.CommitConfig = noTalentWrite
        C_ClassTalents.SetStarterBuildActive = noTalentWrite
        return state, A()
    end
    local function slotFor(item)
        if item.bar == "main" then return (S().nativePage-1)*12+item.index end
        return (item.bar == "utility" and 60 or 48)+item.index
    end
    local function seedBars()
        for slot=1,180 do S().slots[slot] = {kind="item",id=900000+slot} end
        return copy(S().slots)
    end
    local function capture()
        return {slots=copy(S().slots),macros=copy(S().macros),cursor=copy(S().cursor),
            db=copy(TheOneToRuleThemAllDB),placements=S().placements,created=S().created,
            bindingCalls=S().bindingCalls}
    end
    local function unchanged(before)
        expect(equal(before.slots,S().slots), "Action slots changed before approval")
        expect(equal(before.macros,S().macros), "Existing macros changed")
        expect(equal(before.cursor,S().cursor), "Cursor changed")
        expect(equal(before.db,TheOneToRuleThemAllDB), "Backup changed")
        expect(before.placements==S().placements and before.created==S().created, "Native writes occurred")
        expect(before.bindingCalls==S().bindingCalls and S().talentWrites==0, "Bindings or talents changed")
    end
    local function rowsBySlot(plan)
        local rows = {}
        for _, row in ipairs(plan.rows) do
            expect(not rows[row.slot], "A physical slot was assigned twice")
            rows[row.slot] = row
        end
        return rows
    end
    local function publishedSpec(code)
        local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local result = 0
        for bit=0,15 do
            local position = 8+bit
            local character = code:sub(math.floor(position/6)+1,math.floor(position/6)+1)
            local value = alphabet:find(character,1,true)
            if not value or character == "" then return nil end
            local binary = math.floor((value-1)/2^(position%6))%2
            result = result+binary*2^bit
        end
        return result
    end

    test("Standard catalog covers every Retail specialization with matching import headers", function()
        local specs, classes, ids = {}, {}, {}
        expect(#A().standardDefinitions == 40)
        for _, def in ipairs(A().standardDefinitions) do
            expect(not specs[def.spec] and not ids[def.id], "Duplicate standard specialization")
            specs[def.spec], ids[def.id], classes[def.class] = true, true, true
            expect(A().profiles[def.id] and type(A().profiles[def.id].build)=="function")
            expect(#def.main<=9 and #def.utility<=12 and #def.extra<=9)
            expect(def.guide:find("https://www.method.gg/guides/",1,true)==1)
            expect(type(def.patch)=="string" and def.updated:match("^%d%d%d%d%-%d%d%-%d%d$"))
            for _, build in ipairs(def.builds) do
                expect(publishedSpec(build.code)==def.spec, "Talent import belongs to another specialization: " .. def.id)
            end
        end
        local count = 0; for _ in pairs(classes) do count=count+1 end
        expect(count==13 and specs[1480], "A Retail class or Devourer is missing")
    end)
    test("Standard catalog excludes passive talent IDs in place of active buttons", function()
        local passives = {[1265867]=true,[1259003]=true,[1267016]=true,[462486]=true,[466932]=true}
        for _, def in ipairs(A().standardDefinitions) do
            for _, item in ipairs(entries(def)) do
                expect(not passives[item.entry.id], "Passive button in " .. def.id .. ": " .. item.entry.name)
                for _, id in ipairs(item.entry.alternatives or {}) do expect(not passives[id]) end
            end
        end
    end)

    local ids = {}
    for _, def in ipairs(A().standardDefinitions) do ids[#ids+1]=def.id end
    for _, id in ipairs(ids) do
        test(id .. " applies to the native page and restores all previous items", function()
            local def = definition(id)
            local state, addon = fixture(def,59752)
            local before = seedBars()
            local readonly = capture()
            local view = addon.Inspect(id)
            expect(view.canApply, view.applyReason)
            local rows = rowsBySlot(view.plan)
            for _, item in ipairs(entries(def)) do
                local row = rows[slotFor(item)]
                expect(row and row.action.kind=="spell" and row.action.id==item.entry.id,
                    "Wrong position or base spell: " .. item.entry.name)
                if item.bar=="main" then expect(row.mainButton==item.index) end
            end
            expect(rows[58] and rows[58].action.id==59752)
            expect(not rows[59] and not rows[60], "Unknown racials occupied a slot")
            unchanged(readonly)
            expect(addon.Execute("apply " .. id))
            expect(state.created==0 and state.bindingCalls==0 and state.talentWrites==0 and state.cursor==nil)
            expect(TheOneToRuleThemAllDB.backup.mode==id and TheOneToRuleThemAllDB.backup.state=="applied")
            for slot, old in pairs(before) do
                if rows[slot] then
                    expect(state.slots[slot].kind=="spell" and state.slots[slot].id==rows[slot].action.id)
                else
                    expect(equal(old,state.slots[slot]), "Unrelated page or reserved slot changed: " .. slot)
                end
            end
            expect(addon.Execute("undo"))
            expect(equal(before,state.slots) and TheOneToRuleThemAllDB.backup.state=="restored")
        end)
        test(id .. " refuses a missing required spell without changing anything", function()
            local def = definition(id)
            local state, addon = fixture(def)
            seedBars()
            local required
            for _, item in ipairs(entries(def)) do
                if item.entry.required then required=item.entry; break end
            end
            expect(required, "A standard profile has no required core spell")
            state.known[required.id]=nil
            state.book[required.id]=true -- A spellbook listing is not a learned talent.
            for _, replacement in ipairs(required.alternatives or {}) do state.known[replacement]=nil end
            local before = capture()
            expect(not addon.Inspect(id).canApply)
            expect(not addon.Execute("apply " .. id))
            unchanged(before)
        end)
    end

    test("Missing optional spells keep their fixed positions and survive Undo edits", function()
        local def=definition("standard-elemental")
        local state, addon=fixture(def)
        local before=seedBars()
        local skipped={}
        for _, item in ipairs(entries(def)) do
            if not item.entry.required then
                state.known[item.entry.id]=nil
                for _, alternative in ipairs(item.entry.alternatives or {}) do state.known[alternative]=nil end
                skipped[slotFor(item)]=true
            end
        end
        expect(addon.Execute(def.id))
        for slot in pairs(skipped) do expect(equal(before[slot],state.slots[slot])) end
        for _, row in ipairs(TheOneToRuleThemAllDB.backup.rows) do
            expect(not skipped[row.slot], "An untouched optional position entered the backup")
        end
        local edited=next(skipped)
        state.slots[edited]={kind="item",id=1234567}
        expect(addon.Execute("undo"))
        before[edited]={kind="item",id=1234567}
        expect(equal(before,state.slots), "Undo reverted a slot the addon never changed")
    end)
    test("Choice alternatives use their existing position without moving later buttons", function()
        local def=definition("standard-elemental")
        local state, addon=fixture(def)
        local changed={}
        for _, item in ipairs(entries(def)) do
            local alternatives=item.entry.alternatives
            if alternatives and #alternatives>0 then
                state.known[item.entry.id]=nil
                state.known[alternatives[1]]=true
                changed[slotFor(item)]=alternatives[1]
            end
        end
        expect(next(changed))
        expect(addon.Execute(def.id))
        for slot, spell in pairs(changed) do expect(state.slots[slot].id==spell) end
        for _, item in ipairs(entries(def)) do
            local slot=slotFor(item)
            expect(state.slots[slot].id==(changed[slot] or item.entry.id))
        end
    end)
    test("Passive spellbook entries are skipped and missing passive checks refuse Apply", function()
        local def=definition("standard-elemental")
        local state, addon=fixture(def)
        local optional
        for _, item in ipairs(entries(def)) do
            if not item.entry.required and not item.entry.alternatives then optional=item; break end
        end
        expect(optional)
        local slot=slotFor(optional)
        state.slots[slot]={kind="item",id=800001}
        state.passive[optional.entry.id]=true
        expect(addon.Execute(def.id))
        expect(state.slots[slot].kind=="item" and state.slots[slot].id==800001)
        expect(addon.Execute("undo"))
        C_Spell.IsSpellPassive=nil
        local before=capture()
        expect(not addon.Execute(def.id))
        unchanged(before)
    end)

    for _, case in ipairs({
        {"standard-devastation",362969,1265872},
        {"standard-survival",186270,1262293},
        {"standard-restoration-shaman",5394,1267068},
    }) do
        test(case[1] .. " retains the native base while a temporary replacement is active", function()
            local def=definition(case[1])
            local state, addon=fixture(def)
            state.override[case[2]]=case[3]
            state.known[case[2]]=nil; state.known[case[3]]=true
            local expectedSlot
            for _, item in ipairs(entries(def)) do if item.entry.id==case[2] then expectedSlot=slotFor(item) end end
            expect(expectedSlot)
            expect(addon.Execute(def.id))
            expect(state.slots[expectedSlot].id==case[2], "A temporary replacement was installed permanently")
            state.override[case[2]]=nil; state.known[case[2]]=true; state.known[case[3]]=nil
            expect(state.slots[expectedSlot].id==case[2] and addon.Execute("undo"))
        end)
    end

    test("Brewmaster keeps Tiger Palm's slot when Press the Advantage replaces it with a passive", function()
        local def=definition("standard-brewmaster")
        local state,addon=fixture(def)
        local original=seedBars()
        local palmSlot
        for _,item in ipairs(entries(def)) do
            if item.entry.id==100780 then
                expect(not item.entry.required, "Tiger Palm must allow the Press the Advantage build")
                palmSlot=slotFor(item)
            end
        end
        expect(palmSlot)
        state.known[100780]=nil
        state.known[418359]=true
        state.override[100780]=418359
        state.passive[418359]=true
        expect(addon.Execute(def.id))
        expect(equal(original[palmSlot],state.slots[palmSlot]), "Passive replacement overwrote Tiger Palm's position")
        for _,item in ipairs(entries(def)) do
            local slot=slotFor(item)
            if slot~=palmSlot then
                expect(state.slots[slot].kind=="spell" and state.slots[slot].id==item.entry.id,
                    "Skipping Tiger Palm shifted " .. item.entry.name)
            end
        end
        for _,row in ipairs(TheOneToRuleThemAllDB.backup.rows) do
            expect(row.slot~=palmSlot, "The untouched Tiger Palm position entered the backup")
        end
        expect(addon.Execute("undo") and equal(original,state.slots))
    end)

    for _, id in ipairs(ids) do
        if definition(id).role=="HEALER" then
            test(id .. " mouseover changes only marked helpful spells and still restores bars", function()
                local def=definition(id)
                local state, addon=fixture(def,59752)
                local before=seedBars()
                local view=addon.Inspect(id,"mouseover")
                expect(view.canApply,view.applyReason)
                local rows=rowsBySlot(view.plan)
                local count=0
                for _, item in ipairs(entries(def)) do
                    local row=rows[slotFor(item)]
                    expect(row)
                    if item.entry.helpful then
                        count=count+1
                        local macro=row.action
                        expect(macro.kind=="macro" and #macro.name<=16 and #macro.body<=255)
                        local _, casts=macro.body:gsub("/cast","")
                        expect(casts==1 and macro.body:find("[@mouseover,help,",1,true))
                        expect(macro.body:find(state.names[item.entry.id],1,true),"Mouseover spell name was not localized")
                        expect(macro.body:find(item.entry.targetDead and "help,dead]" or "help,nodead]",1,true))
                        expect(not macro.body:find("/castsequence",1,true) and not macro.body:find("/run",1,true))
                    else
                        expect(row.action.kind=="spell" and row.action.id==item.entry.id,
                            "An unmarked spell was converted to a macro")
                    end
                end
                expect(count>0 and #view.plan.macros==count and rows[58].action.kind=="spell")
                expect(addon.Execute("apply " .. id .. " mouseover"))
                expect(state.created==count and state.bindingCalls==0 and state.talentWrites==0)
                expect(addon.Execute("undo") and equal(before,state.slots))
            end)
        end
    end
    test("Damage profiles reject the healer-only mouseover layout", function()
        local def=definition("standard-devastation")
        local _,addon=fixture(def)
        local before=capture()
        expect(not addon.Execute(def.id .. " mouseover"))
        unchanged(before)
    end)
    test("Racial selection uses learned abilities rather than the displayed race name", function()
        local def=definition("standard-devastation")
        local state,addon=fixture(def)
        state.race="UnknownRace"
        state.known[20572]=true -- One known Blood Fury variant.
        state.known[58984]=true -- A second runtime-known racial, e.g. a borrowed ability.
        local view=addon.Inspect(def.id)
        expect(view.canApply,view.applyReason)
        local found={}
        for _,row in ipairs(view.plan.rows) do
            if row.slot>=58 and row.slot<=60 then found[row.action.id]=true end
        end
        expect(found[20572] and found[58984])
        local count=0; for _ in pairs(found) do count=count+1 end
        expect(count==2, "Unknown racial variants were treated as learned")
        state.known[20572]=nil; state.known[58984]=nil
        local empty=rowsBySlot(addon.Inspect(def.id).plan)
        expect(not empty[58] and not empty[59] and not empty[60])
    end)
    test("Too many learned racial families refuse the whole setup before writes", function()
        local def=definition("standard-devastation")
        local state,addon=fixture(def)
        for _,id in ipairs({59752,20572,20594,58984}) do state.known[id]=true end
        seedBars(); local before=capture()
        expect(not addon.Execute(def.id))
        unchanged(before)
    end)
    test("Undo requires the same native form page after a successful standard Apply", function()
        local def=definition("standard-feral")
        local state,addon=fixture(def)
        local original=seedBars()
        expect(addon.Execute(def.id))
        local savedPage,savedForm,savedIndex=state.nativePage,state.formSpell,state.formIndex
        state.nativePage,state.formSpell,state.formIndex=1,0,0
        local before=capture()
        expect(not addon.Execute("undo")); unchanged(before)
        state.nativePage,state.formSpell,state.formIndex=savedPage,savedForm,savedIndex
        expect(addon.Execute("undo") and equal(original,state.slots))
    end)
    test("A preview cannot bypass a later combat or native-page change", function()
        local def=definition("standard-devastation")
        local state,addon=fixture(def)
        expect(addon.Inspect(def.id).canApply)
        state.combat=true
        local before=capture()
        expect(not addon.Execute(def.id)); unchanged(before)
        state.combat=false; state.vehicle=true
        before=capture()
        expect(not addon.Execute(def.id)); unchanged(before)
    end)
    test("Standard registration preserves the existing custom Rogue selection and layout", function()
        local addon=A()
        expect(addon.Inspect().selectedId=="subburst")
        expect(addon.Inspect("subburst","compact").canApply)
        local before=copy(addon.profiles.subburst)
        expect(addon.Execute("subburst"))
        expect(TheOneToRuleThemAllDB.backup.mode=="subburst" and S().slots[73])
        expect(S().created>0 and equal(before,addon.profiles.subburst))
        expect(addon.Execute("undo"))
    end)
    test("Standard registration preserves the existing custom Blood selection", function()
        S().class,S().spec="DEATHKNIGHT",250
        S().unlearned[439843]=true
        expect(A().Inspect().selectedId=="blood-sanlayn")
        expect(A().Execute("blood-sanlayn"))
        expect(TheOneToRuleThemAllDB.backup.mode=="blood-sanlayn" and not S().slots[73])
        expect(S().created==0 and A().Execute("undo"))
    end)
end
