-- Native page selection and slot calculation follow Blizzard's live UI:
-- https://github.com/Gethe/wow-ui-source/tree/15881d522c44cd106d3d8660106ec9f9d2f44167/Interface/AddOns
-- Blizzard_ActionBarController/ActionBarController.lua:148-164
-- Blizzard_FrameXML/SecureTemplates.lua:670-684
local A = TheOneToRuleThemAll
local check = A.api.check
local unavailable = "WoW's main-bar information is unavailable. Reload the UI before trying again; nothing changed."

local function integer(value, minimum)
    return type(value) == "number" and value >= minimum and value % 1 == 0
end

local function flag(api, name)
    check(api and type(api[name]) == "function", unavailable)
    local value = api[name]()
    check(type(value) == "boolean", unavailable)
    return value
end

function A.NativeMainBar()
    check(type(IsMounted) == "function", unavailable)
    local mounted = IsMounted()
    check(type(mounted) == "boolean", unavailable)
    check(not mounted, "Dismount before changing your bars; nothing changed.")
    check(not flag(C_ActionBar, "HasVehicleActionBar"), "Leave the vehicle before changing your bars; nothing changed.")
    check(not flag(C_ActionBar, "HasOverrideActionBar"), "Finish the activity replacing your main bar first; nothing changed.")
    check(not flag(C_ActionBar, "HasTempShapeshiftActionBar"), "Leave the temporary transformation first; nothing changed.")
    check(not flag(C_ActionBar, "IsPossessBarVisible"), "Stop controlling another unit first; nothing changed.")
    check(not flag(C_PetBattles, "IsInBattle"), "Finish the pet battle first; nothing changed.")
    check(type(C_ActionBar.GetActionBarPage) == "function", unavailable)
    check(C_ActionBar.GetActionBarPage() == 1, "Switch your main bar to page 1 (normally Shift+1), then try again; nothing changed.")

    local page = 1
    if flag(C_ActionBar, "HasBonusActionBar") then
        check(type(C_ActionBar.GetBonusBarIndex) == "function", unavailable)
        page = C_ActionBar.GetBonusBarIndex()
        check(integer(page, 2), unavailable)
    end
    check(NUM_ACTIONBAR_BUTTONS == 12, unavailable)
    local first = (page - 1) * NUM_ACTIONBAR_BUTTONS + 1

    check(type(GetShapeshiftForm) == "function" and type(GetNumShapeshiftForms) == "function"
        and type(GetShapeshiftFormInfo) == "function", unavailable)
    local form, count = GetShapeshiftForm(), GetNumShapeshiftForms()
    check(integer(form, 0) and integer(count, 0) and form <= count, unavailable)
    local formSpell = 0
    if form > 0 then
        local _, active, _, spell = GetShapeshiftFormInfo(form)
        check(active == true and integer(spell, 1), "Your form is still changing. Try again once your main bar settles; nothing changed.")
        formSpell = spell
    end

    -- A custom bar may use different pages. Require agreement with the native
    -- buttons instead of assuming a layout from the player's class or form.
    for buttonID = 1, 9 do
        local button = _G["ActionButton" .. buttonID]
        check(button and type(button.CalculateAction) == "function",
            "The native main bar could not be checked. Restore WoW's standard action bar before setup; nothing changed.")
        local ok, slot = pcall(button.CalculateAction, button)
        check(ok and slot == first + buttonID - 1,
            "Your visible main bar does not match WoW's current page. Restore the standard action bar and try again; nothing changed.")
    end
    return {page = page, formSpell = formSpell, first = first}
end

function A.CheckNativeContext(context)
    local current = A.NativeMainBar()
    context = context or {}
    if context.class == "ROGUE" then
        check(current.page == 1,
            "Leave Stealth or Shadow Dance and return to the normal main bar; nothing changed.")
    end
    if context.requiredForm ~= nil then
        check(integer(context.requiredForm, 0), "This profile has no valid required form; nothing changed.")
        if context.requiredForm == 0 then
            check(current.formSpell == 0, "Return to caster form first; nothing changed.")
        else
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(context.requiredForm)
            check(current.formSpell == context.requiredForm,
                "Enter " .. (name or "the required form") .. " first; nothing changed.")
        end
    end
    if context.nativeBar then
        local saved = context.nativeBar
        check(type(saved) == "table" and integer(saved.page, 1) and integer(saved.formSpell, 0)
            and integer(saved.first, 1), "The previous setup has incomplete main-bar information; nothing changed.")
        check(current.page == saved.page and current.formSpell == saved.formSpell and current.first == saved.first,
            "Return to the form and main bar used for this setup before Undo; nothing changed.")
    end
    return current
end
