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
        assert(find(g,'Window').Size.X.Offset==228 and find(g,'Window').Size.Y.Offset==146)
        assert(find(g,'FlightToggle').Size.Y.Offset>=40)
        assert(not r:FindFirstChild('FlyDBZVelocity') and not h.PlatformStand)
        for _,o in ipairs(find(g,'Window'):GetDescendants()) do
            if o.Text~='' then assert(o.Text=='FLY DBZ' or o.Text=='OFF' or o.Text=='×'
                or o.Text=='SPEED' or o.Text=='58' or o.Text=='−' or o.Text=='+') end
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
        assert(#emitters==22)
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
            if o:IsA('ParticleEmitter') or o:IsA('PointLight') or o:IsA('Beam') or o:IsA('Trail') then assert(o:IsDescendantOf(c)) end
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
    test('speed buttons change by two without toggling flight; wheel changes one step', function()
        local w,g=launch();assert(g:GetAttribute('FlightSpeed')==58)
        click(g,'SpeedUp');assert(find(g,'SpeedValue').Text=='60')
        click(g,'SpeedDown');assert(find(g,'SpeedValue').Text=='58')
        find(g,'SpeedControl').MouseEnter:Fire()
        w.services.UserInputService.InputChanged:Fire({UserInputType=w.env.Enum.UserInputType.MouseWheel,Position=w.env.Vector3.new(0,0,1)})
        assert(g:GetAttribute('FlightSpeed')==60)
        w.services.UserInputService.InputChanged:Fire({UserInputType=w.env.Enum.UserInputType.MouseWheel,Position=w.env.Vector3.new(0,0,-1)})
        assert(g:GetAttribute('FlightSpeed')==58 and not g:GetAttribute('FlightEnabled'))
        find(g,'SpeedControl').MouseLeave:Fire()
        w.services.UserInputService.InputChanged:Fire({UserInputType=w.env.Enum.UserInputType.MouseWheel,Position=w.env.Vector3.new(0,0,1)})
        assert(g:GetAttribute('FlightSpeed')==58,'wheel changed speed outside the control')
        assert(find(g,'SpeedUp').Size.Y.Offset>=40 and find(g,'SpeedDown').Size.Y.Offset>=40)
        g:Destroy()
    end)
    test('manual speed applies live, accepts decimals and values above ordinary caps', function()
        local w,g,_,_,r=launch();click(g);w.keys.W=true
        local box=find(g,'SpeedValue')
        box.Text='120';box.FocusLost:Fire(true);w.step(90)
        near(find(r,'FlyDBZVelocity').VectorVelocity.Z,-120)
        box.Text=' 72,5 ';box.FocusLost:Fire(false);w.step(90)
        near(find(r,'FlyDBZVelocity').VectorVelocity.Z,-72.5)
        for _,value in ipairs({'2500','1000000','1e20'}) do
            box.Text=value;box.FocusLost:Fire(true)
            assert(g:GetAttribute('FlightSpeed')==tonumber(value),'arbitrary maximum imposed')
        end
        w.step(120);local velocity=find(r,'FlyDBZVelocity').VectorVelocity
        assert(velocity.Z< -9.9e19 and velocity.Z> -math.huge)
        -- Large opposite directions must not overflow interpolation.
        box.Text='3e38';box.FocusLost:Fire(true);w.step(120)
        w.keys={S=true};w.step(120)
        velocity=find(r,'FlyDBZVelocity').VectorVelocity
        assert(velocity.Z>2.9e38 and velocity.Z<math.huge)
        assert(velocity.X==velocity.X and velocity.Y==velocity.Y)
        g:Destroy()
    end)
    test('invalid or nonrepresentable speed restores last value; zero means hover', function()
        local w,g,_,_,r=launch();local box=find(g,'SpeedValue')
        for _,invalid in ipairs({'','abc','-12','NaN','inf','1e309','1e300'}) do
            box.Text=invalid;box.FocusLost:Fire(true)
            assert(box.Text=='58' and g:GetAttribute('FlightSpeed')==58,invalid)
        end
        box.Text='0';box.FocusLost:Fire(false);click(g,'SpeedDown')
        assert(box.Text=='0','negative speed should not reverse controls')
        click(g);w.keys.W=true;w.step(30);near(find(r,'FlyDBZVelocity').VectorVelocity.Magnitude,0)
        click(g,'SpeedUp');assert(box.Text=='2');g:Destroy()
    end)
    test('focused editing plus step commits entry once; speed survives respawn', function()
        local w,g=launch();local box=find(g,'SpeedValue')
        w.textFocused=box;box.Text='140';click(g,'SpeedUp')
        assert(w.textFocused==nil and g:GetAttribute('FlightSpeed')==142 and box.Text=='142')
        box.FocusLost:Fire(false);assert(g:GetAttribute('FlightSpeed')==142)
        click(g);local _,_,r=w.character();w.keys.W=true;w.step(120)
        near(find(r,'FlyDBZVelocity').VectorVelocity.Z,-142)
        click(g);click(g);assert(box.Text=='142')
        click(g,'Close');click(g,'SpeedUp');box.Text='600';box.FocusLost:Fire(true)
        assert(g:GetAttribute('FlightSpeed')==142,'closed controller accepted input')
        w.step(60);noOwnedObjects(w)
    end)
    test('textured meteor envelope grows from feet with no rigid core lines', function()
        local w,g,_,_,r=launch();local ribbons={};local wake={}
        for _,o in ipairs(r:GetDescendants()) do
            if o:IsA('Beam') then
                local group=o.Name:find('Tail') and wake or ribbons;group[#group+1]=o
            end
        end
        assert(#ribbons==8 and #wake==8)
        for _,o in ipairs(ribbons) do
            assert(not o.Enabled and o.LocalTransparencyModifier==1 and o.Width0==0)
            assert(o.FaceCamera and o.Segments>=12 and o.TextureSpeed>0)
            assert(o.Texture~='' and o.Name~='FlyDBZEnergyCore','untextured line remains')
            assert(o.Attachment0.Position.Y==o.Attachment1.Position.Y)
        end
        click(g);w.step(7)
        local first=ribbons[1];local base=first.Attachment0.Position.Y
        assert(first.Attachment1.Position.Y>base and first.Attachment1.Position.Y<1)
        assert(first.Enabled and first.LocalTransparencyModifier>0)
        w.step(60);local points={}
        for i,o in ipairs(ribbons) do
            assert(o.Enabled and o.LocalTransparencyModifier==0)
            assert(o.Attachment1.Position.Y>1.5 and o.CurveSize0>1 and o.Width0>1.5)
            points[i]=o.Attachment1.Position
        end
        w.step(15)
        for i,o in ipairs(ribbons) do assert(o.Attachment1.Position~=points[i],'static energy ribbon') end
        for _,o in ipairs(wake) do assert(not o.Enabled,'directional tail appeared while hovering') end
        local upper=first.Attachment1.Position.Y
        click(g);w.step(8)
        assert(first.LocalTransparencyModifier>0 and first.LocalTransparencyModifier<1)
        assert(math.abs(first.Attachment1.Position.Y-upper)<0.6,'fade collapsed the aura instead of fading')
        w.step(40)
        for _,o in ipairs(ribbons) do assert(not o.Enabled and o.LocalTransparencyModifier==1) end
        g:Destroy();noOwnedObjects(w)
    end)
    test('aura stays bounded, warm and visible without increasing objects each frame', function()
        local w,g,_,_,r=launch();click(g);w.step(70)
        local countBefore=#w.objects;local particles=0
        local texturedCore=false
        for _,o in ipairs(r:GetDescendants()) do
            if o:IsA('ParticleEmitter') then
                particles+=o.Rate*o.Lifetime[2]
                if o.Name=='FlyDBZFlame' then assert(o.LightEmission<1 and o.Brightness>=3) end
            end
            if o.Name=='FlyDBZHotFlame' then texturedCore=o.Texture~='' end
        end
        assert(texturedCore and particles<260,'unbounded particle load')
        w.step(180);assert(#w.objects==countBefore,'VFX allocated instances every frame')
        click(g);w.step(45);local lamp=find(r,'FlyDBZLight')
        assert(not lamp.Enabled and lamp.Brightness==0)
        g:Destroy();noOwnedObjects(w)
    end)
    test('meteor fire trails movement in all six directions and rises while hovering', function()
        local w,g,_,_,r=launch({playerModule=true});local V=w.env.Vector3
        click(g);w.step(120)
        local flame=find(r,'FlyDBZWakeFlame')
        local function flow() return r.CFrame:VectorToWorldSpace(flame.Parent.CFrame.UpVector) end
        assert(flow():Dot(V.yAxis)>.99)
        local cases={
            {move=V.new(0,0,-1),look=V.new(0,0,-1),tail=V.zAxis},
            {move=V.new(0,0,1),look=V.new(0,0,-1),tail=-V.zAxis},
            {move=V.new(-1,0,0),look=V.new(0,0,-1),tail=V.xAxis},
            {move=V.new(1,0,0),look=V.new(0,0,-1),tail=-V.xAxis},
            {move=V.new(0,0,-1),look=V.yAxis,tail=-V.yAxis},
            {move=V.new(0,0,-1),look=-V.yAxis,tail=V.yAxis},
        }
        for _,case in ipairs(cases) do
            w.move=case.move;w.env.workspace.CurrentCamera.CFrame.LookVector=case.look;w.step(120)
            assert(flow():Dot(case.tail)>.99,'flames did not follow world-space direction')
            assert(flame.Acceleration.Unit:Dot(case.tail)>.99)
            local beam=find(r,'FlyDBZTailFlame')
            local displacement=r.CFrame:VectorToWorldSpace(beam.Attachment1.Position-beam.Attachment0.Position)
            assert(displacement:Dot(case.tail)>4,'meteor wake did not trail movement')
            assert(find(r,'FlyDBZMeteorTrail').Enabled)
        end
        w.move=V.zero;w.step(180)
        assert(flow():Dot(V.yAxis)>.99 and not find(r,'FlyDBZMeteorTrail').Enabled)
        g:Destroy();noOwnedObjects(w)
    end)
    test('reversing and rotated characters keep a continuous finite flame axis', function()
        local w,g,_,_,r=launch({playerModule=true});local V=w.env.Vector3
        r.CFrame=w.env.CFrame.fromMatrix(V.zero,V.new(0,0,-1),V.yAxis,V.xAxis)
        w.move=V.new(0,0,-1);click(g);w.step(120)
        local flame=find(r,'FlyDBZWakeFlame')
        local function flow() return r.CFrame:VectorToWorldSpace(flame.Parent.CFrame.UpVector) end
        assert(flow():Dot(V.zAxis)>.99,'root rotation changed the world flow')
        w.move=V.new(0,0,1);local previous=flow()
        for _=1,90 do
            w.step(2);local nextFlow=flow()
            near(nextFlow.Magnitude,1)
            assert(previous:Dot(nextFlow)>.7,'flame snapped during a half-turn')
            previous=nextFlow
        end
        assert(flow():Dot(-V.zAxis)>.99)
        click(g);w.step(8);assert(flow():Dot(-V.zAxis)>.99,'fade snapped upright')
        w.step(45);assert(not find(r,'FlyDBZMeteorTrail').Enabled)
        g:Destroy();noOwnedObjects(w)
    end)
    test('extreme editable speeds keep finite bounded meteor geometry without allocations', function()
        local w,g,_,_,r=launch();click(g);local box=find(g,'SpeedValue')
        box.Text='3e38';box.FocusLost:Fire(true);w.keys.W=true;w.step(120)
        local objects=#w.objects;w.keys={S=true};w.step(120)
        for _,o in ipairs(r:GetDescendants()) do
            if o:IsA('Beam') then
                local delta=o.Attachment1.Position-o.Attachment0.Position
                assert(delta.Magnitude==delta.Magnitude and delta.Magnitude<18,'unbounded flame geometry')
                assert(o.Width0>0 and o.Width0<6)
            end
        end
        local trail=find(r,'FlyDBZMeteorTrail')
        assert(trail.Enabled and trail.MaxLength>0 and trail.MaxLength<=16)
        assert(#w.objects==objects,'changing direction created VFX instances')
        g:Destroy();noOwnedObjects(w)
    end)
    test('GUI fire stays alive without a character and follows a dragged panel', function()
        local w,g,c=launch();click(g);w.step(60)
        local layer=find(g,'WindowFireLayer');local sprite=find(layer,'GuiFlame')
        local window=find(g,'Window');local previous=sprite.Position
        w.player.CharacterRemoving:Fire(c);w.player.Character=nil;c.Parent=nil;w.step(20)
        assert(layer.Visible and sprite.BackgroundTransparency<1 and sprite.Position~=previous)
        assert(not layer.Active and not sprite.Active,'decoration captures input')
        local input={UserInputType=w.env.Enum.UserInputType.Touch,Position=w.env.Vector3.new(50,50)}
        find(g,'DragHandle').InputBegan:Fire(input);input.Position=w.env.Vector3.new(130,90)
        w.services.UserInputService.InputChanged:Fire(input)
        assert(layer.Position==window.Position,'fire detached during dragging')
        w.services.UserInputService.InputEnded:Fire(input)
        local objects=#w.objects;w.step(120);assert(#w.objects==objects)
        click(g,'Close');w.step(60)
        assert(layer._destroying and sprite._destroying);noOwnedObjects(w)
    end)
    test('quality notice persists through time, toggles and respawn until explicit dismissal', function()
        local w,g=launch();local notice=find(g,'QualityNotice')
        assert(find(notice,'QualityMessage').Text=="For better quality, use Roblox's high graphics settings.")
        assert(notice.Position.X.Scale==.5 and notice.Position.Y.Scale==.5)
        w.step(900);click(g);w.step(60);w.character();w.step(60);click(g)
        assert(notice.Parent==g and notice.GroupTransparency==0)
        assert(not g:GetAttribute('QualityNoticeDismissed'))
        click(g,'DismissQualityNotice');w.step(7)
        assert(notice.Parent==g and notice.GroupTransparency>0 and notice.GroupTransparency<1)
        w.step(12);assert(notice.Parent==nil and g:GetAttribute('QualityNoticeDismissed'))
        click(g);w.character();w.step(60);assert(not g:FindFirstChild('QualityNotice'))
        assert(find(g,'Window').Parent==g and g:GetAttribute('FlightEnabled'),'dismissal stopped flight')
        g:Destroy();noOwnedObjects(w)
    end)
    test('manual GUI close and reexecution safely dispose of the persistent notice', function()
        local w,g=launch();local notice=find(g,'QualityNotice');click(g,'Close');w.step(60)
        assert(notice._destroying);noOwnedObjects(w)
        w.run(source);g=find(w.pg,'FlyDBZ');notice=find(g,'QualityNotice')
        assert(not g:GetAttribute('QualityNoticeDismissed'))
        click(g,'DismissQualityNotice');w.run(source);w.step(60)
        local nextGui=find(w.pg,'FlyDBZ')
        assert(notice._destroying and find(nextGui,'QualityNotice').GroupTransparency==0)
        nextGui:Destroy();noOwnedObjects(w)
    end)
    test('panel fire is hidden in OFF, fades on toggles and stops sprite work when hidden', function()
        local w,g=launch();local layer=find(g,'WindowFireLayer');local sprite=find(layer,'GuiFlame')
        w.step(90);assert(not layer.Visible and sprite.BackgroundTransparency==1)
        click(g);w.step(8)
        assert(layer.Visible and sprite.BackgroundTransparency>0 and sprite.BackgroundTransparency<1)
        w.step(60);local pool=layer:GetChildren()
        click(g);w.step(6);assert(layer.Visible,'OFF cut the fire without a fade')
        w.step(60);assert(not layer.Visible,'OFF left fire visible')
        local position=sprite.Position;w.step(60);assert(sprite.Position==position,'hidden sprites still animated')
        for _=1,6 do click(g);w.step(2) end
        w.step(60);assert(not layer.Visible)
        for _,object in ipairs(pool) do assert(object.Parent==layer and not object._destroying) end
        assert(#layer:GetChildren()==#pool,'toggles created new UI fire objects')
        g:Destroy();noOwnedObjects(w)
    end)
    test('core fire stays anchored to body regions while only the wake changes direction', function()
        local w,g,_,_,r=launch({playerModule=true});local V=w.env.Vector3;click(g);w.step(90)
        local anchors,tipPositions={},{}
        for _,object in ipairs(r:GetDescendants()) do
            if object:IsA('ParticleEmitter') and object.Name~='FlyDBZWakeFlame' then
                anchors[object.Parent]=object.Parent.Position
            elseif object.Name=='FlyDBZHotFlame' then
                anchors[object.Attachment0]=object.Attachment0.Position
                tipPositions[object.Attachment1]=object.Attachment1.Position
            end
        end
        for _,look in ipairs({V.new(0,0,-1),V.new(0,0,1),V.xAxis,-V.xAxis,V.yAxis,-V.yAxis}) do
            w.env.workspace.CurrentCamera.CFrame.LookVector=look;w.move=V.new(0,0,-1);w.step(120)
            for anchor,position in pairs(anchors) do
                assert(anchor.Position==position,'core emission site migrated away from the body')
            end
            for tip,position in pairs(tipPositions) do
                assert((tip.Position-position).Magnitude<1.3,'body envelope swung into the wake')
            end
            assert(find(r,'FlyDBZFlame').LocalTransparencyModifier==0)
            assert(find(r,'FlyDBZWakeFlame').Enabled)
        end
        g:Destroy();noOwnedObjects(w)
    end)
    test('reversals soften the wake and discontinuous positions cannot draw a long bridge', function()
        local w,g,_,_,r=launch();local V=w.env.Vector3;w.keys.W=true;click(g);w.step(120)
        local wake=find(r,'FlyDBZTailFlame');local core=find(r,'FlyDBZHotFlame')
        local trail=find(r,'FlyDBZMeteorTrail');assert(trail.Enabled)
        w.keys={S=true};local maximumFade=0
        for _=1,50 do
            w.step(2);maximumFade=math.max(maximumFade,wake.LocalTransparencyModifier)
            assert(core.LocalTransparencyModifier==0,'turn dimmed the body aura')
        end
        assert(maximumFade>.75,'old-direction wake remained bright while reversing')
        w.step(60);assert(wake.LocalTransparencyModifier<.02 and trail.Enabled)
        local clears=trail.Cleared or 0
        r.CFrame=w.env.CFrame.new(V.new(1000,0,0));w.step(2)
        assert((trail.Cleared or 0)>clears and not trail.Enabled,'teleport joined distant trail points')
        w.step(30);assert(trail.Enabled and trail.MaxLength<=8)
        g:Destroy();noOwnedObjects(w)
    end)
    print(tostring(count)..' behavioral tests passed; Roblox visual/physics validation remains manual.')
end
