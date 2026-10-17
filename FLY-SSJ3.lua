-- FLY DBZ | 1.0 | Made By Reyzn
-- Client controller. Catalog animations require R15 and asset permission.
-- Uses the character's existing Animator; client-created aura is local only.
-- No Fall Damage retains the supplied Natural Disaster Survival place guard.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Input = game:GetService("UserInputService")
local player = Players.LocalPlayer
if not player then return end
local playerGui = player:WaitForChild("PlayerGui")

local CONFIG = {
    Speed = 58,
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
local pendingVelocity
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
local function cancelTween(object)
    if activeTweens[object] then activeTweens[object]:Cancel(); activeTweens[object] = nil end
end
local function round(parent, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius)}, parent)
end
local function gradient(parent, colors, rotation)
    return make("UIGradient", {Color = ColorSequence.new(colors), Rotation = rotation or 0}, parent)
end
local C = Color3.fromRGB
local ZERO = Vector3.zero
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

-- Compact touch-friendly surface: heading, flight switch and editable speed.
local gui = make("ScreenGui", {
    Name = "FlyDBZ", ResetOnSpawn = false, IgnoreGuiInset = false,
    DisplayOrder = 72, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
gui:SetAttribute("Version", "1.0")
gui:SetAttribute("FlightEnabled", false)
gui:SetAttribute("NoFallDamageArmed", game.PlaceId == CONFIG.NoFallPlaceId)
gui:SetAttribute("AnimationStatus", "Idle")
gui:SetAttribute("FlightSpeed", flightSpeed)
local window = make("CanvasGroup", {
    Name = "Window", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 80),
    Size = UDim2.fromOffset(228, 146), BackgroundColor3 = C(28, 28, 32), ZIndex = 3,
    BackgroundTransparency = 0.03, GroupTransparency = 1, BorderSizePixel = 0,
}, gui)
round(window, 15)
local frameStroke = make("UIStroke", {Color = C(112, 115, 126), Transparency = 0.48, Thickness = 1}, window)
gradient(window, {
    ColorSequenceKeypoint.new(0, C(248, 241, 224)),
    ColorSequenceKeypoint.new(0.42, C(198, 196, 202)),
    ColorSequenceKeypoint.new(1, C(139, 138, 147)),
}, 65)
local frameSheen = gradient(frameStroke, {
    ColorSequenceKeypoint.new(0, C(150, 139, 116)),
    ColorSequenceKeypoint.new(0.46, C(255, 244, 200)),
    ColorSequenceKeypoint.new(0.62, C(198, 173, 114)),
    ColorSequenceKeypoint.new(1, C(127, 129, 140)),
}, 25)
local windowScale = make("UIScale", {Scale = 0.96}, window)
local header = make("TextLabel", {
    Name = "DragHandle", BackgroundTransparency = 1, Active = true,
    Position = UDim2.fromOffset(15, 0), Size = UDim2.new(1, -59, 0, 40),
    Text = "FLY DBZ", TextColor3 = C(249, 246, 235), TextSize = 16,
    Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
}, window)
local close = make("TextButton", {
    Name = "Close", BackgroundTransparency = 1, BackgroundColor3 = C(255, 224, 139), Position = UDim2.new(1, -42, 0, 0),
    Size = UDim2.fromOffset(42, 40), Text = "×", TextSize = 23,
    Font = Enum.Font.Gotham, TextColor3 = C(150, 151, 162), AutoButtonColor = false,
}, window)
round(close, 12)
connect(connections, close.MouseEnter, function() if not closing then tween(close, 0.18, {BackgroundTransparency = 0.9, TextColor3 = C(255, 237, 185)}) end end)
connect(connections, close.MouseLeave, function() if not closing then tween(close, 0.2, {BackgroundTransparency = 1, TextColor3 = C(150, 151, 162)}) end end)
local divider = make("Frame", {Name = "HeaderAccent", Position = UDim2.fromOffset(15, 35),
    Size = UDim2.new(1, -30, 0, 1), BorderSizePixel = 0, BackgroundColor3 = C(246, 206, 111)}, window)
local dividerGradient = gradient(divider, {ColorSequenceKeypoint.new(0, C(255, 240, 186)), ColorSequenceKeypoint.new(1, C(71, 69, 71))})
dividerGradient.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.25, 0.75), NumberSequenceKeypoint.new(1, 1)})
local toggle = make("TextButton", {
    Name = "FlightToggle", Position = UDim2.fromOffset(12, 43), Size = UDim2.new(1, -24, 0, 42),
    BackgroundColor3 = C(31, 32, 38), Text = "", AutoButtonColor = false, BorderSizePixel = 0,
}, window)
round(toggle, 11)
gradient(toggle, {ColorSequenceKeypoint.new(0, C(225, 222, 212)),
    ColorSequenceKeypoint.new(0.45, C(165, 166, 181)), ColorSequenceKeypoint.new(1, C(216, 207, 187))}, 30)
