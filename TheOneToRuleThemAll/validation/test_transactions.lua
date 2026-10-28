-- Recovery checks through shipped profiles, including interrupted writes.
return function(c)
    local test, expect, copy, equal = c.test,c.expect,c.copy,c.equal
    local function A() return c.addon() end
    local function S() return c.state() end
    local function apply() return A().Execute("standard-subtlety") end
    local function healer()
        S().class,S().spec="PRIEST",257
        return "standard-holy-priest mouseover"
    end
    local function original()
        S().macros[3]={name="Account",icon=1,body="/cast Original"}
        S().macros[121]={name="Character",icon=1,body="/cast Other"}
        S().slots[1]={kind="macro",id=3}; S().slots[2]={kind="macro",id=121}
        S().slots[3]={kind="item",id=900}; S().slots[61]={kind="spell",id=901}
        return copy(S().slots)
    end
    local function untouched(before)
        expect(equal(before,S().slots) and S().placements==0 and S().created==0)
        expect(S().bindingCalls==0 and TheOneToRuleThemAllDB==nil)
    end
    test("Apply and reload preserve both macro scopes and Undo restores originals",function()
        local before=original(); expect(apply()); c.reload()
        expect(A().Execute("undo") and equal(before,S().slots))
        expect(S().cursor==nil and S().bindingCalls==0)
    end)
    test("Undo finds an original macro after its index moves",function()
        original(); expect(apply()); S().macros[9],S().macros[3]=S().macros[3],nil
        expect(A().Execute("undo") and S().slots[1].id==9)
    end)
    test("Editing an original macro blocks Undo before writes",function()
        original(); expect(apply()); S().macros[3].body="/cast Changed"
        local before=copy(S().slots); local writes=S().placements
        expect(not A().Execute("undo") and equal(before,S().slots) and S().placements==writes)
    end)
    test("A second Apply cannot overwrite the saved original layout",function()
        expect(apply()); local before=copy(TheOneToRuleThemAllDB.backup)
        expect(not apply() and equal(before,TheOneToRuleThemAllDB.backup))
    end)
    test("Repeated Undo preserves later manual edits",function()
        expect(apply() and A().Execute("undo")); S().slots[1]={kind="item",id=999}
        local before=copy(S().slots)
        expect(not A().Execute("undo") and equal(before,S().slots))
    end)
    for _, change in ipairs({
        function() S().class="MAGE" end, function() S().spec=259 end,
        function() S().config=43 end, function() S().savedConfig=85 end,
        function() S().starter=true end,
    }) do
        test("Changed character or loadout cannot restore the wrong bars",function()
            expect(apply()); local before=copy(S().slots); local writes=S().placements
            change(); expect(not A().Execute("undo"))
            expect(equal(before,S().slots) and S().placements==writes)
        end)
    end
    test("Missing spell pickup rolls back the layout",function()
        S().slots[1]={kind="item",id=777}; local before=copy(S().slots); S().failPickup=53
        expect(not apply() and equal(before,S().slots))
        expect(TheOneToRuleThemAllDB.backup.state=="restored")
    end)
    test("Interrupted placement keeps Undo until the cursor is cleared",function()
        S().slots[8]={kind="item",id=777}; local before=copy(S().slots); S().failPlacement=8
        expect(not apply() and S().cursor and TheOneToRuleThemAllDB.backup.state=="needs-undo")
        ClearCursor(); expect(A().Execute("undo") and equal(before,S().slots))
    end)
    test("Combat during placement leaves recoverable originals",function()
        S().slots[1]={kind="item",id=777}; local before=copy(S().slots); local place=PlaceAction
        PlaceAction=function(slot) place(slot); if slot==2 then S().combat=true end end
        expect(not apply() and TheOneToRuleThemAllDB.backup.state=="needs-undo")
        PlaceAction=place; S().combat=false; ClearCursor()
        expect(A().Execute("undo") and equal(before,S().slots))
    end)
    test("Unsupported originals block Apply before anything is picked up",function()
        for _, kind in ipairs({"flyout","summonmount","outfit"}) do
            S().slots[1]={kind=kind,id=800}; local before=copy(S().slots)
            expect(not apply()); untouched(before)
        end
    end)
    test("Missing original item keeps the backup for a later retry",function()
        S().slots[1]={kind="item",id=777}; expect(apply()); S().gone[777]=true
        expect(A().Execute("undo") and S().slots[1]==nil)
        expect(TheOneToRuleThemAllDB.backup.state=="needs-undo")
        S().gone[777]=nil; expect(A().Execute("undo") and S().slots[1].id==777)
        expect(TheOneToRuleThemAllDB.backup.state=="restored")
    end)
    test("Undo restores toys, equipment sets and battle pets",function()
        S().slots[1]={kind="item",id=777}; S().toys[777]=true; S().gone[777]=true
        S().slots[2]={kind="equipmentset",id=5}; S().slots[3]={kind="summonpet",id=6}
        local before=copy(S().slots)
        expect(apply() and A().Execute("undo") and equal(before,S().slots))
    end)
    test("Assisted Combat restores identity after its displayed spell changes",function()
        S().slots[1]={kind="spell",id=S().assistedSpell,assisted=true}
        expect(apply()); S().assistedDynamic=54321
        expect(A().Execute("undo") and S().slots[1].assisted)
    end)
    test("Full macro storage blocks Mouseover without writes",function()
        local command=healer()
        for i=121,150 do S().macros[i]={name="Old"..i,icon=1,body="/cast Other"} end
        local before=copy(S().slots); expect(not A().Execute(command)); untouched(before)
    end)
    test("A macro name collision blocks Mouseover without edits",function()
        local command=healer(); local macro=A().Inspect("standard-holy-priest","mouseover").plan.macros[1]
        S().macros[121]={name=macro.name,icon=1,body="/cast Personal"}
        local before=copy(S().slots); expect(not A().Execute(command)); untouched(before)
        expect(S().macros[121].body=="/cast Personal")
    end)
    test("Long localized names cannot create oversized macros",function()
        local command=healer(); S().names[2061]=string.rep("X",256)
        local before=copy(S().slots); expect(not A().Execute(command)); untouched(before)
    end)
    test("Failed macro creation preserves original bars",function()
        local command=healer(); local before=copy(S().slots)
        CreateMacro=function() error("injected failure") end
        expect(not A().Execute(command) and equal(before,S().slots))
        expect(TheOneToRuleThemAllDB.backup.state=="restored")
    end)
    test("Repeated inspection failure preserves the original macro on the cursor",function()
        original(); local place=PlaceAction
        PlaceAction=function(slot)
            if slot==1 and S().cursor and S().cursor.kind=="macro" then error("injected failure") end
            place(slot)
        end
        expect(not apply() and S().cursor.kind=="macro" and S().cursor.id==3)
        expect(TheOneToRuleThemAllDB==nil or not TheOneToRuleThemAllDB.backup)
    end)
    test("Unknown saved-data versions do not overwrite player data",function()
        TheOneToRuleThemAllDB={version=999,marker="keep"}
        expect(not apply() and TheOneToRuleThemAllDB.marker=="keep" and S().placements==0)
    end)
    test("An older addon backup blocks Apply without editing it",function()
        AstraRogueSetupDB={backup={state="applied",marker="keep"}}
        local before=copy(S().slots); expect(not apply()); untouched(before)
        expect(AstraRogueSetupDB.backup.marker=="keep")
    end)
    test("A retired profile backup restores without its module",function()
        S().slots[1]={kind="spell",id=53}; S().slots[73]={kind="spell",id=53}
        TheOneToRuleThemAllDB={version=1,backup={version=1,mode="retired-profile",layout="retired",
            class="ROGUE",spec=261,config=42,state="applied",requiredPage=1,
            loadout={savedConfig=84,starter=false},rows={
                {slot=1,action={kind="item",id=777}},{slot=73,action={kind="empty"}},
            }}}
        c.reload(); expect(A().Inspect().canUndo and A().Execute("undo"))
        expect(S().slots[1].id==777 and S().slots[73]==nil)
    end)
end
