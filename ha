local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local lp        = Players.LocalPlayer
local character = lp.Character or lp.CharacterAdded:Wait()
local hrp       = character:WaitForChild("HumanoidRootPart")

-- ── Toggles ──────────────────────────────────────────────────────────────────
local ENABLED = {
    chests       = true,
    trickortreat = true,
    dungeon      = true,
}

-- ── Tuning ────────────────────────────────────────────────────────────────────
local WISP_TARGET       = 40
local CHEST_COOLDOWN    = 2
local TOT_COOLDOWN      = 30
local DUNGEON_CHECK_INT = 5
local TP_OFFSET         = Vector3.new(0, 3, 0)
local PROMPT_WAIT       = 0.6
local POST_FIRE_WAIT    = 1.5

-- ── Blacklisted ActionTexts – NEVER fire these ────────────────────────────────
local BLACKLISTED_ACTIONS = {
    ["skip contributions"] = true,
    ["skip"]               = true,
}

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function tpTo(pos)
    if hrp then
        hrp.CFrame = CFrame.new(pos + TP_OFFSET)
    end
end

local function safeFirePrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    local action = prompt.ActionText or ""
    if BLACKLISTED_ACTIONS[action:lower()] then
        return false  -- never fire blacklisted prompts
    end
    local ok, err = pcall(fireproximityprompt, prompt)
    return ok
end

-- ── Wisp count ────────────────────────────────────────────────────────────────
local WISP_VALUE_NAMES = {
    "WillOWisp","Wisps","WillOWisps","HalloweenCurrency",
    "EventCurrency","Wisp","WillOWispCount",
}
local function getWispCount()
    local ls = lp:FindFirstChild("leaderstats")
    if ls then
        for _, n in ipairs(WISP_VALUE_NAMES) do
            local v = ls:FindFirstChild(n)
            if v and v:IsA("ValueBase") then return v.Value end
        end
    end
    local pd = lp:FindFirstChild("PlayerData") or lp:FindFirstChild("Data")
    if pd then
        for _, n in ipairs(WISP_VALUE_NAMES) do
            local v = pd:FindFirstChild(n, true)
            if v and v:IsA("ValueBase") then return v.Value end
        end
    end
    for _, v in ipairs(lp:GetDescendants()) do
        if v:IsA("ValueBase") then
            local lower = v.Name:lower()
            if lower:find("wisp") or lower:find("will") then
                return v.Value
            end
        end
    end
    -- Billboard GUI fallback ("0/40" format)
    local ent = workspace:FindFirstChild("HalloweenDungeonEntrance")
    if ent then
        local bb = ent:FindFirstChildWhichIsA("BillboardGui", true)
        if bb then
            for _, lbl in ipairs(bb:GetDescendants()) do
                if lbl:IsA("TextLabel") or lbl:IsA("TextBox") then
                    local cur = tonumber(lbl.Text:match("^(%d+)/"))
                    if cur then return cur end
                end
            end
        end
    end
    return -1
end

-- ── Find dungeon entrance prompt ──────────────────────────────────────────────
-- Returns the prompt even if Enabled=false so we can attempt fire anyway
local function getDungeonEntrancePrompt()
    local part = workspace:FindFirstChild("HalloweenDungeonEntrance")
    if part then
        local pp = part:FindFirstChildWhichIsA("ProximityPrompt")
        if pp then return pp, part end
    end
    -- Fallback: scan for any PP with "wisp" or "submit" in ActionText
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            local at = obj.ActionText:lower()
            if at:find("wisp") or at:find("submit") or at:find("offer") or at:find("pumpkin") then
                if not BLACKLISTED_ACTIONS[at] then
                    return obj, obj.Parent
                end
            end
        end
    end
    return nil, nil
end

-- ── Check-in prompt ───────────────────────────────────────────────────────────
local function getCheckInPrompt()
    local part = workspace:FindFirstChild("HalloweenCheckIn")
    if part then
        local pp = part:FindFirstChildWhichIsA("ProximityPrompt")
        if pp then return pp, part end
    end
    -- Fallback: scan for "knock" or "trick" ActionText
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            local at = obj.ActionText:lower()
            if at:find("knock") or at:find("trick") or at:find("treat") then
                return obj, obj.Parent
            end
        end
    end
    return nil, nil
end

-- ── Find dungeon FIGHT / START prompt (post-submission) ───────────────────────
-- Scans entire workspace for prompts that start the actual boss fight.
-- Skips anything blacklisted. Called AFTER submitting wisps.
local BOSS_ACTION_KEYWORDS = {
    "enter","start","fight","battle","boss","dungeon","challenge","begin"
}
local function findBossStartPrompt()
    -- First try the known path
    local nf = workspace:FindFirstChild("NodeFold")
    if nf then
        local jb = nf:FindFirstChild("jumpboss")
        if jb then
            for _, pp in ipairs(jb:GetDescendants()) do
                if pp:IsA("ProximityPrompt") then
                    local at = pp.ActionText:lower()
                    if not BLACKLISTED_ACTIONS[at] then
                        -- Check if it has a boss-related action now
                        for _, kw in ipairs(BOSS_ACTION_KEYWORDS) do
                            if at:find(kw) then
                                return pp, pp.Parent
                            end
                        end
                    end
                end
            end
        end
    end
    -- Broad scan fallback
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local at = obj.ActionText:lower()
            if not BLACKLISTED_ACTIONS[at] then
                for _, kw in ipairs(BOSS_ACTION_KEYWORDS) do
                    if at:find(kw) then
                        return obj, obj.Parent
                    end
                end
            end
        end
    end
    return nil, nil
