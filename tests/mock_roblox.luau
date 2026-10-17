-- Small deterministic client harness. It checks controller behavior, not Roblox physics/rendering.
local function newWorld()
    local W={keys={},move=nil,imports={},loadedTracks={},time=0,tasks={},tweens={},warnings={},objects={},requests={},viewport={X=1280,Y=720}}
    local env=setmetatable({}, {__index=getfenv()})
    local function signal()
        local s={links={}}
        function s:Connect(fn)
            local c={Connected=true,fn=fn}
            function c:Disconnect() self.Connected=false end
            self.links[#self.links+1]=c;return c
        end
        function s:Fire(...)
            for _,c in ipairs(table.clone(self.links)) do if c.Connected then W.spawn(c.fn,...) end end
        end
        function s:Wait() return coroutine.yield({signal=self}) end
        function s:Count() local n=0;for _,c in ipairs(self.links) do if c.Connected then n+=1 end end;return n end
        return s
    end
    local function schedule(co,args,at) W.tasks[#W.tasks+1]={co=co,args=args or {},at=at or W.time} end
    function W.resume(co,...)
        if coroutine.status(co)=="dead" then return end
        local ok,value=coroutine.resume(co,...)
        assert(ok,value)
        if coroutine.status(co)~="dead" then
            if type(value)=="table" and value.signal then
                local c;c=value.signal:Connect(function(...) c:Disconnect();W.resume(co,...) end)
            else
                local wait=type(value)=="number" and math.max(value,1/60) or 1/60
                schedule(co,{wait},W.time+wait)
            end
        end
    end
    function W.spawn(fn,...) local co=coroutine.create(fn);W.resume(co,...);return co end
    env.task={spawn=W.spawn,defer=function(fn,...)local co=coroutine.create(fn);schedule(co,{...});return co end,
        delay=function(t,fn,...)local co=coroutine.create(fn);schedule(co,{...},W.time+t);return co end,
        wait=function(t)return coroutine.yield(t or 1/60)end,
        cancel=function(co) if coroutine.status(co)~="dead" then coroutine.close(co) end end}
    env.os=table.clone(os);env.os.clock=function()return W.time end
    env.warn=function(...)W.warnings[#W.warnings+1]=table.concat({...}," ")end
    env.print=function()end
    local vec={};vec.__index=vec
    local function component(n)
        n=n or 0
        if n>3.4028234663852886e38 then return math.huge end
        if n< -3.4028234663852886e38 then return -math.huge end
        return n
    end
    function vec.new(x,y,z)return setmetatable({X=component(x),Y=component(y),Z=component(z)},vec)end
    function vec.__add(a,b)return vec.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z)end
    function vec.__sub(a,b)return vec.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z)end
    function vec.__mul(a,b)if type(a)=="number" then a,b=b,a end;return vec.new(a.X*b,a.Y*b,a.Z*b)end
    function vec.__div(a,b)return a*(1/b)end
    function vec.__unm(a)return a*-1 end
    function vec.__eq(a,b)return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
    function vec:Dot(b)return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
    function vec:Lerp(b,t)return self+(b-self)*t end
    vec.__index=function(t,k)
        if k=="Magnitude" then return math.sqrt(t:Dot(t)) end
        if k=="Unit" then return t/t.Magnitude end
        return vec[k]
    end
    env.Vector3={new=vec.new,zero=vec.new(),xAxis=vec.new(1,0,0),yAxis=vec.new(0,1,0),zAxis=vec.new(0,0,1)}
    env.Vector2={new=vec.new,zero=vec.new()}
    local cf={};cf.__index=cf
    function cf.new(x,y,z)
        local pos=type(x)=="table" and x or vec.new(x,y,z)
        return setmetatable({Position=pos,X=pos.X,Y=pos.Y,Z=pos.Z,RightVector=vec.new(1,0,0),UpVector=vec.new(0,1,0),LookVector=vec.new(0,0,-1)},cf)
    end
    cf.__index=function(t,k)if k=="Rotation" then return cf.new() end;return cf[k]end
    function cf.__mul(a,b)return cf.new(a.Position+b.Position)end
    function cf.__add(a,b)return cf.new(a.Position+b)end
    function cf:PointToObjectSpace(v)return v-self.Position end
    function cf:PointToWorldSpace(v)return v+self.Position end
    function cf:VectorToObjectSpace(v)return v end
    env.CFrame={new=cf.new,Angles=function()return cf.new()end,lookAt=function(p)return cf.new(p)end}
    local color={};color.__index=color
    function color.new(r,g,b)return setmetatable({R=r,G=g,B=b},color)end
    function color:Lerp(b,t)return color.new(self.R+(b.R-self.R)*t,self.G+(b.G-self.G)*t,self.B+(b.B-self.B)*t)end
    env.Color3={new=color.new,fromRGB=function(r,g,b)return color.new(r/255,g/255,b/255)end,
        fromHSV=function(h,s,v)return color.new(v*(1-s*h),v*(1-s*(1-h)),v)end}
    env.UDim={new=function(s,o)return {Scale=s,Offset=o}end}
    env.UDim2={new=function(x,xo,y,yo)return {X={Scale=x,Offset=xo},Y={Scale=y,Offset=yo}}end}
    env.UDim2.fromScale=function(x,y)return env.UDim2.new(x,0,y,0)end
    env.UDim2.fromOffset=function(x,y)return env.UDim2.new(0,x,0,y)end
    for _,key in ipairs({"ColorSequence","ColorSequenceKeypoint","NumberSequence","NumberSequenceKeypoint","NumberRange","TweenInfo"}) do
        env[key]={new=function(...)return {...}end}
    end
    env.Font={new=function(family,weight,style) return {Family=family,Weight=weight,Style=style} end}
    env.Enum=setmetatable({}, {__index=function(t,k)
        local group=setmetatable({}, {__index=function(a,b)local e={Name=b,Value=1};rawset(a,b,e);return e end})
        rawset(t,k,group);return group
    end})
    env.Random={new=function()return {NextNumber=function(_,a,b)return (a+b)/2 end,NextInteger=function(_,a,b)return math.floor((a+b)/2)end}end}
    env.OverlapParams={new=function()return {}end};env.RaycastParams={new=function()return {}end}
    local methods={}
    local events={Ended=true,Loaded=true,TeleportInitFailed=true,Destroying=true,ChildAdded=true,ChildRemoved=true,Changed=true,Activated=true,InputBegan=true,InputEnded=true,InputChanged=true,MouseEnter=true,MouseLeave=true,FocusLost=true,Died=true,StateChanged=true,CharacterAdded=true,CharacterRemoving=true,WindowFocusReleased=true,WindowFocused=true,JumpRequest=true}
    local guiClasses={Frame=true,CanvasGroup=true,TextLabel=true,TextButton=true,TextBox=true,ImageLabel=true,ImageButton=true,ScrollingFrame=true,VideoFrame=true}
    local mt={}
    mt.__index=function(t,k)
        if methods[k] then return methods[k] end
        if events[k] then if not t._signals[k] then t._signals[k]=signal()end;return t._signals[k]end
        if k=="AbsoluteSize" then
            if t._props.AbsoluteSize then return t._props.AbsoluteSize end
            if t.Name=='SafeArea' or t.ClassName=='ScreenGui' or t.ClassName=='PlayerGui' then return vec.new(W.viewport.X,W.viewport.Y)end
            local parent=t.Parent
            local parentSize=parent and parent.AbsoluteSize or vec.new(W.viewport.X,W.viewport.Y)
            local parentScale=parent and parent:GetAttribute('_TotalScale') or 1
            local own=t:FindFirstChildOfClass('UIScale');local scale=parentScale*(own and own.Scale or 1)
            t._attributes._TotalScale=scale
            local size=t.Size
            return vec.new((parentSize.X*size.X.Scale+size.X.Offset*parentScale)*(own and own.Scale or 1),
                (parentSize.Y*size.Y.Scale+size.Y.Offset*parentScale)*(own and own.Scale or 1))
        end
        if k=="AbsolutePosition" then
            if t.Name=='SafeArea' or t.ClassName=='ScreenGui' or t.ClassName=='PlayerGui' then return vec.new()end
            local parent=t.Parent;local ps=parent and parent.AbsoluteSize or vec.new(W.viewport.X,W.viewport.Y)
            local pp=parent and parent.AbsolutePosition or vec.new();local scale=parent and parent:GetAttribute('_TotalScale') or 1
            local pos=t.Position;local anchor=t.AnchorPoint or vec.new();local size=t.AbsoluteSize
            return pp+vec.new(ps.X*pos.X.Scale+pos.X.Offset*scale-anchor.X*size.X,ps.Y*pos.Y.Scale+pos.Y.Offset*scale-anchor.Y*size.Y)
        end
        if k=="AbsoluteContentSize" then return vec.new(510,600)end
        if k=="AssemblyRootPart" then return t end
        if k=="Position" and t:IsA("BasePart") then return t._props.CFrame.Position end
        return t._props[k]
    end
    mt.__newindex=function(t,k,v)
        local old=t._props[k]
        if k=="Parent" and old~=v then
            if old then
                local index=table.find(old._children,t);if index then table.remove(old._children,index)end
            end
            t._props[k]=v
            if v then v._children[#v._children+1]=t end
            if old then old.ChildRemoved:Fire(t)end
            if v then v.ChildAdded:Fire(t)end
        else t._props[k]=v end
        if old~=v then
            if t._signals[k] then t._signals[k]:Fire(v)end
            if t._signals.Changed then t._signals.Changed:Fire(v)end
        end
    end
    function methods:IsA(c)return c==self.ClassName or c=="Instance" or (c=="GuiObject" and guiClasses[self.ClassName]) or (c=="BasePart" and (self.ClassName=="Part" or self.ClassName=="Seat"))end
    function methods:GetChildren()return table.clone(self._children)end
    function methods:GetDescendants()
        local found={}
        for _,c in ipairs(self._children) do found[#found+1]=c;for _,d in ipairs(c:GetDescendants())do found[#found+1]=d end end
        return found
    end
    function methods:FindFirstChild(n,recurse)
        for _,c in ipairs(recurse and self:GetDescendants() or self._children)do if c.Name==n then return c end end
    end
    function methods:FindFirstChildOfClass(c)for _,o in ipairs(self._children)do if o.ClassName==c then return o end end end
    function methods:FindFirstChildWhichIsA(c,recurse)for _,o in ipairs(recurse and self:GetDescendants() or self._children)do if o:IsA(c)then return o end end end
    function methods:WaitForChild(n)return self:FindFirstChild(n)end
    function methods:FindFirstAncestorOfClass(c)local p=self.Parent;while p do if p:IsA(c)then return p end;p=p.Parent end end
    function methods:IsDescendantOf(a)local p=self.Parent;while p do if p==a then return true end;p=p.Parent end;return false end
    function methods:GetFullName()return self.Name end
    function methods:GetPropertyChangedSignal(k)if not self._signals[k]then self._signals[k]=signal()end;return self._signals[k]end
    function methods:SetAttribute(k,v)local old=self._attributes[k];self._attributes[k]=v;if old~=v and self._signals['@'..k]then self._signals['@'..k]:Fire()end end
    function methods:GetAttribute(k)return self._attributes[k]end
    function methods:GetAttributeChangedSignal(k)return self:GetPropertyChangedSignal('@'..k)end
    function methods:ClearAllChildren()for _,c in ipairs(self:GetChildren())do c:Destroy()end end
    function methods:Destroy()
        if self._destroying then return end
        rawset(self,'_destroying',true);self.Destroying:Fire();self:ClearAllChildren();self.Parent=nil
        for _,s in pairs(self._signals)do for _,c in ipairs(s.links)do c:Disconnect()end end
    end
    function methods:ChangeState(s)local old=self.State;self.State=s;self.StateChanged:Fire(old,s)end
    function methods:GetState()return self.State end
    function methods:GetConnectedParts()return {}end
    function methods:IsFocused()return W.textFocused==self end
    function methods:ReleaseFocus()
        if W.textFocused==self then W.textFocused=nil;self.FocusLost:Fire(false)end
    end
    function methods:Play()self.IsPlaying=true;self.Playing=true end
    function methods:Pause()self.IsPlaying=false;self.Playing=false end
    function methods:Resume()self.IsPlaying=true;self.Playing=true end
    function methods:Stop()self.IsPlaying=false;self.Playing=false;self.TimePosition=0 end
    function methods:Emit(n) self.Emitted=(self.Emitted or 0)+n end
    function methods:Clear() self.Cleared=(self.Cleared or 0)+1 end
    function methods:LoadAnimation(animation)
        if W.loadDelay then env.task.wait(W.loadDelay) end
        if W.loadFailure then error('animation not permitted')end
        local track=env.Instance.new('AnimationTrack');track.Length=W.zeroTrackLength and 0 or 1
        track.AnimationId=animation.AnimationId;track.Animator=self
        W.loadedTracks[#W.loadedTracks+1]=track
        return track
    end
    function methods:Fire(...)if self.Event then self.Event:Fire(...)end end
    env.Instance={new=function(c)
        local t=setmetatable({_props={ClassName=c,Name=c,Visible=true,Enabled=true,BackgroundTransparency=0,TextTransparency=0,ImageTransparency=0,Transparency=0,ScrollBarImageTransparency=0,
            Text="",Image="",BackgroundColor3=color.new(1,1,1),Size=env.UDim2.fromOffset(100,100),Position=env.UDim2.fromOffset(0,0),Value=0,CFrame=cf.new(),AssemblyLinearVelocity=vec.new(),AssemblyAngularVelocity=vec.new(),AssemblyMass=10,
            Health=100,AutoRotate=true,PlatformStand=false,Anchored=false,CanCollide=true,WalkSpeed=16,HipHeight=2,MoveDirection=vec.new(),FloorMaterial=env.Enum.Material.Air,State=env.Enum.HumanoidStateType.Freefall,
            RigType=env.Enum.HumanoidRigType.R6,UseJumpPower=true,JumpPower=50,IsLoaded=true,Volume=0,TimeLength=18.35,TimePosition=0,Video='',Playing=false},_children={},_signals={},_attributes={}},mt)
        if c=='BindableEvent'then t.Event=signal()end
        W.objects[#W.objects+1]=t;return t
    end}
    env.typeof=function(v)if type(v)=='table' and v._props then return 'Instance'end;if getmetatable(v)==vec then return 'Vector3'end;return type(v)end
    local services={}
    services.RunService={PreSimulation=signal(),PostSimulation=signal(),Heartbeat=signal(),RenderStepped=signal()}
    services.TweenService={Create=function(_,object,info,props)
        local t={Completed=signal(),cancelled=false,object=object,props=props,duration=info[1] or .1,start={}}
        function t:Cancel()self.cancelled=true end
        function t:Play()
            self.began=W.time
            for k in pairs(props)do self.start[k]=object[k]end
            W.tweens[#W.tweens+1]=self
        end
        return t
    end,GetValue=function(_,x)return x end}
    services.UserInputService=env.Instance.new('UserInputService');services.UserInputService.TouchEnabled=true
    services.UserInputService.GetFocusedTextBox=function()return W.textFocused end
    services.UserInputService.IsKeyDown=function(_,key)return W.keys[key.Name]==true end
    services.UserInputService.GetMouseLocation=function()return vec.new(500,300)end
    env.workspace=env.Instance.new('Workspace');env.workspace.Name='Workspace';env.workspace.Gravity=196.2
    env.workspace.CurrentCamera=env.Instance.new('Camera');env.workspace.CurrentCamera.ViewportSize=vec.new(1280,720)
    env.workspace.GetPartBoundsInRadius=function()return {}end;env.workspace.GetPartBoundsInBox=function()return {}end;env.workspace.Raycast=function()return nil end
    local player=env.Instance.new('Player');player.Name='TestPlayer';player.DisplayName='Test';player.UserId=123
    local pg=env.Instance.new('PlayerGui');pg.Parent=player
    local scripts=env.Instance.new('PlayerScripts');scripts.Parent=player
    services.Players={LocalPlayer=player,GetPlayers=function()return {player}end}
    env.game={PlaceId=189707,JobId='test',GetService=function(_,name)if not services[name]then services[name]=env.Instance.new(name)end;return services[name]end,
        GetObjects=function(_,url)
            W.requests[#W.requests+1]=url
            if W.importDelay then env.task.wait(W.importDelay)end
            if W.importFailure then error('asset permission denied')end
            local folder=env.Instance.new('Folder');folder.Name='CatalogPackage'
            local clip=env.Instance.new('Animation');clip.AnimationId='rbxassetid://'..url:match('(%d+)$')..'7';clip.Parent=folder
            local script=env.Instance.new('Script');script.Name='NeverRun';script.Parent=folder
            W.imports[#W.imports+1]=folder
            return {folder}
        end}
    env.require=function(module)
        assert(module.Name=='PlayerModule')
        if W.controlsFailure then error('no controls')end
        return {GetControls=function()return {GetMoveVector=function()return W.move or vec.new()end}end}
    end
    env.loadstring=function(src)local fn,err=loadstring(src);if fn then setfenv(fn,env)end;return fn,err end
    W.env=env;W.services=services;W.player=player;W.pg=pg
    function W.run(src,...)local fn,err=env.loadstring(src);assert(fn,err);local result;W.spawn(function(...)result=fn(...)end,...);return result end
    function W.step(count,frameDt)
        local dt=frameDt or 1/60
        for _=1,(count or 1)do
            W.time+=dt
            local active={}
            for _,t in ipairs(W.tweens)do
                if not t.cancelled and not t.object._destroying then
                    local alpha=math.clamp((W.time-t.began)/t.duration,0,1)
                    for k,b in pairs(t.props)do
                        local a=t.start[k]
                        if alpha>=1 then t.object[k]=b
                        elseif type(a)=='number' then t.object[k]=a+(b-a)*alpha
                        elseif type(a)=='table' and a.R then t.object[k]=a:Lerp(b,alpha)
                        elseif type(a)=='table' and type(a.X)=='table' then
                            t.object[k]=env.UDim2.new(a.X.Scale+(b.X.Scale-a.X.Scale)*alpha,a.X.Offset+(b.X.Offset-a.X.Offset)*alpha,
                                a.Y.Scale+(b.Y.Scale-a.Y.Scale)*alpha,a.Y.Offset+(b.Y.Offset-a.Y.Offset)*alpha)
                        elseif type(a)=='table' and type(a.X)=='number'then t.object[k]=a:Lerp(b,alpha)end
                    end
                    if alpha<1 then active[#active+1]=t else t.Completed:Fire()end
                end
            end
            W.tweens=active
            for _,key in ipairs({'PreSimulation','PostSimulation','Heartbeat','RenderStepped'})do services.RunService[key]:Fire(dt)end
            local pending=W.tasks;W.tasks={}
            for _,t in ipairs(pending)do if t.at<=W.time then W.resume(t.co,table.unpack(t.args))else W.tasks[#W.tasks+1]=t end end
        end
    end
    function W.character(health)
        local old=player.Character
        if old then player.CharacterRemoving:Fire(old);old.Parent=nil end
        local model=env.Instance.new('Model');model.Name='Character';model.Parent=env.workspace
        local hum=env.Instance.new('Humanoid');hum.Health=health or 100;hum.Parent=model
        local root=env.Instance.new('Part');root.Name='HumanoidRootPart';root.Size=vec.new(2,2,1);root.Parent=model
        local animator=env.Instance.new('Animator');animator.Parent=hum
        player.Character=model;player.CharacterAdded:Fire(model)
        return model,hum,root
    end
    return W
end
return newWorld
