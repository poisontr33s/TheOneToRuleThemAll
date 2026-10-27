-- Descriptions read Blizzard's bindings; they must never assign a key or
-- inspect an action through the cursor. These tests do not emulate the client.
return function(c)
    local test, expect, copy, equal = c.test, c.expect, c.copy, c.equal
    local function row(id, layout, slot)
        local A = c.addon()
        local profile = A.profiles[id or "subburst"]
        local plan = profile.build(A.api, layout or "standard", false)
        for _, r in ipairs(plan.rows) do
            if r.slot == slot then return r, profile end
        end
        error("Missing test row " .. slot)
    end
    local function info(id, layout, slot)
        return c.addon().ControlInfo(row(id, layout, slot))
    end
    local function has(text, part) return text and text:find(part, 1, true) ~= nil end
    local function withGlobal(name, value, fn)
        local original = _G[name]
        _G[name] = value
        local ok, result = pcall(fn)
        _G[name] = original
        expect(ok, result)
        return result
    end

    test("controls show rebound primary and secondary keys without numeric defaults", function()
        local S = c.state()
        S.bindingKeys.ACTIONBUTTON1 = {"Q", "BUTTON4"}
        local result = info("subburst", "standard", 1)
        expect(result.keysText == "Q / BUTTON4" and not result.unbound)
        expect(has(result.actionText, "Backstab") and has(result.actionText, "Shadowstrike"))
        expect(not has(result.actionText, "TOR Builder") and not result.altKeysText)
    end)
    test("controls use Action Bar 2 bindings rather than main-bar keys", function()
        local S = c.state()
        S.bindingKeys.ACTIONBUTTON1 = {"Q"}
        S.bindingKeys.MULTIACTIONBAR1BUTTON1 = {"SHIFT-E", "CTRL-BUTTON5"}
        local result = info("subburst", "standard", 61)
        expect(result.keysText == "Shift+E / Ctrl+BUTTON5")
        expect(result.actionText == "Shadow Dance")
    end)
    test("controls ordinary keys respect overrides rather than promising a different action", function()
        local S = c.state()
        S.bindingKeys.ACTIONBUTTON1 = {"Q", "BUTTON4"}
        local checked = {}
        local result = withGlobal("GetBindingAction", function(key, overrides)
            checked[#checked+1] = {key, overrides}
            return key == "Q" and "CLICK OtherButton:LeftButton" or "ACTIONBUTTON1"
        end, function() return info("subburst", "standard", 1) end)
        expect(result.keysText == "Q (unavailable: bound to another action) / BUTTON4")
        expect(not result.unbound)
        expect(#checked == 2 and checked[1][2] == true and checked[2][2] == true)
    end)
    test("controls use Blizzard localized key labels for normal and Alt mouse bindings", function()
        c.state().bindingKeys.ACTIONBUTTON1 = {"BUTTON4"}
        local checked = {}
        local result = withGlobal("GetBindingText", function(key, abbreviation)
            checked[#checked+1] = {key, abbreviation}
            return key == "BUTTON4" and "Souris 4" or "Alt-Souris 4"
        end, function() return info("subburst", "compact", 1) end)
        expect(result.keysText == "Souris 4")
        expect(result.altKeysText == "Alt-Souris 4 — Spell197835")
        expect(#checked == 2 and checked[1][2] == 1 and checked[2][2] == 1)
    end)
    test("controls keep actual keys when localized labels fail or are empty", function()
        c.state().bindingKeys.ACTIONBUTTON1 = {"SHIFT-BUTTON4"}
        for _, formatter in ipairs({
            function() error("not ready") end,
            function() return "" end,
            function() return nil end,
        }) do
            local result = withGlobal("GetBindingText", formatter, function() return info("subburst", "compact", 1) end)
            expect(result.keysText == "Shift+BUTTON4")
            expect(result.altKeysText == "Alt+Shift+BUTTON4 — Spell197835")
        end
    end)
    test("controls mark an unbound slot without inventing a key", function()
        local result = info("subburst", "standard", 7)
        expect(result.unbound and result.keysText == "Unbound")
    end)
    test("controls compact chords follow rebound keys including existing modifiers", function()
        local S = c.state()
        S.bindingKeys.ACTIONBUTTON1 = {"SHIFT-Q", "CTRL-BUTTON4"}
        local result = info("subburst", "compact", 1)
        expect(result.keysText == "Shift+Q / Ctrl+BUTTON4")
        expect(result.altKeysText == "Alt+Shift+Q / Alt+Ctrl+BUTTON4 — Spell197835")
        expect(not has(result.altKeysText, "Alt+1"))
    end)
    test("controls compact Alt conflicts are unavailable and use override-aware lookup", function()
        local S = c.state()
        S.bindingKeys.ACTIONBUTTON1 = {"Q", "E"}
        S.bindings["ALT-Q"] = "ACTIONPAGE1"
        S.bindings["ALT-E"] = "ACTIONBUTTON1"
        local original = GetBindingAction
        local checked = {}
        GetBindingAction = function(key, overrides)
            checked[#checked+1] = {key, overrides}
            return original(key)
        end
        local result = info("subburst", "compact", 1)
        GetBindingAction = original
        expect(has(result.altKeysText, "Alt+Q (unavailable: bound to another action)"))
        expect(has(result.altKeysText, " / Alt+E — Spell197835"))
        expect(#checked == 4)
        for _, call in ipairs(checked) do expect(call[2] == true) end
    end)
    test("controls compact never describes an Alt-only key as the ordinary action", function()
        c.state().bindingKeys.ACTIONBUTTON1 = {"ALT-Q"}
        local result = info("subburst", "compact", 1)
        expect(result.keysText == "No key without Alt" and not result.unbound)
        expect(result.altKeysText == "Alt+Q — Spell197835")
    end)
    test("controls compact keeps ordinary and already-Alt keys separate without duplicate chords", function()
        c.state().bindingKeys.ACTIONBUTTON1 = {"Q", "ALT-Q"}
        local result = info("subburst", "compact", 1)
        expect(result.keysText == "Q")
        expect(result.altKeysText == "Alt+Q — Spell197835")
    end)
    test("controls compact unbound alternate gives no made-up modifier key", function()
        c.state().bindingKeys.ACTIONBUTTON2 = {}
        local result = info("subburst", "compact", 2)
        expect(result.unbound and result.keysText == "Unbound")
        expect(has(result.altKeysText, "No bound key — Black Powder / Coup de Grace"))
    end)
    test("controls describe localized macro abilities and Assassination alternates", function()
        local S = c.state()
        S.names[1329], S.names[51723] = "Mutilation", "Éventail de couteaux"
        S.names[32645], S.names[1247227] = "Envenimer", "Tempête cramoisie"
        S.bindingKeys.ACTIONBUTTON1 = {"Q"}
        S.bindingKeys.ACTIONBUTTON2 = {"E"}
        local generator = info("assa", "compact", 1)
        local spender = info("assa", "compact", 2)
        expect(generator.actionText == "Mutilation" and generator.altKeysText == "Alt+Q — Éventail de couteaux")
        expect(spender.actionText == "Envenimer" and spender.altKeysText == "Alt+E — Tempête cramoisie")
    end)
    test("controls describe native Coup replacement and coupled burst without macro IDs", function()
        local S = c.state()
        S.names[196819] = "Eviscerate"
        expect(info("subburst", "standard", 3).actionText == "Eviscerate / Coup de Grace")
        expect(info("subburst", "standard", 6).actionText == "Shadow Dance + Shadow Blades + Goremaw's Bite")
        expect(info("sub", "standard", 6).actionText == "Shadow Dance + Shadow Blades")
    end)
    test("controls map Rogue stealth slots only for Rogue profiles", function()
        local A = c.addon()
        local r, p = row("subburst", "compact", 73)
        local mirrored = A.ControlInfo(r, p)
        expect(mirrored.keysText == "1" and has(mirrored.altKeysText, "Alt+1"))
        for _, profile in ipairs({{class="MAGE"}, {}}) do
            local result = A.ControlInfo(r, profile)
            expect(result.keysText == "Check your action-bar addon" and not result.unbound)
        end
    end)
    test("controls unknown slots and malformed rows do not invent supported bindings", function()
        local A = c.addon()
        for _, slot in ipairs({0, 13, 48, 85, 1.5, "1"}) do
            local result = A.ControlInfo({slot=slot, action={kind="spell", id=1766}}, {class="ROGUE"})
            expect(result.keysText == "Check your action-bar addon")
        end
        local result = A.ControlInfo(nil, nil)
        expect(result.actionText == "Unknown action" and result.keysText == "Check your action-bar addon")
    end)
    test("controls tolerate unavailable or failing binding APIs", function()
        local originalKey, originalAction = GetBindingKey, GetBindingAction
        GetBindingKey = nil
        local absent = info("subburst", "compact", 1)
        GetBindingKey = function() error("not ready") end
        local failed = info("subburst", "standard", 1)
        GetBindingKey = originalKey
        GetBindingAction = nil
        local cannotCheck = info("subburst", "compact", 1)
        GetBindingAction = originalAction
        expect(absent.keysText == "Bindings unavailable" and not absent.unbound)
        expect(has(absent.altKeysText, "Bindings unavailable"))
        expect(failed.keysText == "Bindings unavailable")
        expect(has(cannotCheck.altKeysText, "unavailable: binding cannot be checked"))
    end)
    test("controls tolerate missing primary key, duplicate keys and unavailable spell names", function()
        local S = c.state()
        local originalKey = GetBindingKey
        GetBindingKey = function() return nil, "Q" end
        local secondary = info("subburst", "standard", 1)
        GetBindingKey = originalKey
        expect(secondary.keysText == "Q")
        S.bindingKeys.ACTIONBUTTON1 = {"Q", "Q"}
        expect(info("subburst", "standard", 1).keysText == "Q")
        local original = C_Spell.GetSpellName
        C_Spell.GetSpellName = function() return nil end
        local result = c.addon().ControlInfo({slot=7, action={kind="spell", id=1766}}, {class="ROGUE"})
        C_Spell.GetSpellName = original
        expect(result.actionText == "Spell 1766")
    end)
    test("controls inspecting all profiles preserves actions macros cursor bindings and saved data", function()
        local S, A = c.state(), c.addon()
        S.cursor = {kind="item", id=1234}
        S.slots[1] = {kind="macro", id=121}
        S.macros[121] = {name="Original", body="/cast Original", icon=134400}
        TheOneToRuleThemAllDB = {version=1, marker="unchanged"}
        local before = {slots=copy(S.slots),macros=copy(S.macros),cursor=copy(S.cursor),bindings=copy(S.bindings),
            bindingKeys=copy(S.bindingKeys),db=copy(TheOneToRuleThemAllDB),created=S.created,placements=S.placements,bindingCalls=S.bindingCalls}
        for _, profile in pairs(A.profiles) do
            for layout in pairs(profile.layouts) do
                local plan = profile.build(A.api, layout, false)
                local beforePlan = copy(plan)
                for _, r in ipairs(plan.rows) do A.ControlInfo(r, profile) end
                expect(equal(plan, beforePlan), "Description mutated the plan")
            end
        end
        expect(equal(before.slots,S.slots) and equal(before.macros,S.macros) and equal(before.cursor,S.cursor))
        expect(equal(before.bindings,S.bindings) and equal(before.bindingKeys,S.bindingKeys) and equal(before.db,TheOneToRuleThemAllDB))
        expect(before.created==S.created and before.placements==S.placements and before.bindingCalls==S.bindingCalls)
    end)
end
