-- FLY DBZ | 1.0 | Made By Reyzn
-- Client controller. Catalog animations require R15 and asset permission.
-- Uses the character's existing Animator. Starts OFF; death/reset disarms everything.
-- No Fall Damage retains the supplied Natural Disaster Survival place guard.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
if not player then return end
local playerGui = player:WaitForChild("PlayerGui")

-- BEGIN NO FALL COORDINATOR
local createNoFallLease = (function()
-- Shared, client-local ownership of a velocity pulse. No callbacks yield here.
-- The ledger lives in PlayerGui so separately executed scripts can cooperate
-- without depending on shared Lua globals or on signal delivery order.
return function(ownerGui, priority)
    local parent = ownerGui.Parent
    local ledger = parent:FindFirstChild("ReyznNoFallDamage_v1")
    local function value(class, name, container, initial)
        local object = Instance.new(class)
        object.Name = name
        object.Value = initial
        object.Parent = container
        return object
    end
    if not ledger then
        ledger = Instance.new("Folder")
        ledger.Name = "ReyznNoFallDamage_v1"
        local clients = Instance.new("Folder")
        clients.Name = "Clients"
        clients.Parent = ledger
        value("ObjectValue", "Owner", ledger, nil)
        value("ObjectValue", "PendingOwner", ledger, nil)
        value("ObjectValue", "Root", ledger, nil)
        value("ObjectValue", "Character", ledger, nil)
        value("Vector3Value", "Velocity", ledger, Vector3.zero)
        ledger.Parent = parent
    end
    local clients = ledger:FindFirstChild("Clients")
    local owner = ledger:FindFirstChild("Owner")
    local pending = ledger:FindFirstChild("PendingOwner")
    local rootValue = ledger:FindFirstChild("Root")
    local characterValue = ledger:FindFirstChild("Character")
    local velocityValue = ledger:FindFirstChild("Velocity")
    local token = value("ObjectValue", ownerGui.Name.."Lease", clients, ownerGui)
    token:SetAttribute("Priority", priority)
    token:SetAttribute("Enabled", false)
    local disposed = false
    local destructionConnection
    local lease = {changed = owner:GetPropertyChangedSignal("Value")}

    local function restorePending()
        local root, character, velocity = rootValue.Value, characterValue.Value, velocityValue.Value
        pending.Value = nil
        rootValue.Value = nil
        characterValue.Value = nil
        if root and character and root.Parent == character and not root.Anchored
            and root.AssemblyLinearVelocity == Vector3.zero then
            root.AssemblyLinearVelocity = velocity
        end
    end
    local function chooseOwner()
        local winner, best = nil, -math.huge
        for _, candidate in ipairs(clients:GetChildren()) do
            local gui = candidate.Value
            local rank = candidate:GetAttribute("Priority")
            if gui and gui.Parent == parent and candidate:GetAttribute("Enabled") and rank > best then
                winner, best = candidate, rank
            end
        end
        if owner.Value ~= winner then
            -- Finish the outgoing pulse before publishing the incoming owner.
            -- A queued restore from the old script then cannot touch the new one.
            restorePending()
            owner.Value = winner
        end
    end
    function lease:isOwner()
        return not disposed and owner.Value == token and token:GetAttribute("Enabled") == true
    end
    function lease:setEnabled(enabled)
        if disposed then return end
        if token:GetAttribute("Enabled") ~= enabled then
            token:SetAttribute("Enabled", enabled)
            chooseOwner()
        end
    end
    function lease:restore()
        if not disposed and pending.Value == token then restorePending() end
    end
    -- Other cooperating controllers read the real velocity even between the
    -- zeroing and restoration phases. A correction invalidates that old pulse,
    -- including corrections to zero, so it cannot be undone by a queued restore.
    function lease:readVelocity(root)
        local saved=not disposed and rootValue.Value
        if saved and pending.Value and saved.Parent == characterValue.Value
            and (saved==root or saved.AssemblyRootPart==root.AssemblyRootPart)
            and root.AssemblyLinearVelocity == Vector3.zero then
            return velocityValue.Value
        end
        return root.AssemblyLinearVelocity
    end
    function lease:writeVelocity(root, velocity)
        if disposed or not root.Parent then return end
        local saved=rootValue.Value
        if saved and (saved==root or saved.AssemblyRootPart==root.AssemblyRootPart) then
            pending.Value = nil
            rootValue.Value = nil
            characterValue.Value = nil
        end
        root.AssemblyLinearVelocity = velocity
    end
    function lease:pulse(root)
        if not self:isOwner() then return false end
        self:restore()
        if not root.Parent or root.Anchored then return false end
        rootValue.Value = root
        characterValue.Value = root.Parent
        velocityValue.Value = root.AssemblyLinearVelocity
        pending.Value = token
        root.AssemblyLinearVelocity = Vector3.zero
        return true
    end
    function lease:destroy()
        if disposed then return end
        self:restore()
        self:setEnabled(false)
        disposed = true
        if destructionConnection then destructionConnection:Disconnect() end
        token:Destroy()
        if #clients:GetChildren() == 0 then ledger:Destroy() end
    end
    destructionConnection = ownerGui.Destroying:Connect(function() lease:destroy() end)
    return lease
end
end)()
-- END NO FALL COORDINATOR

