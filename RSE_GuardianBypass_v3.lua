-- [[ RSE GuardianBypass v1 ]]
-- Game:    Ride & Steal Eggs  (PlaceId 15448459363)
-- Engine:  Roblox / Luau  |  macOS executor
--
-- Flow:
--   1. เปิด UI → เลือก biome (ตรวจว่าอยู่ใน zone ไหนอัตโนมัติ หรือเลือกเอง)
--   2. กด BYPASS → ระบบ clone decoy วิ่งล่อ guardian + anchor ตัวจริง
--   3. UI บอก "พร้อมขโมย" → กด STEAL → fire prompt บน egg
--   4. กด BYPASS ALL GUARDS → anchor ทุก guardian พร้อมกัน

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local RS         = game:GetService("ReplicatedStorage")

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local hrp  = char:WaitForChild("HumanoidRootPart")

-- ─── Guardian map ──────────────────────────────────────────────────────────────
-- ชื่อ guardian ใน-game, ชื่อสัตว์สำหรับแสดง UI, สีธีม
local BIOME_INFO = {
    { name="Desert",     guardian="DesertGuardian",     creature="Dune Demon Lion",       color=Color3.fromRGB(230,170,50),  emoji="🦁" },
    { name="Forest",     guardian="ForestGuardian",     creature="Forest Colossus",        color=Color3.fromRGB(80,200,80),   emoji="🌳" },
    { name="Lake",       guardian="LakeGuardian",       creature="River Demon Capybara",   color=Color3.fromRGB(80,180,255),  emoji="💧" },
    { name="Jungle",     guardian="JungleGuardian",     creature="Jungle Guardian",        color=Color3.fromRGB(40,160,60),   emoji="🌿" },
    { name="Sakura",     guardian="SakuraGuardian",     creature="Sakura Guardian",        color=Color3.fromRGB(255,160,200), emoji="🌸" },
    { name="Farm",       guardian="FarmGuardian",       creature="Farm Guardian",          color=Color3.fromRGB(200,220,80),  emoji="🌾" },
    { name="Lagoon",     guardian="LagoonGuardian",     creature="Lagoon Guardian",        color=Color3.fromRGB(60,220,200),  emoji="🐊" },
    { name="Volcano",    guardian="VolcanoGuardian",    creature="Inferno Warlord",        color=Color3.fromRGB(255,80,40),   emoji="🌋" },
    { name="Prehistoric",guardian="PrehistoricGuardian",creature="Prehistoric Guardian",   color=Color3.fromRGB(180,120,60),  emoji="🦕" },
    { name="Snow",       guardian="SnowGuardian",       creature="Ice Demon Yeti",         color=Color3.fromRGB(160,230,255), emoji="❄️" },
}

-- ─── State ─────────────────────────────────────────────────────────────────────
-- bypassActive[biomeName] = { parts, decoy, anchorConn, decoyMoveConn }
local bypassActive  = {}
local statusCbs     = {}
local noclipConn    = nil
local noclipOn      = false

-- ─── Helpers ───────────────────────────────────────────────────────────────────
local function getBiomes()
    return workspace:FindFirstChild("Map")
        and workspace.Map:FindFirstChild("Biomes")
end

local function getGuardian(biomeName, guardianName)
    local biomes = getBiomes()
    if not biomes then return nil end
    local biomeF = biomes:FindFirstChild(biomeName)
    if not biomeF then return nil end
    return biomeF:FindFirstChild(guardianName)
end

local function getPlayerBase()
    local bases = workspace:FindFirstChild("Map")
        and workspace.Map:FindFirstChild("Bases")
    if not bases then return nil end
    for _, b in ipairs(bases:GetChildren()) do
        if b:GetAttribute("OwnerId") == lp.UserId then return b end
    end
end

local function getBaseSpawnCF()
    local base = getPlayerBase()
    if base then
        local sp = base:FindFirstChild("Spawn")
        if sp and sp:IsA("BasePart") then return sp.CFrame + Vector3.new(0,5,0) end
    end
    return hrp.CFrame -- stay put ถ้าหาไม่เจอ
end

-- ตรวจว่าตอนนี้อยู่ใน biome ไหน (ใกล้ guardian ไหนที่สุด)
local function detectCurrentBiome()
    local biomes = getBiomes()
    if not biomes then return nil end
    local best, bestDist = nil, math.huge
    for _, info in ipairs(BIOME_INFO) do
        local biomeF = biomes:FindFirstChild(info.name)
        if biomeF then
            local g = biomeF:FindFirstChild(info.guardian)
            if g then
                local hrpG = g:FindFirstChild("HumanoidRootPart")
                if hrpG then
                    local d = (hrp.Position - hrpG.Position).Magnitude
                    if d < bestDist then bestDist = d; best = info end
                end
            end
            -- fallback: ใช้ nest ใดๆ ก็ได้
            local nestsF = biomeF:FindFirstChild("Nests")
            if nestsF then
                for _, nest in ipairs(nestsF:GetChildren()) do
                    local egg = nest:FindFirstChild("Egg")
                    if egg and egg:IsA("BasePart") then
                        local d = (hrp.Position - egg.Position).Magnitude
                        if d < bestDist then bestDist = d; best = info end
                        break
                    end
                end
            end
        end
    end
    if bestDist < 600 then return best end
    return nil
end

