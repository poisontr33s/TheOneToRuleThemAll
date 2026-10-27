local source = debug.getinfo(1, "S").source:gsub("^@", "")
local modulePath = (source:match("^(.*)[/\\]") or ".") .. "/../NativeBar.lua"

return function(ctx)
    local test, expect = ctx.test, ctx.expect
    local function prepare()
        local state = {selected = 1, page = 1, form = 0, count = 0, spell = 0, bonus = false}
        C_ActionBar = {
            GetActionBarPage = function() return state.selected end,
            HasBonusActionBar = function() return state.bonus end,
            GetBonusBarIndex = function() return state.page end,
        }
        for _, name in ipairs({"HasVehicleActionBar", "HasOverrideActionBar", "HasTempShapeshiftActionBar", "IsPossessBarVisible"}) do
            C_ActionBar[name] = function() return state[name] or false end
        end
        C_PetBattles = {IsInBattle = function() return state.petBattle or false end}
        IsMounted = function() return state.mounted or false end
        NUM_ACTIONBAR_BUTTONS = 12
        GetShapeshiftForm = function() return state.form end
        GetNumShapeshiftForms = function() return state.count end
        GetShapeshiftFormInfo = function(index)
            expect(index == state.form)
            return 1, true, true, state.spell
        end
        for id = 1, 9 do
            _G["ActionButton" .. id] = {CalculateAction = function()
                return id + ((state.bonus and state.page or 1) - 1) * 12
            end}
        end
        dofile(modulePath)
        return state, ctx.addon()
    end
    local function blocked(callback, text)
        local ok, message = pcall(callback)
        expect(not ok and tostring(message):find(text, 1, true), tostring(message))
    end

    test("native unshifted main bar uses page one", function()
        local _, addon = prepare()
        local bar = addon.NativeMainBar()
        expect(bar.page == 1 and bar.first == 1 and bar.formSpell == 0)
    end)
    test("native form layout uses the observed bonus page rather than form order", function()
        local state, addon = prepare()
        state.form, state.count, state.spell = 4, 5, 768
        state.bonus, state.page = true, 9
        local bar = addon.CheckNativeContext({requiredForm = 768})
        expect(bar.page == 9 and bar.first == 97 and bar.formSpell == 768)
    end)
    test("a stance without a bonus page keeps the ordinary main bar", function()
        local state, addon = prepare()
        state.form, state.count, state.spell = 1, 2, 386208
        local bar = addon.NativeMainBar()
        expect(bar.page == 1 and bar.first == 1 and bar.formSpell == 386208)
    end)
    test("Rogue bonus pages block setup even without a reported shapeshift form", function()
        local state, addon = prepare()
        state.bonus, state.page = true, 7
        blocked(function() addon.CheckNativeContext({class = "ROGUE"}) end, "Leave Stealth or Shadow Dance")
        expect(addon.CheckNativeContext({class = "DRUID"}).page == 7)
        state.bonus, state.page = false, 1
        expect(addon.CheckNativeContext({class = "ROGUE"}).page == 1)
    end)
    test("native Undo context requires both the recorded page and form", function()
        local state, addon = prepare()
        state.form, state.count, state.spell = 2, 3, 5487
        state.bonus, state.page = true, 8
        local saved = addon.NativeMainBar()
        expect(addon.CheckNativeContext({nativeBar = saved}).first == saved.first)
        state.spell = 768
        blocked(function() addon.CheckNativeContext({nativeBar = saved}) end, "before Undo")
        state.spell, state.page = 5487, 9
        blocked(function() addon.CheckNativeContext({nativeBar = saved}) end, "before Undo")
    end)
    test("a missing required form blocks setup", function()
        local _, addon = prepare()
        blocked(function() addon.CheckNativeContext({requiredForm = 768}) end, "Enter ")
    end)
    test("caster form requirement accepts zero and rejects an active form", function()
        local state, addon = prepare()
        expect(addon.CheckNativeContext({requiredForm = 0}).formSpell == 0)
        state.form, state.count, state.spell = 1, 1, 5487
        blocked(function() addon.CheckNativeContext({requiredForm = 0}) end, "Return to caster form")
    end)
    for _, name in ipairs({"HasVehicleActionBar", "HasOverrideActionBar", "HasTempShapeshiftActionBar", "IsPossessBarVisible", "petBattle"}) do
        test("native setup blocks " .. name, function()
            local state, addon = prepare()
            state[name] = true
            blocked(addon.NativeMainBar, "nothing changed")
        end)
    end
    test("native setup rejects a manually paged main bar", function()
        local state, addon = prepare()
        state.selected = 2
        blocked(addon.NativeMainBar, "page 1")
    end)
    test("native setup rejects mounted players even on the ordinary main bar", function()
        local state, addon = prepare()
        state.mounted = true
        blocked(addon.NativeMainBar, "Dismount before changing your bars")
    end)
    test("native setup requires the mounted-state API", function()
        local _, addon = prepare()
        IsMounted = nil
        blocked(addon.NativeMainBar, "information is unavailable")
    end)
    test("native setup rejects missing and invalid API readings", function()
        local state, addon = prepare()
        C_ActionBar.HasBonusActionBar = nil
        blocked(addon.NativeMainBar, "information is unavailable")
        C_ActionBar.HasBonusActionBar = function() return 0 end
        blocked(addon.NativeMainBar, "information is unavailable")
        C_ActionBar.HasBonusActionBar = function() return true end
        state.page = 1
        blocked(addon.NativeMainBar, "information is unavailable")
    end)
    test("native setup rejects a form transition with no active spell", function()
        local state, addon = prepare()
        state.form, state.count, state.spell = 1, 1, 0
        blocked(addon.NativeMainBar, "form is still changing")
    end)
    test("native setup rejects missing or differently paged native buttons", function()
        local _, addon = prepare()
        ActionButton9.CalculateAction = function() return 99 end
        blocked(addon.NativeMainBar, "does not match")
        ActionButton9 = nil
        blocked(addon.NativeMainBar, "could not be checked")
    end)
    test("native context rejects an incomplete saved record", function()
        local _, addon = prepare()
        blocked(function() addon.CheckNativeContext({nativeBar = {page = 1}}) end, "incomplete main-bar information")
    end)
end
