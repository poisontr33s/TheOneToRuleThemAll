-- Behavioral frame mocks. These exercise callbacks, event subscriptions and
-- button state; they do not emulate WoW rendering or secure execution.
local previousNames = {}
-- Exact set audited for this release against 12.1.5 event declarations.
-- This is an allowlist, not a general emulation of all client events.
local knownEvents = {
    PLAYER_REGEN_DISABLED=true, PLAYER_REGEN_ENABLED=true,
    PLAYER_SPECIALIZATION_CHANGED=true, PLAYER_TALENT_UPDATE=true,
    ACTIONBAR_PAGE_CHANGED=true, UPDATE_STEALTH=true, UPDATE_MACROS=true,
    UPDATE_BINDINGS=true, CURSOR_CHANGED=true,
}
return function(state)
    for _, name in ipairs(previousNames) do _G[name] = nil end
    previousNames = {}
    local S = state
    S.frames = {}
    UISpecialFrames = {}
    local methods = {}
    local function region(kind, name, parent)
        local obj = setmetatable({kind=kind, name=name, parent=parent, shown=true,
            enabled=true, scripts={}, events={}, points={}, width=0, height=0,
            text="", verticalScroll=0}, {__index=methods})
        S.frames[#S.frames+1] = obj
        if name then _G[name] = obj; previousNames[#previousNames+1] = name end
        return obj
    end
    function methods:SetSize(w,h) self.width=w; self.height=h end
    function methods:SetWidth(w) self.width=w end
    function methods:SetHeight(h) self.height=h end
    function methods:GetWidth() return self.width end
    function methods:GetHeight() return self.height end
    function methods:SetPoint(...) self.points[#self.points+1]={...} end
    function methods:SetAllPoints(target) self.allPoints=target or self.parent end
    function methods:ClearAllPoints() self.points={} end
    function methods:SetScript(event,fn) self.scripts[event]=fn end
    function methods:GetScript(event) return self.scripts[event] end
    function methods:HookScript(event,fn)
        local prior=self.scripts[event]
        self.scripts[event]=function(...)
            if prior then prior(...) end
            fn(...)
        end
    end
    function methods:Show()
        local changed=not self.shown; self.shown=true
        if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function methods:Hide()
        local changed=self.shown; self.shown=false
        if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:IsShown() return self.shown end
    function methods:IsVisible()
        return self.shown and (not self.parent or self.parent:IsVisible())
    end
    function methods:SetEnabled(value) self.enabled=not not value end
    function methods:IsEnabled() return self.enabled end
    function methods:Enable() self.enabled=true end
    function methods:Disable() self.enabled=false end
    function methods:Click(button)
        if self.enabled and self:IsVisible() and self.scripts.OnClick then
            self.scripts.OnClick(self,button or "LeftButton")
        end
    end
    function methods:SetText(text) self.text=tostring(text or "") end
    function methods:GetText() return self.text end
    function methods:GetStringHeight()
        local lines=0
        for _ in (self.text.."\n"):gmatch("[^\n]*\n") do lines=lines+1 end
        -- Enough for scrolling bounds in behavioral tests; not visual QA.
        return math.max(1,lines)*14
    end
    function methods:SetFormattedText(fmt,...) self:SetText(string.format(fmt,...)) end
    function methods:SetScrollChild(child) self.scrollChild=child end
    function methods:SetVerticalScroll(n) self.verticalScroll=n end
    function methods:GetVerticalScroll() return self.verticalScroll end
    function methods:RegisterEvent(event)
        assert(knownEvents[event], "Unknown or unaudited frame event: "..tostring(event))
        self.events[event]=true
    end
    function methods:UnregisterEvent(event) self.events[event]=nil end
    function methods:UnregisterAllEvents() self.events={} end
    function methods:IsEventRegistered(event) return not not self.events[event] end
    function methods:GetName() return self.name end
    function methods:CreateFontString(name,layer,template)
        return region("FontString",name,self)
    end
    function methods:CreateTexture(name,layer)
        return region("Texture",name,self)
    end
    function methods:SetHighlightTexture(texture)
        self.highlight=type(texture)=="table" and texture or region("Texture",nil,self)
    end
    function methods:GetHighlightTexture() return self.highlight end
    function methods:StartMoving() self.moving=true end
    function methods:StopMovingOrSizing() self.moving=false end
    for _, method in ipairs({"SetFrameStrata","SetClampedToScreen","SetMovable",
        "EnableMouse","RegisterForDrag","EnableMouseWheel","SetNormalFontObject",
        "SetHighlightFontObject","SetDisabledFontObject","SetColorTexture",
        "SetVertexColor","SetFontObject","SetJustifyH","SetJustifyV","SetTextColor",
        "SetWordWrap","SetNonSpaceWrap","SetSpacing","SetAlpha","SetFont",
        "SetTexture","SetDrawLayer","SetBackdrop","SetBackdropColor","SetBackdropBorderColor"}) do
        methods[method]=function(self,...) self["mock_"..method]={...} end
    end
    UIParent=region("Frame","UIParent",nil)
    UIParent:SetSize(1920,1080)
    CreateFrame=function(kind,name,parent,template)
        return region(kind,name,parent)
    end
    S.dispatchUIEvent=function(event,...)
        for _, frame in ipairs(S.frames) do
            if frame.events[event] and frame.scripts.OnEvent then
                frame.scripts.OnEvent(frame,event,...)
            end
        end
    end
end