local CONFIG = {
    Speed = 5,
    MinSpeed = 5,
    MaxSpeed = 5000,
    SpeedStep = 5,
    Acceleration = 9,
    NoFallPlaceId = 189707,
    -- These are catalog package IDs, NOT AnimationTrack content IDs.
    Packages = {
        Idle = 102994438121065,
        Run = 107411587365865,
        Climb = 82749924026067,
        Fall = 138553022046795,
    },
}
local old = playerGui:FindFirstChild("FlyDBZ")
if old then old:Destroy() end

local alive, closing, wantedFlight, focused = true, false, false, true
local connections, characterConnections, bodyConnections = {}, {}, {}
local activeTweens, reported = {}, {}
local currentCharacter, body, controls
local flightSpeed = CONFIG.Speed
local function make(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties or {}) do object[key] = value end
    object.Parent = parent
    return object
end
local function connect(bucket, event, callback)
    local connection = event:Connect(callback)
    bucket[#bucket + 1] = connection
    return connection
end
local function disconnectAll(bucket)
    for _, connection in ipairs(bucket) do connection:Disconnect() end
    table.clear(bucket)
end
local function warnOnce(key, message)
    if reported[key] then return end
    reported[key] = true
    warn("[FLY DBZ] " .. message)
end
local function tween(object, duration, goal, style)
    local previous = activeTweens[object]
    if previous then previous:Cancel() end
    local animation = TweenService:Create(object,
        TweenInfo.new(duration, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
    activeTweens[object] = animation
    animation:Play()
    return animation
end
local function round(parent, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius)}, parent)
end
local function gradient(parent, colors, rotation)
    return make("UIGradient", {Color = ColorSequence.new(colors), Rotation = rotation or 0}, parent)
end
local C = Color3.fromRGB
local ZERO = Vector3.zero

-- Compact touch-friendly surface: heading, flight switch and editable speed.
local gui = make("ScreenGui", {
    Name = "FlyDBZ", ResetOnSpawn = false, IgnoreGuiInset = false,
    DisplayOrder = 72, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
gui:SetAttribute("Version", "1.0")
gui:SetAttribute("FlightEnabled", false)
gui:SetAttribute("NoFallDamageArmed", false)
gui:SetAttribute("AnimationStatus", "Idle")
gui:SetAttribute("FlightSpeed", flightSpeed)
-- Reyzn X owns priority 100; this independent flight window uses priority 10.
local noFallLease = createNoFallLease(gui, 10)
gui:SetAttribute("NoFallCoordinatorVersion", 1)
connect(connections, noFallLease.changed, function()
    if alive then gui:SetAttribute("NoFallDamageArmed", noFallLease:isOwner()) end
end)
local window = make("CanvasGroup", {
    Name = "Window", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 80),
    Size = UDim2.fromOffset(240, 156), BackgroundColor3 = C(25, 27, 32), ZIndex = 3,
    BackgroundTransparency = 0, GroupTransparency = 0, BorderSizePixel = 0,
}, gui)
round(window, 15)
make("UIStroke", {Color = C(99, 105, 120), Transparency = 0.45, Thickness = 1}, window)
gradient(window, {
    ColorSequenceKeypoint.new(0, C(255, 255, 255)),
    ColorSequenceKeypoint.new(1, C(190, 194, 205)),
}, 90)
local header = make("TextLabel", {
    Name = "DragHandle", BackgroundTransparency = 1, Active = true,
    Position = UDim2.fromOffset(15, 0), Size = UDim2.new(1, -59, 0, 40),
    Text = "FLY DBZ", TextColor3 = C(242, 244, 250), TextSize = 16,
    Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
}, window)
local close = make("TextButton", {
    Name = "Close", BackgroundTransparency = 1, BackgroundColor3 = C(180, 187, 204), Position = UDim2.new(1, -42, 0, 0),
    Size = UDim2.fromOffset(42, 40), Text = "×", TextSize = 23,
    Font = Enum.Font.Gotham, TextColor3 = C(150, 151, 162), AutoButtonColor = false,
}, window)
round(close, 12)
connect(connections, close.MouseEnter, function() if not closing then tween(close, 0.18, {BackgroundTransparency = 0.9, TextColor3 = C(245, 246, 250)}) end end)
connect(connections, close.MouseLeave, function() if not closing then tween(close, 0.2, {BackgroundTransparency = 1, TextColor3 = C(150, 151, 162)}) end end)
make("Frame", {Name = "HeaderDivider", Position = UDim2.fromOffset(14, 37),
    Size = UDim2.new(1, -28, 0, 1), BorderSizePixel = 0,
    BackgroundColor3 = C(64, 68, 78), BackgroundTransparency = 0.5}, window)
local toggle = make("TextButton", {
    Name = "FlightToggle", Position = UDim2.fromOffset(12, 47), Size = UDim2.new(1, -24, 0, 42),
    BackgroundColor3 = C(34, 37, 44), Text = "", AutoButtonColor = false, BorderSizePixel = 0,
}, window)
round(toggle, 11)
local toggleStroke = make("UIStroke", {Thickness = 1, Color = C(80, 82, 96), Transparency = 0.45}, toggle)
local stateLabel = make("TextLabel", {
    Name = "State", BackgroundTransparency = 1, Text = "OFF", Font = Enum.Font.GothamBold,
    TextSize = 13, TextColor3 = C(149, 151, 161), TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(15, 0), Size = UDim2.new(1, -76, 1, 0), ZIndex = 4,
}, toggle)
local track = make("Frame", {
    Name = "SwitchTrack", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -13, 0.5, 0),
    Size = UDim2.fromOffset(44, 24), BackgroundColor3 = C(17, 18, 22), BorderSizePixel = 0, ZIndex = 4,
}, toggle)
round(track, 12)
local knob = make("Frame", {
    Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
    Size = UDim2.fromOffset(18, 18), BackgroundColor3 = C(131, 134, 145), BorderSizePixel = 0, ZIndex = 5,
}, track)
round(knob, 9)
local function paintToggle(enabled)
    gui:SetAttribute("FlightEnabled", enabled)
    stateLabel.Text = enabled and "ON" or "OFF"
    stateLabel.TextColor3 = enabled and C(225, 238, 247) or C(149, 151, 161)
    toggle.BackgroundColor3 = enabled and C(40, 53, 64) or C(34, 37, 44)
    toggleStroke.Color = enabled and C(120, 147, 166) or C(80, 82, 96)
    tween(knob, 0.16, {Position = UDim2.new(0, enabled and 23 or 3, 0.5, 0),
        BackgroundColor3 = enabled and C(198, 221, 235) or C(131, 134, 145)})
end

local speedRow = make("Frame", {
    Name = "SpeedControl", Position = UDim2.fromOffset(12, 100), Size = UDim2.new(1, -24, 0, 44),
    BackgroundColor3 = C(15, 17, 21), BorderSizePixel = 0, Active = true,
}, window)
round(speedRow, 10)
local speedStroke = make("UIStroke", {Color = C(77, 80, 91), Transparency = 0.6, Thickness = 1}, speedRow)
local function speedButton(name, text, position)
    local button = make("TextButton", {
        Name = name, Text = text, Position = position, Size = UDim2.fromOffset(44, 44),
        Font = Enum.Font.GothamMedium, TextSize = 24, TextColor3 = C(230, 233, 242),
        BackgroundColor3 = C(43, 47, 57), BackgroundTransparency = 0,
        BorderSizePixel = 0, AutoButtonColor = false,
    }, speedRow)
    round(button, 10)
    make("UIStroke", {Color = C(99, 106, 124), Transparency = 0.65, Thickness = 1}, button)
    return button
end
local speedDown = speedButton("SpeedDown", "−", UDim2.fromOffset(0, 0))
local speedUp = speedButton("SpeedUp", "+", UDim2.new(1, -44, 0, 0))
local speedBox = make("TextBox", {
    Name = "SpeedValue", Position = UDim2.fromOffset(51, 0), Size = UDim2.new(1, -102, 1, 0),
    BackgroundTransparency = 1, Text = tostring(flightSpeed), PlaceholderText = "5",
    TextColor3 = C(240, 242, 248), PlaceholderColor3 = C(120, 120, 130),
    Font = Enum.Font.GothamMedium, TextSize = 19, TextScaled = true,
    ClearTextOnFocus = false, MultiLine = false, TextEditable = true,
}, speedRow)
make("UIPadding", {PaddingTop = UDim.new(0, 15), PaddingBottom = UDim.new(0, 4)}, speedBox)
make("UITextSizeConstraint", {MinTextSize = 14, MaxTextSize = 19}, speedBox)
make("TextLabel", {
    Name = "SpeedLabel", Position = UDim2.fromOffset(51, 3), Size = UDim2.new(1, -102, 0, 12),
    BackgroundTransparency = 1, Text = "SPEED", TextColor3 = C(143, 145, 156),
    Font = Enum.Font.GothamMedium, TextSize = 9, ZIndex = 2,
}, speedRow)
local function applySpeed(value)
    if not alive or closing then return false end
    local valid = type(value) == "number" and value == value and math.abs(value) < math.huge
    if valid then
        flightSpeed = math.floor(math.clamp(value, CONFIG.MinSpeed, CONFIG.MaxSpeed) + 0.5)
        gui:SetAttribute("FlightSpeed", flightSpeed)
    end
    speedBox.Text = tostring(flightSpeed)
    speedStroke.Color = valid and C(77, 80, 91) or C(189, 113, 113)
    speedDown.TextColor3 = flightSpeed <= CONFIG.MinSpeed and C(101, 106, 119) or C(230, 233, 242)
    speedUp.TextColor3 = flightSpeed >= CONFIG.MaxSpeed and C(101, 106, 119) or C(230, 233, 242)
    return valid
end
connect(connections, speedBox.FocusLost, function()
    applySpeed(tonumber((speedBox.Text:gsub(",", "."))))
end)
local function stepSpeed(direction)
    if not alive or closing then return end
    -- Commit an in-progress entry before applying a step, independently of
    -- whether mobile FocusLost arrives before or after Activated.
    if speedBox:IsFocused() then
        applySpeed(tonumber((speedBox.Text:gsub(",", "."))))
        speedBox:ReleaseFocus()
    end
    applySpeed(flightSpeed + direction * CONFIG.SpeedStep)
end
connect(connections, speedDown.Activated, function() stepSpeed(-1) end)
connect(connections, speedUp.Activated, function() stepSpeed(1) end)
applySpeed(flightSpeed)
local overSpeed = false
connect(connections, speedRow.MouseEnter, function() overSpeed = true end)
connect(connections, speedRow.MouseLeave, function() overSpeed = false end)
-- One input listener avoids duplicate steps when the pointer is over a child
-- control rather than the row background.
connect(connections, Input.InputChanged, function(input)
    if focused and overSpeed and input.UserInputType == Enum.UserInputType.MouseWheel and input.Position.Z ~= 0 then
        stepSpeed(input.Position.Z > 0 and 1 or -1)
    end
end)

-- Resolve the real AnimationId from each allowed catalog package. Imported
-- containers are never parented into the DataModel and no imported code runs.
local resolvedIds = {}
local function resolveAnimation(packageId)
    if resolvedIds[packageId] then return resolvedIds[packageId] end
    local ok, objects = pcall(function() return game:GetObjects("rbxassetid://" .. packageId) end)
    if not ok or type(objects) ~= "table" then return nil end
    local id
    local function inspect(object)
        if not id and object:IsA("Animation") then
            local candidate = object.AnimationId
            local digits = candidate:match("^rbxassetid://(%d+)$") or candidate:match("[?&]id=(%d+)")
            if digits and tonumber(digits) ~= packageId then id = "rbxassetid://" .. digits end
        end
    end
    for _, object in ipairs(objects) do
        pcall(function()
            inspect(object)
            for _, child in ipairs(object:GetDescendants()) do inspect(child) end
        end)
        object:Destroy()
    end
    if id then resolvedIds[packageId] = id end
    return id
end
local function validBody(b)
    local bottom=workspace.FallenPartsDestroyHeight
    return alive and not closing and body == b and not b.retired
        and currentCharacter and currentCharacter:IsDescendantOf(workspace)
        and player.Character == currentCharacter and b.root.Parent == currentCharacter
        and b.humanoid.Parent == currentCharacter and b.humanoid.Health > 0
        and (type(bottom)~="number" or b.root.Position.Y>bottom+4)
end
local function clearAnimations(b)
    b.animationGeneration += 1
    for _, trackObject in pairs(b.tracks) do trackObject:Stop(0); trackObject:Destroy() end
    table.clear(b.tracks)
    b.animator, b.mode = nil, nil
end
local function loadAnimations(b, animator)
    if not wantedFlight or not b.flying or not validBody(b) then return end
    if b.animator == animator then return end
    clearAnimations(b)
    b.animator = animator
    local generation = b.animationGeneration
    if b.humanoid.RigType ~= Enum.HumanoidRigType.R15 then
        gui:SetAttribute("AnimationStatus", "R15Required")
        warnOnce("rig", "The SSJ3 catalog pack requires R15. Flight still works on R6.")
        return
    end
    gui:SetAttribute("AnimationStatus", "Loading")
    local function current()
        return wantedFlight and b.flying and validBody(b)
            and b.animationGeneration == generation and animator.Parent == b.humanoid
    end
    task.spawn(function()
        local loaded = 0
        for _, name in ipairs({"Idle", "Run", "Climb", "Fall"}) do
            if not current() then return end
            local id = resolveAnimation(CONFIG.Packages[name])
            if not current() then return end
            if id then
                local animation = make("Animation", {Name = "FlyDBZ" .. name, AnimationId = id})
                local ok, result = pcall(function() return animator:LoadAnimation(animation) end)
                animation:Destroy()
                if not current() then
                    if ok and result then result:Stop(0); result:Destroy() end
                    return
                end
                if ok and result then
                    result.Priority = Enum.AnimationPriority.Action
                    result.Looped = true
                    b.tracks[name] = result
                    loaded += 1
                end
            end
        end
        if not current() then return end
        gui:SetAttribute("AnimationStatus", loaded > 0 and "Loaded" or "Unavailable")
        if loaded < 4 then
            warnOnce("assets", "Some SSJ3 clips could not be loaded. Roblox asset permissions still apply; flight remains available.")
        end
        -- LoadAnimation can return a track before its content succeeds or fails.
        task.delay(8, function()
            if not current() then return end
            local playable = 0
            for name, trackObject in pairs(b.tracks) do
                if trackObject.Length > 0 then playable += 1
                else trackObject:Stop(0); trackObject:Destroy(); b.tracks[name] = nil; b.mode = nil end
            end
            gui:SetAttribute("AnimationStatus", playable > 0 and "Ready" or "Unavailable")
            if loaded > 0 and playable == 0 then
                warnOnce("permission", "Roblox did not deliver playable SSJ3 clips. Check R15 and animation permissions.")
            end
        end)
    end)
end
local function updateAnimation(b, move)
    local desired = "Idle"
    if move.Magnitude > 0.08 then
        desired = move.Y > 0.4 and "Climb" or (move.Y < -0.4 and "Fall" or "Run")
    end
    if not b.tracks[desired] then desired = "Idle" end
    local nextTrack = b.tracks[desired]
    if not nextTrack then return end
    if b.mode ~= desired or not nextTrack.IsPlaying then
        for name, other in pairs(b.tracks) do if name ~= desired and other.IsPlaying then other:Stop(0.22) end end
        nextTrack:Play(0.22, 1, desired == "Run" and 0.7 or 0.8)
        b.mode = desired
    end
end

-- Two non-yielding phases replace the supplied Heartbeat callback's yielding
-- RenderStepped:Wait(). A pending write is restored before physics or on cleanup.
local function restoreVelocity()
    noFallLease:restore()
end
local function stopFlight(b)
    restoreVelocity()
    noFallLease:setEnabled(false)
    local wasFlying = b.flying
    b.flying = false
    b.smoothed = ZERO
    if b.velocity then b.velocity:Destroy(); b.velocity = nil end
    if b.orientation then b.orientation:Destroy(); b.orientation = nil end
    if b.flightAttachment then b.flightAttachment:Destroy(); b.flightAttachment = nil end
    if wasFlying and b.humanoid.Parent then
        if b.humanoid.AutoRotate == false then b.humanoid.AutoRotate = b.savedAutoRotate end
        if b.humanoid.PlatformStand == true then b.humanoid.PlatformStand = b.savedPlatformStand end
        if b.humanoid.Health > 0 and not b.savedPlatformStand then b.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end
    clearAnimations(b)
    if body == b then
        gui:SetAttribute("NoFallDamageArmed", false)
        gui:SetAttribute("AnimationStatus", "Idle")
    end
end
local function startFlight(b)
    if not wantedFlight or not validBody(b) or b.root.Anchored or b.humanoid.SeatPart then return false end
    if b.flying then return true end
    restoreVelocity()
    b.flying = true
    b.savedAutoRotate, b.savedPlatformStand = b.humanoid.AutoRotate, b.humanoid.PlatformStand
    b.humanoid.AutoRotate = false
    b.humanoid.PlatformStand = true
    b.flightAttachment = make("Attachment", {Name = "FlyDBZMoverAttachment"}, b.root)
    b.velocity = make("LinearVelocity", {
        Name = "FlyDBZVelocity", Attachment0 = b.flightAttachment, RelativeTo = Enum.ActuatorRelativeTo.World,
        VelocityConstraintMode = Enum.VelocityConstraintMode.Vector, ForceLimitsEnabled = false, VectorVelocity = ZERO,
    }, b.root)
    b.orientation = make("AlignOrientation", {
        Name = "FlyDBZOrientation", Attachment0 = b.flightAttachment, Mode = Enum.OrientationAlignmentMode.OneAttachment,
        RigidityEnabled = false, Responsiveness = 18, MaxTorque = math.huge, MaxAngularVelocity = 12,
        CFrame = b.root.CFrame.Rotation,
    }, b.root)
    b.smoothed = ZERO
    noFallLease:setEnabled(game.PlaceId == CONFIG.NoFallPlaceId)
    gui:SetAttribute("NoFallDamageArmed", noFallLease:isOwner())
    local animator = b.humanoid:FindFirstChildOfClass("Animator")
    if animator then loadAnimations(b, animator) end
    return true
end
local function deactivate(retireBody)
    wantedFlight = false
    gui:SetAttribute("NoFallDamageArmed", false)
    restoreVelocity()
    if body then
        if retireBody then body.retired = true end
        stopFlight(body)
    end
    paintToggle(false)
end
local function releaseBody()
    local previous = body
    if not previous then return end
    disconnectAll(bodyConnections)
    stopFlight(previous)
    body = nil
end
local function refreshBody()
    if not alive or not currentCharacter then return end
    local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
    local root = currentCharacter:FindFirstChild("HumanoidRootPart")
    if body and (body.humanoid ~= humanoid or body.root ~= root) then
        deactivate(true)
        releaseBody()
    end
    if not humanoid or not root or not root:IsA("BasePart") then return end
    if body then return end
    local b = {humanoid = humanoid, root = root, flying = false, retired = humanoid.Health <= 0,
        tracks = {}, animationGeneration = 0, smoothed = ZERO}
    body = b
    connect(bodyConnections, humanoid.Died, function() if body == b then deactivate(true) end end)
    connect(bodyConnections, humanoid:GetPropertyChangedSignal("Health"), function()
        if body == b and humanoid.Health <= 0 then deactivate(true) end
    end)
    connect(bodyConnections, humanoid.ChildAdded, function(child)
        if child:IsA("Animator") and wantedFlight and b.flying and validBody(b) then loadAnimations(b, child) end
    end)
    connect(bodyConnections, humanoid.ChildRemoved, function(child)
        if child == b.animator then
            clearAnimations(b)
            gui:SetAttribute("AnimationStatus", "Idle")
        end
    end)
end
local function bindCharacter(character)
    -- A new life never inherits ON, even when CharacterRemoving was skipped.
    deactivate(true)
    disconnectAll(characterConnections)
    restoreVelocity()
    releaseBody()
    currentCharacter = character
    if not character then return end
    connect(characterConnections, character.ChildAdded, refreshBody)
    connect(characterConnections, character.ChildRemoved, refreshBody)
    refreshBody()
end

-- Roblox PlayerModule supplies the same analog move vector for touch and WASD.
-- Missing/modified PlayerModule falls back to physical keys or Humanoid movement.
task.spawn(function()
    local scripts = player:WaitForChild("PlayerScripts", 8)
    local module = scripts and scripts:WaitForChild("PlayerModule", 8)
    if not module or not alive then return end
    local ok, result = pcall(function() return require(module):GetControls() end)
    if alive and ok then controls = result end
end)
local function moveDirection(b, camera)
    if not focused or Input:GetFocusedTextBox() then return ZERO end
    local localMove
    if controls then
        local ok, result = pcall(function() return controls:GetMoveVector() end)
        if ok and typeof(result) == "Vector3" then localMove = result end
    end
    local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
    if right.Magnitude < 0.001 then right = Vector3.xAxis else right = right.Unit end
    local flatForward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
    if flatForward.Magnitude < 0.001 then
        local look = b.root.CFrame.LookVector
        flatForward = Vector3.new(look.X, 0, look.Z)
    end
    if flatForward.Magnitude < 0.001 then flatForward = -Vector3.zAxis else flatForward = flatForward.Unit end
    if not localMove then
        local x = (Input:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (Input:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
        local z = (Input:IsKeyDown(Enum.KeyCode.S) and 1 or 0) - (Input:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
        if x ~= 0 or z ~= 0 then localMove = Vector3.new(x, 0, z)
        else
            local worldMove = b.humanoid.MoveDirection
            localMove = Vector3.new(worldMove:Dot(right), 0, -worldMove:Dot(flatForward))
        end
    end
    local direction = right * localMove.X - camera.CFrame.LookVector * localMove.Z
    return direction.Magnitude > 1 and direction.Unit or direction
end

local dragging, dragStart, windowStart
local function endDrag() dragging = nil end
connect(connections, header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, windowStart = input, input.Position, window.Position
    end
end)
connect(connections, Input.InputChanged, function(input)
    if not dragging then return end
    if input == dragging or (dragging.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - dragStart
        window.Position = UDim2.new(windowStart.X.Scale, windowStart.X.Offset + delta.X, windowStart.Y.Scale, windowStart.Y.Offset + delta.Y)
    end
end)
connect(connections, Input.InputEnded, function(input)
    if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then endDrag() end
end)
connect(connections, Input.WindowFocusReleased, function() focused = false; endDrag() end)
connect(connections, Input.WindowFocused, function() focused = true end)
connect(connections, toggle.Activated, function()
    if not alive or closing then return end
    if wantedFlight then deactivate(false); return end
    -- Do not queue an activation on a corpse or during character construction.
    if not body or not validBody(body) then return end
    wantedFlight = true
    if not startFlight(body) then deactivate(false); return end
    paintToggle(true)
end)
connect(connections, player.CharacterAdded, bindCharacter)
connect(connections, player.CharacterRemoving, function(character)
    if character == currentCharacter then bindCharacter(nil) end
end)

connect(connections, RunService.PreSimulation, function(dt)
    restoreVelocity()
    local b = body
    if not b then return end
    if not validBody(b) then
        if wantedFlight or b.flying then deactivate(true) end
        return
    end
    if b.root.Anchored or b.humanoid.SeatPart then
        if b.flying then stopFlight(b) end
        return
    end
    if wantedFlight and not b.flying then startFlight(b) end
    if not b.flying then return end
    local camera = workspace.CurrentCamera
    local direction = camera and moveDirection(b, camera) or ZERO
    local target = direction * flightSpeed
    local blend = 1 - math.exp(-CONFIG.Acceleration * math.min(dt, 0.1))
    -- Interpolate components as numbers; large opposite velocities can overflow
    -- a Vector3 subtraction even when each requested value is finite.
    b.smoothed = Vector3.new(b.smoothed.X * (1 - blend) + target.X * blend,
        b.smoothed.Y * (1 - blend) + target.Y * blend, b.smoothed.Z * (1 - blend) + target.Z * blend)
    if math.max(math.abs(b.smoothed.X), math.abs(b.smoothed.Y), math.abs(b.smoothed.Z)) < 0.015 then b.smoothed = ZERO end
    b.velocity.VectorVelocity = b.smoothed
    if camera then
        local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
        if forward.Magnitude > 0.01 then
            b.orientation.CFrame = CFrame.lookAt(ZERO, forward.Unit) * CFrame.Angles(-math.rad(9) * direction.Magnitude, 0, 0)
        end
    end
    updateAnimation(b, direction)
end)
connect(connections, RunService.Heartbeat, function()
    local b = body
    if not wantedFlight or not b or not b.flying or not validBody(b)
        or game.PlaceId ~= CONFIG.NoFallPlaceId or b.root.Anchored then return end
    noFallLease:pulse(b.root)
end)
connect(connections, RunService.RenderStepped, restoreVelocity)

local function cleanup()
    if not alive then return end
    alive, wantedFlight = false, false
    gui:SetAttribute("FlightEnabled", false)
    gui:SetAttribute("NoFallDamageArmed", false)
    restoreVelocity()
    disconnectAll(connections)
    disconnectAll(characterConnections)
    releaseBody()
    noFallLease:destroy()
    for _, animation in pairs(activeTweens) do animation:Cancel() end
    table.clear(activeTweens)
    controls, currentCharacter = nil, nil
end
connect(connections, gui.Destroying, cleanup)
connect(connections, close.Activated, function()
    if closing then return end
    closing = true
    deactivate(false)
    gui:Destroy()
end)
if player.Character then bindCharacter(player.Character) end
return gui