-- ─── Scan eggs in biome ────────────────────────────────────────────────────────
local function scanBiomeEggs(biomeName)
    local biomes = getBiomes()
    if not biomes then return {} end
    local biomeF = biomes:FindFirstChild(biomeName)
    if not biomeF then return {} end
    local nestsF = biomeF:FindFirstChild("Nests")
    if not nestsF then return {} end

    local results = {}
    local now = tick()
    for _, nest in ipairs(nestsF:GetChildren()) do
        local egg = nest:FindFirstChild("Egg")
        if egg and egg:IsA("BasePart") then
            local locked = egg:GetAttribute("LockedUntil")
            if (not locked) or (locked <= now) then
                local kg  = tonumber(egg:GetAttribute("Kg")) or 0
                local mut = egg:GetAttribute("Mutation") or "Normal"
                local aura= egg:GetAttribute("Aura")
                local en  = egg:GetAttribute("EggName") or nest.Name
                results[#results+1] = {
                    egg=egg, nest=nest,
                    eggName=en, kg=kg,
                    mutation=aura or mut,
                }
            end
        end
    end
    table.sort(results, function(a,b) return a.kg > b.kg end)
    return results
end

-- ─── Decoy system ──────────────────────────────────────────────────────────────
-- สร้าง Model ที่มี HumanoidRootPart + Humanoid เพื่อให้ guardian AI detect ว่าเป็น "target"
-- แล้ว loop ย้ายออกห่างจาก egg zone ทุก frame
local function spawnDecoy(guardianHRP)
    -- ทิศหนีออกจากตัวเราและ egg — ออกไปด้านหลัง guardian
    local awayDir = (guardianHRP.Position - hrp.Position).Unit
    local startPos = guardianHRP.Position + awayDir * 60
    startPos = Vector3.new(startPos.X, guardianHRP.Position.Y + 2, startPos.Z)

    -- Model ที่มี HumanoidRootPart + Humanoid — ให้ AI ของเกม detect เป็น character
    local mdl = Instance.new("Model")
    mdl.Name = "RSE_DecoyChar"

    local root = Instance.new("Part")
    root.Name        = "HumanoidRootPart"
    root.Size        = Vector3.new(2, 2, 1)
    root.Anchored    = true   -- เราควบคุม position เอง ไม่ให้ physics กวน
    root.CanCollide  = false
    root.Transparency = 1
    root.CFrame      = CFrame.new(startPos)
    root.Parent      = mdl

    local hum = Instance.new("Humanoid")
    hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    hum.Parent = mdl

    mdl.PrimaryPart = root
    mdl.Parent      = workspace

    -- Loop ย้าย decoy ออกไปเรื่อยๆ + zigzag เล็กน้อยเพื่อดึงความสนใจ AI
    -- หยุดอัตโนมัติถ้า model ถูก destroy
    local t = 0
    local moveConn = RunService.Heartbeat:Connect(function(dt)
        if not mdl.Parent then return end
        t = t + dt
        -- drift ออกไปทิศ awayDir ด้วย speed 8 studs/s + sine zigzag
        local side   = Vector3.new(-awayDir.Z, 0, awayDir.X)
        local offset = awayDir * (dt * 8) + side * (math.sin(t * 2) * dt * 4)
        local cur    = root.CFrame
        root.CFrame  = CFrame.new(cur.Position + offset)
    end)

    return mdl, moveConn
end

local function removeDecoy(decoy, moveConn)
    if moveConn then pcall(function() moveConn:Disconnect() end) end
    if decoy and decoy.Parent then
        pcall(function() decoy:Destroy() end)
    end
end

