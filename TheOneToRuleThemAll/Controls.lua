-- Read-only descriptions of the selected layout and Blizzard keybindings.
-- Binding names match Bindings_Standard.xml and MultiActionBars.lua: Bar 2
-- is MultiBarBottomLeft (page 6). Custom action-bar addons may use other keys.
local A = TheOneToRuleThemAll

local function bindingFor(slot, profile)
    if type(slot) ~= "number" or slot % 1 ~= 0 then return end
    if slot >= 1 and slot <= 12 then return "ACTIONBUTTON" .. slot end
    if slot >= 61 and slot <= 72 then return "MULTIACTIONBAR1BUTTON" .. (slot - 60) end
    if profile and profile.class == "ROGUE" and slot >= 73 and slot <= 84 then
        return "ACTIONBUTTON" .. (slot - 72)
    end
end

local function actionText(action)
    if type(action) ~= "table" then return "Unknown action" end
    if type(action.displayText) == "string" and action.displayText ~= "" then return action.displayText end
    if action.kind == "macro" then return tostring(action.name or "Unnamed macro") .. " (macro)" end
    if type(action.id) == "number" and action.kind == "spell" then
        local ok, name = pcall(A.api.spellName, action.id)
        if ok and type(name) == "string" and name ~= "" then return name end
        return "Spell " .. action.id
    end
    return "Unknown action"
end

local function keyText(key)
    -- Use the same localized key label as Blizzard's action buttons when it is
    -- available. Never infer a numbered default for an unbound button.
    if type(GetBindingText) == "function" then
        local ok, text = pcall(GetBindingText, key, 1)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    -- Preserve mouse/gamepad tokens if their localized labels are unavailable.
    return (key:gsub("ALT%-", "Alt+"):gsub("CTRL%-", "Ctrl+"):gsub("SHIFT%-", "Shift+"))
end

local function availableKeyText(key, binding)
    local text = keyText(key)
    if type(GetBindingAction) ~= "function" then return text .. " (unavailable: binding cannot be checked)" end
    local ok, action = pcall(GetBindingAction, key, true)
    if not ok or (action ~= nil and type(action) ~= "string") then
        return text .. " (unavailable: binding cannot be checked)"
    end
    if action and action ~= "" and action ~= binding then
        return text .. " (unavailable: bound to another action)"
    end
    return text
end

function A.ControlInfo(row, profile)
    row = type(row) == "table" and row or {}
    local action = type(row.action) == "table" and row.action or {}
    local alternate = type(action.altDisplayText) == "string" and action.altDisplayText ~= "" and action.altDisplayText or nil
    local info = {actionText=actionText(action),keysText="Check your action-bar addon",unbound=false}
    local binding = bindingFor(row.slot, profile)
    if not binding then
        if alternate then info.altKeysText = "Check your action-bar addon — " .. alternate end
        return info
    end
    if type(GetBindingKey) ~= "function" then
        info.keysText = "Bindings unavailable"
        if alternate then info.altKeysText = "Bindings unavailable — " .. alternate end
        return info
    end
    local ok, first, second = pcall(GetBindingKey, binding)
    if not ok then
        info.keysText = "Bindings unavailable"
        if alternate then info.altKeysText = "Bindings unavailable — " .. alternate end
        return info
    end
    local keys, seen, returned = {}, {}, {first, second}
    for i = 1, 2 do
        local key = returned[i]
        if type(key) == "string" and key ~= "" and not seen[key] then
            keys[#keys+1] = key
            seen[key] = true
        end
    end
    info.unbound = #keys == 0
    local ordinary, alternates, seenAlt = {}, {}, {}
    for _, key in ipairs(keys) do
        local hasAlt = key:find("ALT-", 1, true) ~= nil
        if not alternate or not hasAlt then ordinary[#ordinary+1] = availableKeyText(key, binding) end
        if alternate then
            local chord = hasAlt and key or ("ALT-" .. key)
            if not seenAlt[chord] then
                alternates[#alternates+1] = availableKeyText(chord, binding)
                seenAlt[chord] = true
            end
        end
    end
    info.keysText = #ordinary > 0 and table.concat(ordinary, " / ") or (info.unbound and "Unbound" or "No key without Alt")
    if alternate then
        info.altKeysText = (#alternates > 0 and table.concat(alternates, " / ") or "No bound key") .. " — " .. alternate
    end
    return info
end
