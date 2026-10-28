return function(c)
    local test, expect = c.test,c.expect
    local function info(slot, button)
        return c.addon().ControlInfo({slot=slot,mainButton=button,action={kind="spell",id=53}},
            {class="ROGUE",nativeMainBar=true})
    end
    test("Controls use real keys for each bar and native form page",function()
        local S=c.state()
        S.bindingKeys.ACTIONBUTTON1={"Q","BUTTON4"}
        S.bindingKeys.MULTIACTIONBAR1BUTTON1={"SHIFT-E"}
        S.bindingKeys.MULTIACTIONBAR2BUTTON1={"CTRL-F"}
        expect(info(1).keysText=="Q / BUTTON4" and info(97,1).keysText=="Q / BUTTON4")
        expect(info(61).keysText=="Shift+E" and info(49).keysText=="Ctrl+F")
        expect(info(1).actionText=="Backstab" and S.bindingCalls==0)
    end)
    test("Binding overrides are reported without changing bindings",function()
        c.state().bindings["1"]="CLICK OtherButton:LeftButton"
        expect(info(1).keysText:find("unavailable: bound to another action",1,true))
        expect(c.state().bindingCalls==0)
    end)
    test("Alt bindings remain ordinary keys without Compact",function()
        c.state().bindingKeys.ACTIONBUTTON1={"ALT-Q"}; expect(info(1).keysText=="Alt+Q")
    end)
    test("Unbound or unsupported slots never invent keys",function()
        expect(info(9).keysText=="Unbound" and info(9).unbound)
        expect(info(13).keysText=="Check your action-bar addon")
    end)
    test("Unavailable APIs leave readable controls",function()
        GetBindingKey=nil; expect(info(1).keysText=="Bindings unavailable")
        C_Spell.GetSpellName=function() return nil end; expect(info(1).actionText=="Spell 53")
    end)
    test("Localized labels preserve a secondary key",function()
        GetBindingKey=function() return nil,"BUTTON4" end
        GetBindingText=function() return "Souris 4" end; expect(info(1).keysText=="Souris 4")
    end)
end
