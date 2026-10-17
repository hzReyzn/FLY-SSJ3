local newWorld = require('./mock_roblox')
return function(source)
    local count = 0
    local function test(name, fn) fn(); count += 1; print('PASS '..name) end
    local function find(parent, name) return assert(parent:FindFirstChild(name, true), 'missing '..name) end
    local function near(a,b) assert(math.abs(a-b)<0.025, tostring(a)..' ~= '..tostring(b)) end
    local function click(gui, name) find(gui, name or 'FlightToggle').Activated:Fire() end
    local function launch(options)
        options = options or {}
        local w = newWorld()
        if options.place then w.env.game.PlaceId = options.place end
        for key,value in pairs(options) do w[key] = value end
        local char,hum,root = w.character()
        if not options.r6 then hum.RigType = w.env.Enum.HumanoidRigType.R15 end
        if options.playerModule then
            local module = w.env.Instance.new('ModuleScript');module.Name='PlayerModule';module.Parent=w.player:FindFirstChild('PlayerScripts')
        end
        w.run(source)
        return w,find(w.pg,'FlyDBZ'),char,hum,root
    end
    local function noOwnedObjects(w)
        for _,o in ipairs(w.objects) do
            if o.Name:find('FlyDBZ') then assert(o._destroying or o.Parent == nil, 'leaked '..o.Name) end
            if o.ClassName == 'AnimationTrack' then assert(o._destroying, 'track not disposed') end
        end
        for _,event in pairs(w.services.RunService) do assert(event:Count()==0, 'frame connection leaked') end
        assert(w.player.CharacterAdded:Count()==0 and w.player.CharacterRemoving:Count()==0)
    end
    local function assertOff(g,r)
        assert(find(g,'State').Text=='OFF' and not g:GetAttribute('FlightEnabled'))
        assert(not g:GetAttribute('NoFallDamageArmed'))
        if r then assert(not r:FindFirstChild('FlyDBZVelocity') and not r:FindFirstChild('FlyDBZOrientation')) end
    end
    local function editSpeed(g,text)
        local box=find(g,'SpeedValue');box.Text=text;box.FocusLost:Fire(true)
    end
    test('initial state is OFF with speed five, no protection or animation started', function()
        local w,g,_,h,r=launch();w.step(30);assertOff(g,r)
        assert(g:GetAttribute('Version')=='1.0' and g:GetAttribute('FlightSpeed')==5)
        assert(find(g,'SpeedValue').Text=='5' and not h.PlatformStand)
        assert(#w.loadedTracks==0 and #w.requests==0,'OFF loaded an animation')
        assert(find(g,'Window').Size.X.Offset<=250 and find(g,'Window').Size.Y.Offset<=170)
        for _,name in ipairs({'FlightToggle','SpeedUp','SpeedDown'}) do assert(find(g,name).Size.Y.Offset>=40) end
        g:Destroy();noOwnedObjects(w)
    end)
    test('no VFX, announcement or graphics mutations are created in any state', function()
        local w,g=launch();click(g);w.step(60);click(g);w.character();w.step(30)
        local forbidden={ParticleEmitter=true,Beam=true,Trail=true,PointLight=true,SpotLight=true,
            Fire=true,Smoke=true,Sparkles=true,Sound=true,BloomEffect=true,ColorCorrectionEffect=true}
        for _,object in ipairs(w.objects) do
            assert(not forbidden[object.ClassName],'effect created: '..object.ClassName)
            assert(object.Name~='QualityNotice' and object.Name~='ActivationFlash' and object.Name~='WindowFireLayer')
            if object.Text then assert(not object.Text:find('graphics settings')) end
        end
        local objects=#w.objects;w.step(180);assert(#w.objects==objects,'idle frame allocation')
        g:Destroy();noOwnedObjects(w)
    end)
    test('No Fall Damage only pulses in ON and manual OFF restores a pending pulse', function()
        local w,g,_,_,r=launch();local v=w.env.Vector3.new(5,-130,7)
        r.AssemblyLinearVelocity=v;w.services.RunService.Heartbeat:Fire(.02);assert(r.AssemblyLinearVelocity==v)
        click(g);assert(g:GetAttribute('NoFallDamageArmed'))
        w.services.RunService.Heartbeat:Fire(.02);assert(r.AssemblyLinearVelocity==w.env.Vector3.zero)
        w.services.RunService.RenderStepped:Fire(.02);assert(r.AssemblyLinearVelocity==v)
        w.services.RunService.Heartbeat:Fire(.02);click(g);assertOff(g,r)
        assert(r.AssemblyLinearVelocity==v);w.step(3);assert(r.AssemblyLinearVelocity==v)
        g:Destroy();noOwnedObjects(w)
    end)
    test('No Fall Damage fallback respects external velocity writes', function()
        local w,g,_,_,r=launch();click(g);local v=w.env.Vector3.new(1,-90,3)
        r.AssemblyLinearVelocity=v;w.services.RunService.Heartbeat:Fire(.02)
        w.services.RunService.PreSimulation:Fire(.02);assert(r.AssemblyLinearVelocity==v)
        w.services.RunService.Heartbeat:Fire(.02)
        local other=w.env.Vector3.new(20,10,0);r.AssemblyLinearVelocity=other
        w.services.RunService.RenderStepped:Fire(.02);assert(r.AssemblyLinearVelocity==other)
        w.services.RunService.Heartbeat:Fire(.02);g:Destroy();assert(r.AssemblyLinearVelocity==other)
        noOwnedObjects(w)
    end)
    test('place guard and temporarily anchored characters do not receive protection pulses', function()
        local w,g,_,_,r=launch({place=123});click(g);local v=w.env.Vector3.new(0,-100,0)
        r.AssemblyLinearVelocity=v;w.step(2)
        assert(r.AssemblyLinearVelocity==v and not g:GetAttribute('NoFallDamageArmed'));g:Destroy()
        w,g,_,_,r=launch();click(g);r.Anchored=true;r.AssemblyLinearVelocity=v;w.step(2)
        assert(not r:FindFirstChild('FlyDBZVelocity') and not g:GetAttribute('NoFallDamageArmed'))
        assert(r.AssemblyLinearVelocity==v)
        r.Anchored=false;w.step(2);assert(find(r,'FlyDBZVelocity') and g:GetAttribute('NoFallDamageArmed'))
        g:Destroy();noOwnedObjects(w)
    end)
    test('owned movers and humanoid settings are fully restored on OFF', function()
        local w,g,_,h,r=launch();click(g)
        assert(find(g,'State').Text=='ON' and h.PlatformStand and not h.AutoRotate)
        assert(find(r,'FlyDBZVelocity').ForceLimitsEnabled==false)
        assert(find(r,'FlyDBZVelocity').RelativeTo.Name=='World')
        assert(find(r,'FlyDBZOrientation').Mode.Name=='OneAttachment')
        click(g);assertOff(g,r);assert(h.AutoRotate and not h.PlatformStand)
        assert(not r:FindFirstChild('FlyDBZMoverAttachment'))
        for _,track in ipairs(w.loadedTracks) do assert(track._destroying and not track.IsPlaying) end
        g:Destroy();noOwnedObjects(w)
    end)
    test('preexisting humanoid settings survive an activation cycle', function()
        local w,g,_,h=launch();h.PlatformStand=true;h.AutoRotate=false
        click(g);click(g);assert(h.PlatformStand and not h.AutoRotate);g:Destroy()
    end)
    test('PC WASD, normalized diagonals, smooth stop and vertical camera control', function()
        local w,g,_,_,r=launch();click(g);w.keys.W=true;w.step(90)
        local mover=find(r,'FlyDBZVelocity');near(mover.VectorVelocity.Z,-5)
        w.keys.D=true;w.step(90);near(mover.VectorVelocity.Magnitude,5)
        assert(mover.VectorVelocity.X>3.5 and mover.VectorVelocity.Z< -3.5)
        w.keys={};w.step(90);near(mover.VectorVelocity.Magnitude,0)
        w.env.workspace.CurrentCamera.CFrame.LookVector=w.env.Vector3.new(0,.6,-.8)
        w.keys.W=true;w.step(90);near(mover.VectorVelocity.Y,3);near(mover.VectorVelocity.Z,-4)
        g:Destroy()
    end)
    test('mobile joystick preserves analog movement and hover', function()
        local w,g,_,_,r=launch({playerModule=true});click(g)
        w.move=w.env.Vector3.new(.5,0,0);w.step(90);near(find(r,'FlyDBZVelocity').VectorVelocity.X,2.5)
        w.move=w.env.Vector3.new(0,0,-1);w.step(90);near(find(r,'FlyDBZVelocity').VectorVelocity.Z,-5)
        w.move=w.env.Vector3.zero;w.step(90);near(find(r,'FlyDBZVelocity').VectorVelocity.Magnitude,0)
        g:Destroy()
    end)
    test('fallback touch movement, typing, focus loss and camera loss are handled', function()
        local w,g,_,h,r=launch();click(g);h.MoveDirection=w.env.Vector3.new(1,0,0);w.step(90)
        local mover=find(r,'FlyDBZVelocity');near(mover.VectorVelocity.X,5)
        w.textFocused=true;w.step(90);near(mover.VectorVelocity.Magnitude,0)
        w.textFocused=nil;w.services.UserInputService.WindowFocusReleased:Fire();w.step(90);near(mover.VectorVelocity.Magnitude,0)
        w.services.UserInputService.WindowFocused:Fire();w.step(90);near(mover.VectorVelocity.X,5)
        w.env.workspace.CurrentCamera=nil;w.step(90);near(mover.VectorVelocity.Magnitude,0);g:Destroy()
    end)
    test('SSJ3 clips load only in ON on the existing Animator and are disposed in OFF', function()
        local w,g,_,h=launch();assert(#w.loadedTracks==0);click(g);assert(#w.loadedTracks==4)
        local animator=h:FindFirstChildOfClass('Animator')
        for _,track in ipairs(w.loadedTracks) do
            assert(track.Animator==animator and track.AnimationId:sub(-1)=='7')
            assert(track.Priority.Name=='Action' and track.Looped)
        end
        for _,object in ipairs(w.imports) do assert(object._destroying and object.Parent==nil) end
        w.step(2);assert(w.loadedTracks[1].IsPlaying)
        w.keys.W=true;w.step(3);assert(w.loadedTracks[2].IsPlaying and not w.loadedTracks[1].IsPlaying)
        click(g);for _,track in ipairs(w.loadedTracks) do assert(track._destroying and not track.IsPlaying) end
        click(g);w.step(2);assert(#w.loadedTracks==8 and w.loadedTracks[6].IsPlaying)
        local count=0;for _,o in ipairs(w.objects) do if o:IsA('Animator') then count+=1 end end
        assert(count==1,'client created an Animator');g:Destroy();noOwnedObjects(w)
    end)
    test('R6 and denied packages preserve usable flight without replacement animation', function()
        for _,options in ipairs({{r6=true},{importFailure=true},{loadFailure=true},{zeroTrackLength=true}}) do
            local w,g,_,_,r=launch(options);click(g);w.step(500)
            assert(find(r,'FlyDBZVelocity') and #w.warnings>0)
            assert(g:GetAttribute('AnimationStatus')==(options.r6 and 'R15Required' or 'Unavailable'))
            g:Destroy();noOwnedObjects(w)
        end
    end)
    test('death shuts off flight, protection and tracks until a fresh manual activation', function()
        local w,g,_,h,r=launch();click(g);w.step(5)
        local v=w.env.Vector3.new(3,-90,2);r.AssemblyLinearVelocity=v;w.services.RunService.Heartbeat:Fire(.02)
        h.Health=0;assertOff(g,r);assert(r.AssemblyLinearVelocity==v)
        h.Died:Fire();click(g);assertOff(g,r)
        for _,track in ipairs(w.loadedTracks) do assert(track._destroying and not track.IsPlaying) end
        local _,h2,r2=w.character();h2.RigType=w.env.Enum.HumanoidRigType.R15;w.step(90)
        assertOff(g,r2);assert(not h2.PlatformStand)
        r2.AssemblyLinearVelocity=v;w.step(3);assert(r2.AssemblyLinearVelocity==v)
        click(g);w.step(3);assert(g:GetAttribute('FlightEnabled') and g:GetAttribute('NoFallDamageArmed'))
        assert(find(r2,'FlyDBZVelocity') and w.loadedTracks[#w.loadedTracks-3].IsPlaying)
        g:Destroy();noOwnedObjects(w)
    end)
    test('reset without Died and CharacterAdded without removing both discard ON', function()
        for _,skipRemoving in ipairs({false,true}) do
            local w,g,_,_,r=launch();click(g);w.step(3)
            if skipRemoving then w.player.Character=nil end
            local _,h2,r2=w.character();w.step(10);assertOff(g,r2)
            assert(not r:FindFirstChild('FlyDBZVelocity') and not h2.PlatformStand)
            for _,track in ipairs(w.loadedTracks) do assert(track._destroying and not track.IsPlaying) end
            click(g);assert(find(r2,'FlyDBZVelocity'));g:Destroy();noOwnedObjects(w)
        end
    end)
    test('missing character parts cannot queue ON; late Animator binds only while active', function()
        local w,g=launch();local c,h,r=w.character();h.RigType=w.env.Enum.HumanoidRigType.R15
        h.Parent=nil;r.Parent=nil;local anim=h:FindFirstChildOfClass('Animator');anim.Parent=nil
        click(g);assertOff(g)
        h.Parent=c;r.Parent=c;w.step(1);assertOff(g,r)
        click(g);assert(find(r,'FlyDBZVelocity') and #w.loadedTracks==0)
        anim.Parent=h;w.step(2);assert(#w.loadedTracks==4)
        local count=#w.loadedTracks;w.step(90);assert(#w.loadedTracks==count)
        g:Destroy();noOwnedObjects(w)
    end)
    test('replaced root disarms the old body and requires manual ON', function()
        local w,g,c,_,r=launch();click(g);r.Parent=nil;assertOff(g,r)
        local root=w.env.Instance.new('Part');root.Name='HumanoidRootPart';root.Parent=c;w.step(2)
        assertOff(g,root);click(g);assert(find(root,'FlyDBZVelocity'))
        g:Destroy();noOwnedObjects(w)
    end)
    test('falling into the void disarms before Roblox destroys the root', function()
        local w,g,_,_,r=launch();w.env.workspace.FallenPartsDestroyHeight=-500;click(g);w.step(2)
        r.CFrame=w.env.CFrame.new(0,-501,0);w.step(2);assertOff(g,r)
        assert(r.Parent,'test must cover a root that still exists')
        click(g);assertOff(g,r)
        local _,_,fresh=w.character();w.step(2);assertOff(g,fresh)
        click(g);assert(find(fresh,'FlyDBZVelocity'));g:Destroy();noOwnedObjects(w)
    end)
    test('detaching the whole character without removal events shuts down flight', function()
        local w,g,c,_,r=launch();click(g);c.Parent=nil;w.step(2);assertOff(g,r)
        for _,track in ipairs(w.loadedTracks) do assert(track._destroying and not track.IsPlaying) end
        local _,_,fresh=w.character();w.step(2);assertOff(g,fresh)
        g:Destroy();noOwnedObjects(w)
    end)
    test('late imports and animation loads cannot reactivate after OFF, death or close', function()
        for _,options in ipairs({{importDelay=1},{loadDelay=1}}) do
            for _,action in ipairs({'off','death','close'}) do
                local w,g,_,h,r=launch(options);click(g)
                if action=='off' then click(g) elseif action=='death' then h.Health=0;h.Died:Fire() else g:Destroy() end
                w.step(300)
                for _,object in ipairs(w.imports) do assert(object._destroying) end
                for _,track in ipairs(w.loadedTracks) do assert(track._destroying and not track.IsPlaying) end
                if action~='close' then assertOff(g,r);g:Destroy() end
                noOwnedObjects(w)
            end
        end
    end)
    test('Animator replacement discards old clips and binds the replacement once', function()
        local w,g,_,h=launch();click(g);w.step(3)
        local old=h:FindFirstChildOfClass('Animator');old.Parent=nil
        for _,track in ipairs(w.loadedTracks) do assert(track._destroying) end
        local animator=w.env.Instance.new('Animator');animator.Parent=h;w.step(3)
        assert(#w.loadedTracks==8 and w.loadedTracks[5].Animator==animator and w.loadedTracks[5].IsPlaying)
        g:Destroy();noOwnedObjects(w)
    end)
    test('rapid toggles and reexecution do not duplicate subscriptions or inherit ON', function()
        local w,g=launch();for _=1,30 do click(g);w.step(1) end;assertOff(g)
        click(g);w.run(source);local nextGui=find(w.pg,'FlyDBZ');assert(nextGui~=g and g._destroying)
        assertOff(nextGui)
        for _,key in ipairs({'PreSimulation','Heartbeat','RenderStepped'}) do assert(w.services.RunService[key]:Count()==1) end
        nextGui:Destroy();noOwnedObjects(w)
    end)
    test('close immediately stops functions, restores the pending velocity and cleans up', function()
        local w,g,_,h,r=launch();click(g);w.step(3)
        local v=w.env.Vector3.new(10,-10,3);r.AssemblyLinearVelocity=v;w.services.RunService.Heartbeat:Fire(.02)
        click(g,'Close');assert(g.Parent==nil and r.AssemblyLinearVelocity==v)
        assert(not h.PlatformStand and not r:FindFirstChild('FlyDBZVelocity'))
        w.step(60);noOwnedObjects(w)
    end)
    test('mouse and touch dragging follow movement and stop on release', function()
        local w,g=launch();local window=find(g,'Window')
        for _,touch in ipairs({false,true}) do
            local p=window.Position
            local input={UserInputType=touch and w.env.Enum.UserInputType.Touch or w.env.Enum.UserInputType.MouseButton1,Position=w.env.Vector3.new(100,100)}
            find(g,'DragHandle').InputBegan:Fire(input)
            local change=touch and input or {UserInputType=w.env.Enum.UserInputType.MouseMovement}
            change.Position=w.env.Vector3.new(150,130);w.services.UserInputService.InputChanged:Fire(change)
            near(window.Position.X.Offset,p.X.Offset+50);near(window.Position.Y.Offset,p.Y.Offset+30)
            w.services.UserInputService.InputEnded:Fire(input)
            change.Position=w.env.Vector3.new(200,200);w.services.UserInputService.InputChanged:Fire(change)
            near(window.Position.X.Offset,p.X.Offset+50)
        end
        g:Destroy()
    end)
    test('buttons and wheel step by five with both lower and upper bounds', function()
        local w,g=launch();click(g,'SpeedDown');assert(find(g,'SpeedValue').Text=='5')
        click(g,'SpeedUp');assert(find(g,'SpeedValue').Text=='10')
        find(g,'SpeedControl').MouseEnter:Fire()
        w.services.UserInputService.InputChanged:Fire({UserInputType=w.env.Enum.UserInputType.MouseWheel,Position=w.env.Vector3.new(0,0,1)})
        assert(g:GetAttribute('FlightSpeed')==15)
        w.services.UserInputService.InputChanged:Fire({UserInputType=w.env.Enum.UserInputType.MouseWheel,Position=w.env.Vector3.new(0,0,-1)})
        assert(g:GetAttribute('FlightSpeed')==10)
        find(g,'SpeedControl').MouseLeave:Fire()
        w.services.UserInputService.InputChanged:Fire({UserInputType=w.env.Enum.UserInputType.MouseWheel,Position=w.env.Vector3.new(0,0,1)})
        assert(g:GetAttribute('FlightSpeed')==10);assertOff(g)
        editSpeed(g,'4999');click(g,'SpeedUp');assert(g:GetAttribute('FlightSpeed')==5000)
        click(g,'SpeedUp');assert(g:GetAttribute('FlightSpeed')==5000)
        click(g,'SpeedDown');assert(g:GetAttribute('FlightSpeed')==4995)
        g:Destroy()
    end)
    test('speed changes during flight apply without restarting movers or animation', function()
        local w,g,_,_,r=launch();click(g);w.keys.W=true;w.step(90)
        local mover=find(r,'FlyDBZVelocity');local track=w.loadedTracks[2];near(mover.VectorVelocity.Z,-5)
        click(g,'SpeedUp');w.step(90);near(mover.VectorVelocity.Z,-10)
        editSpeed(g,'140');w.step(90);near(mover.VectorVelocity.Z,-140)
        click(g,'SpeedDown');w.step(90);near(mover.VectorVelocity.Z,-135)
        editSpeed(g,'9000');w.step(120);near(mover.VectorVelocity.Z,-5000)
        assert(find(r,'FlyDBZVelocity')==mover and #w.loadedTracks==4 and track.IsPlaying)
        assert(g:GetAttribute('FlightEnabled') and g:GetAttribute('NoFallDamageArmed'))
        g:Destroy();noOwnedObjects(w)
    end)
    test('manual entry clamps finite values, rounds decimals and rejects invalid text', function()
        local w,g=launch();local box=find(g,'SpeedValue')
        for _,text in ipairs({'0','-12','1'}) do editSpeed(g,text);assert(box.Text=='5') end
        for _,text in ipairs({'5001','1000000','1e300'}) do editSpeed(g,text);assert(box.Text=='5000') end
        editSpeed(g,'72,5');assert(box.Text=='73')
        for _,text in ipairs({'','abc','NaN','inf','1e309'}) do editSpeed(g,text);assert(box.Text=='73') end
        g:Destroy()
    end)
    test('editing plus a step commits once; chosen speed persists after death while OFF', function()
        local w,g,_,h=launch();local box=find(g,'SpeedValue')
        w.textFocused=box;box.Text='140';click(g,'SpeedUp')
        assert(w.textFocused==nil and box.Text=='145' and g:GetAttribute('FlightSpeed')==145)
        box.FocusLost:Fire(false);assert(box.Text=='145')
        click(g);h.Health=0;h.Died:Fire();local _,_,r=w.character();w.step(90)
        assertOff(g,r);assert(box.Text=='145')
        click(g);w.keys.W=true;w.step(90);near(find(r,'FlyDBZVelocity').VectorVelocity.Z,-145)
        g:Destroy();noOwnedObjects(w)
    end)
    test('starting without a character never queues automatic activation', function()
        local w=newWorld();w.run(source);local g=find(w.pg,'FlyDBZ')
        click(g);assertOff(g);local _,_,r=w.character();w.step(30);assertOff(g,r)
        click(g);assert(find(r,'FlyDBZVelocity'));g:Destroy();noOwnedObjects(w)
    end)
    print(tostring(count)..' behavioral tests passed; Roblox physics/rendering validation remains manual.')
end
