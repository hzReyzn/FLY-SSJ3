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
