-- Yipyep's Blood layouts keep the same core actions for either hero tree.
-- These are manual setup profiles, not a simulated tank ranking or rotation.
-- Spell/talent IDs: SimC 12aa5dc041b0, Retail 12.1.5 (DBC 12.1.5.70575).
-- See engine/dbc/generated/{trait_data,sc_spell_data}.inc in that revision.
local A = TheOneToRuleThemAll

local HEART_STRIKE, MARROWREND = 206930, 195182
local VAMPIRIC_STRIKE_TALENT, VAMPIRIC_STRIKE = 433901, 433895
local REAPERS_MARK = 439843
local CORE = {HEART_STRIKE, MARROWREND, 49998, 50842, 43265, 49028}
local REQUIRED = {HEART_STRIKE, MARROWREND, 49998, 50842, 43265, 49028, 48265, 48707}

local EVIDENCE = {
    patch="12.1.5 / spell data: SimC 12aa5dc041b0",
    gear="Yipyep's existing gear; this setup does not require a gear template.",
    tuning="Manual action layout for the Shed Assymetry Blood foundation and its hero variants; no new damage or survivability ranking.",
    validation="Setup, preservation and recovery are covered by mocked API tests; live-client setup and native spell replacements still need in-game verification.",
}

-- Keep utility positions stable when talents are absent. Missing optional
-- spells must not clear a slot or shift the remaining utility buttons left.
local UTILITY = {
    {slot=61,id=48792,name="Icebound Fortitude"},
    {slot=62,id=55233,name="Vampiric Blood"},
    {slot=63,id=49039,name="Lichborne"},
    {slot=64,id=49576,name="Death Grip"},
    {slot=65,id=207167,name="Blinding Sleet"},
    {slot=66,id=212552,name="Wraith Walk"},
    {slot=67,id=61999,name="Raise Ally"},
    -- Slot 68 is the mutually exclusive Abomination Limb / Gorefiend choice.
    {slot=69,id=48743,name="Death Pact"},
    {slot=70,id=195292,name="Death's Caress"},
    -- Deathbringer uses slot 71 for its separate Reaper's Mark button.
    {slot=72,id=56222,name="Dark Command"},
}

local function build(hero, api, layout, enforce)
    api.check(layout == "standard", "This Blood profile has a Standard layout only; nothing changed.")
    local sanlayn = hero == "sanlayn"
    local heroName = sanlayn and "San'layn" or "Deathbringer"
    local heroSpell = sanlayn and VAMPIRIC_STRIKE_TALENT or REAPERS_MARK
    if enforce then
        api.check(api.learned(heroSpell), "Load a " .. heroName .. " Blood talent loadout first; nothing changed.")
        for _, id in ipairs(REQUIRED) do
            api.check(api.learned(id), "Missing " .. api.spellName(id) .. ". Load a compatible Blood talent loadout first; nothing changed.")
        end
    end

    local plan = {rows={},macros={},skipped={},lines={
        "1 Heart Strike; 2 Marrowrend; 3 Death Strike; 4 Blood Boil; 5 Death and Decay; 6 Dancing Rune Weapon.",
        "7 Mind Freeze when learned; 8 Death's Advance; 9 Anti-Magic Shell. Each ability has its own button.",
        "Death and Decay uses normal ground targeting. Choose Death Strike, movement and defensive cooldowns yourself.",
        "Utility uses fixed Bar 2 positions. An unlearned optional ability leaves its existing slot untouched.",
    }}

    local function add(slot, id)
        local action
        if id == HEART_STRIKE or id == MARROWREND then
            -- A.api.spell resolves overrides immediately. Save the native base
            -- button instead: an active Vampiric Strike / Exterminate proc
            -- must not become a permanently placed temporary spell.
            action = {kind="spell",id=id}
        else
            action = api.spell(id)
        end
        if id == HEART_STRIKE and sanlayn then
            action.displayText = api.spellName(HEART_STRIKE) .. " / " .. api.spellName(VAMPIRIC_STRIKE) .. " (native replacement)"
        end
        plan.rows[#plan.rows+1] = {slot=slot,action=action}
    end

    local function optional(slot, id, fallbackName)
        if api.learned(id) then
            add(slot,id)
        else
            local ok, name = pcall(api.spellName,id)
            local position = slot >= 61 and slot <= 72 and ("Bar 2 slot " .. (slot-60)) or ("main slot " .. slot)
            plan.skipped[#plan.skipped+1] = (ok and name or fallbackName) .. " (" .. position .. " unchanged)"
        end
    end

    for slot,id in ipairs(CORE) do add(slot,id) end
    optional(7,47528,"Mind Freeze")
    if not api.learned(47528) then
        plan.lines[#plan.lines+1] = "Mind Freeze is not learned: main slot 7 stays as it is. This layout does not add an interrupt talent."
    end
    add(8,48265)
    add(9,48707)
    for _,spell in ipairs(UTILITY) do optional(spell.slot,spell.id,spell.name) end

    -- Midnight moved Abomination Limb into the Blood choice node and changed
    -- its spell ID. Do not use the former class/covenant spell (315443).
    if api.learned(1263569) then
        add(68,1263569)
    else
        optional(68,108199,"Gorefiend's Grasp / Abomination Limb")
    end
    if sanlayn then
        plan.lines[#plan.lines+1] = "San'layn: Heart Strike uses WoW's native Vampiric Strike replacement on the same button. Bar 2 slot 11 stays as it is."
    else
        add(71,REAPERS_MARK)
        plan.lines[#plan.lines+1] = "Deathbringer: Reaper's Mark is separate on Bar 2 slot 11. Check that button's displayed key before applying."
    end
    table.sort(plan.rows,function(a,b) return a.slot < b.slot end)
    return plan
end

for _,hero in ipairs({
    {id="sanlayn",label="San'layn"},
    {id="deathbringer",label="Deathbringer"},
}) do
    local id, label = hero.id, hero.label
    A.RegisterProfile({
        id="blood-" .. id,class="DEATHKNIGHT",spec=250,specName="Blood",
        label="Shed Assymetry Blood - " .. label,requiredPage=1,
        evidence=EVIDENCE,
        layouts={standard={description="Blood core on 1-6; separate interrupt, movement and defensive buttons"}},
        recommendedWhen=function(api)
            return pcall(build,id,api,"standard",true)
        end,
        build=function(api,layout,enforce) return build(id,api,layout,enforce) end,
    })
end