-- ─── Bypass ────────────────────────────────────────────────────────────────────
-- คืน { success, parts, decoy, anchorConn, decoyMoveConn }
local function bypassGuardian(info, onStatus)
    local function upd(msg) if onStatus then onStatus(msg) end end

    local guardian = getGuardian(info.name, info.guardian)
    if not guardian then
        upd("❌ ไม่เจอ " .. info.guardian)
        return false, {}, nil, nil, nil
    end

    local parts = {}
    for _, p in ipairs(guardian:GetDescendants()) do
        if p:IsA("BasePart") then parts[#parts+1] = p end
    end
    local hrpG = guardian:FindFirstChild("HumanoidRootPart")

    upd("🔍 เจอ " .. info.guardian .. " — " .. #parts .. " parts")
    task.wait(0.15)

    -- 1. spawn decoy ก่อน — ให้ AI มี target ใหม่ก่อน lock
    local decoy, decoyMoveConn = nil, nil
    if hrpG then
        decoy, decoyMoveConn = spawnDecoy(hrpG)
        upd("🪤 Decoy วิ่งล่อ guardian...")
        task.wait(0.4)
    end

    -- 2. disable AI scripts ทั้งหมดใน guardian (ตัด chase loop)
    upd("🔇 ปิด AI scripts...")
    for _, s in ipairs(guardian:GetDescendants()) do
        if s:IsA("Script") or s:IsA("LocalScript") then
            pcall(function() s.Disabled = true end)
        end
    end

    -- 3. freeze Humanoid (WalkSpeed=0, PlatformStand, MoveTo กับที่)
    local hum = guardian:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function()
            hum.WalkSpeed    = 0
            hum.JumpPower    = 0
            hum.PlatformStand = true
            if hrpG then hum:MoveTo(hrpG.Position) end
        end)
    end

    -- 4. anchor + zero velocity ทุก part
    upd("🧊 Anchor guardian...")
    for _, p in ipairs(parts) do
        pcall(function()
            p.Anchored                = true
            p.CanCollide              = false
            p.AssemblyLinearVelocity  = Vector3.zero
            p.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    -- 5. kill Animator (หยุด walk animation)
    for _, ac in ipairs(guardian:GetDescendants()) do
        if ac:IsA("Animator") then
            pcall(function() ac:Destroy() end)
        end
    end

    -- 6. Heartbeat loop re-zero velocity — ป้องกัน server override ทุก frame
    local anchorConn = RunService.Heartbeat:Connect(function()
        for _, p in ipairs(parts) do
            pcall(function()
                if p.Parent then
                    p.AssemblyLinearVelocity  = Vector3.zero
                    p.AssemblyAngularVelocity = Vector3.zero
                end
            end)
        end
        -- re-freeze humanoid ทุก frame ป้องกัน script server reset WalkSpeed
        if hum and hum.Parent then
            pcall(function()
                hum.WalkSpeed     = 0
                hum.PlatformStand = true
            end)
        end
    end)

    task.wait(0.2)
    upd("✅ Bypass สำเร็จ — " .. info.creature .. " ตัวแข็ง + decoy กำลังล่อ")

    return true, parts, decoy, anchorConn, decoyMoveConn
end

local function releaseGuardian(biomeName, parts, decoy, anchorConn, decoyMoveConn)
    -- disconnect loops ก่อน
    if anchorConn    then pcall(function() anchorConn:Disconnect()    end) end
    removeDecoy(decoy, decoyMoveConn)
    -- unanchor
    for _, p in ipairs(parts) do
        pcall(function()
            p.Anchored   = false
            p.CanCollide = false
        end)
    end
    bypassActive[biomeName] = nil
end

-- ─── Steal ─────────────────────────────────────────────────────────────────────
local function stealEgg(egg, onStatus)
    local function upd(msg) if onStatus then onStatus(msg) end end

    if not egg or not egg.Parent then
        upd("❌ Egg หายแล้ว")
        return false
    end

    local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
        or (egg.Parent and egg.Parent:FindFirstChildWhichIsA("ProximityPrompt", true))

    upd("🚀 เข้าหา egg...")
    hrp.CFrame = egg.CFrame + Vector3.new(0, 2.5, 0)
    task.wait(0.35)

    if not egg.Parent then upd("❌ Egg หายหลัง TP"); return false end

    if prompt then
        -- เก็บค่าเดิมของ game ไว้คืนทีหลัง
        local origHold = prompt.HoldDuration
        local origDist = prompt.MaxActivationDistance
        pcall(function()
            prompt.HoldDuration         = 0
            prompt.MaxActivationDistance = 32  -- ให้ใหญ่พอ แต่ไม่ทำลาย server check
        end)
        local fired = false
        for i = 1, 3 do
            upd(string.format("🔓 Fire (%d/3)...", i))
            pcall(fireproximityprompt, prompt)
            task.wait(0.3)
            if not egg.Parent then
                upd("✅ Egg stolen!"); fired = true; break
            end
        end
        -- คืนค่า proximity เป็นของตัวเกม
        pcall(function()
            prompt.HoldDuration         = origHold
            prompt.MaxActivationDistance = origDist
        end)
        if not fired then upd("⚠️ อาจจะ steal แล้ว — เช็คกระเป๋า") end
    else
        upd("⚠️ ไม่เจอ prompt บน egg นี้")
        return false
    end

    task.wait(0.4)
    return true
end

-- ─── NoClip ────────────────────────────────────────────────────────────────────
local function setNoclip(on)
    noclipOn = on
    if on and not noclipConn then
        noclipConn = RunService.Stepped:Connect(function()
            if not noclipOn then
                noclipConn:Disconnect(); noclipConn = nil; return
            end
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end)
    end
end

-- ════════════════════════════════════════════════════════════════
--  UI
-- ════════════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = "RSE_GuardianBypass_v1"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = (pcall(function() return gethui() end) and gethui()) or lp.PlayerGui

local C = {
    bg       = Color3.fromRGB(10, 8, 20),
    panel    = Color3.fromRGB(14, 11, 26),
    title    = Color3.fromRGB(20, 14, 40),
    accent   = Color3.fromRGB(130, 80, 230),
    dim      = Color3.fromRGB(65, 38, 120),
    text     = Color3.fromRGB(215, 200, 255),
    sub      = Color3.fromRGB(130, 115, 170),
    green    = Color3.fromRGB(110, 240, 130),
    gold     = Color3.fromRGB(255, 215, 60),
    red      = Color3.fromRGB(220, 70, 60),
    strip    = Color3.fromRGB(20, 15, 36),
    sep      = Color3.fromRGB(45, 35, 75),
    bypass   = Color3.fromRGB(190, 50, 240),
    bypassDim= Color3.fromRGB(90, 24, 120),
    steal    = Color3.fromRGB(50, 190, 110),
    stealDim = Color3.fromRGB(24, 90, 55),
}

-- main panel
local panel = Instance.new("Frame", gui)
panel.Name = "Main"
panel.Size = UDim2.new(0, 270, 0, 415)
panel.Position = UDim2.new(0.5, -135, 0.03, 0)
panel.BackgroundColor3 = C.panel
panel.BorderSizePixel = 0
panel.Active = true; panel.Draggable = true
Instance.new("UICorner", panel).CornerRadius = UDim.new(0,12)
do local s=Instance.new("UIStroke",panel); s.Color=C.accent; s.Thickness=1.5 end

-- title bar
local tBar = Instance.new("Frame", panel)
tBar.Size = UDim2.new(1,0,0,28); tBar.BackgroundColor3 = C.title; tBar.BorderSizePixel = 0
Instance.new("UICorner", tBar).CornerRadius = UDim.new(0,12)
do -- square bottom corners
    local fix = Instance.new("Frame", tBar)
    fix.Size = UDim2.new(1,0,0.5,0); fix.Position = UDim2.new(0,0,0.5,0)
    fix.BackgroundColor3 = C.title; fix.BorderSizePixel = 0
end
local tGrad = Instance.new("UIGradient", tBar)
tGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(32,18,62)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(16,10,36)),
}); tGrad.Rotation = 90