end

-- ── GUI ───────────────────────────────────────────────────────────────────────
local sg = Instance.new("ScreenGui")
sg.Name           = "HalloweenBot_v4"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = true
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent         = lp.PlayerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size                   = UDim2.new(0, 300, 0, 270)
mainFrame.Position               = UDim2.new(0, 10, 0.5, -135)
mainFrame.BackgroundColor3       = Color3.fromRGB(15, 10, 30)
mainFrame.BackgroundTransparency = 0.08
mainFrame.BorderSizePixel        = 0
mainFrame.Active                 = true
mainFrame.Draggable              = true
mainFrame.Parent                 = sg

local function addCorner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 10)
    c.Parent = p
end
addCorner(mainFrame)

local stroke = Instance.new("UIStroke")
stroke.Color     = Color3.fromRGB(220, 80, 0)
stroke.Thickness = 2
stroke.Parent    = mainFrame

local titleBar = Instance.new("Frame")
titleBar.Size             = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(200, 60, 0)
titleBar.BorderSizePixel  = 0
titleBar.Parent           = mainFrame
addCorner(titleBar)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size                   = UDim2.new(1, 0, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text                   = "🎃  Halloween Bot  v4"
titleLabel.TextColor3             = Color3.new(1,1,1)
titleLabel.Font                   = Enum.Font.GothamBold
titleLabel.TextSize               = 14
titleLabel.Parent                 = titleBar

local statusLabel = Instance.new("TextLabel")
statusLabel.Size                   = UDim2.new(1, -10, 0, 20)
statusLabel.Position               = UDim2.new(0, 5, 0, 40)
statusLabel.BackgroundTransparency = 1
statusLabel.Text                   = "Status: Initialising..."
statusLabel.TextColor3             = Color3.fromRGB(255, 200, 50)
statusLabel.Font                   = Enum.Font.Gotham
statusLabel.TextSize               = 12
statusLabel.TextXAlignment         = Enum.TextXAlignment.Left
statusLabel.Parent                 = mainFrame

local function makeToggle(label, key, yPos)
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(1, -20, 0, 36)
    btn.Position         = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3 = ENABLED[key] and Color3.fromRGB(30,120,30) or Color3.fromRGB(110,30,30)
    btn.BorderSizePixel  = 0
    btn.Font             = Enum.Font.Gotham
    btn.TextSize         = 12
    btn.TextColor3       = Color3.new(1,1,1)
    btn.Text             = (ENABLED[key] and "✅  " or "❌  ") .. label
    btn.Parent           = mainFrame
    addCorner(btn, 6)
    btn.MouseButton1Click:Connect(function()
        ENABLED[key] = not ENABLED[key]
        btn.BackgroundColor3 = ENABLED[key] and Color3.fromRGB(30,120,30) or Color3.fromRGB(110,30,30)
        btn.Text = (ENABLED[key] and "✅  " or "❌  ") .. label
    end)
end

makeToggle("Pumpkin Chest Collect",   "chests",       64)
makeToggle("Trick or Treat (Castle)", "trickortreat", 106)
makeToggle("Wisp Submit + Dungeon",   "dungeon",      148)

local wispLabel = Instance.new("TextLabel")
wispLabel.Size                   = UDim2.new(1, -10, 0, 18)
wispLabel.Position               = UDim2.new(0, 5, 0, 196)
wispLabel.BackgroundTransparency = 1
wispLabel.Text                   = "Will-o'-Wisps: reading..."
wispLabel.TextColor3             = Color3.fromRGB(180, 160, 255)
wispLabel.Font                   = Enum.Font.Gotham
wispLabel.TextSize               = 11
wispLabel.TextXAlignment         = Enum.TextXAlignment.Left
wispLabel.Parent                 = mainFrame

local debugLabel = Instance.new("TextLabel")
debugLabel.Size                   = UDim2.new(1, -10, 0, 36)
debugLabel.Position               = UDim2.new(0, 5, 0, 218)
debugLabel.BackgroundTransparency = 1
debugLabel.Text                   = ""
debugLabel.TextColor3             = Color3.fromRGB(120, 120, 120)
debugLabel.Font                   = Enum.Font.Gotham
debugLabel.TextSize               = 10
debugLabel.TextXAlignment         = Enum.TextXAlignment.Left
debugLabel.TextWrapped            = true
debugLabel.Parent                 = mainFrame

-- ── Loop: Chests ──────────────────────────────────────────────────────────────
local function chestLoop()
    while true do
        if ENABLED.chests then
            statusLabel.Text = "Status: Scanning chests..."
            local found = 0
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj.Name == "Treasure" then
                    local root = obj:FindFirstChild("RootPart")
                    local prompt = root and root:FindFirstChildWhichIsA("ProximityPrompt")
                    if root and prompt then
                        tpTo(root.Position)
                        task.wait(PROMPT_WAIT)
                        if safeFirePrompt(prompt) then
                            found += 1
                        end
                        task.wait(POST_FIRE_WAIT)
                    end
                end
            end
            statusLabel.Text = found > 0
                and ("Status: Collected " .. found .. " chest(s)")
                or  "Status: No chests found"
        end
        task.wait(CHEST_COOLDOWN)
    end
end

-- ── Loop: Trick or Treat ──────────────────────────────────────────────────────
local function trickortreatLoop()
    while true do
        if ENABLED.trickortreat then
            local prompt, part = getCheckInPrompt()
            if prompt then
                debugLabel.Text = "ToT prompt: " .. prompt.ActionText
                statusLabel.Text = "Status: Trick or treating..."
                tpTo(part.Position)
                task.wait(PROMPT_WAIT)
                if safeFirePrompt(prompt) then
                    statusLabel.Text = "Status: Knocked! (" .. TOT_COOLDOWN .. "s cooldown)"
                end
            else
                statusLabel.Text = "Status: Castle door not found"
                debugLabel.Text  = "ToT: no prompt found"
            end
        end
        task.wait(TOT_COOLDOWN)
    end
end

-- ── Loop: Wisp Submit + Dungeon Boss ─────────────────────────────────────────
local function dungeonLoop()
    while true do
        if ENABLED.dungeon then
            local wc = getWispCount()
            local wcStr = wc >= 0 and tostring(wc) or "?"
            wispLabel.Text = "Will-o'-Wisps: " .. wcStr
                          .. (wc >= 0 and (" / " .. WISP_TARGET) or "")

            -- Only attempt submission if we have enough wisps (or can't read count)
            local shouldAttempt = (wc < 0) or (wc >= WISP_TARGET)

            local submittedThisRound = false

            if shouldAttempt then
                local ep, epart = getDungeonEntrancePrompt()
                if ep and epart then
                    debugLabel.Text  = "Submitting to: " .. (ep.ActionText ~= "" and ep.ActionText or ep.Parent.Name)
                    statusLabel.Text = "Status: Submitting wisps..."
                    tpTo(epart.Position)
                    task.wait(PROMPT_WAIT)
                    -- Use pcall – fire even if Enabled=false (server may gate differently)
                    local ok = pcall(fireproximityprompt, ep)
                    if ok then
                        submittedThisRound = true
                        statusLabel.Text = "Status: Wisps submitted! Waiting for dungeon..."
                        task.wait(3.0)  -- give server time to open dungeon
                    else
                        statusLabel.Text = "Status: Fire failed (wisp prompt)"
                        debugLabel.Text  = "pcall failed on entrance PP"
                    end
                else
                    statusLabel.Text = "Status: Entrance prompt not found"
                    debugLabel.Text  = "getDungeonEntrancePrompt() = nil"
                end
            else
                local countStr = tostring(wc) .. "/" .. WISP_TARGET
                statusLabel.Text = "Status: Need more wisps (" .. countStr .. ")"
                debugLabel.Text  = "Waiting for 40 wisps before submitting"
            end

            -- After submission, scan for the boss/dungeon-start prompt
            if submittedThisRound then
                statusLabel.Text = "Status: Looking for dungeon start..."
                -- Give server up to 6 extra seconds to spawn the dungeon prompt
                local bp, bpart = nil, nil
                for attempt = 1, 4 do
                    bp, bpart = findBossStartPrompt()
                    if bp then break end
                    task.wait(1.5)
                end

                if bp and bpart then
                    debugLabel.Text  = "Boss prompt: " .. bp.ActionText .. " @ " .. bp.Parent.Name
                    statusLabel.Text = "Status: Starting dungeon!"
                    tpTo(bpart.Position)
                    task.wait(PROMPT_WAIT)
                    if safeFirePrompt(bp) then
                        statusLabel.Text = "Status: Dungeon started! ✅"
                    else
                        statusLabel.Text = "Status: Dungeon prompt fire failed"
                    end
                else
                    statusLabel.Text = "Status: Dungeon start prompt not found"
                    debugLabel.Text  = "No boss/enter prompt found after submission"
                end
            end
        end
        task.wait(DUNGEON_CHECK_INT)
    end
end

-- ── Respawn ───────────────────────────────────────────────────────────────────
lp.CharacterAdded:Connect(function(c)
    character = c
    hrp = c:WaitForChild("HumanoidRootPart")
end)

-- ── Start ─────────────────────────────────────────────────────────────────────
task.spawn(chestLoop)
task.spawn(trickortreatLoop)
task.spawn(dungeonLoop)

print("[HalloweenBot v4] ✅ All loops started.")
print("[HalloweenBot v4] 🔧 Blacklist: never fires 'Skip Contributions'")
print("[HalloweenBot v4] 🔧 Wisp submit: pcall-based, fires at 40+ wisps")
print("[HalloweenBot v4] 🔧 Boss: broad keyword scan after submission")