local toggleScale = make("UIScale", {Scale = 1}, toggle)
local toggleStroke = make("UIStroke", {Thickness = 1, Color = C(80, 82, 96), Transparency = 0.45}, toggle)
local light = make("Frame", {
    Name = "ActiveLight", BackgroundColor3 = C(255, 216, 83), BackgroundTransparency = 1,
    BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 2,
}, toggle)
round(light, 11)
local toggleSheen = gradient(light, {
    ColorSequenceKeypoint.new(0, C(255, 250, 168)),
    ColorSequenceKeypoint.new(0.45, C(248, 183, 53)),
    ColorSequenceKeypoint.new(1, C(255, 230, 111)),
}, -25)
local flash = make("Frame", {
    Name = "ActivationFlash", BackgroundColor3 = C(255, 250, 212), BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, ZIndex = 3,
}, toggle)
round(flash, 11)
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
    tween(stateLabel, 0.22, {TextColor3 = enabled and C(255, 245, 193) or C(149, 151, 161)})
    tween(knob, 0.24, {Position = UDim2.new(0, enabled and 23 or 3, 0.5, 0),
        BackgroundColor3 = enabled and C(255, 238, 153) or C(131, 134, 145)})
    tween(light, 0.32, {BackgroundTransparency = enabled and 0.78 or 1})
    tween(toggleStroke, 0.28, {Color = enabled and C(255, 217, 100) or C(80, 82, 96), Transparency = enabled and 0.2 or 0.45})
    tween(frameStroke, 0.4, {Color = enabled and C(214, 187, 119) or C(112, 115, 126), Transparency = enabled and 0.25 or 0.48})
    cancelTween(flash)
    flash.BackgroundTransparency = enabled and 0.5 or 1
    if enabled then tween(flash, 0.65, {BackgroundTransparency = 1}) end
    toggleScale.Scale = 0.976
    tween(toggleScale, 0.24, {Scale = 1})
end

local speedRow = make("Frame", {
    Name = "SpeedControl", Position = UDim2.fromOffset(12, 93), Size = UDim2.new(1, -24, 0, 42),
    BackgroundColor3 = C(26, 27, 33), BorderSizePixel = 0, Active = true,
}, window)
round(speedRow, 10)
gradient(speedRow, {ColorSequenceKeypoint.new(0, C(218, 216, 211)),
    ColorSequenceKeypoint.new(0.5, C(179, 179, 191)), ColorSequenceKeypoint.new(1, C(220, 218, 211))}, 90)
local speedStroke = make("UIStroke", {Color = C(77, 80, 91), Transparency = 0.6, Thickness = 1}, speedRow)
local function speedButton(name, text, position)
    local button = make("TextButton", {
        Name = name, Text = text, Position = position, Size = UDim2.fromOffset(42, 42),
        Font = Enum.Font.Gotham, TextSize = 22, TextColor3 = C(218, 218, 226),
        BackgroundColor3 = C(255, 222, 122), BackgroundTransparency = 1,
        BorderSizePixel = 0, AutoButtonColor = false,
    }, speedRow)
    round(button, 10)
    return button
end
local speedDown = speedButton("SpeedDown", "−", UDim2.fromOffset(0, 0))
local speedUp = speedButton("SpeedUp", "+", UDim2.new(1, -42, 0, 0))
local speedBox = make("TextBox", {
    Name = "SpeedValue", Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -84, 1, 0),
    BackgroundTransparency = 1, Text = tostring(flightSpeed), PlaceholderText = "58",
    TextColor3 = C(240, 237, 225), PlaceholderColor3 = C(120, 120, 130),
    Font = Enum.Font.GothamMedium, TextSize = 16, TextScaled = true,
    ClearTextOnFocus = false, MultiLine = false, TextEditable = true,
}, speedRow)
make("UIPadding", {PaddingTop = UDim.new(0, 15), PaddingBottom = UDim.new(0, 4)}, speedBox)
make("UITextSizeConstraint", {MinTextSize = 10, MaxTextSize = 16}, speedBox)
make("TextLabel", {
    Name = "SpeedLabel", Position = UDim2.fromOffset(42, 3), Size = UDim2.new(1, -84, 0, 12),
    BackgroundTransparency = 1, Text = "SPEED", TextColor3 = C(143, 145, 156),
    Font = Enum.Font.GothamMedium, TextSize = 9, ZIndex = 2,
}, speedRow)
local function applySpeed(value)
    if not alive or closing then return false end
    -- No gameplay cap. Reject invalid/infinite values and values that overflow
    -- Roblox's Vector3 storage instead of sending NaN/Inf into the physics solver.
    local valid = type(value) == "number" and value == value and value >= 0 and value < math.huge
    if valid then valid = Vector3.new(value, 0, 0).X < math.huge end
    if valid then
        flightSpeed = value
        gui:SetAttribute("FlightSpeed", value)
    end
    speedBox.Text = tostring(flightSpeed)
    cancelTween(speedStroke)
    speedStroke.Color = valid and C(255, 221, 137) or C(218, 131, 128)
    speedStroke.Transparency = 0.2
    tween(speedStroke, 0.4, {Color = C(77, 80, 91), Transparency = 0.6})
    return valid
