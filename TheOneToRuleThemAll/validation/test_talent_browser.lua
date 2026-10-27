-- These tests exercise the real browser callbacks with native-widget mocks.
-- They check byte preservation and absence of writes, not talent performance.
return function(c)
    local test, expect, copy, equal = c.test, c.expect, c.copy, c.equal
    local function references()
        local entries = {
            {id="standard-subtlety",class="ROGUE",spec=261,specName="Subtlety",
                guide="https://www.method.gg/guides/subtlety-rogue/talents",
                patch="test patch",updated="test date",builds={
                    {label="Raid reference",content="raid",hero="Deathstalker",code="CraidFixture/+=="},
                    {label="Mythic+ reference",content="dungeon",hero="Deathstalker",
                        code="Cfixture/+" .. string.rep("Ab9/+", 80) .. "=="},
                    {label="Mythic+ alternative",content="dungeon",hero="Trickster",code="CsecondFixture/+=="},
                }},
            {id="standard-assassination",class="ROGUE",spec=259,specName="Assassination",
                guide="https://www.method.gg/guides/assassination-rogue/talents",
                builds={{label="Assassination reference",content="dungeon",code="CotherSpecFixture/+=="}}},
        }
        c.addon().standardDefinitions = entries
        return entries
    end
    local function baseline()
        local S = c.state()
        return {slots=copy(S.slots),macros=copy(S.macros),cursor=copy(S.cursor),
            created=S.created,placements=S.placements,bindingCalls=S.bindingCalls,
            db=copy(TheOneToRuleThemAllDB),config=S.config,savedConfig=S.savedConfig}
    end
    local function unchanged(before)
        local S = c.state()
        expect(equal(before.slots,S.slots),"Talent browser changed action slots")
        expect(equal(before.macros,S.macros),"Talent browser changed macros")
        expect(equal(before.cursor,S.cursor),"Talent browser changed the cursor")
        expect(before.created==S.created and before.placements==S.placements,"Talent browser wrote a layout")
        expect(before.bindingCalls==S.bindingCalls,"Talent browser changed bindings")
        expect(equal(before.db,TheOneToRuleThemAllDB),"Talent browser changed saved data")
        expect(before.config==S.config and before.savedConfig==S.savedConfig,"Talent browser changed loadout identity")
    end
    test("Talent browser stays lazy and reuses its window after close",function()
        local A,S = c.addon(),c.state()
        expect(A.talentBrowser==nil and #S.frames==1)
        references(); local before=baseline()
        A.ShowTalentBuilds()
        local panel,count=A.talentBrowser,#S.frames
        expect(panel:IsShown() and panel:IsEventRegistered("PLAYER_TALENT_UPDATE"))
        panel.closeButton:Click()
        expect(not panel:IsShown() and not next(panel.events))
        A.ShowTalentBuilds()
        expect(A.talentBrowser==panel and #S.frames==count and panel:IsShown())
        unchanged(before)
    end)
    test("Method Mythic+ codes can be copied without any action or talent writes",function()
        local A,S = c.addon(),c.state()
        local entries=references()
        S.slots[1]={kind="item",id=123}; S.cursor={kind="item",id=456}
        TheOneToRuleThemAllDB={playerNote="keep this"}
        local before=baseline()
        local function forbidden() error("A reference browser attempted a write") end
        A.Execute=forbidden
        C_ClassTalents.ImportLoadout=forbidden
        C_ClassTalents.CommitConfig=forbidden
        C_ClassTalents.SetStarterBuildActive=forbidden
        local previousTraits=C_Traits
        C_Traits={PurchaseRank=forbidden,RefundRank=forbidden,CommitConfig=forbidden,ResetTree=forbidden}
        local ok,err=pcall(function()
            A.ShowTalentBuilds("standard-subtlety")
            local panel=A.talentBrowser
            expect(panel.reference==entries[1] and panel.codeBox:GetText()==entries[1].builds[2].code)
            panel.selectButton:Click()
            expect(panel.codeBox.focused and panel.codeBox.highlighted[1]==0)
            panel.nextButton:Click(); panel.previousButton:Click()
            expect(panel.codeBox:GetText()==entries[1].builds[2].code)
            S.dispatchUIEvent("PLAYER_TALENT_UPDATE")
            panel.closeButton:Click()
            unchanged(before)
        end)
        C_Traits=previousTraits
        expect(ok,err)
    end)
    test("Mythic+ selector skips raid and preserves published order, codes and source details",function()
        local A=c.addon(); local entries=references()
        A.ShowTalentBuilds(entries[1].id)
        local panel=A.talentBrowser
        expect(panel.codeBox:GetText()==entries[1].builds[2].code)
        expect(#panel.builds==2 and panel.builds[1]==entries[1].builds[2])
        expect(panel.builds[2]==entries[1].builds[3])
        expect(panel.sourceBox:GetText()==entries[1].guide)
        local metadata=panel.metadataText:GetText()
        for _,text in ipairs({"Deathstalker","Mythic+","test patch","test date"}) do
            expect(metadata:find(text,1,true),"Missing provenance: " .. text)
        end
        expect(panel.hint:GetText():find("Ctrl+C",1,true) and panel.hint:GetText():find("import",1,true))
        panel.nextButton:Click()
        expect(panel.codeBox:GetText()==entries[1].builds[3].code)
        expect(panel.metadataText:GetText():find("Trickster",1,true))
        panel.nextButton:Click()
        expect(panel.codeBox:GetText()==entries[1].builds[2].code)
        panel.previousButton:Click()
        expect(panel.codeBox:GetText()==entries[1].builds[3].code)
    end)
    test("Typing cannot corrupt a displayed import code or its guide address",function()
        local A=c.addon(); local entries=references(); local before=baseline()
        A.ShowTalentBuilds()
        local panel=A.talentBrowser
        panel.codeBox:SetText("edited code")
        panel.sourceBox:SetText("edited address")
        expect(panel.codeBox:GetText()==entries[1].builds[2].code)
        expect(panel.sourceBox:GetText()==entries[1].guide)
        panel.sourceBox:SetFocus()
        expect(panel.sourceBox.highlighted[1]==0)
        panel.sourceBox:GetScript("OnEscapePressed")(panel.sourceBox)
        expect(not panel.sourceBox.focused)
        unchanged(before)
    end)
    test("Only nonempty published codes enter the build selector",function()
        local A=c.addon(); local entries=references()
        local valid=entries[1].builds[3]
        entries[1].builds={{content="dungeon"},{content="dungeon",code=""},{content="dungeon",code=" \n\t"},{content="dungeon",code=123},valid}
        A.ShowTalentBuilds()
        local panel=A.talentBrowser
        expect(#panel.builds==1 and panel.codeBox:GetText()==valid.code)
        expect(not panel.nextButton:IsEnabled() and not panel.previousButton:IsEnabled())
        expect(panel.selectButton:IsEnabled())
    end)
    test("A raid-only source leaves a link without substituting a raid code",function()
        local A=c.addon(); local entries=references(); entries[1].builds={entries[1].builds[1]}
        A.ShowTalentBuilds()
        local panel=A.talentBrowser
        expect(panel.codeBox:GetText()=="" and panel.sourceBox:GetText()==entries[1].guide)
        expect(not panel.selectButton:IsEnabled() and not panel.nextButton:IsEnabled())
        expect(panel.buildText:GetText():find("No Method Mythic+ code",1,true))
        panel.sourceBox:SetFocus(); expect(panel.sourceBox.highlighted[1]==0)
        A.standardDefinitions=nil
        panel:Refresh()
        expect(panel.codeBox:GetText()=="" and panel.sourceBox:GetText()=="")
        expect(not A.HasTalentReference() and not panel.selectButton:IsEnabled())
    end)
    test("Spec changes replace stale references without importing the new build",function()
        local A,S=c.addon(),c.state(); local entries=references(); local before=baseline()
        A.ShowTalentBuilds("standard-subtlety")
        local panel=A.talentBrowser
        panel.nextButton:Click(); S.spec=259
        S.dispatchUIEvent("PLAYER_SPECIALIZATION_CHANGED","party1")
        expect(panel.codeBox:GetText()==entries[1].builds[3].code)
        S.dispatchUIEvent("PLAYER_SPECIALIZATION_CHANGED","player")
        expect(panel.codeBox:GetText()==entries[2].builds[1].code and panel.profileId==nil)
        S.class="MAGE"; S.spec=62
        S.dispatchUIEvent("PLAYER_SPECIALIZATION_CHANGED","player")
        expect(panel.codeBox:GetText()=="" and panel.sourceBox:GetText()=="")
        unchanged(before)
    end)
    test("An explicit unknown or other-spec profile cannot show the wrong reference",function()
        local A=c.addon(); local entries=references()
        A.ShowTalentBuilds(entries[1].id)
        expect(A.talentBrowser.codeBox:GetText()~="")
        A.ShowTalentBuilds("missing-profile")
        expect(A.talentBrowser.codeBox:GetText()=="" and not A.HasTalentReference("missing-profile"))
        A.ShowTalentBuilds("standard-assassination")
        expect(A.talentBrowser.codeBox:GetText()=="" and not A.HasTalentReference("standard-assassination"))
    end)
    test("Talent references can be read in combat without applying a layout",function()
        local A,S=c.addon(),c.state(); references(); S.combat=true
        local before=baseline()
        A.ShowTalentBuilds()
        A.talentBrowser.nextButton:Click(); A.talentBrowser.selectButton:Click()
        expect(A.talentBrowser:IsShown() and A.talentBrowser.codeBox.focused)
        unchanged(before)
    end)
    test("Bar3 preview shows the real bound keys and local ability names",function()
        local A,S=c.addon(),c.state()
        S.names[999001]="Local extra ability"; S.names[999002]="Local racial"
        S.bindingKeys.MULTIACTIONBAR2BUTTON1={"F9"}
        S.bindingKeys.MULTIACTIONBAR2BUTTON10={"CTRL-R"}
        local inspect=A.Inspect
        A.Inspect=function(...)
            local snapshot=inspect(...)
            snapshot.plan.rows[#snapshot.plan.rows+1]={slot=49,action={kind="spell",id=999001}}
            snapshot.plan.rows[#snapshot.plan.rows+1]={slot=58,action={kind="spell",id=999002}}
            return snapshot
        end
        local before=baseline(); A.TogglePanel()
        local text=A.panel.previewText:GetText()
        local bar3=text:match("Action Bar 3(.-)Using this layout")
        expect(bar3 and bar3:find("Slot 1   Local extra ability",1,true))
        expect(bar3:find("Slot 10   Local racial",1,true))
        expect(bar3:find("Keys: F9",1,true) and bar3:find("Keys: Ctrl+R",1,true))
        expect(text:find("Action Bar 3: slots 1, 10",1,true))
        unchanged(before)
    end)
    test("Native form rows keep main-button labels and refresh when the form changes",function()
        local A,S=c.addon(),c.state()
        S.bindingKeys.ACTIONBUTTON1={"Q"}; S.names[999003]="Local form attack"
        local inspect=A.Inspect
        A.Inspect=function(...)
            local snapshot=inspect(...)
            -- The real Standard engine supplies mainButton for the active
            -- native form. This fixture isolates how the UI displays it.
            snapshot.profile=copy(snapshot.profile)
            snapshot.profile.nativeMainBar=true
            snapshot.plan.rows={{slot=97,mainButton=1,action={kind="spell",id=999003}}}
            return snapshot
        end
        local before=baseline(); A.TogglePanel()
        local panel=A.panel
        local text=panel.previewText:GetText()
        expect(text:find("Slot 1   Local form attack",1,true) and text:find("Keys: Q",1,true))
        expect(text:find("selected form only",1,true) and not text:find("Stealth / Dance bar",1,true))
        S.names[999003]="Changed form attack"
        S.dispatchUIEvent("UPDATE_SHAPESHIFT_FORM")
        expect(panel.previewText:GetText():find("Slot 1   Changed form attack",1,true))
        unchanged(before)
    end)
end