local tLbl = Instance.new("TextLabel", tBar)
tLbl.Size = UDim2.new(1,-44,1,0); tLbl.Position = UDim2.new(0,12,0,0)
tLbl.BackgroundTransparency = 1; tLbl.TextColor3 = C.text
tLbl.TextScaled = true; tLbl.Font = Enum.Font.GothamBold
tLbl.Text = "🛡️  RSE Guardian Bypass  v1"
tLbl.TextXAlignment = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", tBar)
closeBtn.Size = UDim2.new(0,20,0,20); closeBtn.Position = UDim2.new(1,-24,0.5,-10)
closeBtn.BackgroundColor3 = C.red; closeBtn.BorderSizePixel = 0
closeBtn.Text = "✕"; closeBtn.TextScaled = true; closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.new(1,1,1)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,6)

-- separator util
local function sep(yOff)
    local s = Instance.new("Frame", panel)
    s.Size = UDim2.new(1,-16,0,1); s.Position = UDim2.new(0,8,0,yOff)
    s.BackgroundColor3 = C.sep; s.BorderSizePixel = 0
end

-- status bar (global)
local statusBar = Instance.new("Frame", panel)
statusBar.Size = UDim2.new(1,-16,0,20); statusBar.Position = UDim2.new(0,8,0,32)
statusBar.BackgroundColor3 = C.strip; statusBar.BorderSizePixel = 0
Instance.new("UICorner", statusBar).CornerRadius = UDim.new(0,6)
local statusLbl = Instance.new("TextLabel", statusBar)
statusLbl.Size = UDim2.new(1,-8,1,0); statusLbl.Position = UDim2.new(0,4,0,0)
statusLbl.BackgroundTransparency = 1; statusLbl.TextColor3 = C.text
statusLbl.TextScaled = true; statusLbl.Font = Enum.Font.Gotham
statusLbl.Text = "กด Detect Zone หรือเลือก biome"; statusLbl.TextXAlignment = Enum.TextXAlignment.Left

local function setStatus(msg) statusLbl.Text = msg end

-- detect + bypass all row
sep(55)
local topRow = Instance.new("Frame", panel)
topRow.Size = UDim2.new(1,-16,0,24); topRow.Position = UDim2.new(0,8,0,58)
topRow.BackgroundTransparency = 1
do local l=Instance.new("UIListLayout",topRow)
   l.FillDirection=Enum.FillDirection.Horizontal; l.Padding=UDim.new(0,6) end

local function makeBtn(parent, w, txt, bg)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(0,w,1,0); b.BackgroundColor3 = bg; b.BorderSizePixel = 0
    b.TextScaled = true; b.Font = Enum.Font.GothamBold; b.TextColor3 = Color3.new(1,1,1)
    b.Text = txt; Instance.new("UICorner", b).CornerRadius = UDim.new(0,7)
    return b
end

local detectBtn  = makeBtn(topRow, 95, "📍 Detect Zone", C.dim)
local bypassAllBtn = makeBtn(topRow, 140, "⚡ Bypass All Guards", Color3.fromRGB(160,40,200))

-- noclip toggle
local noClipBtn = makeBtn(topRow, 0, "NoClip OFF", C.dim)
noClipBtn.Size = UDim2.new(1,-247,1,0)
noClipBtn.MouseButton1Click:Connect(function()
    noclipOn = not noclipOn
    setNoclip(noclipOn)
    noClipBtn.Text = noclipOn and "NoClip ON" or "NoClip OFF"
    noClipBtn.BackgroundColor3 = noclipOn and C.accent or C.dim
end)

sep(85)

-- zone info bar
local zoneBar = Instance.new("Frame", panel)
zoneBar.Size = UDim2.new(1,-16,0,20); zoneBar.Position = UDim2.new(0,8,0,88)
zoneBar.BackgroundColor3 = C.strip; zoneBar.BorderSizePixel = 0
Instance.new("UICorner", zoneBar).CornerRadius = UDim.new(0,6)
local zoneLbl = Instance.new("TextLabel", zoneBar)
zoneLbl.Size = UDim2.new(1,-8,1,0); zoneLbl.Position = UDim2.new(0,4,0,0)
zoneLbl.BackgroundTransparency = 1; zoneLbl.TextColor3 = C.gold
zoneLbl.TextScaled = true; zoneLbl.Font = Enum.Font.GothamSemibold
zoneLbl.Text = "Zone: ยังไม่ตรวจ"; zoneLbl.TextXAlignment = Enum.TextXAlignment.Left

-- egg list label
local eggListLbl = Instance.new("TextLabel", panel)
eggListLbl.Size = UDim2.new(1,-16,0,12); eggListLbl.Position = UDim2.new(0,8,0,111)
eggListLbl.BackgroundTransparency = 1; eggListLbl.TextColor3 = C.sub
eggListLbl.TextScaled = true; eggListLbl.Font = Enum.Font.GothamSemibold
eggListLbl.Text = "🥚 ไข่ใน zone (เรียงตาม kg)"; eggListLbl.TextXAlignment = Enum.TextXAlignment.Left

