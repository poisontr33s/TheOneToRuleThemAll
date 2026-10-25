-- First included class module. These layouts share the same four tested
-- policies; changing physical key layout is not a new damage simulation.
local A = TheOneToRuleThemAll
local GEAR_REFERENCE = "fixed template: 321 armor/rings; 328 neck/trinkets/weapons; tier head/shoulders/chest/legs; 6x Flawless Quick Lapis (quality 2)"
local GEAR_LOCK = "TOR_Hero321_Ascended328_TierHSCL_6QuickLapis_2026-10-25"
local SUB_EVIDENCE = {
    patch="12.1.5 / SimC 12aa5dc041b0",
    gear=GEAR_REFERENCE,
    gearLock=GEAR_LOCK,
    tuning="Published results include current-live controls and an announced October 27 nerf forecast; forecast is not live verification.",
    validation="Simulation policy tested; live-client setup testing remains.",
}
local ASSA_EVIDENCE = {
    patch="12.1.5 / SimC 12aa5dc041b0",
    gear=GEAR_REFERENCE,
    gearLock=GEAR_LOCK,
    tuning="Assassination uses current-live tuning; the Subtlety October 27 forecast does not change this profile.",
    validation="Simulation policy tested; live-client setup testing remains.",
}
local SUB_BURST_EVIDENCE = {
    patch="12.1.5 / SimC 12aa5dc041b0",
    gear=GEAR_REFERENCE,
    gearLock=GEAR_LOCK,
    policyId="subtlety_six_gore_cooldown_after_opener_strict",
    tuning="Announced October 27 Subtlety nerf is modeled as a forecast, not verified future live behavior.",
    validation="Coupled Goremaw policy tested on the locked reference template; live-client setup and casting tests remain.",
}
local function build(mode,api,layout,enforce)
    local sp, name, known, check, macro = api.spell,api.spellName,api.learned,api.check,api.macro
    local compact = layout == "compact"
    local goreBurst = mode == "subburst"
    local main,utility,required,hero,label,lines,macros
    macros = {}
    if mode ~= "assa" then
        hero,label = 441423,"Trickster Subtlety"
        required = {197835,319175,280719,185313,121471,185438,196819,1856,1766,1966}
        if mode == "sub" or goreBurst then required[#required+1]=426591 end
        if compact then
            required[#required+1]=31224
            if mode ~= "sub" then required[#required+1]=185311 end
        end
        if enforce then check(known(53) or known(200758),"Missing a learned Subtlety builder; nothing changed.") end
        local builder = known(200758) and 200758 or api.resolved(53)
        local burstBody = "#showtooltip\n/cast " .. name(185313) .. "\n/cast " .. name(121471)
        if goreBurst then burstBody = "#showtooltip " .. name(426591) .. "\n/cast " .. name(185313) .. "\n/cast " .. name(121471) .. "\n/cast " .. name(426591) end
        local burst = macro(goreBurst and "TOR GBurst" or "TOR Burst",burstBody)
        if compact then
            local generator = macro("TOR CBuilder","#showtooltip\n/cast [mod:alt] " .. name(197835) .. "; [bonusbar:1] " .. name(185438) .. "; " .. name(builder))
            -- In AoE, Coup is attempted first as in the guide macro. The plain
            -- Eviscerate name retains its native temporary Coup replacement.
            local finisher = macro("TOR CFinish","#showtooltip\n/cast [mod:alt] " .. name(441423) .. "\n/cast [mod:alt] " .. name(319175) .. "; " .. name(196819))
            macros = {generator,finisher,burst}
            main = {generator,finisher,sp(280719),burst,sp(mode=="sub" and 426591 or 31224),sp(mode=="sub" and 31224 or 185311),sp(1766),sp(1966),sp(1856)}
            if goreBurst then main = {generator,finisher,sp(280719),burst,sp(31224),sp(185311),sp(1766),sp(1966),sp(1856)} end
            lines = {
                "1 Builder / Alt+1 Storm; 2 Eviscerate-Coup / Alt+2 Black Powder-Coup; 3 Secret Technique; 4 Dance+Blades.",
                "5 " .. (mode=="sub" and "Goremaw; 6 Cloak" or "Cloak; 6 Vial") .. "; 7 Kick; 8 Feint; 9 Vanish. Alt is held manually, not an automatic AoE selector.",
                (mode=="sub" and "Five" or "Four") .. " rotation keys plus Alt, " .. (mode=="sub" and "seven" or "six") .. " action choices, plus items. Fewer numbered keys does not mean fewer casts or decisions.",
            }
            if goreBurst then
                lines = {
                    "1 Builder / Alt+1 Storm; 2 Eviscerate-Coup / Alt+2 Black Powder-Coup; 3 Secret Technique; 4 Dance+Blades+Goremaw.",
                    "5 Cloak; 6 Vial; 7 Kick; 8 Feint; 9 Vanish. Hold Alt manually for the alternate action on 1 or 2.",
                    "Four rotation keys plus Alt, six action choices, plus items. Establish Slice and Dice before the first planned burst; this macro is not a rotation button.",
                }
            end
        else
            local aoe = macro("TOR AoE","#showtooltip\n/cast " .. name(441423) .. "\n/cast " .. name(319175))
            local generator = macro("TOR Builder","#showtooltip\n/cast [bonusbar:1] " .. name(185438) .. "; " .. name(builder))
            macros = {aoe,burst,generator}
            main = {generator,sp(197835),{kind="spell",id=196819},aoe,sp(280719),burst,sp(1766),sp(mode=="sub" and 426591 or 1966),sp(1856)}
            lines = {
                "1 Builder; 2 Storm; 3 Eviscerate/Coup; 4 AoE; 5 Secret Technique; 6 Dance+Blades; 7 Kick; 8 " .. (mode=="sub" and "Goremaw" or "Feint") .. "; 9 Vanish.",
                (mode=="sub" and "Seven" or "Six") .. " routine class buttons, plus items. Separate Dance and Blades remain on bar 2.",
            }
            if goreBurst then
                lines = {
                    "1 Builder; 2 Storm; 3 Eviscerate/Coup; 4 AoE; 5 Secret Technique; 6 Dance+Blades+Goremaw; 7 Kick; 8 Feint; 9 Vanish.",
                    "Six routine class buttons, plus items. Goremaw remains in the burst macro; separate Dance and Blades remain on bar 2.",
                    "Establish Slice and Dice before the first planned burst. A later press can use Goremaw while Dance is already active; do not spam this as a rotation button.",
                }
            end
        end
        if goreBurst then
            lines[#lines+1]="After Slice and Dice is active, use the burst key when Goremaw is ready and for normal Dance windows. Goremaw has no separate button in this policy."
        end
        if mode=="sublite" then lines[#lines+1]="Goremaw is not bound by this lighter policy; its talent remains in the reference build." end
        utility = {185313,121471,1784,1966,31224,5277,185311,2983,36554,2094,408,57934}
    else
        hero,label = 452536,"Fatebound Assassination"
        required = {1329,51723,32645,1247227,703,1943,1766,385627,360194}
        if compact then required[#required+1]=1966; required[#required+1]=1856 end
        if compact then
            local generator = macro("TOR ABuilder","#showtooltip\n/cast [mod:alt] " .. name(51723) .. "; " .. name(1329))
            local spendSpread = macro("TOR ASpend","#showtooltip\n/cast [mod:alt] " .. name(1247227) .. "; " .. name(32645))
            macros = {generator,spendSpread}
            main = {generator,spendSpread,sp(703),sp(1943),sp(385627),sp(360194),sp(1766),sp(1966),sp(1856)}
            lines = {
                "1 Mutilate / Alt+1 Fan; 2 Envenom / Alt+2 Crimson Tempest; 3 Garrote; 4 Rupture; 5 Kingsbane; 6 Deathmark; 7 Kick; 8 Feint; 9 Vanish.",
                "Crimson Tempest generates/spreads bleeds; it is not an AoE finisher. Envenom remains the spender in AoE.",
                "Six rotation keys plus Alt, eight action choices, plus items. Alt is manual; no automatic resource or target-count decisions.",
            }
        else
            main = {sp(1329),sp(51723),sp(32645),sp(1247227),sp(703),sp(1943),sp(1766),sp(385627),sp(360194)}
            lines = {"1 Mutilate; 2 Fan; 3 Envenom; 4 Crimson Tempest; 5 Garrote; 6 Rupture; 7 Kick; 8 Kingsbane; 9 Deathmark.",
                "Eight routine class buttons, plus items. Crimson Tempest generates/spreads bleeds; Envenom remains the spender."}
        end
        utility = {1856,5938,1784,1966,31224,5277,185311,2983,36554,2094,408,57934}
        lines[#lines+1]="Vanish and Shiv remain on bar 2. Tea is not bound; this policy assumes its automatic talent use."
    end
    if enforce then
        check(known(hero),"Missing " .. name(hero) .. ". Load a compatible " .. label .. " talent loadout first.")
        for _, id in ipairs(required) do check(known(id),"Missing " .. name(id) .. ". Load a compatible " .. label .. " talent loadout first.") end
    end
    local plan = {rows={},macros=macros,skipped={},lines=lines}
    for i,action in ipairs(main) do
        plan.rows[#plan.rows+1]={slot=i,action=action}
        plan.rows[#plan.rows+1]={slot=72+i,action=action}
    end
    for i,id in ipairs(utility) do
        if known(id) then plan.rows[#plan.rows+1]={slot=60+i,action=sp(id)}
        else plan.skipped[#plan.skipped+1]=name(id) end
    end
    return plan
end

-- Selected six-key policy. Keep the earlier "sub" profile ID unchanged so
-- saved choices and the seven-key comparison remain unambiguous.
A.RegisterProfile({id="subburst",class="ROGUE",spec=261,specName="Subtlety",label="Trickster Subtlety - coupled Goremaw burst",requiredPage=1,blockedWhileStealthed=true,
    evidence=SUB_BURST_EVIDENCE,
    layouts={standard={description="6 rotation keys; Goremaw in the burst macro"},compact={description="4 rotation keys plus Alt; 6 action choices",altSlots={1,2}}},
    recommendedWhen=function(api)
        local compatible = pcall(build,"subburst",api,"standard",true)
        return compatible
    end,
    build=function(api,layout,enforce) return build("subburst",api,layout,enforce) end})
for _, row in ipairs({
    {id="sub",label="Trickster Subtlety - seven action choices",spec=261,specName="Subtlety",normal="7 rotation keys; separate ST/AoE",compact="5 rotation keys with Alt+1/2; 7 action choices",evidence=SUB_EVIDENCE},
    {id="sublite",label="Trickster Subtlety - six action choices",spec=261,specName="Subtlety",normal="6 rotation keys; Goremaw omitted",compact="4 rotation keys with Alt+1/2; 6 action choices",evidence=SUB_EVIDENCE},
    {id="assa",label="Fatebound Assassination - relaxed spend",spec=259,specName="Assassination",normal="8 rotation keys",compact="6 rotation keys with Alt+1/2; 8 action choices",evidence=ASSA_EVIDENCE},
}) do
    local mode=row.id
    A.RegisterProfile({id=mode,class="ROGUE",spec=row.spec,specName=row.specName,label=row.label,requiredPage=1,blockedWhileStealthed=true,
        evidence=row.evidence,
        layouts={standard={description=row.normal},compact={description=row.compact,altSlots={1,2}}},
        build=function(api,layout,enforce) return build(mode,api,layout,enforce) end})
end