end
connect(connections, speedBox.FocusLost, function()
    applySpeed(tonumber((speedBox.Text:gsub(",", "."))))
end)
local function stepSpeed(direction, button)
    if not alive or closing then return end
    -- Commit an in-progress entry before applying a step, independently of
    -- whether mobile FocusLost arrives before or after Activated.
    if speedBox:IsFocused() then
        applySpeed(tonumber((speedBox.Text:gsub(",", "."))))
        speedBox:ReleaseFocus()
    end
    applySpeed(math.max(0, flightSpeed + direction * 2))
    if button then
        cancelTween(button)
        button.BackgroundTransparency = 0.83
        tween(button, 0.3, {BackgroundTransparency = 1})
    end
end
connect(connections, speedDown.Activated, function() stepSpeed(-1, speedDown) end)
connect(connections, speedUp.Activated, function() stepSpeed(1, speedUp) end)
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

-- Overlapping, tapered tongues of warm light, behind the card. These native
-- gradient surfaces avoid the dark particle-texture stamps seen in normal UI
-- blending. The pool is completely hidden in OFF, after its short fade.
local uiFireLayer = make("Frame", {Name = "WindowFireLayer", BackgroundTransparency = 1,
    AnchorPoint = window.AnchorPoint, Position = window.Position, Size = window.Size,
    ClipsDescendants = false, Active = false, ZIndex = 1}, gui)
local uiFireScale = make("UIScale", {Scale = windowScale.Scale}, uiFireLayer)
connect(connections, window:GetPropertyChangedSignal("Position"), function() uiFireLayer.Position = window.Position end)
local uiFire = {clock = 0, strength = 0, particles = {}}
uiFireLayer.Visible = false
local flameFade = NumberSequence.new({NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.18, 0.18), NumberSequenceKeypoint.new(0.65, 0),
    NumberSequenceKeypoint.new(1, 0.7)})
for i = 1, 24 do
    local edge = i <= 14 and "top" or (i <= 18 and "left" or (i <= 22 and "right" or "bottom"))
    local along = edge == "top" and ((i - 0.5) / 14)
        or (edge == "left" and ((i - 14.5) / 4) or (edge == "right" and ((i - 18.5) / 4) or ((i - 22.5) / 2)))
    local layers = {}
    for layer = 1, 3 do
        local sprite = make("Frame", {Name = "GuiFlame", BackgroundTransparency = 1,
            BackgroundColor3 = layer == 1 and C(255, 165, 32) or (layer == 2 and C(255, 203, 62) or C(255, 240, 151)),
            BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1),
            Size = UDim2.fromOffset(12, 18), ZIndex = 1, Active = false}, uiFireLayer)
        round(sprite, 12)
        local shade = gradient(sprite, {ColorSequenceKeypoint.new(0, C(255, 193, 81)),
            ColorSequenceKeypoint.new(1, C(255, 255, 255))}, 90)
        shade.Transparency = flameFade
        layers[layer] = sprite
    end
    uiFire.particles[#uiFire.particles + 1] = {layers = layers, edge = edge, along = along,
        phase = (i * 0.61803398875) % 1, life = 0.95 + (i % 5) * 0.13}
end
function uiFire:Update(dt)
    self.clock += dt
    local strengthTarget = not closing and wantedFlight and 0.9 or 0
    self.strength += (strengthTarget - self.strength) * (1 - math.exp(-9 * dt))
    if strengthTarget == 0 and self.strength < 0.002 then self.strength = 0 end
    local visibility = self.strength * (1 - window.GroupTransparency)
    uiFireScale.Scale = windowScale.Scale
    uiFireLayer.Visible = visibility > 0
    -- No sprite work while OFF. Keep only the small metallic surface sheen.
    frameSheen.Offset = Vector2.new(math.sin(self.clock * 0.48) * 0.45, 0)
    toggleSheen.Offset = Vector2.new(math.sin(self.clock * 0.7) * 0.22, 0)
    if visibility == 0 then return end
    local width, height = window.Size.X.Offset, window.Size.Y.Offset
    for _, particle in ipairs(self.particles) do
        local age = (self.clock / particle.life + particle.phase) % 1
        local envelope = math.sin(age * math.pi) ^ 0.8
        local sway = math.sin(self.clock * 2.5 + particle.phase * 11)
        local tongueHeight = 13 + envelope * (12 + particle.phase * 7)
        local x, y
        if particle.edge == "top" then x, y = width * particle.along, 7
        elseif particle.edge == "bottom" then x, y = width * particle.along, height + 6
        else x, y = particle.edge == "left" and 1 or width - 1, height * particle.along + 10 end
        for layer, sprite in ipairs(particle.layers) do
            local outer, core = layer == 1, layer == 3
            sprite.Position = UDim2.fromOffset(x + sway * (core and 1 or 2), y)
            sprite.Size = UDim2.fromOffset(outer and 27 or (core and 5 or 11),
                tongueHeight * (outer and 0.72 or (core and 0.62 or 1)))
            sprite.Rotation = sway * (outer and 5 or 13)
            sprite.BackgroundTransparency = 1 - visibility * envelope * (outer and 0.18 or (core and 0.7 or 0.46))
        end
    end
end

-- This notice has no timeout and does not block the joystick outside its card.
-- Flight toggles and respawns never dismiss it; only its explicit button does.
gui:SetAttribute("QualityNoticeDismissed", false)
local notice = make("CanvasGroup", {Name = "QualityNotice", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.86, 0, 0, 132),
    BackgroundColor3 = C(23, 24, 29), BackgroundTransparency = 0.03, BorderSizePixel = 0,
    GroupTransparency = 1, ZIndex = 20, Active = true}, gui)