-- egg scroll list
local eggScroll = Instance.new("ScrollingFrame", panel)
eggScroll.Size = UDim2.new(1,-8,0,115); eggScroll.Position = UDim2.new(0,4,0,125)
eggScroll.BackgroundTransparency = 1; eggScroll.BorderSizePixel = 0
eggScroll.ScrollBarThickness = 3; eggScroll.ScrollBarImageColor3 = C.accent
eggScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
eggScroll.CanvasSize = UDim2.new(0,0,0,0)
local eggLayout = Instance.new("UIListLayout", eggScroll)
eggLayout.Padding = UDim.new(0,4)
local eggPad = Instance.new("UIPadding", eggScroll)
eggPad.PaddingLeft  = UDim.new(0,4); eggPad.PaddingRight  = UDim.new(0,4)
eggPad.PaddingTop   = UDim.new(0,4); eggPad.PaddingBottom = UDim.new(0,4)

sep(243)

-- bypass panel
local bpHeader = Instance.new("TextLabel", panel)
bpHeader.Size = UDim2.new(1,-16,0,12); bpHeader.Position = UDim2.new(0,8,0,247)
bpHeader.BackgroundTransparency = 1; bpHeader.TextColor3 = C.sub
bpHeader.TextScaled = true; bpHeader.Font = Enum.Font.GothamSemibold
bpHeader.Text = "🛡️ Guardian Bypass"; bpHeader.TextXAlignment = Enum.TextXAlignment.Left

-- guardian display card
local gCard = Instance.new("Frame", panel)
gCard.Size = UDim2.new(1,-16,0,50); gCard.Position = UDim2.new(0,8,0,262)
gCard.BackgroundColor3 = C.strip; gCard.BorderSizePixel = 0
Instance.new("UICorner", gCard).CornerRadius = UDim.new(0,10)
do local s=Instance.new("UIStroke",gCard); s.Color=C.sep; s.Thickness=1 end

local gNameLbl = Instance.new("TextLabel", gCard)
gNameLbl.Size = UDim2.new(0.6,0,0.55,0); gNameLbl.Position = UDim2.new(0,10,0,4)
gNameLbl.BackgroundTransparency = 1; gNameLbl.TextColor3 = C.text
gNameLbl.TextScaled = true; gNameLbl.Font = Enum.Font.GothamBold
gNameLbl.Text = "— เลือก biome —"; gNameLbl.TextXAlignment = Enum.TextXAlignment.Left

local gStatusLbl = Instance.new("TextLabel", gCard)
gStatusLbl.Size = UDim2.new(0.6,0,0.4,0); gStatusLbl.Position = UDim2.new(0,10,0.58,0)
gStatusLbl.BackgroundTransparency = 1; gStatusLbl.TextColor3 = C.sub
gStatusLbl.TextScaled = true; gStatusLbl.Font = Enum.Font.Gotham
gStatusLbl.Text = "รอ detect zone"; gStatusLbl.TextXAlignment = Enum.TextXAlignment.Left

local bypassBtn = Instance.new("TextButton", gCard)
bypassBtn.Size = UDim2.new(0,80,0,26); bypassBtn.Position = UDim2.new(1,-88,0.5,-13)
bypassBtn.BackgroundColor3 = C.bypass; bypassBtn.BorderSizePixel = 0
bypassBtn.TextScaled = true; bypassBtn.Font = Enum.Font.GothamBold
bypassBtn.TextColor3 = Color3.new(1,1,1); bypassBtn.Text = "BYPASS"
Instance.new("UICorner", bypassBtn).CornerRadius = UDim.new(0,8)

-- bypass status
local bpStatusBar = Instance.new("Frame", panel)
bpStatusBar.Size = UDim2.new(1,-16,0,20); bpStatusBar.Position = UDim2.new(0,8,0,315)
bpStatusBar.BackgroundColor3 = C.strip; bpStatusBar.BorderSizePixel = 0
Instance.new("UICorner", bpStatusBar).CornerRadius = UDim.new(0,6)
local bpStatusLbl = Instance.new("TextLabel", bpStatusBar)
bpStatusLbl.Size = UDim2.new(1,-8,1,0); bpStatusLbl.Position = UDim2.new(0,4,0,0)
bpStatusLbl.BackgroundTransparency = 1; bpStatusLbl.TextColor3 = C.green
bpStatusLbl.TextScaled = true; bpStatusLbl.Font = Enum.Font.Gotham
bpStatusLbl.Text = "รอ bypass..."; bpStatusLbl.TextXAlignment = Enum.TextXAlignment.Left

local function setBpStatus(msg) bpStatusLbl.Text = msg end

-- release button
sep(338)
local releaseBtn = Instance.new("TextButton", panel)
releaseBtn.Size = UDim2.new(1,-16,0,24); releaseBtn.Position = UDim2.new(0,8,0,342)
releaseBtn.BackgroundColor3 = Color3.fromRGB(60,50,100); releaseBtn.BorderSizePixel = 0
releaseBtn.TextScaled = true; releaseBtn.Font = Enum.Font.GothamSemibold
releaseBtn.TextColor3 = C.sub; releaseBtn.Text = "🔓 Release Guardian (Unfreeze)"
Instance.new("UICorner", releaseBtn).CornerRadius = UDim.new(0,8)

-- mini button
local miniBtn = Instance.new("TextButton", gui)
miniBtn.Size = UDim2.new(0,40,0,40); miniBtn.Position = UDim2.new(0,8,0.5,-20)
miniBtn.BackgroundColor3 = C.title; miniBtn.BorderSizePixel = 0
miniBtn.TextScaled = true; miniBtn.Font = Enum.Font.GothamBold
miniBtn.TextColor3 = C.text; miniBtn.Text = "🛡️"; miniBtn.Visible = false
Instance.new("UICorner", miniBtn).CornerRadius = UDim.new(0,10)
do local s=Instance.new("UIStroke",miniBtn); s.Color=C.accent; s.Thickness=1.2 end

