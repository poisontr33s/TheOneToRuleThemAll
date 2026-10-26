local realPrint = print
local addonDir = os.getenv("TOR_ADDON_DIR")
if not addonDir then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    addonDir = (source:match("^(.*)[/\\]") or ".") .. "/.."
end
local function loadAddon()
    for line in io.lines(addonDir .. "/TheOneToRuleThemAll.toc") do
        if line:match("%.lua$") then dofile(addonDir .. "/" .. line) end
    end
end
local S
local installUIMocks = dofile(addonDir .. "/validation/ui_mocks.lua")
local function copy(t)
    if type(t) ~= "table" then return t end
    local r = {}; for k,v in pairs(t) do r[k]=copy(v) end; return r
end
local function equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function expect(v,m) assert(v,m or "expectation failed") end
local function reset()
    S={slots={},macros={},cursor=nil,messages={},spec=261,config=42,class="ROGUE",
       savedConfig=84,starter=false,
       combat=false,stealth=false,page=1,missing={},unlearned={[200758]=true},override={},race="Nightborne",created=0,placements=0,bindingCalls=0,
       assistedSpell=1229376,assistedDynamic=12345,assistedVariant="identity",bindings={},bindingKeys={ACTIONBUTTON1={"1"},ACTIONBUTTON2={"2"}}}
    TheOneToRuleThemAllDB=nil; TheOneToRuleThemAll=nil; AstraRogueSetupDB=nil; AstraSubSetupDB=nil; SlashCmdList={}
    print=function(msg) S.messages[#S.messages+1]=msg end
    -- Most binding tests use the formatter fallback; focused tests install it.
    GetBindingText=nil
    -- Removed global aliases must stay absent: accidental reuse must fail.
    GetSpecialization=nil
    GetSpecializationInfo=nil
    C_SpecializationInfo={GetSpecialization=function() return 3 end,
      GetSpecializationInfo=function(index) assert(index==3);return S.spec end}
    UnitClass=function() return S.localizedClass or "Rogue",S.class end
    UnitRace=function() return S.race,S.race end
    InCombatLockdown=function() return S.combat end
    IsStealthed=function() return S.stealth end
    C_ClassTalents={GetActiveConfigID=function() return S.config end,
      GetLastSelectedSavedConfigID=function(spec) assert(spec==S.spec); return S.savedConfig end,
      GetStarterBuildActive=function() return S.starter end}
    GetBindingAction=function(key) return S.bindings[key] or "" end
    GetBindingKey=function(action) return table.unpack(S.bindingKeys[action] or {}) end
    C_ActionBar={
      GetActionBarPage=function() return S.page end,
      IsAssistedCombatAction=function(slot) return S.slots[slot] and S.slots[slot].assisted or false end
    }
    C_AssistedCombat={GetActionSpell=function() return S.assistedSpell end}
    Constants={MacroConsts={MAX_ACCOUNT_MACROS=120,MAX_CHARACTER_MACROS=30}}
    local names={[441423]="Coup de Grace",[319175]="Black Powder",[185313]="Shadow Dance",
      [121471]="Shadow Blades",[185438]="Shadowstrike",[53]="Backstab",
      [426591]="Goremaw's Bite",[260364]="Arcane Pulse",[200758]="Gloomblade",
      [452536]="Hand of Fate",[1247227]="Crimson Tempest",[385627]="Kingsbane",[360194]="Deathmark"}
    S.names=names
    C_Spell={
      GetSpellName=function(id) return S.names[id] or "Spell"..id end,
      GetOverrideSpell=function(id) return S.override[id] or id end,
      PickupSpell=function(id)
        if S.failPickup==id then return end
        S.cursor={kind="spell",id=id}
        if id==S.assistedSpell then S.cursor.assisted=true end
      end}
    C_SpellBook={
      IsSpellKnownOrInSpellBook=function(id) return not S.missing[id] end,
      IsSpellKnown=function(id) return not S.missing[id] and not S.unlearned[id] end
    }
    IsPlayerSpell=function(id) return not S.missing[id] and not S.unlearned[id] end
    C_Item={PickupItem=function(id) S.cursor={kind="item",id=id} end}
    PickupFlyout=nil
    C_EquipmentSet={PickupEquipmentSet=function(id) S.cursor={kind="equipmentset",id=id} end}
    C_PetJournal={PickupPet=function(id) S.cursor={kind="summonpet",id=id} end}
    GetMacroInfo=function(index)
      local m=S.macros[index]; if m then return m.name,m.icon,m.body end
    end
    GetNumMacros=function()
      local a,c=0,0; for i in pairs(S.macros) do if i<=120 then a=a+1 else c=c+1 end end
      return a,c
    end
    CreateMacro=function(name,icon,body,character)
      assert(character,"Macros must be character-scoped")
      for i=121,150 do
        if not S.macros[i] then
          S.macros[i]={name=name,icon=icon,body=body}; S.created=S.created+1; return i
        end
      end
      error("macro capacity")
    end
    PickupMacro=function(index)
      if S.macros[index] then S.cursor={kind="macro",id=index} end
    end
    GetActionInfo=function(slot)
      local a=S.slots[slot]; if not a then return end
      if a.kind=="macro" then return "macro",987654,"spell" end
      if a.assisted then
        if S.assistedVariant=="subtype" then return "spell",S.assistedDynamic,"assistedcombat" end
        if S.assistedVariant=="stringid" then return "spell","assistedcombat" end
        return "spell",S.assistedDynamic
      end
      return a.kind,a.id,a.subtype
    end
    PickupAction=function(slot)
      S.cursor=S.slots[slot]; S.slots[slot]=nil
    end
    GetCursorInfo=function()
      if S.cursor then return S.cursor.kind,S.cursor.id end
    end
    ClearCursor=function() S.cursor=nil end
    PlaceAction=function(slot)
      if S.failPlacement==slot and S.cursor and S.cursor.kind=="spell" and S.cursor.id==280719 then
        S.failPlacement=nil; error("injected placement failure")
      end
      S.placements=S.placements+1
      S.cursor,S.slots[slot]=S.slots[slot],S.cursor
    end
    for _,n in ipairs({"SetBinding","SetBindingClick","SaveBindings","LoadBindings"}) do
      _G[n]=function() S.bindingCalls=S.bindingCalls+1; error("Binding mutation is forbidden") end
    end
    installUIMocks(S)
    loadAddon()
end
local function command(s) SlashCmdList.THEONETORULETHEMALL(s) end
local function messageContains(s)
    for _,m in ipairs(S.messages) do if m:find(s,1,true) then return true end end
    return false
end
local function oldMacro(index,name)
    S.macros[index]={name=name or "Original",icon=134400,body="/cast Original Ability"}
end
local function actionCount()
    local n=0; for _ in pairs(S.slots) do n=n+1 end; return n
end
local total,failed=0,0
local function test(name,fn)
    total=total+1; reset()
    local ok,e=pcall(fn)
    if ok then realPrint("PASS "..name) else failed=failed+1; realPrint("FAIL "..name..": "..tostring(e)) end
end
test("Sub creates three localized character macros and reversible 30-slot plan",function()
    command("sub")
    expect(S.created==3 and actionCount()==30)
    expect(TheOneToRuleThemAllDB.backup.state=="applied" and #TheOneToRuleThemAllDB.backup.rows==30)
    expect(S.bindingCalls==0 and S.cursor==nil)
end)
test("Assa installs eight attacks plus Kick without requiring macro space",function()
    S.spec=259
    for i=121,150 do oldMacro(i,"Existing"..i) end
    command("assa")
    local ids={1329,51723,32645,1247227,703,1943,1766,385627,360194}
    for i,id in ipairs(ids) do expect(S.slots[i].id==id and S.slots[72+i].id==id) end
    expect(S.created==0 and actionCount()==30 and S.bindingCalls==0)
    expect(TheOneToRuleThemAllDB.backup.mode=="assa")
end)
test("normal and Stealth mirrors preserve unrelated pages and slots10-12",function()
    for _,i in ipairs({10,11,12,13,25,37,49,60,82,83,84,85}) do S.slots[i]={kind="spell",id=1000+i} end
    local prior=copy(S.slots); command("sub")
    for i=1,9 do expect(equal(S.slots[i],S.slots[72+i])) end
    for i,a in pairs(prior) do expect(equal(S.slots[i],a),"unrelated slot changed "..i) end
    expect(S.slots[7].id==1766 and S.slots[8].id==426591 and S.slots[9].id==1856)
end)
test("Sub macro bodies preserve contextual builder and deliberate burst",function()
    command("sub"); local bodies={}
    for _,m in pairs(S.macros) do bodies[m.name]=m.body; expect(#m.body<=255) end
    expect(bodies["TOR AoE"]=="#showtooltip\n/cast Coup de Grace\n/cast Black Powder")
    expect(bodies["TOR Burst"]=="#showtooltip\n/cast Shadow Dance\n/cast Shadow Blades")
    expect(bodies["TOR Builder"]=="#showtooltip\n/cast [bonusbar:1] Shadowstrike; Backstab")
    expect(S.slots[61].id==185313 and S.slots[62].id==121471)
end)
test("localized names rather than English literals are placed in macro text",function()
    S.names[53]="Attaque sournoise"; S.names[185438]="Frappe-ténèbres"
    S.names[441423]="Coup localisé"; S.names[319175]="Poudre noire"
    command("sub")
    expect(S.macros[123].body=="#showtooltip\n/cast [bonusbar:1] Frappe-ténèbres; Attaque sournoise")
    expect(S.macros[121].body=="#showtooltip\n/cast Coup localisé\n/cast Poudre noire")
end)
test("overlong localized macro aborts without writes",function()
    S.names[185438]=string.rep("X",240); command("sub")
    expect(S.created==0 and S.placements==0 and (not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup))
    expect(messageContains("255-byte"))
end)
test("learned Gloomblade replaces non-stealth builder name",function()
    S.unlearned[200758]=nil; S.missing[53]=true
    command("sub")
    expect(TheOneToRuleThemAllDB.backup.state=="applied")
    expect(S.macros[123].body=="#showtooltip\n/cast [bonusbar:1] Shadowstrike; Gloomblade")
end)
test("native Eviscerate base remains placed with temporary Coup override",function()
    S.override[196819]=441423; command("sub")
    expect(S.slots[3].id==196819 and S.slots[75].id==196819)
end)
test("unlearned Gloomblade spellbook entry does not replace Backstab",function()
    command("sub"); expect(S.macros[123].body:find("Backstab",1,true))
end)
test("sublite omits Goremaw and racial but keeps Feint on main8",function()
    command("sublite")
    for _,a in pairs(S.slots) do expect(a.id~=426591 and a.id~=260364) end
    expect(S.slots[8].id==1966 and S.slots[80].id==1966)
    expect(messageContains("Goremaw is not bound"))
end)
test("default Sub keeps Goremaw main8 and Feint on bar2",function()
    command("sub")
    expect(S.slots[8].id==426591 and S.slots[80].id==426591)
    expect(S.slots[64].id==1966 and messageContains("Seven routine class buttons"))
end)
test("default Sub rejects unlearned Goremaw before writes",function()
    S.unlearned[426591]=true; command("sub")
    expect(S.placements==0 and S.created==0 and (not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup))
    expect(messageContains("Missing Goremaw's Bite"))
end)
test("sublite permits missing Goremaw and undo restores original main8",function()
    S.missing[426591]=true; S.slots[8]={kind="item",id=333}
    local prior=copy(S.slots); command("sublite")
    expect(S.slots[8].id==1966 and TheOneToRuleThemAllDB.backup.mode=="sublite")
    command("undo"); expect(equal(prior,S.slots))
end)
test("Assa preserves Vanish Shiv and shared utilities outside rotation row",function()
    S.spec=259; command("assa")
    expect(S.slots[61].id==1856 and S.slots[62].id==5938)
    expect(S.slots[63].id==1784 and S.slots[64].id==1966)
    expect(S.slots[72].id==57934)
    expect(messageContains("Tea is not bound"))
end)
for _,mode in ipairs({"sub","sublite","assa"}) do
    test(mode.." undo restores empty spell item and both macro scopes",function()
        if mode=="assa" then S.spec=259 end
        oldMacro(3,"AccountOriginal"); oldMacro(121,"CharOriginal")
        S.slots[1]={kind="macro",id=3}; S.slots[2]={kind="macro",id=121}
        S.slots[3]={kind="item",id=33447}; S.slots[61]={kind="spell",id=1234}
        local prior=copy(S.slots); command(mode); command("undo")
        expect(equal(prior,S.slots) and TheOneToRuleThemAllDB.backup.state=="restored")
    end)
end
test("undo resolves original macro identity after index movement",function()
    oldMacro(121); S.slots[1]={kind="macro",id=121}; command("sub")
    local old=S.macros[121]; S.macros[121]=S.macros[124]; S.macros[124]=old
    command("undo")
    expect(S.slots[1].kind=="macro" and S.slots[1].id==124)
end)
for _,scenario in ipairs({
  {"combat",function() S.combat=true end,"Leave combat"},
  {"wrong spec",function() S.spec=259 end,"Select Subtlety"},
  {"wrong class",function() S.class="MAGE" end,"No matching tested module"},
  {"occupied cursor",function() S.cursor={kind="item",id=42} end,"Put down"},
  {"wrong page",function() S.page=2 end,"page 1"},
  {"Stealth",function() S.stealth=true end,"Leave Stealth"}
}) do
    test("guard refuses "..scenario[1],function()
        S.slots[1]={kind="spell",id=999}; scenario[2]()
        local before=copy(S.slots); local cursor=copy(S.cursor); command("sub")
        expect(equal(before,S.slots) and equal(cursor,S.cursor))
        expect(S.created==0 and S.placements==0 and messageContains(scenario[3]))
    end)
end
test("Assa rejects other spec and unavailable Fatebound root",function()
    command("assa"); expect(S.placements==0 and messageContains("Select Assassination"))
    S.spec=259; S.unlearned[452536]=true; command("assa")
    expect(S.placements==0 and messageContains("Missing Hand of Fate"))
end)
test("required learned talent rejects spellbook-only entry without writes",function()
    S.unlearned[441423]=true; command("sub")
    expect(S.created==0 and S.placements==0 and (not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup))
    expect(messageContains("Missing Coup de Grace"))
end)
test("Assa requires current Crimson Tempest generator ID",function()
    S.spec=259; S.missing[1247227]=true; command("assa")
    expect(S.created==0 and S.placements==0 and messageContains("Missing Crimson Tempest"))
end)
test("same-name unrelated macro collision causes zero writes",function()
    oldMacro(1,"TOR AoE"); command("sub")
    expect(S.created==0 and S.placements==0 and messageContains("different macro"))
end)
test("Sub refuses insufficient character macro space",function()
    for i=121,150 do oldMacro(i,"Existing"..i) end
    command("sub")
    expect(S.created==0 and S.placements==0 and messageContains("free character macro"))
end)
test("repeated setup and other mode cannot overwrite original snapshot",function()
    S.slots[1]={kind="spell",id=7000}; command("sub")
    local backup=TheOneToRuleThemAllDB.backup; local before=copy(S.slots)
    command("sub"); S.spec=259; command("assa")
    expect(TheOneToRuleThemAllDB.backup==backup and equal(S.slots,before))
    expect(S.created==3 and backup.rows[1].action.id==7000)
end)
test("failed spell pickup rolls back all prior writes",function()
    S.slots[1]={kind="spell",id=7000}; S.slots[2]={kind="item",id=4000}
    local prior=copy(S.slots); S.failPickup=280719; command("sub")
    expect(equal(prior,S.slots) and TheOneToRuleThemAllDB.backup.state=="restored")
    expect(messageContains("Original bars restored"))
end)
test("placement exception retains undo until cursor cleared",function()
    S.slots[1]={kind="spell",id=7000}; local prior=copy(S.slots)
    S.failPlacement=5; command("sub")
    expect(TheOneToRuleThemAllDB.backup.state=="needs-undo")
    expect(S.cursor and S.cursor.id==280719)
    ClearCursor(); command("undo"); expect(equal(prior,S.slots))
end)
test("undo rejects changed spec or talent loadout before writes",function()
    command("sub"); local before=copy(S.slots); local p=S.placements
    S.config=99; command("undo")
    expect(equal(before,S.slots) and p==S.placements)
    S.config=42; S.spec=259; command("undo")
    expect(equal(before,S.slots) and p==S.placements)
    expect(messageContains("same class, specialization and talent loadout"))
end)
test("unsupported existing action aborts before replacement",function()
    S.slots[3]={kind="unsupported",id=12}; local prior=copy(S.slots)
    command("sub")
    expect(equal(S.slots,prior) and S.created==0 and messageContains("unsupported action"))
end)
test("unlearned utility leaves existing slot untouched",function()
    S.unlearned[57934]=true; S.slots[72]={kind="spell",id=8000}
    command("sub")
    expect(S.slots[72].id==8000 and #TheOneToRuleThemAllDB.backup.rows==29)
end)
test("changed original macro blocks undo before overwrite",function()
    oldMacro(121); S.slots[1]={kind="macro",id=121}; command("sub")
    local before=copy(S.slots); local p=S.placements
    S.macros[121].body="/cast Changed"; command("undo")
    expect(equal(before,S.slots) and p==S.placements and messageContains("Original macro"))
end)
test("successful undo allows reusing generated macros and changing mode",function()
    command("sub"); command("undo"); command("sub")
    expect(S.created==3 and TheOneToRuleThemAllDB.backup.state=="applied")
    command("undo"); S.spec=259; command("assa")
    expect(S.created==3 and TheOneToRuleThemAllDB.backup.mode=="assa")
end)
test("learned spell query falls back to IsPlayerSpell",function()
    C_SpellBook.IsSpellKnown=nil; command("sub")
    expect(TheOneToRuleThemAllDB.backup.state=="applied")
end)
test("assisted combat restores identity despite changing display spell",function()
    S.slots[2]={kind="spell",id=S.assistedSpell,assisted=true}; command("sub")
    expect(TheOneToRuleThemAllDB.backup.rows[3].action.kind=="assisted")
    S.assistedDynamic=54321; command("undo")
    expect(S.slots[2].assisted and S.slots[2].id==S.assistedSpell)
end)
test("unavailable assisted identity aborts before replacement",function()
    S.slots[2]={kind="spell",id=S.assistedSpell,assisted=true}; S.assistedSpell=nil
    local before=copy(S.slots); command("sub")
    expect(equal(S.slots,before) and S.created==0 and S.placements==0)
    expect((not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup) and messageContains("Assisted Combat spell is unavailable"))
end)
test("unsupported flyout rejects setup without changing actions or creating macros",function()
    expect(PickupFlyout==nil)
    oldMacro(1,"ExistingAccountMacro")
    S.slots[1]={kind="macro",id=1};S.slots[61]={kind="flyout",id=123}
    local before=copy(S.slots)
    local ok,problem=TheOneToRuleThemAll.Execute("subburst")
    expect(not ok and problem:find("unsupported action 'flyout'",1,true))
    expect(equal(S.slots,before) and S.created==0 and S.placements==0 and S.cursor==nil)
    expect(not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup)
end)
for _,entry in ipairs({{"equipmentset",42},{"summonpet","BattlePet-0-000000123456"}}) do
    test("undo restores "..entry[1],function()
        S.slots[2]={kind=entry[1],id=entry[2]}; local before=copy(S.slots)
        command("sub"); command("undo"); expect(equal(S.slots,before))
    end)
end
test("independent fork never touches v1 saved backup",function()
    AstraSubSetupDB={sentinel="original-v1"}; local old=AstraSubSetupDB
    command("sub"); command("undo")
    expect(AstraSubSetupDB==old and old.sentinel=="original-v1")
end)

local function macroBodies()
    local bodies={}
    for _,m in pairs(S.macros) do bodies[m.name]=m.body end
    return bodies
end
local function slotBody(slot)
    local a=S.slots[slot]
    expect(a and a.kind=="macro", "Expected macro in slot "..slot)
    return S.macros[a.id].body
end
local function contains(text,fragment) return text and text:find(fragment,1,true)~=nil end

test("list and status make no action or macro writes",function()
    command("list"); command("status")
    expect(S.placements==0 and S.created==0 and S.bindingCalls==0)
    expect(#S.messages>0)
    expect(not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup)
end)
test("preview standard and compact are read only",function()
    S.slots[1]={kind="spell",id=777}; local before=copy(S.slots)
    command("preview sub"); command("preview sub compact")
    expect(equal(before,S.slots) and S.created==0 and S.placements==0)
    expect(not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup)
end)
test("unsupported class list and apply do not install rogue bars",function()
    S.class="MAGE"; S.spec=62; S.slots[1]={kind="spell",id=777}
    local before=copy(S.slots); command("list"); command("apply sub")
    expect(equal(before,S.slots) and S.created==0 and S.placements==0)
    expect(not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup)
end)
test("unknown profile rejects before writes",function()
    command("apply totally_unknown_profile")
    expect(S.placements==0 and S.created==0)
    expect(not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup)
end)
test("invalid layout rejects before writes",function()
    command("apply sub aggressive")
    expect(S.placements==0 and S.created==0)
end)
test("pending old Astra backup blocks apply without altering either backup",function()
    AstraRogueSetupDB={version=1,backup={state="applied",sentinel="prior"}}
    local before=copy(AstraRogueSetupDB); command("apply sub")
    expect(S.placements==0 and S.created==0 and equal(before,AstraRogueSetupDB))
    expect(messageContains("Astra"))
end)
test("restored old Astra snapshot permits independent install",function()
    AstraRogueSetupDB={version=1,backup={state="restored",sentinel="prior"}}
    local before=copy(AstraRogueSetupDB); command("apply sub")
    expect(TheOneToRuleThemAllDB.backup.state=="applied" and equal(before,AstraRogueSetupDB))
end)
test("compact Sub retains five offensive keys and dedicated immediate utilities",function()
    command("apply sub compact")
    expect(TheOneToRuleThemAllDB.backup.layout=="compact")
    expect(contains(slotBody(1),"Shadowstrike") and contains(slotBody(1),"Backstab"))
    expect(contains(slotBody(1),"mod:alt") and contains(slotBody(1),"Spell197835"))
    expect(contains(slotBody(2),"Black Powder") and contains(slotBody(2),"Coup de Grace"))
    expect(S.slots[3].id==280719 and contains(slotBody(4),"Shadow Dance"))
    expect(S.slots[5].id==426591 and S.slots[6].id==31224)
    expect(S.slots[7].id==1766 and S.slots[8].id==1966 and S.slots[9].id==1856)
    expect(S.slots[67].id==185311, "Vial remains on bar 2")
    for i=1,9 do expect(equal(S.slots[i],S.slots[72+i])) end
    expect(S.bindingCalls==0)
end)
test("compact SubLite excludes Goremaw and preserves Vanish escape",function()
    command("sublite compact")
    expect(TheOneToRuleThemAllDB.backup.mode=="sublite" and TheOneToRuleThemAllDB.backup.layout=="compact")
    for _,a in pairs(S.slots) do expect(a.id~=426591) end
    expect(S.slots[5].id==31224 and S.slots[6].id==185311)
    expect(S.slots[7].id==1766 and S.slots[8].id==1966 and S.slots[9].id==1856)
end)
test("compact Assa has six offensive keys and distinct cooldown buttons",function()
    S.spec=259; command("assa compact")
    expect(TheOneToRuleThemAllDB.backup.state=="applied")
    expect(contains(slotBody(1),"mod:alt") and contains(slotBody(1),"Spell1329") and contains(slotBody(1),"Spell51723"))
    expect(contains(slotBody(2),"Crimson Tempest") and contains(slotBody(2),"Spell32645"))
    expect(S.slots[3].id==703 and S.slots[4].id==1943)
    expect(S.slots[5].id==385627 and S.slots[6].id==360194 and S.slots[7].id==1766)
    expect(S.slots[8].id==1966 and S.slots[9].id==1856)
end)
test("Alt numeric binding conflict refuses compact without changing bindings",function()
    S.bindings["ALT-1"]="MULTIACTIONBAR1BUTTON1"; command("sub compact")
    expect(S.placements==0 and S.created==0 and S.bindingCalls==0)
    expect(messageContains("ALT-1"))
end)
test("Alt alternate key binding conflict also refuses compact",function()
    S.bindingKeys.ACTIONBUTTON1={"Q"}; S.bindings["ALT-Q"]="MULTIACTIONBAR2BUTTON2"
    command("sub compact")
    expect(S.placements==0 and S.created==0 and S.bindingCalls==0)
    expect(messageContains("ALT-Q"))
end)
test("Alt second alternate binding conflict is checked",function()
    S.bindingKeys.ACTIONBUTTON2={"2","E"}; S.bindings["ALT-E"]="JUMP"
    command("sub compact")
    expect(S.placements==0 and S.created==0 and messageContains("ALT-E"))
end)
test("standard profile remains available with conflicting Alt bindings",function()
    S.bindings["ALT-1"]="JUMP"; command("sub")
    expect(TheOneToRuleThemAllDB.backup.state=="applied")
end)
test("compact placement failure retains recoverable original bars",function()
    S.slots[3]={kind="item",id=555}; local before=copy(S.slots)
    S.failPlacement=3; command("sub compact")
    expect(TheOneToRuleThemAllDB.backup.state=="needs-undo")
    ClearCursor(); command("undo"); expect(equal(before,S.slots))
end)
test("normal to compact layout requires undo first",function()
    command("sub"); local before=copy(S.slots); local backup=TheOneToRuleThemAllDB.backup
    command("sub compact")
    expect(equal(before,S.slots) and TheOneToRuleThemAllDB.backup==backup)
    command("undo"); command("sub compact")
    expect(TheOneToRuleThemAllDB.backup.layout=="compact")
end)
test("all generated macro names and localized bodies fit native limits",function()
    command("sub compact")
    for _,m in pairs(S.macros) do expect(#m.name<=16 and #m.body<=255) end
    command("undo"); S.spec=259; command("assa compact")
    for _,m in pairs(S.macros) do expect(#m.name<=16 and #m.body<=255) end
end)
test("macro output never contains a timed or castsequence rotation",function()
    command("sub compact")
    for _,m in pairs(S.macros) do
        expect(not contains(m.body,"/run") and not contains(m.body,"/castsequence") and not contains(m.body,"/click"))
    end
end)

-- This intentionally interprets only the secure condition subset emitted by our
-- own macros. It checks branch order, not WoW's protected casting API or GCD.
local function castBranches(body,alt,bonus)
    local result={}
    for line in body:gmatch("[^\n]+") do
        local expression=line:match("^/cast%s+(.+)$")
        if expression then
            for branch in expression:gmatch("[^;]+") do
                branch=branch:match("^%s*(.-)%s*$")
                local conditions,name=branch:match("^%[([^%]]+)%]%s*(.+)$")
                local matches=true
                if conditions then
                    for condition in conditions:gmatch("[^,]+") do
                        if condition=="mod:alt" then matches=matches and alt
                        elseif condition=="nomod:alt" then matches=matches and not alt
                        elseif condition=="bonusbar:1" then matches=matches and bonus==1
                        else error("unmodeled macro condition: "..condition) end
                    end
                else name=branch end
                if matches then result[#result+1]=name; break end
            end
        end
    end
    return result
end
test("compact builder selects AoE with Alt even in Stealth",function()
    command("sub compact"); local body=slotBody(1)
    expect(equal(castBranches(body,false,0),{"Backstab"}))
    expect(equal(castBranches(body,false,1),{"Shadowstrike"}))
    expect(equal(castBranches(body,true,0),{"Spell197835"}))
    expect(equal(castBranches(body,true,1),{"Spell197835"}))
end)
test("compact spender exposes Eviscerate normally and Black Powder on Alt",function()
    command("sub compact"); local body=slotBody(2)
    local normal=castBranches(body,false,0);local aoe=castBranches(body,true,0)
    expect(normal[#normal]=="Spell196819" and aoe[#aoe]=="Black Powder")
    expect(aoe[1]=="Coup de Grace")
end)
test("compact Assa branches keep generator and spender intentions explicit",function()
    S.spec=259;command("assa compact")
    expect(equal(castBranches(slotBody(1),false,0),{"Spell1329"}))
    expect(equal(castBranches(slotBody(1),true,0),{"Spell51723"}))
    expect(equal(castBranches(slotBody(2),false,0),{"Spell32645"}))
    expect(equal(castBranches(slotBody(2),true,0),{"Crimson Tempest"}))
end)
test("a registered second class owns its own slots without Rogue mirroring",function()
    S.class="MAGE"; S.spec=62
    TheOneToRuleThemAll.RegisterProfile({id="mage_mock",class="MAGE",spec=62,specName="Arcane",label="Test module",layouts={standard={description="test"}},build=function(api)
        return {rows={{slot=2,action=api.spell(777)}},macros={},lines={}}
    end})
    S.slots[2]={kind="item",id=55}; S.slots[74]={kind="spell",id=333}
    local before=copy(S.slots); command("apply mage_mock")
    expect(S.slots[2].id==777 and S.slots[74].id==333)
    expect(TheOneToRuleThemAllDB.backup.class=="MAGE" and #TheOneToRuleThemAllDB.backup.rows==1)
    command("undo"); expect(equal(before,S.slots))
end)
test("unsupported saved-data schema blocks changes",function()
    TheOneToRuleThemAllDB={version=999,sentinel="preserved"}
    command("sub")
    expect(S.placements==0 and S.created==0 and TheOneToRuleThemAllDB.sentinel=="preserved")
    expect(messageContains("Unknown saved-data version"))
end)
test("compact permits Alt chord already mapped to its same action",function()
    S.bindingKeys.ACTIONBUTTON1={"1","ALT-1"};S.bindings["ALT-1"]="ACTIONBUTTON1"
    S.bindings["ALT-2"]="ACTIONBUTTON2";command("sub compact")
    expect(TheOneToRuleThemAllDB.backup.state=="applied" and S.bindingCalls==0)
end)
test("compact rejects ordinary action reachable only through Alt",function()
    S.bindingKeys.ACTIONBUTTON1={"ALT-1"};S.bindings["ALT-1"]="ACTIONBUTTON1"
    command("sub compact")
    expect(S.placements==0 and S.created==0 and messageContains("key without Alt"))
end)
test("compact checks Alt chord of existing Shift-modified key",function()
    S.bindingKeys.ACTIONBUTTON1={"SHIFT-Q"};S.bindings["ALT-SHIFT-Q"]="JUMP"
    command("sub compact")
    expect(S.placements==0 and S.created==0 and messageContains("ALT-SHIFT-Q"))
end)
test("compact checks Alt chord of existing Ctrl-modified key",function()
    S.bindingKeys.ACTIONBUTTON2={"CTRL-E"};S.bindings["ALT-CTRL-E"]="JUMP"
    command("sub compact")
    expect(S.placements==0 and S.created==0 and messageContains("ALT-CTRL-E"))
end)
test("compact requires a binding to each modified action slot",function()
    S.bindingKeys.ACTIONBUTTON2={};command("sub compact")
    expect(S.placements==0 and S.created==0 and messageContains("key without Alt"))
end)
test("combat entered during setup preserves pending undo until safe",function()
    S.slots[1]={kind="item",id=555};local before=copy(S.slots)
    local create=CreateMacro
    CreateMacro=function(...)
        local id=create(...);S.combat=true;return id
    end
    command("sub")
    expect(TheOneToRuleThemAllDB.backup.state=="needs-undo")
    expect(equal(before,S.slots) and S.created==1)
    S.combat=false;command("undo")
    expect(equal(before,S.slots) and TheOneToRuleThemAllDB.backup.state=="restored")
end)
test("macro creation failure leaves original bars and recoverable state",function()
    S.slots[1]={kind="spell",id=555};local before=copy(S.slots)
    CreateMacro=function() return nil end
    command("sub")
    expect(equal(before,S.slots) and TheOneToRuleThemAllDB.backup.state=="restored")
    expect(messageContains("WoW did not create"))
end)
test("one-shot macro inspection placement error restores then proceeds",function()
    oldMacro(121,"PriorMacro");S.slots[1]={kind="macro",id=121}
    local before=copy(S.slots);local place=PlaceAction;local failures=0
    PlaceAction=function(slot)
        if slot==1 and S.cursor and S.cursor.kind=="macro" and S.cursor.id==121 and failures==0 then
            failures=failures+1;error("injected inspection placement failure")
        end
        return place(slot)
    end
    command("sub")
    expect(failures==1 and TheOneToRuleThemAllDB.backup.state=="applied" and S.cursor==nil)
    command("undo");expect(equal(before,S.slots))
end)
test("repeated macro inspection errors preserve original cursor and explain slot",function()
    oldMacro(121,"PriorMacro");S.slots[1]={kind="macro",id=121};S.slots[2]={kind="item",id=777}
    local before=copy(S.slots);local place=PlaceAction;local failures=0
    PlaceAction=function(slot)
        if slot==1 and S.cursor and S.cursor.kind=="macro" and S.cursor.id==121 then
            failures=failures+1;error("persistent inspection placement failure")
        end
        return place(slot)
    end
    command("sub")
    expect(failures==2 and S.created==0 and S.placements==0)
    expect(S.cursor and S.cursor.kind=="macro" and S.cursor.id==121 and S.slots[1]==nil)
    expect((not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup) and messageContains("Macro inspection stopped at slot 1"))
    expect(messageContains("Preserve the action on your cursor"))
    PlaceAction=place;PlaceAction(1);expect(equal(before,S.slots) and S.cursor==nil)
end)
test("macro inspection stops before pickup if combat begins",function()
    oldMacro(121,"PriorMacro");S.slots[1]={kind="macro",id=121}
    local before=copy(S.slots);local info=GetActionInfo
    GetActionInfo=function(slot)
        if slot==1 then S.combat=true end
        return info(slot)
    end
    command("sub")
    expect(equal(before,S.slots) and S.cursor==nil and S.created==0 and S.placements==0)
    expect(messageContains("stopped before picking up"))
end)
test("profile cannot place an undeclared macro",function()
    TheOneToRuleThemAll.RegisterProfile({id="badmacro",class="ROGUE",spec=261,label="Invalid module",layouts={standard={description="test"}},build=function(api)
        return {rows={{slot=1,action=api.macro("Undeclared","/cast Spell777")}},macros={}}
    end})
    S.slots[1]={kind="item",id=666};local before=copy(S.slots)
    command("apply badmacro")
    expect(equal(before,S.slots) and S.created==0 and S.placements==0 and messageContains("did not declare"))
end)
test("profile cannot place an invalid spell identifier",function()
    TheOneToRuleThemAll.RegisterProfile({id="badspell",class="ROGUE",spec=261,label="Invalid module",layouts={standard={description="test"}},build=function()
        return {rows={{slot=1,action={kind="spell",id=0}}},macros={}}
    end})
    command("apply badspell")
    expect(S.created==0 and S.placements==0 and messageContains("invalid spell"))
end)
test("released Goremaw burst profile is present and factory-free",function()
    expect(TheOneToRuleThemAll.profiles.subburst~=nil)
    expect(TheOneToRuleThemAll.BuildPendingRogueBurstProfile==nil)
    command("list");expect(messageContains("subburst"))
    command("apply subburst")
    expect(S.created==3 and TheOneToRuleThemAllDB.backup.state=="applied")
end)
test("released burst standard emits explicit Dance Blades Goremaw macro",function()
    command("subburst")
    local expected="#showtooltip Goremaw's Bite\n/cast Shadow Dance\n/cast Shadow Blades\n/cast Goremaw's Bite"
    expect(slotBody(6)==expected and S.macros[S.slots[6].id].name=="TOR GBurst")
    expect(S.created==3 and TheOneToRuleThemAllDB.backup.mode=="subburst")
    expect(S.slots[5].id==280719 and S.slots[7].id==1766 and S.slots[8].id==1966 and S.slots[9].id==1856)
    expect(S.slots[61].id==185313 and S.slots[62].id==121471)
    for _,action in pairs(S.slots) do expect(action.id~=426591) end
    expect(not contains(slotBody(6),"/castsequence") and not contains(slotBody(6),"bonusbar"))
end)
test("released burst compact keeps four rotation keys and immediate utilities",function()
    command("subburst compact")
    expect(TheOneToRuleThemAllDB.backup.state=="applied" and S.created==3)
    expect(equal(castBranches(slotBody(1),true,1),{"Spell197835"}))
    expect(S.slots[3].id==280719 and contains(slotBody(4),"/cast Goremaw's Bite"))
    expect(S.slots[5].id==31224 and S.slots[6].id==185311 and S.slots[7].id==1766 and S.slots[8].id==1966 and S.slots[9].id==1856)
    for i=1,9 do expect(equal(S.slots[i],S.slots[72+i])) end
end)
for _,layout in ipairs({"standard","compact"}) do
    test("released burst "..layout.." requires learned Goremaw before writes",function()
        S.unlearned[426591]=true;command("subburst "..layout)
        expect(S.created==0 and S.placements==0 and messageContains("Missing Goremaw's Bite"))
    end)
end
for _,layout in ipairs({"standard","compact"}) do
    test("released burst "..layout.." undo restores prior macros items and empty slots",function()
        oldMacro(121,"PriorMacro");S.slots[1]={kind="macro",id=121};S.slots[61]={kind="item",id=999}
        local before=copy(S.slots);command("subburst "..layout);command("undo")
        expect(equal(before,S.slots) and TheOneToRuleThemAllDB.backup.state=="restored")
    end)
    test("released burst "..layout.." rejects incompatible hero before writes",function()
        S.unlearned[441423]=true;command("subburst "..layout)
        expect(S.created==0 and S.placements==0 and messageContains("Missing Coup de Grace"))
    end)
end
test("separate and coupled burst layouts coexist without macro-name collisions",function()
    command("sub");command("undo");command("subburst")
    expect(TheOneToRuleThemAllDB.backup.state=="applied" and S.created==4)
    expect(contains(slotBody(6),"/cast Goremaw's Bite"))
    command("undo");command("subburst compact")
    expect(TheOneToRuleThemAllDB.backup.state=="applied" and S.created==6 and contains(slotBody(4),"/cast Goremaw's Bite"))
end)
local recommendationText="Compatible starting profile: /tor subburst"
test("help recommends released burst only with compatible current build",function()
    command("help")
    expect(messageContains(recommendationText) and S.created==0 and S.placements==0 and S.bindingCalls==0)
    expect(not TheOneToRuleThemAllDB or not TheOneToRuleThemAllDB.backup)
end)
for _,scenario in ipairs({
    {"another class",function() S.class="MAGE" end},
    {"another specialization",function() S.spec=259 end},
    {"another hero tree",function() S.unlearned[441423]=true end},
    {"missing Goremaw",function() S.unlearned[426591]=true end},
    {"missing Secret Technique",function() S.unlearned[280719]=true end},
}) do
    test("help suppresses burst recommendation for "..scenario[1],function()
        scenario[2]();command("help")
        expect(not messageContains(recommendationText))
        expect(S.created==0 and S.placements==0 and S.bindingCalls==0)
    end)
end
local ctx={test=test,expect=expect,copy=copy,equal=equal,command=command,messageContains=messageContains,state=function() return S end,addon=function() return TheOneToRuleThemAll end,reload=loadAddon}
dofile(addonDir .. "/validation/test_core_v2.lua")(ctx)
dofile(addonDir .. "/validation/test_controls.lua")(ctx)
dofile(addonDir .. "/validation/test_ui.lua")(ctx)
dofile(addonDir .. "/validation/test_deathknight.lua")(ctx)
TOR_TEST_TOTAL=total; TOR_TEST_FAILED=failed
realPrint(string.format("RESULT: %d tests, %d passed, %d failed",total,total-failed,failed))
assert(failed==0,"Mock tests failed")
