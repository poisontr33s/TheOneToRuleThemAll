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
      GetSpecializationInfo=function(index) assert(index==3)
        return S.spec,({[259]="Assassination",[260]="Outlaw",[261]="Subtlety"})[S.spec] or "Other" end}
    UnitClass=function() return S.localizedClass or "Rogue",S.class end
    UnitRace=function() return S.race,S.race end
    InCombatLockdown=function() return S.combat end
    IsStealthed=function() return S.stealth end
    IsMounted=function() return false end
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
    local names={[53]="Backstab",[185438]="Shadowstrike",[260364]="Arcane Pulse"}
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
    -- Deprecated spell/page globals must stay absent, like the specialization ones.
    IsPlayerSpell=nil
    GetActionBarPage=nil
    -- S.gone marks items, sets and pets that can no longer be picked up.
    S.gone={}; S.toys={}
    C_Item={PickupItem=function(id) if not S.gone[id] then S.cursor={kind="item",id=id} end end,
      GetItemNameByID=function(id) return "Item"..id end}
    PlayerHasToy=function(id) return S.toys[id] or false end
    C_ToyBox={PickupToyBoxItem=function(id) if S.toys[id] then S.cursor={kind="item",id=id} end end}
    PickupFlyout=nil
    C_EquipmentSet={PickupEquipmentSet=function(id) if not S.gone[id] then S.cursor={kind="equipmentset",id=id} end end,
      GetEquipmentSetInfo=function(id) return "Set"..id end}
    C_PetJournal={PickupPet=function(id) if not S.gone[id] then S.cursor={kind="summonpet",id=id} end end}
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
    C_ActionBar.HasVehicleActionBar=function() return false end
    C_ActionBar.HasOverrideActionBar=function() return false end
    C_ActionBar.HasTempShapeshiftActionBar=function() return false end
    C_ActionBar.IsPossessBarVisible=function() return false end
    C_ActionBar.HasBonusActionBar=function() return false end
    C_PetBattles={IsInBattle=function() return false end}
    GetShapeshiftForm=function() return 0 end
    GetNumShapeshiftForms=function() return 0 end
    GetShapeshiftFormInfo=function() return nil end
    NUM_ACTIONBAR_BUTTONS=12
    for button=1,9 do _G["ActionButton"..button]={CalculateAction=function() return button end} end
    C_Spell.IsSpellPassive=function() return false end
    loadAddon()
    -- Each fixture starts with one race.
    for _, racial in ipairs(TheOneToRuleThemAll.racialDefinitions or {}) do
        for _, id in ipairs(racial.ids) do if id~=260364 then S.unlearned[id]=true end end
    end
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
local ctx={test=test,expect=expect,copy=copy,equal=equal,command=command,messageContains=messageContains,state=function() return S end,addon=function() return TheOneToRuleThemAll end,reload=loadAddon}
for _, name in ipairs({"transactions", "controls", "ui", "talent_browser", "native_bar", "standard"}) do
    dofile(addonDir .. "/validation/test_" .. name .. ".lua")(ctx)
end
TOR_TEST_TOTAL=total; TOR_TEST_FAILED=failed
realPrint(string.format("RESULT: %d tests, %d passed, %d failed",total,total-failed,failed))
assert(failed==0,"Mock tests failed")