-- ─── Egg row builder ───────────────────────────────────────────────────────────
local MUT_COLOR = {
    Normal  = Color3.fromRGB(200,200,215),
    Gold    = Color3.fromRGB(255,215,50),
    Diamond = Color3.fromRGB(80,220,255),
    Rainbow = Color3.fromRGB(255,100,255),
    Secret  = Color3.fromRGB(255,60,60),
}

local function clearEggList()
    for _, c in ipairs(eggScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
end

local selectedEgg = nil
local selectedRow = nil

local function buildEggRows(eggs)
    clearEggList()
    selectedEgg = nil; selectedRow = nil
    if #eggs == 0 then
        local empty = Instance.new("Frame", eggScroll)
        empty.Size = UDim2.new(1,0,0,30); empty.BackgroundTransparency = 1; empty.BorderSizePixel = 0
        local lbl = Instance.new("TextLabel", empty)
        lbl.Size = UDim2.fromScale(1,1); lbl.BackgroundTransparency = 1
        lbl.TextColor3 = C.sub; lbl.TextScaled = true; lbl.Font = Enum.Font.Gotham
        lbl.Text = "ไม่เจอไข่ใน zone นี้"
        return
    end
    for i, entry in ipairs(eggs) do
        local row = Instance.new("Frame", eggScroll)
        row.Name = "EggRow_"..i
        row.LayoutOrder = i
        row.Size = UDim2.new(1,0,0,32)
        row.BackgroundColor3 = Color3.fromRGB(18,14,32)
        row.BorderSizePixel = 0
        Instance.new("UICorner", row).CornerRadius = UDim.new(0,8)

        local stroke = Instance.new("UIStroke", row)
        stroke.Color = C.sep; stroke.Thickness = 1

        -- rank
        local rank = Instance.new("TextLabel", row)
        rank.Size = UDim2.new(0,20,1,0); rank.Position = UDim2.new(0,4,0,0)
        rank.BackgroundTransparency = 1; rank.TextColor3 = C.sub
        rank.TextScaled = true; rank.Font = Enum.Font.GothamBold
        rank.Text = tostring(i)

        -- info
        local info = Instance.new("TextLabel", row)
        info.Size = UDim2.new(1,-100,1,0); info.Position = UDim2.new(0,26,0,0)
        info.BackgroundTransparency = 1
        info.TextColor3 = MUT_COLOR[entry.mutation] or C.text
        info.TextScaled = true; info.Font = Enum.Font.Gotham
        info.TextXAlignment = Enum.TextXAlignment.Left
        local mutStr = entry.mutation ~= "Normal" and (" [" .. entry.mutation .. "]") or ""
        info.Text = string.format("🥚 %s — %.2f kg%s", entry.eggName, entry.kg, mutStr)

        -- steal btn
        local sb = Instance.new("TextButton", row)
        sb.Size = UDim2.new(0,62,0,24); sb.Position = UDim2.new(1,-66,0.5,-12)
        sb.BackgroundColor3 = C.stealDim; sb.BorderSizePixel = 0
        sb.TextScaled = true; sb.Font = Enum.Font.GothamBold
        sb.TextColor3 = Color3.fromRGB(140,240,160); sb.Text = "STEAL"
        Instance.new("UICorner", sb).CornerRadius = UDim.new(0,7)

        -- click row to select
        local entryRef = entry
        local function onSelect()
            if selectedRow then
                local selStroke = selectedRow:FindFirstChildOfClass("UIStroke")
                if selStroke then selStroke.Color = C.sep end
                selectedRow.BackgroundColor3 = Color3.fromRGB(18,14,32)
            end
            selectedEgg   = entryRef
            selectedRow   = row
            stroke.Color  = MUT_COLOR[entryRef.mutation] or C.accent
            row.BackgroundColor3 = Color3.fromRGB(24,18,44)
            setStatus("เลือก: " .. entryRef.eggName .. " — " .. entryRef.kg .. " kg")
        end

        row.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then onSelect() end
        end)

        sb.MouseButton1Click:Connect(function()
            onSelect()
            task.spawn(function()
                sb.Text = "..."; sb.BackgroundColor3 = C.dim
                local ok = stealEgg(entryRef.egg, setStatus)
                task.wait(0.8)
                sb.Text = "STEAL"; sb.BackgroundColor3 = C.stealDim
            end)
        end)
    end
end

-- ─── Current biome state ───────────────────────────────────────────────────────
local currentInfo  = nil
local bypassDone   = false
local bypassParts  = {}
local bypassDecoy  = nil

