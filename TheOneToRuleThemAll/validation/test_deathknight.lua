-- Exercise the second real class through the same inspection, placement and
-- restore paths as Rogue. These are native-API mocks, not live casting tests.
return function(c)
    local test, expect, copy, equal = c.test, c.expect, c.copy, c.equal
    local profiles = {
        {id="blood-sanlayn", hero=433901, otherHero=439843},
        {id="blood-deathbringer", hero=439843, otherHero=433901},
    }
    local required = {206930,195182,49998,50842,43265,49028,48265,48707}
    local main = {206930,195182,49998,50842,43265,49028,47528,48265,48707}
    local function blood(profile)
        local S = c.state()
        S.class, S.localizedClass, S.spec = "DEATHKNIGHT", "Death Knight", 250
        S.unlearned[profile.otherHero] = true
        S.names[206930], S.names[433895] = "Heart Strike", "Vampiric Strike"
        S.names[433901], S.names[439843] = "Vampiric Strike talent", "Reaper's Mark"
        S.names[47528], S.names[49028] = "Mind Freeze", "Dancing Rune Weapon"
        return S, c.addon()
    end
    local function unchanged(before)
        local S = c.state()
        expect(equal(before.slots,S.slots), "Original action slots changed")
        expect(equal(before.macros,S.macros), "Existing macros changed")
        expect(equal(before.cursor,S.cursor), "Existing cursor changed")
        expect(equal(before.db,TheOneToRuleThemAllDB), "Saved backup changed")
        expect(before.placements==S.placements and before.created==S.created and before.bindingCalls==S.bindingCalls,
            "Unexpected native write")
    end
    local function capture()
        local S = c.state()
        return {slots=copy(S.slots),macros=copy(S.macros),cursor=copy(S.cursor),db=copy(TheOneToRuleThemAllDB),
            placements=S.placements,created=S.created,bindingCalls=S.bindingCalls}
    end

    for _, profile in ipairs(profiles) do
        test(profile.id.." selects the learned hero and inspects without writes",function()
            local S, A = blood(profile)
            S.macros[121]={name="Original",icon=1,body="/cast Original"}
            S.slots[1]={kind="macro",id=121}
            local before=capture()
            local view=A.Inspect()
            expect(view.selectedId==profile.id and view.canApply and #view.profiles==2)
            expect(view.layout=="standard" and view.plan and not view.canUndo)
            expect(A.Execute("preview "..profile.id))
            unchanged(before)
        end)
        test(profile.id.." preserves occupied cursor during blocked inspection",function()
            local S, A = blood(profile)
            S.cursor={kind="item",id=33447}
            local before=capture()
            local view=A.Inspect(profile.id)
            expect(not view.canApply and view.plan)
            expect(not A.Execute(profile.id))
            unchanged(before)
        end)
        test(profile.id.." rejects another class or specialization before writes",function()
            local S, A = blood(profile)
            S.slots[1]={kind="item",id=33447}
            local before=capture()
            S.class="ROGUE"
            expect(not A.Execute(profile.id)); unchanged(before)
            S.class, S.spec="DEATHKNIGHT",251
            expect(not A.Execute(profile.id)); unchanged(before)
            S.spec=252
            expect(not A.Execute(profile.id)); unchanged(before)
        end)
        test(profile.id.." rejects an unlearned hero talent before writes",function()
            local S, A = blood(profile)
            S.unlearned[profile.hero]=true
            S.unlearned[profile.otherHero]=nil
            local before=capture()
            local view=A.Inspect(profile.id)
            expect(not view.canApply and view.plan)
            expect(not A.Execute(profile.id)); unchanged(before)
        end)
        test(profile.id.." requires every core Blood action including DRW",function()
            local S, A = blood(profile)
            local before=capture()
            for _, id in ipairs(required) do
                S.unlearned[id]=true
                local ok=A.Execute(profile.id)
                expect(not ok, "Missing core spell accepted: "..id)
                unchanged(before)
                S.unlearned[id]=nil
            end
        end)
        test(profile.id.." installs standalone actions without macros or stealth pages",function()
            local S, A = blood(profile)
            for i=121,150 do S.macros[i]={name="Personal"..i,icon=1,body="/cast Personal"} end
            local preserved={10,11,12,13,25,37,49,60,73,74,75,76,77,78,79,80,81,82,83,84,85}
            for _, slot in ipairs(preserved) do S.slots[slot]={kind="item",id=90000+slot} end
            local before=copy(S.slots)
            expect(A.Execute(profile.id))
            for slot,id in ipairs(main) do
                expect(S.slots[slot].kind=="spell" and S.slots[slot].id==id, "Incorrect Blood main slot "..slot)
            end
            for _, slot in ipairs(preserved) do expect(equal(S.slots[slot],before[slot]),"Unrelated slot changed "..slot) end
            expect(S.created==0 and S.bindingCalls==0 and S.cursor==nil)
            expect(TheOneToRuleThemAllDB.backup.class=="DEATHKNIGHT" and TheOneToRuleThemAllDB.backup.spec==250)
            expect(TheOneToRuleThemAllDB.backup.mode==profile.id and TheOneToRuleThemAllDB.backup.state=="applied")
        end)
        test(profile.id.." restores mixed previous actions after addon reload",function()
            local S, A = blood(profile)
            S.macros[3]={name="AccountOriginal",icon=1,body="/cast Account ability"}
            S.macros[121]={name="CharacterOriginal",icon=2,body="/cast Character ability"}
            S.slots[1]={kind="macro",id=3}; S.slots[2]={kind="macro",id=121}
            S.slots[3]={kind="item",id=33447}; S.slots[4]={kind="equipmentset",id=77}
            S.slots[5]={kind="summonpet",id="BattlePet-TEST"}; S.slots[61]={kind="spell",id=999}
            S.slots[71]={kind="item",id=777}; S.slots[73]={kind="spell",id=888}
            local original=copy(S.slots)
            expect(A.Execute(profile.id))
            local persisted=copy(TheOneToRuleThemAllDB)
            TheOneToRuleThemAllDB=persisted
            c.reload()
            A=c.addon()
            expect(A.Inspect(profile.id).canUndo)
            expect(A.Execute("undo"))
            expect(equal(original,S.slots),"Reloaded Undo did not restore the original actions")
            expect(TheOneToRuleThemAllDB.backup.state=="restored")
        end)
        test(profile.id.." keeps optional unlearned utility in its original slots",function()
            local S, A = blood(profile)
            local optional={ [7]=47528,[61]=48792,[62]=55233,[63]=49039,[64]=49576,
                [65]=207167,[66]=212552,[67]=61999,[68]=1263569,[69]=48743,[70]=195292,[72]=56222 }
            S.unlearned[108199]=true
            for slot,id in pairs(optional) do
                S.unlearned[id]=true
                S.slots[slot]={kind="item",id=91000+slot}
            end
            local original=copy(S.slots)
            expect(A.Execute(profile.id))
            for slot,action in pairs(original) do expect(equal(action,S.slots[slot]),"Optional slot overwritten "..slot) end
            for _, row in ipairs(TheOneToRuleThemAllDB.backup.rows) do
                expect(not optional[row.slot],"Skipped optional slot entered Undo backup")
            end
            -- A later manual edit of an untouched slot must also survive Undo.
            S.slots[7]={kind="spell",id=123456}
            expect(A.Execute("undo"))
            expect(S.slots[7].id==123456)
        end)
        test(profile.id.." recovers original bars when Death Strike cannot be placed",function()
            local S, A = blood(profile)
            S.slots[1]={kind="item",id=555}; S.slots[61]={kind="spell",id=666}
            local original=copy(S.slots)
            S.failPickup=49998
            expect(not A.Execute(profile.id))
            expect(equal(original,S.slots) and S.cursor==nil)
            expect(TheOneToRuleThemAllDB.backup.state=="restored")
        end)
        test(profile.id.." blocks another class and changed-loadout restoration",function()
            local S, A = blood(profile)
            expect(A.Execute(profile.id))
            local before=capture()
            S.class, S.spec="ROGUE",261
            expect(not A.Execute("undo")); unchanged(before)
            S.class, S.spec="DEATHKNIGHT",250
            S.savedConfig=85
            expect(not A.Execute("undo")); unchanged(before)
            S.savedConfig=84
            expect(A.Execute("undo"))
        end)
        test(profile.id.." UI offers Standard and preserves existing setup until Apply",function()
            local S, A = blood(profile)
            local before=capture()
            expect(A.Execute("ui"))
            local panel=A.panel
            expect(panel and panel:IsShown() and panel.selectedId==profile.id)
            expect(panel.standardButton:IsEnabled() and not panel.compactButton:IsEnabled())
            expect(panel.applyButton:IsEnabled())
            unchanged(before)
            panel.applyButton:Click()
            expect(TheOneToRuleThemAllDB.backup.state=="applied" and panel.undoButton:IsEnabled())
            panel.undoButton:Click()
            expect(TheOneToRuleThemAllDB.backup.state=="restored")
            expect(S.created==0 and S.bindingCalls==0)
        end)
        test(profile.id.." rejects Compact without offering a nonexistent layout",function()
            local _, A=blood(profile)
            local before=capture()
            local view=A.Inspect(profile.id,"compact")
            expect(not view.canApply and view.applyReason:find("Unknown layout",1,true))
            expect(not A.Execute(profile.id.." compact"))
            expect(A.Execute("help"))
            expect(c.messageContains("Compatible starting profile: /tor "..profile.id))
            expect(not c.messageContains("Add compact"))
            unchanged(before)
        end)
    end

    test("San'layn installs base Heart Strike while Vampiric Strike is temporarily active",function()
        local S, A=blood(profiles[1])
        S.override[206930]=433895
        S.unlearned[206930]=true
        expect(A.Execute("blood-sanlayn"))
        expect(S.slots[1].kind=="spell" and S.slots[1].id==206930)
        S.override[206930]=nil
        expect(S.slots[1].id==206930,"Temporary proc spell was permanently installed")
        expect(A.Execute("undo"))
    end)
    test("San'layn spellbook proc availability does not substitute for the learned hero talent",function()
        local S, A=blood(profiles[1])
        S.unlearned[433901]=true
        S.override[206930]=433895
        local before=capture()
        expect(not A.Execute("blood-sanlayn")); unchanged(before)
    end)
    test("Deathbringer preserves base Marrowrend during Exterminate and gives Reaper a separate action",function()
        local S, A=blood(profiles[2])
        S.override[195182]=441424
        expect(A.Execute("blood-deathbringer"))
        expect(S.slots[2].id==195182 and S.slots[71].id==439843)
        expect(S.slots[6].id==49028 and S.slots[3].id==49998)
        expect(S.created==0)
        S.override[195182]=nil
        expect(S.slots[2].id==195182)
    end)
    test("San'layn leaves Deathbringer's utility slot untouched",function()
        local S, A=blood(profiles[1])
        S.slots[71]={kind="item",id=444}
        expect(A.Execute("blood-sanlayn"))
        expect(S.slots[71].kind=="item" and S.slots[71].id==444)
        for _, row in ipairs(TheOneToRuleThemAllDB.backup.rows) do expect(row.slot~=71) end
    end)
    test("Blood utility slot 68 falls back to learned Gorefiend's Grasp",function()
        local S, A=blood(profiles[1])
        S.unlearned[1263569]=true
        expect(A.Execute("blood-sanlayn"))
        expect(S.slots[68].id==108199)
    end)
end