make("UISizeConstraint", {MinSize = Vector2.new(0, 132), MaxSize = Vector2.new(360, 132)}, notice)
round(notice, 16)
make("UIStroke", {Color = C(220, 190, 115), Transparency = 0.32, Thickness = 1}, notice)
gradient(notice, {ColorSequenceKeypoint.new(0, C(245, 237, 214)), ColorSequenceKeypoint.new(1, C(180, 181, 197))}, 60)
local noticeScale = make("UIScale", {Scale = 0.96}, notice)
make("TextLabel", {Name = "QualityMessage", Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 58),
    BackgroundTransparency = 1, Text = "For better quality, use Roblox's high graphics settings.",
    TextColor3 = C(243, 240, 229), Font = Enum.Font.GothamMedium, TextSize = 14,
    TextWrapped = true, ZIndex = 21}, notice)
local dismissNotice = make("TextButton", {Name = "DismissQualityNotice", AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 79), Size = UDim2.new(1, -40, 0, 40), Text = "OK",
    Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C(255, 237, 182),
    BackgroundColor3 = C(61, 51, 30), BorderSizePixel = 0, AutoButtonColor = false, ZIndex = 21}, notice)
round(dismissNotice, 10)
make("UIStroke", {Color = C(207, 175, 102), Transparency = 0.55}, dismissNotice)
local noticeClosing = false
connect(connections, dismissNotice.Activated, function()
    if not alive or closing or noticeClosing then return end
    noticeClosing = true
    gui:SetAttribute("QualityNoticeDismissed", true)
    dismissNotice.Active = false
    tween(notice, 0.22, {GroupTransparency = 1})
    tween(noticeScale, 0.22, {Scale = 0.97})
    task.delay(0.24, function()
        if not alive then return end
        cancelTween(notice); cancelTween(noticeScale)
        notice:Destroy()
    end)
end)
tween(notice, 0.4, {GroupTransparency = 0})
tween(noticeScale, 0.4, {Scale = 1})

-- A close, body-anchored flame envelope plus a separately steered wake. Only
-- the wake turns with velocity; the whole aura no longer rolls around the body.
-- All attachments stay on this character. No global lighting, sound or new
-- instances/NumberSequences per animation frame.
local Aura = {}
Aura.__index = Aura
local function unitAndSpeed(vector)
    local largest = math.max(math.abs(vector.X), math.abs(vector.Y), math.abs(vector.Z))
    if largest < 0.001 or largest ~= largest or largest == math.huge then return ZERO, 0 end
    local scaled = Vector3.new(vector.X / largest, vector.Y / largest, vector.Z / largest)
    return scaled.Unit, largest * scaled.Magnitude
end
local function turnAxis(from, to, alpha)
    local dot = math.clamp(from:Dot(to), -1, 1)
    if dot > 0.999 then return from:Lerp(to, alpha).Unit end
    if dot < -0.999 then
        -- A half-turn needs a stable perpendicular; linear interpolation would
        -- cross zero and snap when reversing from ascent to descent.
        local reference = math.abs(from.X) < 0.9 and Vector3.xAxis or Vector3.zAxis
        local perpendicular = from:Cross(reference).Unit
        return (from * math.cos(math.pi * alpha) + perpendicular * math.sin(math.pi * alpha)).Unit
    end
    local angle = math.acos(dot)
    return (from * math.sin((1 - alpha) * angle) + to * math.sin(alpha * angle)).Unit
end
local function flowBasis(axis)
    local reference = math.abs(axis.Y) < 0.92 and Vector3.yAxis or Vector3.zAxis
    local across = axis:Cross(reference).Unit
    return across, axis:Cross(across).Unit