local function loadBiome(info)
    currentInfo = info
    bypassDone  = false
    -- update guardian card
    gNameLbl.Text   = info.emoji .. " " .. info.creature
    gNameLbl.TextColor3 = info.color
    gStatusLbl.Text = "Guardian: " .. info.guardian
    setBpStatus("กด BYPASS เพื่อ freeze guardian")
    bypassBtn.BackgroundColor3 = C.bypass
    bypassBtn.Text = "BYPASS"
    -- scan eggs
    local eggs = scanBiomeEggs(info.name)
    zoneLbl.Text = "Zone: " .. info.emoji .. " " .. info.name .. "  (" .. #eggs .. " eggs ready)"
    buildEggRows(eggs)
    setStatus("โหลด " .. info.name .. " — เจอ " .. #eggs .. " eggs")
end

-- biome selector (dropdown style - ใช้ scroll panel เล็กๆ)
local selectorOpen = false
local selectorPanel = nil

local function closeBiomeSelector()
    if selectorPanel then selectorPanel:Destroy(); selectorPanel = nil end
    selectorOpen = false
end

local biomeSelectBtn = makeBtn(topRow, 0, "🗺️ เลือก Biome ▼", C.dim)
-- จัดขนาดหลังจาก topRow มี children อื่นแล้ว — เราจะแก้ size โดยใช้ SizeConstraint
-- topRow มี: detectBtn(110) + bypassAllBtn(160) + noclipBtn(แดง) → เพิ่ม biomeSelectBtn ข้างหน้า
-- ปรับ: เอา noclip ออกจาก topRow ย้ายไป row ล่าง

-- ────────── reorg top row ──────────────────────────────────────────────────────
-- ล้าง children topRow แล้วสร้างใหม่
do
    for _, c in ipairs(topRow:GetChildren()) do
        if c:IsA("GuiObject") then c:Destroy() end
    end
end

-- row 1: detect + bypass all
local row1 = Instance.new("Frame", panel)
row1.Size = UDim2.new(1,-16,0,24); row1.Position = UDim2.new(0,8,0,58)
row1.BackgroundTransparency = 1
do local l=Instance.new("UIListLayout",row1)
   l.FillDirection=Enum.FillDirection.Horizontal; l.Padding=UDim.new(0,6) end

local r1Detect = makeBtn(row1, 0, "📍 Detect Zone", C.dim)
r1Detect.Size = UDim2.new(0,95,1,0)
local r1BypassAll = makeBtn(row1, 0, "⚡ Bypass All Guards", Color3.fromRGB(155,35,195))
r1BypassAll.Size = UDim2.new(1,-101,1,0)

-- row 2: biome selector + noclip
local row2 = Instance.new("Frame", panel)
row2.Size = UDim2.new(1,-16,0,22); row2.Position = UDim2.new(0,8,0,85)
row2.BackgroundTransparency = 1
do local l=Instance.new("UIListLayout",row2)
   l.FillDirection=Enum.FillDirection.Horizontal; l.Padding=UDim.new(0,6) end

local r2BiomeBtn = makeBtn(row2, 0, "🗺️ เลือก Biome ▼", C.dim)
r2BiomeBtn.Size = UDim2.new(0.65,-3,1,0)
local r2NoClip = makeBtn(row2, 0, "NoClip OFF", C.dim)
r2NoClip.Size = UDim2.new(0.35,-3,1,0)

r2NoClip.MouseButton1Click:Connect(function()
    noclipOn = not noclipOn
    setNoclip(noclipOn)
    r2NoClip.Text = noclipOn and "NoClip ON" or "NoClip OFF"
    r2NoClip.BackgroundColor3 = noclipOn and C.accent or C.dim
end)

-- reposition other elements down to make room for row2 (mobile layout)
sep(110)
zoneBar.Position    = UDim2.new(0,8,0,113)
eggListLbl.Position = UDim2.new(0,8,0,136)
eggScroll.Position  = UDim2.new(0,4,0,150)
eggScroll.Size      = UDim2.new(1,-8,0,105)
sep(258)
bpHeader.Position   = UDim2.new(0,8,0,262)
gCard.Position      = UDim2.new(0,8,0,276)
bpStatusBar.Position= UDim2.new(0,8,0,329)
releaseBtn.Position = UDim2.new(0,8,0,352)

-- remove old topRow
topRow:Destroy()
detectBtn = r1Detect
bypassAllBtn = r1BypassAll

-- ─── Biome selector dropdown ───────────────────────────────────────────────────
r2BiomeBtn.MouseButton1Click:Connect(function()
    if selectorOpen then closeBiomeSelector(); return end
    selectorOpen = true

    selectorPanel = Instance.new("Frame", gui)
    selectorPanel.Size = UDim2.new(0,200,0,#BIOME_INFO*30+8)
    -- position below r2BiomeBtn
    local absPos = r2BiomeBtn.AbsolutePosition
    local absSize = r2BiomeBtn.AbsoluteSize
    selectorPanel.Position = UDim2.new(0, absPos.X, 0, absPos.Y + absSize.Y + 4)
    selectorPanel.BackgroundColor3 = Color3.fromRGB(18,14,34)
    selectorPanel.BorderSizePixel = 0
    selectorPanel.ZIndex = 20
    Instance.new("UICorner", selectorPanel).CornerRadius = UDim.new(0,10)
    do local s=Instance.new("UIStroke",selectorPanel); s.Color=C.accent; s.Thickness=1 end

    local ll = Instance.new("UIListLayout", selectorPanel)
    ll.Padding = UDim.new(0,2)
    local pp = Instance.new("UIPadding", selectorPanel)
    pp.PaddingLeft = UDim.new(0,4); pp.PaddingRight = UDim.new(0,4)
    pp.PaddingTop  = UDim.new(0,4); pp.PaddingBottom = UDim.new(0,4)

    for _, info in ipairs(BIOME_INFO) do
        local row = Instance.new("TextButton", selectorPanel)
        row.Size = UDim2.new(1,0,0,26); row.BackgroundColor3 = Color3.fromRGB(22,17,40)
        row.BorderSizePixel = 0; row.ZIndex = 21
        row.TextScaled = true; row.Font = Enum.Font.GothamSemibold
        row.TextColor3 = info.color; row.TextXAlignment = Enum.TextXAlignment.Left
        row.Text = "  " .. info.emoji .. " " .. info.name
        Instance.new("UICorner", row).CornerRadius = UDim.new(0,6)
        local infoRef = info
        row.MouseButton1Click:Connect(function()
            closeBiomeSelector()
            r2BiomeBtn.Text = "🗺️ " .. infoRef.emoji .. " " .. infoRef.name .. " ▼"
            loadBiome(infoRef)
        end)
    end
end)

-- ─── Detect Zone ───────────────────────────────────────────────────────────────
detectBtn.MouseButton1Click:Connect(function()
    setStatus("🔍 กำลัง detect zone...")
    task.spawn(function()
        task.wait(0.1)
        local found = detectCurrentBiome()
        if found then
            r2BiomeBtn.Text = "🗺️ " .. found.emoji .. " " .. found.name .. " ▼"
            loadBiome(found)
        else
            setStatus("⚠️ อยู่นอก zone — ลอง เดินเข้า biome แล้วกดใหม่")
        end
    end)
end)

-- ─── Bypass button ─────────────────────────────────────────────────────────────
bypassBtn.MouseButton1Click:Connect(function()
    if not currentInfo then
        setBpStatus("❌ ยังไม่ได้เลือก biome")
        return
    end
    if bypassActive[currentInfo.name] then
        setBpStatus("⚠️ bypass นี้ active อยู่แล้ว — กด Release ก่อน")
        return
    end

    bypassBtn.BackgroundColor3 = C.bypassDim; bypassBtn.Text = "..."
    task.spawn(function()
        local ok, parts, decoy, anchorConn, decoyMoveConn = bypassGuardian(currentInfo, setBpStatus)
        if ok then
            bypassActive[currentInfo.name] = { parts=parts, decoy=decoy, anchorConn=anchorConn, decoyMoveConn=decoyMoveConn }
            bypassParts = parts; bypassDecoy = decoy
            bypassDone = true
            bypassBtn.Text = "✅ FROZEN"
            bypassBtn.BackgroundColor3 = Color3.fromRGB(60,160,80)
            setBpStatus("✅ " .. currentInfo.creature .. " ตัวแข็ง — พร้อมขโมย")
            setStatus("✅ Bypass สำเร็จ — กด STEAL บน egg ที่ต้องการ")
        else
            bypassBtn.Text = "BYPASS"; bypassBtn.BackgroundColor3 = C.bypass
        end
    end)
end)

-- ─── Bypass ALL guards ─────────────────────────────────────────────────────────
bypassAllBtn.MouseButton1Click:Connect(function()
    bypassAllBtn.BackgroundColor3 = C.dim; bypassAllBtn.Text = "⏳ Bypassing..."
    task.spawn(function()
        local count = 0
        for _, info in ipairs(BIOME_INFO) do
            if not bypassActive[info.name] then
                local ok, parts, decoy, anchorConn, decoyMoveConn = bypassGuardian(info, setStatus)
                if ok then
                    bypassActive[info.name] = { parts=parts, decoy=decoy, anchorConn=anchorConn, decoyMoveConn=decoyMoveConn }
                    count = count + 1
                end
                task.wait(0.1)
            end
        end
        bypassAllBtn.Text = string.format("✅ Frozen %d guards", count)
        bypassAllBtn.BackgroundColor3 = Color3.fromRGB(60,150,80)
        setStatus(string.format("✅ Bypass สำเร็จ %d guardian — พร้อมขโมยทุก zone", count))
        task.wait(3)
        bypassAllBtn.Text = "⚡ Bypass All Guards"
        bypassAllBtn.BackgroundColor3 = Color3.fromRGB(155,35,195)
    end)
end)

-- ─── Release button ────────────────────────────────────────────────────────────
releaseBtn.MouseButton1Click:Connect(function()
    if not currentInfo then return end
    local state = bypassActive[currentInfo.name]
    if state then
        releaseGuardian(currentInfo.name, state.parts, state.decoy, state.anchorConn, state.decoyMoveConn)
        bypassDone = false; bypassParts = {}; bypassDecoy = nil
        bypassBtn.Text = "BYPASS"; bypassBtn.BackgroundColor3 = C.bypass
        setBpStatus("🔓 Guardian released")
        setStatus("🔓 " .. currentInfo.creature .. " unfrozen")
    else
        setBpStatus("ไม่มี active bypass ใน " .. (currentInfo and currentInfo.name or "?"))
    end
end)

-- ─── Close / mini ──────────────────────────────────────────────────────────────
closeBtn.MouseButton1Click:Connect(function()
    -- release all
    for name, state in pairs(bypassActive) do
        releaseGuardian(name, state.parts, state.decoy, state.anchorConn, state.decoyMoveConn)
    end
    TweenService:Create(panel, TweenInfo.new(0.18), {Size=UDim2.new(0,270,0,0)}):Play()
    task.wait(0.22); gui:Destroy()
end)

miniBtn.MouseButton1Click:Connect(function() panel.Visible=true; miniBtn.Visible=false end)
tBar.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton2 then
        panel.Visible=false; miniBtn.Visible=true
        closeBiomeSelector()
    end
end)

-- click anywhere else = close dropdown
gui.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 and selectorOpen then
        -- delay ให้ button click ทำงานก่อน
        task.wait(0.05)
        closeBiomeSelector()
    end
end)

-- char respawn
lp.CharacterAdded:Connect(function(c)
    char = c; hrp = c:WaitForChild("HumanoidRootPart")
    noclipOn = false
    r2NoClip.Text = "NoClip OFF"; r2NoClip.BackgroundColor3 = C.dim
end)

-- auto detect on boot
task.delay(2, function()
    local found = detectCurrentBiome()
    if found then
        r2BiomeBtn.Text = "🗺️ " .. found.emoji .. " " .. found.name .. " ▼"
        loadBiome(found)
    end
end)

-- ready 🛡️
