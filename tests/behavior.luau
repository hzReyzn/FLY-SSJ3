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
    test('compact neutral GUI starts OFF, permanent No Fall Damage armed', function()
        local w,g,_,h,r=launch();w.step(30)
        assert(find(g,'State').Text=='OFF' and not g:GetAttribute('FlightEnabled'))
        assert(g:GetAttribute('NoFallDamageArmed') and g:GetAttribute('Version')=='1.0')
        assert(find(g,'Window').Size.X.Offset==228 and find(g,'Window').Size.Y.Offset==96)
        assert(find(g,'FlightToggle').Size.Y.Offset>=40)
        assert(not r:FindFirstChild('FlyDBZVelocity') and not h.PlatformStand)
        for _,o in ipairs(g:GetDescendants()) do
            if o.Text~='' then assert(o.Text=='FLY DBZ' or o.Text=='OFF' or o.Text=='×') end
        end
        g:Destroy();noOwnedObjects(w)
    end)
    test('NFD pulses while flight OFF and restores before rendering', function()
        local w,g,_,_,r=launch()
        local velocity=w.env.Vector3.new(5,-130,7);r.AssemblyLinearVelocity=velocity
        w.services.RunService.Heartbeat:Fire(1/60)
        assert(r.AssemblyLinearVelocity==w.env.Vector3.zero)
        w.services.RunService.RenderStepped:Fire(1/60)
        assert(r.AssemblyLinearVelocity==velocity and find(g,'State').Text=='OFF')
        g:Destroy()
    end)
    test('NFD fallback, external velocity writes, and close restoration', function()
        local w,g,_,_,r=launch();local v=w.env.Vector3.new(1,-90,3)
        r.AssemblyLinearVelocity=v;w.services.RunService.Heartbeat:Fire(.02)
        w.services.RunService.PreSimulation:Fire(.02);assert(r.AssemblyLinearVelocity==v)
        w.services.RunService.Heartbeat:Fire(.02)
        local other=w.env.Vector3.new(20,10,0);r.AssemblyLinearVelocity=other
        w.services.RunService.RenderStepped:Fire(.02);assert(r.AssemblyLinearVelocity==other)
        w.services.RunService.Heartbeat:Fire(.02);g:Destroy();assert(r.AssemblyLinearVelocity==other)
        noOwnedObjects(w)
    end)
    test('NFD respects supplied place guard and anchored roots', function()
        local w,g,_,_,r=launch({place=123});local v=w.env.Vector3.new(0,-100,0)
        r.AssemblyLinearVelocity=v;w.services.RunService.Heartbeat:Fire(.02)
        assert(r.AssemblyLinearVelocity==v and not g:GetAttribute('NoFallDamageArmed'));g:Destroy()
        w,g,_,_,r=launch();r.Anchored=true;r.AssemblyLinearVelocity=v
        w.services.RunService.Heartbeat:Fire(.02);assert(r.AssemblyLinearVelocity==v);g:Destroy()
    end)
    test('flight creates only owned modern movers and restores humanoid settings', function()
        local w,g,_,h,r=launch();click(g)
        assert(find(g,'State').Text=='ON' and h.PlatformStand and not h.AutoRotate)
        assert(find(r,'FlyDBZVelocity').ForceLimitsEnabled==false)
        assert(find(r,'FlyDBZVelocity').RelativeTo.Name=='World')
        assert(find(r,'FlyDBZOrientation').Mode.Name=='OneAttachment')
        assert(find(g,'ActivationFlash').BackgroundTransparency<1)
        click(g);w.step(45)
        assert(find(g,'State').Text=='OFF' and h.AutoRotate and not h.PlatformStand)
        assert(not r:FindFirstChild('FlyDBZVelocity') and not r:FindFirstChild('FlyDBZMoverAttachment'))
        assert(find(g,'ActiveLight').BackgroundTransparency==1);g:Destroy();noOwnedObjects(w)
    end)
    test('existing PlatformStand and AutoRotate values are preserved', function()
        local w,g,_,h=launch();h.PlatformStand=true;h.AutoRotate=false
        click(g);click(g);assert(h.PlatformStand and not h.AutoRotate);g:Destroy()
    end)
    test('PC WASD, normalized diagonals, smooth stop and pitched-camera altitude', function()
        local w,g,_,_,r=launch();click(g);w.keys.W=true;w.step(90)
        local mover=find(r,'FlyDBZVelocity');near(mover.VectorVelocity.Z,-58)
        w.keys.D=true;w.step(90);near(mover.VectorVelocity.Magnitude,58)
        assert(mover.VectorVelocity.X>40 and mover.VectorVelocity.Z< -40)
        w.keys={};w.step(90);near(mover.VectorVelocity.Magnitude,0)
        w.env.workspace.CurrentCamera.CFrame.LookVector=w.env.Vector3.new(0,.6,-.8)
        w.keys.W=true;w.step(90);near(mover.VectorVelocity.Y,34.8);near(mover.VectorVelocity.Z,-46.4)
        g:Destroy()
    end)
    test('mobile PlayerModule joystick keeps analog strength and hover', function()
        local w,g,_,_,r=launch({playerModule=true});click(g)
        w.move=w.env.Vector3.new(.5,0,0);w.step(90);near(find(r,'FlyDBZVelocity').VectorVelocity.X,29)
        w.move=w.env.Vector3.new(0,0,-1);w.step(90);near(find(r,'FlyDBZVelocity').VectorVelocity.Z,-58)
        w.move=w.env.Vector3.zero;w.step(90);near(find(r,'FlyDBZVelocity').VectorVelocity.Magnitude,0)
        g:Destroy()
    end)
    test('fallback touch move, focus loss, typing and camera loss neutralize movement', function()
        local w,g,_,h,r=launch();click(g);h.MoveDirection=w.env.Vector3.new(1,0,0);w.step(90)
        local mover=find(r,'FlyDBZVelocity');near(mover.VectorVelocity.X,58)
        w.textFocused=true;w.step(90);near(mover.VectorVelocity.Magnitude,0)
        w.textFocused=nil;w.services.UserInputService.WindowFocusReleased:Fire();w.step(90);near(mover.VectorVelocity.Magnitude,0)
        w.services.UserInputService.WindowFocused:Fire();w.step(90);near(mover.VectorVelocity.X,58)
        w.env.workspace.CurrentCamera=nil;w.step(90);near(mover.VectorVelocity.Magnitude,0);g:Destroy()
    end)
    test('aura reveals feet first, then upper bands, fades smoothly and is pooled', function()
        local w,g,_,_,r=launch();local emitters={}
        for _,o in ipairs(r:GetDescendants()) do if o:IsA('ParticleEmitter') then emitters[#emitters+1]=o end end
        assert(#emitters==16)
        for _,o in ipairs(emitters) do assert(not o.Enabled and o.LocalTransparencyModifier==1) end
        click(g);w.step(7)
        local bottom,top
        for _,o in ipairs(emitters) do
            assert(o.LockedToPart and o.Speed[1]>0 and o.Acceleration.Y>0)
            if o.Parent.Position.Y< -2 then bottom=o end
            if o.Parent.Position.Y>1 then top=o end
        end
        assert(bottom.Enabled and bottom.LocalTransparencyModifier<1 and not top.Enabled)
        w.step(60);assert(top.Enabled and top.LocalTransparencyModifier==0)
        click(g);w.step(8);assert(bottom.LocalTransparencyModifier>0 and bottom.LocalTransparencyModifier<1)
        w.step(40);assert(not bottom.Enabled and bottom.LocalTransparencyModifier==1)
        local objects=#w.objects
        click(g);w.step(60);assert(#w.objects==objects+3,'only three movers should be recreated')
        for _,o in ipairs(emitters) do assert(o.Parent and not o._destroying) end
        g:Destroy();noOwnedObjects(w)
    end)
    test('only character owns aura, no sound, no global lighting mutation', function()
        local w,g,c=launch();click(g);w.step(60)
        for _,o in ipairs(w.objects) do
            assert(o.ClassName~='Sound' and o.ClassName~='BloomEffect' and o.ClassName~='ColorCorrectionEffect')
            if o:IsA('ParticleEmitter') or o:IsA('PointLight') then assert(o:IsDescendantOf(c)) end
        end
        g:Destroy()
    end)
    test('real package IDs resolve to content IDs on the existing Animator', function()
        local w,g,_,h=launch();assert(#w.loadedTracks==4)
        local animator=h:FindFirstChildOfClass('Animator')
        for _,track in ipairs(w.loadedTracks) do
            assert(track.Animator==animator and track.AnimationId:sub(-1)=='7')
            assert(track.Priority.Name=='Action' and track.Looped and not track.IsPlaying)
        end
        for _,object in ipairs(w.imports) do assert(object._destroying and object.Parent==nil) end
        local animatorCount=0;for _,o in ipairs(w.objects) do if o:IsA('Animator') then animatorCount+=1 end end
        assert(animatorCount==1,'local Animator incorrectly created')
        click(g);w.step(2);assert(w.loadedTracks[1].IsPlaying)
        w.keys.W=true;w.step(3);assert(w.loadedTracks[2].IsPlaying and not w.loadedTracks[1].IsPlaying)
        click(g);for _,track in ipairs(w.loadedTracks) do assert(not track.IsPlaying) end
        g:Destroy()
    end)
    test('R6 and denied packages keep flight usable without unrelated animation', function()
        for _,options in ipairs({{r6=true},{importFailure=true},{loadFailure=true},{zeroTrackLength=true}}) do
            local w,g,_,_,r=launch(options);click(g);w.step(500)
            assert(find(r,'FlyDBZVelocity') and #w.warnings>0)
            assert(g:GetAttribute('AnimationStatus')==(options.r6 and 'R15Required' or 'Unavailable'))
            assert(not w.pg:FindFirstChild('ErrorMessage'));g:Destroy();noOwnedObjects(w)
        end
    end)
    test('ON survives death and respawn, OFF stays OFF, old body resources released', function()
        local w,g,_,h,r=launch();click(g);w.step(60)
        h.Health=0;h.Died:Fire();assert(not r:FindFirstChild('FlyDBZVelocity'))
        assert(g:GetAttribute('FlightEnabled') and find(g,'State').Text=='ON')
        local _,h2,r2=w.character();w.step(60)
        assert(h2.PlatformStand and find(r2,'FlyDBZVelocity'))
        assert(not r:FindFirstChild('FlyDBZAuraAnchor'))
        click(g);local _,h3,r3=w.character();w.step(2)
        assert(not h3.PlatformStand and not r3:FindFirstChild('FlyDBZVelocity'))
        r3.AssemblyLinearVelocity=w.env.Vector3.new(0,-90,0);w.services.RunService.Heartbeat:Fire(.02)
        assert(r3.AssemblyLinearVelocity==w.env.Vector3.zero)
        g:Destroy();noOwnedObjects(w)
    end)
    test('late character parts and Animator bind once without indefinite waits', function()
        local w,g=launch();click(g)
        local c,h,r=w.character();h.RigType=w.env.Enum.HumanoidRigType.R15
        h.Parent=nil;r.Parent=nil
        local anim=h:FindFirstChildOfClass('Animator');anim.Parent=nil
        h.Parent=c;r.Parent=c;w.step(1);assert(find(r,'FlyDBZVelocity'))
        anim.Parent=h;w.step(2);assert(#w.loadedTracks==8)
        local countBefore=#w.loadedTracks;w.step(90);assert(#w.loadedTracks==countBefore)
        g:Destroy();noOwnedObjects(w)
    end)
    test('root replacement and anchoring safely suspend and resume requested flight', function()
        local w,g,c,h,r=launch();click(g)
        r.Anchored=true;w.step(2);assert(not r:FindFirstChild('FlyDBZVelocity') and not h.PlatformStand)
        r.Anchored=false;w.step(2);assert(find(r,'FlyDBZVelocity'))
        r.Parent=nil
        local root=w.env.Instance.new('Part');root.Name='HumanoidRootPart';root.Size=w.env.Vector3.new(2,2,1);root.Parent=c
        w.step(2);assert(find(root,'FlyDBZVelocity') and not r:FindFirstChild('FlyDBZAuraAnchor'))
        g:Destroy();noOwnedObjects(w)
    end)
    test('rapid toggles and reexecution do not duplicate per-frame subscriptions', function()
        local w,g=launch()
        for _=1,30 do click(g);w.step(1) end
        assert(not g:GetAttribute('FlightEnabled'))
        for _,key in ipairs({'PreSimulation','Heartbeat','RenderStepped'}) do assert(w.services.RunService[key]:Count()==1) end
        w.run(source);local nextGui=find(w.pg,'FlyDBZ');assert(nextGui~=g and g._destroying)
        for _,key in ipairs({'PreSimulation','Heartbeat','RenderStepped'}) do assert(w.services.RunService[key]:Count()==1) end
        nextGui:Destroy();noOwnedObjects(w)
    end)
    test('close button fades aura and GUI, disables controls and cleans everything', function()
        local w,g,_,_,r=launch();click(g);w.step(60);click(g,'Close')
        assert(not r:FindFirstChild('FlyDBZVelocity'))
        click(g);assert(not g:GetAttribute('FlightEnabled'))
        w.step(10);assert(find(g,'Window').GroupTransparency>0 and find(g,'Window').GroupTransparency<1)
        w.step(40);assert(g.Parent==nil);noOwnedObjects(w)
    end)
    test('asset imports and LoadAnimation completing after close cannot leak tracks', function()
        for _,options in ipairs({{importDelay=1},{loadDelay=1}}) do
            local w,g=launch(options);g:Destroy();w.step(160)
            for _,object in ipairs(w.imports) do assert(object._destroying) end
            noOwnedObjects(w)
        end
    end)
    test('mouse and touch drag follow delta, release and focus loss stop dragging', function()
        local w,g=launch();w.step(30);local window=find(g,'Window')
        for _,touch in ipairs({false,true}) do
            local p=window.Position
            local input={UserInputType=touch and w.env.Enum.UserInputType.Touch or w.env.Enum.UserInputType.MouseButton1,Position=w.env.Vector3.new(100,100)}
            find(g,'DragHandle').InputBegan:Fire(input)
            local change=touch and input or {UserInputType=w.env.Enum.UserInputType.MouseMovement}
            change.Position=w.env.Vector3.new(150,130)
            w.services.UserInputService.InputChanged:Fire(change)
            near(window.Position.X.Offset,p.X.Offset+50);near(window.Position.Y.Offset,p.Y.Offset+30)
            w.services.UserInputService.InputEnded:Fire(input)
            change.Position=w.env.Vector3.new(200,200);w.services.UserInputService.InputChanged:Fire(change)
            near(window.Position.X.Offset,p.X.Offset+50)
        end
        g:Destroy()
    end)
    print(tostring(count)..' behavioral tests passed; Roblox visual/physics validation remains manual.')
end