end
function Aura.new(root, humanoid)
    local self = setmetatable({objects = {}, emitters = {}, ribbons = {}, clock = 0,
        running = false, reveal = 0, targetOn = false, root = root,
        axis = Vector3.yAxis, across = Vector3.xAxis, motion = 0, alignment = 0}, Aura)
    self.level = make("NumberValue", {Name = "FlyDBZAuraLevel", Value = 0})
    self.objects[#self.objects + 1] = self.level
    local bottom = -math.max(2.7, humanoid.HipHeight + root.Size.Y * 0.5)
    local height = math.max(6.2, humanoid.HipHeight + root.Size.Y + 2.4)
    local radiusX = math.max(1.3, root.Size.X * 0.65)
    local radiusZ = math.max(0.95, root.Size.Z * 0.7)
    local gold = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C(255, 246, 143)),
        ColorSequenceKeypoint.new(0.3, C(255, 224, 31)),
        ColorSequenceKeypoint.new(0.72, C(255, 175, 12)),
        ColorSequenceKeypoint.new(1, C(245, 133, 20)),
    })
    local alpha = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.065, 0.06),
        NumberSequenceKeypoint.new(0.4, 0.12), NumberSequenceKeypoint.new(0.78, 0.44),
        NumberSequenceKeypoint.new(1, 1),
    })
    local function emitterAt(position, gate, size, rate, index, spark, wake)
        local attachment = make("Attachment", {Name = "FlyDBZAuraAnchor", Position = position}, root)
        self.objects[#self.objects + 1] = attachment
        local particle = make("ParticleEmitter", {
            Name = wake and "FlyDBZWakeFlame" or (spark and "FlyDBZEmbers" or "FlyDBZFlame"), Enabled = false, Rate = 0,
            Texture = spark and "rbxasset://textures/particles/sparkles_main.dds" or FIRE_TEXTURE,
            Color = gold, LightEmission = spark and 1 or 0.58, LightInfluence = 0, Brightness = spark and 4 or 3,
            Transparency = alpha, LocalTransparencyModifier = 1,
            Lifetime = spark and NumberRange.new(0.3, 0.5) or (wake and NumberRange.new(0.28, 0.42) or NumberRange.new(0.4, 0.58)),
            Speed = spark and NumberRange.new(6, 9) or (wake and NumberRange.new(7, 10) or NumberRange.new(5.5, 7.5)),
            Acceleration = Vector3.new(0, 5, 0), Drag = 0.8,
            EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(9, 9),
            Orientation = Enum.ParticleOrientation.FacingCamera,
            Rotation = NumberRange.new(-8, 8), RotSpeed = NumberRange.new(-8, 8),
            LockedToPart = true, VelocityInheritance = 0, ZOffset = 0,
            Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, size * 0.45),
                NumberSequenceKeypoint.new(0.16, size, size * 0.12),
                NumberSequenceKeypoint.new(0.6, size * 0.6),
                NumberSequenceKeypoint.new(1, 0),
            }),
        }, attachment)
        self.emitters[#self.emitters + 1] = {object = particle, anchor = attachment, origin = position,
            gate = gate, rate = rate, phase = index * 1.79, wake = wake == true}
    end
    for i = 1, 8 do
        local angle = i * math.pi / 4
        emitterAt(Vector3.new(math.cos(angle) * radiusX, bottom, math.sin(angle) * radiusZ), 0, 1.95, 22, i, false)
    end
    for i = 1, 6 do
        local angle = i * math.pi / 3 + 0.3
        emitterAt(Vector3.new(math.cos(angle) * (radiusX + 0.5), bottom * 0.3, math.sin(angle) * (radiusZ + 0.35)),
            0.28, 1.85, 18, i + 8, false, true)
    end
    for i = 1, 4 do
        local angle = i * math.pi / 2 + 0.15
        emitterAt(Vector3.new(math.cos(angle) * radiusX, 1.2, math.sin(angle) * radiusZ), 0.6, 1.4, 14, i + 14, false)
        emitterAt(Vector3.new(math.cos(angle) * radiusX, bottom, math.sin(angle) * radiusZ), 0.1, 0.1, 5, i + 18, true)
    end
    local rimAlpha = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.08, 0.62),
        NumberSequenceKeypoint.new(0.45, 0.65), NumberSequenceKeypoint.new(0.82, 0.8),
        NumberSequenceKeypoint.new(1, 1),
    })
    local coreAlpha = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.32),
        NumberSequenceKeypoint.new(0.55, 0.4), NumberSequenceKeypoint.new(0.9, 0.7),
        NumberSequenceKeypoint.new(1, 1),
    })
    local coreColor = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C(255, 202, 30)),
        ColorSequenceKeypoint.new(0.55, C(255, 244, 143)),
        ColorSequenceKeypoint.new(1, C(255, 225, 60)),
    })
    for i = 1, 8 do
        local wake = i > 4
        local angle = i * math.pi / 2 + 0.09 * math.sin(i * 2.3)
        local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
        local origin = Vector3.new(radial.X * radiusX, bottom, radial.Z * radiusZ)
        local start = make("Attachment", {Name = "FlyDBZRibbonBase", Position = origin,
            Axis = (radial * 0.58 + Vector3.yAxis * 0.82).Unit}, root)
        local tip = make("Attachment", {Name = "FlyDBZRibbonTip", Position = origin,
            Axis = (-radial * 0.22 + Vector3.yAxis).Unit}, root)
        self.objects[#self.objects + 1] = start
        self.objects[#self.objects + 1] = tip
        local layers = {}
        for layer = 1, 2 do
            local core = layer == 2
            local ribbon = make("Beam", {
                Name = wake and (core and "FlyDBZTailFlame" or "FlyDBZTailEnvelope")
                    or (core and "FlyDBZHotFlame" or "FlyDBZHeatEnvelope"),
                Attachment0 = start, Attachment1 = tip, Enabled = false, FaceCamera = true,
                Segments = 16, Width0 = 0, Width1 = 0, CurveSize0 = 0, CurveSize1 = 0,
                Texture = core and FIRE_TEXTURE or SMOKE_TEXTURE,
                TextureMode = Enum.TextureMode.Wrap, TextureLength = 4.8 + i * 0.1,
                TextureSpeed = 1.8 + i * 0.075, LightEmission = core and 0.65 or 0.5,
                Brightness = core and 2.8 or 2.4, LightInfluence = 0,
                Color = core and coreColor or gold, Transparency = core and coreAlpha or rimAlpha,
                LocalTransparencyModifier = 1, ZOffset = 0,
            }, start)
            layers[#layers + 1] = {object = ribbon, width = core and 1.7 or 2.55}
        end
        self.ribbons[#self.ribbons + 1] = {start = start, tip = tip, origin = origin,
            angle = angle, radial = radial, wake = wake, radiusX = radiusX, radiusZ = radiusZ,
            phase = i * 1.73, gate = (i % 3) * 0.035,
            height = height * (0.84 + 0.16 * (0.5 + 0.5 * math.sin(i * 2.4))), layers = layers}
    end
    self.trailLeft = make("Attachment", {Name = "FlyDBZTrailLeft", Position = Vector3.new(-1.4, 0, 0)}, root)
    self.trailRight = make("Attachment", {Name = "FlyDBZTrailRight", Position = Vector3.new(1.4, 0, 0)}, root)
    self.objects[#self.objects + 1] = self.trailLeft
    self.objects[#self.objects + 1] = self.trailRight
    self.trail = make("Trail", {Name = "FlyDBZMeteorTrail", Attachment0 = self.trailLeft,
        Attachment1 = self.trailRight, Enabled = false, FaceCamera = true,
        Texture = FIRE_TEXTURE, TextureMode = Enum.TextureMode.Wrap, TextureLength = 2.7,
        Lifetime = 0.18, MaxLength = 8, MinLength = 0.16, LightEmission = 0.65,
        LightInfluence = 0, Brightness = 2.8, Color = gold, LocalTransparencyModifier = 1,
        WidthScale = NumberSequence.new({NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.35, 0.8), NumberSequenceKeypoint.new(1, 0)}),
        Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.52),
            NumberSequenceKeypoint.new(0.3, 0.65), NumberSequenceKeypoint.new(1, 1)}),
    }, self.trailLeft)
    local lampAnchor = make("Attachment", {Name = "FlyDBZLightAnchor"}, root)
    self.objects[#self.objects + 1] = lampAnchor
    self.lamp = make("PointLight", {Name = "FlyDBZLight", Color = C(255, 211, 85),
        Brightness = 0, Range = 11, Shadows = false, Enabled = false}, lampAnchor)
    return self
end
function Aura:Set(enabled)
    if enabled and not self.running then
        self.reveal, self.motion, self.alignment, self.axis, self.across = 0, 0, 0, Vector3.yAxis, Vector3.xAxis
        self.lastPosition = self.root.Position
        self.trail:Clear()
    end
    self.running = true
    self.targetOn = enabled
    self.burst = enabled
    if not enabled then self.trail.Enabled = false end
    tween(self.level, enabled and 0.9 or 0.6, {Value = enabled and 1 or 0}, Enum.EasingStyle.Sine)
end
function Aura:Update(dt, velocity)
    if not self.running then return end
    self.clock += dt
    local level = self.level.Value
    if self.targetOn then self.reveal = math.max(self.reveal, level) end
    if self.targetOn then
        -- Use the flight controller's smoothed world velocity, before the
        -- no-fall pulse. This prevents alternating zero-velocity VFX jitter.
        local direction, speed = unitAndSpeed(velocity or ZERO)
        local step = math.min(dt, 0.1)
        local strength = math.clamp((speed - 2.5) / 48, 0, 1)
        strength = strength * strength * (3 - 2 * strength)
        self.motion += (strength - self.motion) * (1 - math.exp(-7 * step))
        local aligned = 0
        if strength > 0 then
            local target = -direction
            local angle = math.acos(math.clamp(self.axis:Dot(target), -1, 1))
            local blend = math.min(1 - math.exp(-10 * step), 4.8 * step / math.max(angle, 0.001))
            self.axis = turnAxis(self.axis, target, blend)
            aligned = math.clamp((self.axis:Dot(target) + 0.1) / 1.1, 0, 1) ^ 2
        elseif self.motion < 0.005 then
            -- Reset only when the wake is invisible, not by swinging it up
            -- through the character when the joystick is released.
            self.axis, self.across, self.motion = Vector3.yAxis, Vector3.xAxis, 0
        end
        self.alignment += (aligned - self.alignment) * (1 - math.exp(-12 * step))
    end
    -- Transport the previous perpendicular instead of changing reference axes
    -- at a vertical threshold, which would visibly rotate the flame ring.
    local projected = self.across - self.axis * self.across:Dot(self.axis)
    if projected.Magnitude < 0.001 then self.across = flowBasis(self.axis)
    else self.across = projected.Unit end
    local axis = self.root.CFrame:VectorToObjectSpace(self.axis).Unit
    local across = self.root.CFrame:VectorToObjectSpace(self.across).Unit
    local around = axis:Cross(across).Unit
    local wakeVisibility = self.motion * self.alignment
    local coreAxis = (Vector3.yAxis + axis * (self.motion * 0.18)).Unit
    local coreAcross = (Vector3.xAxis - coreAxis * coreAxis.X).Unit
    for _, ribbon in ipairs(self.ribbons) do
        local amount = math.clamp((level - ribbon.gate) / (1 - ribbon.gate), 0, 1)
        if ribbon.wake then amount *= wakeVisibility end
        local growth = math.clamp((self.reveal - ribbon.gate) / (1 - ribbon.gate), 0, 1)
        local wave = math.sin(self.clock * 2.8 + ribbon.phase)
        local drift = math.sin(self.clock * 4.1 + ribbon.phase * 0.7) * 0.19
        local rise
        if ribbon.wake then
            local radial = across * math.cos(ribbon.angle) + around * math.sin(ribbon.angle)
            local origin = axis * 0.3 + radial * 1.2
            rise = math.max(0.03, (2.5 + self.motion * 3.3) * growth * (1 + 0.035 * wave))
            ribbon.start.Position = origin
            ribbon.start.Axis = (axis * 0.95 + radial * 0.25).Unit
            ribbon.tip.Position = origin + axis * rise - radial * (0.75 * growth)
                + axis:Cross(radial) * (drift * growth)
            ribbon.tip.Axis = (axis - radial * 0.16).Unit
        else
            rise = math.max(0.03, ribbon.height * growth * (1 + 0.035 * wave))
            ribbon.start.Position = ribbon.origin
            ribbon.start.Axis = (Vector3.yAxis + ribbon.radial * 0.3).Unit
            ribbon.tip.Position = ribbon.origin + Vector3.yAxis * rise
                - ribbon.radial * (0.45 * growth) + axis * (self.motion * 0.55 * growth)
                + Vector3.yAxis:Cross(ribbon.radial) * (drift * growth)
            ribbon.tip.Axis = (Vector3.yAxis - ribbon.radial * 0.12).Unit
        end
        for _, layer in ipairs(ribbon.layers) do
            local beam = layer.object
            beam.Enabled = amount > 0.005
            beam.LocalTransparencyModifier = 1 - amount
            beam.Width0 = layer.width * amount * (0.95 + 0.05 * wave)
            beam.Width1 = layer.width * 0.06 * amount
            beam.CurveSize0 = rise * (0.3 + 0.035 * wave)
            beam.CurveSize1 = rise * (0.19 + 0.03 * math.sin(self.clock * 2.1 + ribbon.phase))
        end
    end
    for _, item in ipairs(self.emitters) do
        local amount = math.clamp((level - item.gate) / (1 - item.gate), 0, 1)
        if item.wake then amount *= wakeVisibility end
        local pulse = 0.9 + 0.1 * math.sin(self.clock * 3.1 + item.phase)
        item.object.LocalTransparencyModifier = 1 - amount
        item.object.Rate = item.rate * amount * pulse
        item.object.Enabled = amount > 0.005
        if item.wake then
            local ring = across * math.cos(item.phase) + around * math.sin(item.phase)
            item.anchor.CFrame = CFrame.fromMatrix(axis * 0.45 + ring * 1.1, across, axis)
            item.object.Acceleration = self.axis * (5 + self.motion * 4)
        else
            -- Keep the emitting sites on the same body regions in every
            -- direction. A restrained lean adds flow without relocating them.
            item.anchor.CFrame = CFrame.fromMatrix(item.origin, coreAcross, coreAxis)
            item.object.Acceleration = self.root.CFrame:VectorToWorldSpace(coreAxis) * 5
        end
        if self.burst and level > 0.14 and item.gate == 0 then item.object:Emit(4) end
    end
    if level > 0.14 then self.burst = false end
    self.trailLeft.Position = -across * 1.1
    self.trailRight.Position = across * 1.1
    local position = self.root.Position
    local jumped = self.lastPosition and (position - self.lastPosition).Magnitude > 24
    self.lastPosition = position
    local trailActive = self.targetOn and wakeVisibility > 0.3 and level > 0.05 and not jumped
    if self.trailWasActive and (jumped or self.alignment < 0.35) then self.trail:Clear() end
    self.trail.Enabled = trailActive
    self.trail.LocalTransparencyModifier = 1 - level * wakeVisibility
    self.trailWasActive = trailActive
    self.lamp.Enabled = level > 0.005
    self.lamp.Brightness = level * (1.7 + 0.16 * math.sin(self.clock * 3.5))
    if level <= 0 and not self.burst then
        self.running = false
        self.reveal = 0
        self.trail:Clear()
        self.trailWasActive = false
        for _, item in ipairs(self.emitters) do item.object:Clear() end
    end
end
function Aura:Destroy()
    cancelTween(self.level)
    for _, object in ipairs(self.objects) do object:Destroy() end
    table.clear(self.emitters)
    table.clear(self.ribbons)
    table.clear(self.objects)
end

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
    return alive and body == b and b.root.Parent == currentCharacter
        and b.humanoid.Parent == currentCharacter and b.humanoid.Health > 0
end
local function stopTracks(b)
    b.mode = nil
    for _, trackObject in pairs(b.tracks) do trackObject:Stop(0.22) end
end
local function loadAnimations(b, animator)
    if b.animator == animator then return end
    for _, trackObject in pairs(b.tracks) do trackObject:Stop(0); trackObject:Destroy() end
    table.clear(b.tracks)
    b.animator = animator
    b.mode = nil
    b.animationGeneration += 1
    local generation = b.animationGeneration
    if b.humanoid.RigType ~= Enum.HumanoidRigType.R15 then
        gui:SetAttribute("AnimationStatus", "R15Required")
        warnOnce("rig", "The SSJ3 catalog pack requires R15. Flight and aura still work on R6.")
        return
    end
    gui:SetAttribute("AnimationStatus", "Loading")
    local function current()
        return validBody(b) and b.animationGeneration == generation and animator.Parent == b.humanoid
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
    local pending = pendingVelocity
    pendingVelocity = nil
    if pending and pending.root.Parent == pending.character
        and pending.root.AssemblyLinearVelocity == ZERO then
        pending.root.AssemblyLinearVelocity = pending.velocity
    end
end
local function stopFlight(b)
    restoreVelocity()
    if not b.flying then return end
    b.flying = false
    if b.velocity then b.velocity:Destroy(); b.velocity = nil end
    if b.orientation then b.orientation:Destroy(); b.orientation = nil end
    if b.flightAttachment then b.flightAttachment:Destroy(); b.flightAttachment = nil end
    if b.humanoid.Parent then
        if b.humanoid.AutoRotate == false then b.humanoid.AutoRotate = b.savedAutoRotate end
        if b.humanoid.PlatformStand == true then b.humanoid.PlatformStand = b.savedPlatformStand end
        if b.humanoid.Health > 0 and not b.savedPlatformStand then b.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end
    stopTracks(b)
    b.aura:Set(false)
end
local function startFlight(b)
    if b.flying or not validBody(b) or b.root.Anchored or b.humanoid.SeatPart then return end
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
    b.aura:Set(true)
end
local function releaseBody()
    local previous = body
    if not previous then return end
    disconnectAll(bodyConnections)
    stopFlight(previous)
    previous.animationGeneration += 1
    previous.aura:Destroy()
    for _, trackObject in pairs(previous.tracks) do trackObject:Stop(0); trackObject:Destroy() end
    table.clear(previous.tracks)
    body = nil
end
local function refreshBody()
    if not alive or not currentCharacter then return end
    local humanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
    local root = currentCharacter:FindFirstChild("HumanoidRootPart")
    if body and (body.humanoid ~= humanoid or body.root ~= root) then releaseBody() end
    if not humanoid or not root or not root:IsA("BasePart") then return end
    if body then return end
    local b = {humanoid = humanoid, root = root, flying = false, tracks = {}, animationGeneration = 0, smoothed = ZERO}
    body = b
    b.aura = Aura.new(root, humanoid)
    connect(bodyConnections, humanoid.Died, function() if body == b then stopFlight(b) end end)
    connect(bodyConnections, humanoid.ChildAdded, function(child)
        if child:IsA("Animator") and validBody(b) then loadAnimations(b, child) end
    end)
    connect(bodyConnections, humanoid.ChildRemoved, function(child)
        if child == b.animator then
            b.animationGeneration += 1
            stopTracks(b)
            for _, trackObject in pairs(b.tracks) do trackObject:Destroy() end
            table.clear(b.tracks)
            b.animator = nil
        end
    end)
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then loadAnimations(b, animator) end
    if wantedFlight then startFlight(b) end
end
local function bindCharacter(character)
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
    wantedFlight = not wantedFlight
    paintToggle(wantedFlight)
    if body then if wantedFlight then startFlight(body) else stopFlight(body) end end
end)
connect(connections, player.CharacterAdded, bindCharacter)
connect(connections, player.CharacterRemoving, function(character)
    if character == currentCharacter then bindCharacter(nil) end
end)

connect(connections, RunService.PreSimulation, function(dt)
    restoreVelocity()
    local b = body
    if not b or not validBody(b) then return end
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
local auraAccumulator = 0
connect(connections, RunService.Heartbeat, function(dt)
    local b = body
    -- VFX bookkeeping runs at 30 Hz; Roblox simulates the particles independently.
    auraAccumulator += dt
    if auraAccumulator >= 1 / 30 then
        if b then b.aura:Update(auraAccumulator, b.flying and b.smoothed or ZERO) end
        uiFire:Update(auraAccumulator)
        auraAccumulator = 0
    end
    if game.PlaceId ~= CONFIG.NoFallPlaceId or not b or not validBody(b) or b.root.Anchored then return end
    restoreVelocity()
    pendingVelocity = {root = b.root, character = currentCharacter, velocity = b.root.AssemblyLinearVelocity}
    b.root.AssemblyLinearVelocity = ZERO
end)
connect(connections, RunService.RenderStepped, restoreVelocity)

local function cleanup()
    if not alive then return end
    alive, wantedFlight = false, false
    restoreVelocity()
    disconnectAll(connections)
    disconnectAll(characterConnections)
    releaseBody()
    for _, animation in pairs(activeTweens) do animation:Cancel() end
    table.clear(activeTweens)
    controls, currentCharacter = nil, nil
end
connect(connections, gui.Destroying, cleanup)
connect(connections, close.Activated, function()
    if closing then return end
    closing = true
    -- Stop physics immediately; allow the aura and small GUI to fade before disposal.
    wantedFlight = false
    if body then stopFlight(body) end
    paintToggle(false)
    tween(window, 0.3, {GroupTransparency = 1})
    tween(windowScale, 0.3, {Scale = 0.96})
    if notice.Parent then tween(notice, 0.3, {GroupTransparency = 1}) end
    task.delay(0.65, function() if alive then gui:Destroy() end end)
end)
if player.Character then bindCharacter(player.Character) end
tween(window, 0.4, {GroupTransparency = 0})
tween(windowScale, 0.4, {Scale = 1})
