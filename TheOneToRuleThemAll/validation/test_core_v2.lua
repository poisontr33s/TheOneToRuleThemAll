return function(ctx)
    local test, expect, copy, equal = ctx.test,ctx.expect,ctx.copy,ctx.equal
    local function A() return ctx.addon() end
    local function S() return ctx.state() end
    local function untouched()
        expect(S().placements==0 and S().created==0 and S().bindingCalls==0)
    end

    test("setup and undo run with current specialization APIs and absent deprecated globals",function()
        expect(GetSpecialization==nil and GetSpecializationInfo==nil)
        expect(type(C_SpecializationInfo.GetSpecialization)=="function")
        expect(A().Execute("subburst") and A().Execute("undo"))
    end)
    test("direct Apply lists every affected Bar2 slot on one line with the key consequence",function()
        local ids={185313,121471,1784,1966,31224,5277,185311,2983,36554,2094,408,57934}
        for i,id in ipairs(ids) do S().names[id]="Utility"..string.char(64+i) end
        expect(A().Execute("subburst"))
        local line
        for _,m in ipairs(S().messages) do if m:find("Action Bar 2 after Apply:",1,true) then line=m end end
        expect(line,"Missing Action Bar 2 line")
        for i in ipairs(ids) do expect(line:find(i.." Utility"..string.char(64+i),1,true),"Missing utility slot "..i) end
        expect(line:find("Keys you have bound to these slots will cast them",1,true))
        expect(not ctx.messageContains("Evidence:") and not ctx.messageContains("SimC"))
        expect(not ctx.messageContains("fixed template") and not ctx.messageContains("Reference model only"))
    end)
    test("chat preview omits model details and reports only learned utility assignments",function()
        S().unlearned[2983]=true
        local before=copy(S().slots)
        expect(A().Execute("preview subburst"))
        expect(ctx.messageContains("7 Spell185311") and ctx.messageContains("9 Spell36554"))
        expect(not ctx.messageContains("Spell2983"))
        expect(not ctx.messageContains("Evidence:") and not ctx.messageContains("SimC"))
        expect(equal(before,S().slots) and TheOneToRuleThemAllDB==nil);untouched()
    end)

    test("inspection selects compatible recommended profile without initializing saved data",function()
        local view=A().Inspect()
        expect(view.selectedId=="subburst" and view.canApply and not view.canUndo)
        expect(#view.profiles==3 and #view.plan.rows==30)
        expect(TheOneToRuleThemAllDB==nil); untouched()
    end)
    test("inspection never picks up an existing macro or changes cursor",function()
        S().macros[1]={name="Personal",icon=134400,body="/cast My Spell"}
        S().slots[1]={kind="macro",id=1}
        local before=copy(S().slots)
        PickupAction=function() error("Read-only inspection picked up an action") end
        expect(A().Inspect("subburst").canApply)
        expect(equal(before,S().slots) and S().cursor==nil); untouched()
    end)
    test("inspection reports Alt conflicts before any saved-data or action changes",function()
        S().bindings["ALT-1"]="OTHER"
        local view=A().Inspect("subburst","compact")
        expect(not view.canApply and view.applyReason:find("ALT-1",1,true))
        expect(view.plan and TheOneToRuleThemAllDB==nil); untouched()
    end)
    test("inspection checks missing required hero and macro capacity",function()
        S().unlearned[441423]=true
        expect(not A().Inspect("subburst").canApply)
        S().unlearned[441423]=nil
        for i=121,150 do S().macros[i]={name="Other"..i,icon=1,body="/cast Other"} end
        local view=A().Inspect("subburst")
        expect(not view.canApply and view.applyReason:find("free character macro",1,true))
        expect(TheOneToRuleThemAllDB==nil); untouched()
    end)
    test("unsupported alt inspection never chooses a Rogue fallback",function()
        S().class="DEATHKNIGHT";S().spec=252
        local view=A().Inspect()
        expect(#view.profiles==0 and not view.selectedId and not view.canApply)
        local explicit=A().Inspect("subburst")
        expect(not explicit.canApply and not explicit.plan)
        expect(TheOneToRuleThemAllDB==nil); untouched()
    end)
    test("explicit invalid profile and layout remain blocked without silent substitution",function()
        local unknown=A().Inspect("unknown")
        expect(unknown.selectedId=="unknown" and not unknown.canApply)
        local invalid=A().Inspect("subburst","unknown")
        expect(not invalid.canApply and invalid.applyReason:find("Unknown layout",1,true))
        untouched()
    end)
    test("check command preserves saved data and original action slots",function()
        S().slots[1]={kind="item",id=123}
        local before=copy(S().slots)
        local ok=A().Execute("check subburst compact")
        expect(ok and equal(before,S().slots) and TheOneToRuleThemAllDB==nil)
        expect(ctx.messageContains("Check only: nothing was changed.")); untouched()
    end)
    test("repeated Undo does not overwrite later manual changes",function()
        A().Execute("subburst");A().Execute("undo")
        S().slots[1]={kind="item",id=999}
        local before=copy(S().slots);local placements=S().placements
        local ok,problem=A().Execute("undo")
        expect(not ok and problem:find("already been restored",1,true))
        expect(equal(before,S().slots) and placements==S().placements)
        expect(not A().Inspect().canUndo)
    end)
    test("saved loadout switch blocks Undo even when active config ID stays identical",function()
        A().Execute("subburst")
        local before=copy(S().slots);local placements=S().placements
        S().savedConfig=85
        expect(S().config==42 and not A().Inspect().canUndo)
        expect(not A().Execute("undo"))
        expect(equal(before,S().slots) and S().placements==placements)
        S().savedConfig=84
        expect(A().Inspect().canUndo and A().Execute("undo"))
    end)
    test("starter build switch blocks Undo with unchanged saved and active config IDs",function()
        A().Execute("subburst")
        local placements=S().placements;S().starter=true
        expect(not A().Inspect().canUndo and not A().Execute("undo"))
        expect(S().placements==placements)
        S().starter=false;expect(A().Execute("undo"))
    end)
    test("nil saved loadout is distinguished from a later selected saved loadout",function()
        S().savedConfig=nil;A().Execute("subburst")
        expect(TheOneToRuleThemAllDB.backup.loadout.savedConfig==false)
        S().savedConfig=84;expect(not A().Inspect().canUndo)
        S().savedConfig=nil;expect(A().Execute("undo"))
    end)
    test("legacy 0.1 snapshot remains recoverable with an explicit identity limitation",function()
        A().Execute("subburst")
        TheOneToRuleThemAllDB.backup.loadout=nil
        local before=copy(TheOneToRuleThemAllDB)
        local view=A().Inspect()
        expect(view.canUndo and type(view.legacyUndo)=="string")
        expect(equal(before,TheOneToRuleThemAllDB))
        expect(A().Execute("undo"))
    end)
    test("inspection blocks Undo after original macro has been edited",function()
        S().macros[1]={name="Original",icon=1,body="/cast Original"}
        S().slots[1]={kind="macro",id=1}
        A().Execute("subburst");S().macros[1].body="/cast Edited"
        local placements=S().placements;local before=copy(S().slots)
        local view=A().Inspect()
        expect(not view.canUndo and view.undoReason:find("has changed",1,true))
        expect(equal(before,S().slots) and S().placements==placements)
    end)
    test("inspection rejects unsupported saved schema without changing it",function()
        TheOneToRuleThemAllDB={version=999,sentinel="keep"}
        local before=copy(TheOneToRuleThemAllDB)
        local view=A().Inspect()
        expect(not view.canApply and not view.canUndo)
        expect(equal(before,TheOneToRuleThemAllDB));untouched()
    end)
    test("stale ready inspection cannot bypass combat guard on Execute",function()
        expect(A().Inspect().canApply)
        S().combat=true
        local ok,problem=A().Execute("apply subburst")
        expect(not ok and problem:find("combat",1,true))
        untouched()
    end)
end
