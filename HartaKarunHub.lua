-- Harta Karun Hub | single-file loader
-- Cara pakai di executor: loadstring(game:HttpGet("https://raw.githubusercontent.com/haytinahyzina-bot/HartaKarunHub/main/HartaKarunHub.lua"))()

-- Harta Karun Dungeon | Master loops (farm hover, combat, esp, movement)
-- Dieksekusi sekali. Semua fitur dikendalikan lewat tabel _G.HK (lihat UI-Obsidian.lua).
-- Tested di: Harta Karun Dungeon [UPDATE 1.5], PlaceId 106484206883664.

_G.HK = _G.HK or {
    hover = true,   -- hover tidur di atas kepala mob terdekat
    height = 6.5,   -- jarak vertikal di atas mob (4 - 12)
    chest = true,   -- auto loot chest bertipe "loot" dalam 20 stud

    atk = true,     -- spam basic attack
    skill = false,  -- spam skill
    rate = 0.25,    -- jeda antar attack (detik)

    esp = true,     -- ESP nama + HP mob
    loot = true,    -- auto loot (dipakai bareng chest)

    speed = 32,     -- walkspeed target (dipaksa tiap frame)
    noclip = false,
    infjump = true,
    fly = false,
    flyspeed = 60,

    tick = 0,       -- counter bukti loop hidup
    target = "none",-- target hover saat ini
    stealth = true, -- serang tanpa animasi ayunan
}

-- ID animasi ayunan basic attack (Ronin/Animations + OriginalAttacks).
-- Track yang cocok di-stop tiap frame render -> damage tetap masuk (server-side).
_G.HKSwingIds = {
    ["106806110702885"] = true, ["109893308802725"] = true,
    ["126671356379936"] = true, ["112357005052418"] = true,
    ["105520255900501"] = true, ["113090603838738"] = true,
    ["82343948148104"] = true,
}

local P = game.Players.LocalPlayer
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Inputs = game.ReplicatedStorage.Player.Remotes.Inputs

local function getGen()
    for _, c in ipairs(workspace:GetChildren()) do
        if string.find(c.Name, "Generated") then
            return c
        end
    end
    return nil
end

-- Daftar pengecualian hover (nama model). Contoh: Galran si NPC lobby.
-- NPC quest (folder Dialogue_NPCS), dummy latihan, dan karakter pemain
-- selalu di-skip otomatis.
_G.HKBlock = _G.HKBlock or { "Galran", "BananitaDolphinita", "Forge Archon", "Awakened Devil", "Rig" }
-- Cache target PER ZONA: habiskan semua mob di 1 room dulu baru pindah.
-- Tiap 0.5 detik: petakan mob hidup ke Room_%d+ terdekat (jarak XZ dari
-- pivot room). Selama room aktif masih ada mob, target = mob terdekat DI
-- ROOM ITU. Room bersih -> pindah ke room milik mob terdekat global.
-- Aturan hidup (TANPA filter nama/jenis):
--   Humanoid.Health > 0 ATAU
--   (CanAttack == true dan State ~= "Dead") ATAU
--   (punya attribute HealthOverride dan State ~= "Dead").
-- Satu-satunya yang di-skip: karakter pemain (sendiri + pemain lain).
_G.HKTarget = nil
_G.HKZone = { room = nil }
task.spawn(function()
    while true do
        pcall(function()
            local hrp = P.Character and P.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local gen = getGen()
                if gen then
                    local rooms = {}
                    for _, c in ipairs(gen:GetChildren()) do
                        local n = string.match(c.Name, "^Room_(%d+)$")
                        if n and c:IsA("Model") then
                            local ok, piv = pcall(function() return c:GetPivot() end)
                            if ok then rooms[tonumber(n)] = piv.Position end
                        end
                    end
                    local byRoom = {}
                    local best, bestRoom, bd = nil, nil, 1e9
                    local chars = {}
                    for _, pl in ipairs(game.Players:GetPlayers()) do
                        if pl.Character then chars[pl.Character] = true end
                    end
                    local function mobAlive(m)
                        for _, n in ipairs(_G.HKBlock) do
                            if m.Name == n then return false end
                        end
                        local fn = m:GetFullName()
                        if string.find(fn, "Dialogue_NPCS")
                            or string.find(fn, "Combat_Dummies")
                            or string.find(fn, "PlayerModels") then
                            return false
                        end
                        local hum = m:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then return true end
                        local st = m:GetAttribute("State")
                        if m:GetAttribute("CanAttack") == true and st ~= "Dead" then
                            return true
                        end
                        if m:GetAttribute("HealthOverride") ~= nil and st ~= "Dead" then
                            return true
                        end
                        return false
                    end
                    for _, d in ipairs(workspace:GetDescendants()) do
                        if d:IsA("Model") and d ~= P.Character and not chars[d]
                            and string.find(d:GetFullName(), "Generated") then
                            if mobAlive(d) then
                                local th = d:FindFirstChild("HumanoidRootPart")
                                    or d:FindFirstChild("Torso")
                                if th then
                                    local dist = (th.Position - hrp.Position).Magnitude
                                    if dist < 600 then
                                        local rn, rd = 0, 1e9
                                        for n, pos in pairs(rooms) do
                                            local dxz = Vector2.new(
                                                th.Position.X - pos.X,
                                                th.Position.Z - pos.Z).Magnitude
                                            if dxz < rd then rn, rd = n, dxz end
                                        end
                                        byRoom[rn] = byRoom[rn] or {}
                                        table.insert(byRoom[rn], { m = d, d = dist })
                                        if dist < bd then best, bestRoom, bd = d, rn, dist end
                                    end
                                end
                            end
                        end
                    end
                    local cur = _G.HKZone.room
                    local tgt = nil
                    if cur and byRoom[cur] and #byRoom[cur] > 0 then
                        table.sort(byRoom[cur], function(a, b) return a.d < b.d end)
                        tgt = byRoom[cur][1]
                    elseif best then
                        _G.HKZone.room = bestRoom
                        tgt = { m = best, d = bd }
                    else
                        _G.HKZone.room = nil
                    end
                    _G.HKTarget = tgt and tgt.m or nil
                    if tgt then
                        _G.HK.target = "R" .. tostring(_G.HKZone.room) .. " "
                            .. tgt.m.Name .. " " .. tostring(math.floor(tgt.d)) .. "st"
                    else
                        _G.HK.target = "no mob"
                    end
                end
            end
        end)
        task.wait(0.5)
    end
end)

-- Loop utama: hover + speed lock + fly + noclip + auto chest
RS.Heartbeat:Connect(function()
    _G.HK.tick += 1
    local ch = P.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then
        _G.HK.target = "dead/none"
        return
    end

    if _G.HK.noclip then
        for _, v in ipairs(ch:GetDescendants()) do
            if v:IsA("BasePart") and v.CanCollide then
                v.CanCollide = false
            end
        end
    end

    if hum.WalkSpeed ~= _G.HK.speed then
        hum.WalkSpeed = _G.HK.speed
    end

    if _G.HK.fly then
        local cf = hrp.CFrame
        local mv = Vector3.new()
        if UIS:IsKeyDown(Enum.KeyCode.W) then mv += workspace.CurrentCamera.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then mv -= workspace.CurrentCamera.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then mv -= workspace.CurrentCamera.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then mv += workspace.CurrentCamera.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then mv += Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then mv -= Vector3.new(0, 1, 0) end
        if mv.Magnitude > 0 then
            hrp.CFrame = cf + mv.Unit * (_G.HK.flyspeed * 0.05)
            hrp.Velocity = Vector3.new()
        end
    end

    local mob = _G.HKTarget
    local dist = 0
    if mob and mob.Parent then
        local okMob = false
        local mhum = mob:FindFirstChildOfClass("Humanoid")
        if mhum and mhum.Health > 0 then okMob = true end
        local mst = mob:GetAttribute("State")
        if mob:GetAttribute("CanAttack") == true and mst ~= "Dead" then
            okMob = true
        end
        if mob:GetAttribute("HealthOverride") ~= nil and mst ~= "Dead" then
            okMob = true
        end
        if okMob then
            local th0 = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Torso")
            if th0 then dist = (th0.Position - hrp.Position).Magnitude end
        else
            mob = nil
        end
    else
        mob = nil
    end
    if _G.HK.hover and mob then
        -- Tidur di atas kepala, menghadap ke bawah (CFrame melihat ke mob).
        -- Basic attack tetap kena, melee mob tidak sampai.
        -- Batas 600 stud: di luar itu (beda map) tidak dikejar.
        local th = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Torso")
        if th and (th.Position - hrp.Position).Magnitude <= 600 then
            hum.AutoRotate = false
            -- Tinggi dijepit maks 30.
            local h = _G.HK.height
            if h > 30 then h = 30 end
            if h < 4 then h = 4 end
            hrp.CFrame = CFrame.new(th.Position + Vector3.new(0, h, 0), th.Position)
            hrp.Velocity = Vector3.new()
            hrp.RotVelocity = Vector3.new()
            _G.HK.target = mob.Name .. " " .. tostring(math.floor(dist)) .. "st"
        end
    else
        -- Tidak ada target: JANGAN kunci posisi, biar bebas gerak manual.
        hum.AutoRotate = true
        if mob then
            _G.HK.target = mob.Name .. " (hover off)"
        else
            _G.HK.target = "no mob"
        end
    end
end)

-- Pemburu chest: kalau tidak ada target mob, teleport ke chest "loot" yang
-- masih enabled, tembak prompt-nya, lanjut. Begitu ada mob, hover farm
-- langsung ambil alih lagi.
task.spawn(function()
    while true do
        if _G.HK.chest and _G.HKTarget == nil then
            pcall(function()
                local hrp = P.Character and P.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local best, bd, bpr = nil, 1e9, nil
                    for _, d in ipairs(workspace:GetDescendants()) do
                        if d:IsA("ProximityPrompt") and d.Enabled
                            and string.find(string.lower(d.ActionText), "loot")
                            and string.find(d:GetFullName(), "Generated") then
                            local m = d.Parent
                            while m and not m:IsA("Model") do m = m.Parent end
                            if m then
                                local ok, piv = pcall(function() return m:GetPivot() end)
                                if ok then
                                    local dist = (piv.Position - hrp.Position).Magnitude
                                    if dist < bd then best, bd, bpr = m, dist, d end
                                end
                            end
                        end
                    end
                    if best and bpr then
                        local piv = best:GetPivot()
                        hrp.CFrame = CFrame.new(piv.X, piv.Y + 4, piv.Z + 2)
                        hrp.Velocity = Vector3.new()
                        task.wait(0.6)
                        pcall(function() fireproximityprompt(bpr) end)
                    end
                end
            end)
        end
        task.wait(2)
    end
end)

-- Spam attack
task.spawn(function()
    while true do
        if _G.HK.atk then
            pcall(function() Inputs.Attack:FireServer() end)
        end
        task.wait(_G.HK.rate)
    end
end)

-- Spam skill
task.spawn(function()
    while true do
        if _G.HK.skill then
            pcall(function() Inputs.Skill:FireServer() end)
        end
        task.wait(1.2)
    end
end)

-- Infinite jump
UIS.JumpRequest:Connect(function()
    if _G.HK.infjump and P.Character then
        local hum = P.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- ESP nama + HP
task.spawn(function()
    while true do
        if _G.HK.esp then
            pcall(function()
                for _, d in ipairs(workspace:GetDescendants()) do
                    if d:IsA("Model") and d ~= P.Character
                        and not d:FindFirstChild("HK_ESP") then
                        local skip = false
                        for _, pl in ipairs(game.Players:GetPlayers()) do
                            if pl.Character == d then skip = true break end
                        end
                        local label, color = nil, Color3.new(1, 0.35, 0.35)
                        if not skip then
                            local hum = d:FindFirstChildOfClass("Humanoid")
                            if hum and hum.Health > 0 then
                                label = d.Name .. " " .. tostring(math.floor(hum.Health))
                            else
                                local st = d:GetAttribute("State")
                                if (d:GetAttribute("CanAttack") == true
                                    or d:GetAttribute("HealthOverride") ~= nil)
                                    and st ~= "Dead" then
                                    label = d.Name .. " Lv" .. tostring(d:GetAttribute("Level"))
                                        .. " " .. tostring(st)
                                    color = Color3.new(1, 0.6, 0.2)
                                end
                            end
                        end
                        if label then
                            local ador = d:FindFirstChild("HumanoidRootPart")
                                or d:FindFirstChild("Torso")
                            if ador then
                                local bb = Instance.new("BillboardGui")
                                bb.Name = "HK_ESP"
                                bb.Size = UDim2.new(0, 150, 0, 32)
                                bb.StudsOffset = Vector3.new(0, 3, 0)
                                bb.AlwaysOnTop = true
                                bb.Adornee = ador
                                bb.Parent = d
                                local tl = Instance.new("TextLabel")
                                tl.Size = UDim2.new(1, 0, 1, 0)
                                tl.BackgroundTransparency = 1
                                tl.TextColor3 = color
                                tl.TextStrokeTransparency = 0
                                tl.TextSize = 13
                                tl.Font = Enum.Font.Code
                                tl.Text = label
                                tl.Parent = bb
                            end
                        end
                    end
                end
            end)
        end
        task.wait(3)
    end
end)

-- Stealth: potong animasi ayunan secepatnya (pre-render). Damage tidak
-- terpengaruh karena hitungannya di server.
RS.RenderStepped:Connect(function()
    if not (_G.HK and _G.HK.stealth) then return end
    local ch = P.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local anim = hum and hum:FindFirstChildOfClass("Animator")
    if not anim then return end
    for _, tr in ipairs(anim:GetPlayingAnimationTracks()) do
        local id = tr.Animation and tr.Animation.AnimationId or ""
        local num = string.match(id, "(%d+)")
        if num and _G.HKSwingIds[num] then
            pcall(function() tr:Stop(0) end)
        end
    end
end)

-- Interceptor skill: bungkus Activate tiap skill Ronin supaya argumen ASLI
-- (state + param) yang dipakai game bisa ditangkap saat tombol skill ditekan
-- manual. Hasil tangkapan tersimpan di _G.HKSkillArgs.
for _, m in ipairs(game.ReplicatedStorage.Classes.Ronin.Skills:GetChildren()) do
    local ok, data = pcall(require, m)
    if ok and type(data) == "table" and type(data.Activate) == "function"
        and not data._HKwrapped then
        data._HKwrapped = true
        local orig = data.Activate
        data.Activate = function(a, b)
            _G.HKSkillArgs = _G.HKSkillArgs or {}
            local function shape(v, d)
                if d > 3 then return type(v) end
                if type(v) ~= "table" then
                    return type(v) .. "=" .. tostring(v):sub(1, 40)
                end
                local s = "{"
                for k, vv in pairs(v) do
                    s ..= tostring(k) .. ":" .. shape(vv, d + 1) .. " "
                    if #s > 300 then break end
                end
                return s .. "}"
            end
            _G.HKSkillArgs[m.Name] = { a = shape(a, 0), b = shape(b, 0) }
            return orig(a, b)
        end
    end
end

-- Anti AFK
pcall(function()
    local VU = game:GetService("VirtualUser")
    P.Idled:Connect(function()
        VU:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VU:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end)

print("[HK] loops aktif")


-- Harta Karun Dungeon | Auto Spin + live preview (gacha SummoningService)
-- Aman: hanya memutar ke slot DUMP yang tidak di-lock. Slot 1 & 2 WAJIB
-- locked, kalau tidak loop berhenti sendiri. Dapat Exotic -> kunci + stop.
-- Rate: Normal Exotic 0.05% | Lucky Exotic 0.1% (pity Exotic 500).

-- Harta Karun Dungeon | Auto Spin + live preview (gacha SummoningService)
-- Aman: hanya memutar ke slot DUMP yang tidak di-lock. Slot lain WAJIB
-- locked, kalau tidak loop berhenti sendiri. Dapat target -> kunci + stop.
-- Rate: Normal Exotic 0.05% | Lucky Exotic 0.1% (pity Exotic 500).
-- Dipakai oleh UI-Obsidian (tab Summon) dan overlay HK_Spin.
-- Guard generasi: reload file menaikkan gen, loop lama ikut mati.

_G.HKSpinGen = (_G.HKSpinGen or 0) + 1
local GEN = _G.HKSpinGen

_G.HKSpin = {
    on = false,
    mode = "LuckyFirst", -- "LuckyFirst" | "Lucky" | "Normal"
    delay = 1.2,
    targetRarity = "Exotic", -- berhenti saat rarity >= ini
    targetClass = "",        -- berhenti saat nama class cocok ("" = abaikan)
    dumpSlot = 3,
    log = {},
    counts = {},
    sessionRolls = 0,
}

_G.HKSpinRank = { Rare = 1, Epic = 2, Legendary = 3, Mythic = 4, Celestial = 5, Exotic = 6 }

-- Catatan: tidak ada overlay sendiri. Kontrol lewat tab Summon di UI
-- Obsidian (slot dump, mode, target rarity/class, START/STOP, status).
-- Overlay lama HK_Spin sengaja tidak dibuat lagi.

local RAR = { Rare = "R", Epic = "E", Legendary = "L", Mythic = "M", Celestial = "C", Exotic = "X" }

task.spawn(function()
    local function getRF(s, n)
        local ok, rf = pcall(function()
            return game.ReplicatedStorage.Packages._Index["sleitnick_knit@1.7.0"]
                .knit.Services[s].RF[n]
        end)
        if ok then return rf end
    end
    local spin = getRF("SummoningService", "Spin")
    local gd = getRF("SummoningService", "GetSlotData")
    local sc = getRF("SummoningService", "GetSpinCounts")
    local tl = getRF("SummoningService", "ToggleSlotLock")
    local function refresh()
        -- Ditampilkan lewat label status di tab Summon (UI Obsidian).
        -- Riwayat lengkap tetap di _G.HKSpin.log.
        if _G.HKLib and not _G.HKLib.Unloaded then
            pcall(function()
                local last = "belum putar"
                if #_G.HKSpin.log > 0 then last = _G.HKSpin.log[#_G.HKSpin.log] end
                _G.HKLib.Options.HKSpinStatus:SetText(
                    "roll:" .. tostring(_G.HKSpin.sessionRolls) .. " | " .. tostring(last))
            end)
        end
    end
    refresh()
    while GEN == _G.HKSpinGen do
        if _G.HKSpin.on and spin and gd then
            local okAll, err = pcall(function()
                local _, slots = pcall(function() return gd:InvokeServer() end)
                if type(slots) ~= "table" then error("slot?") end
                local ds = _G.HKSpin.dumpSlot
                if slots.Slots[ds] == nil then error("slot " .. tostring(ds) .. " tidak ada") end
                for i in ipairs(slots.Slots) do
                    if i ~= ds and slots.SlotLocks[i] ~= true then
                        error("slot " .. tostring(i) .. " tidak locked!")
                    end
                end
                if slots.SlotLocks[ds] ~= false then
                    error("slot dump sudah locked (dapat bagus?)")
                end
                if slots.ActiveIndex ~= _G.HKSpin.dumpSlot then
                    local sw = getRF("SummoningService", "SwitchSlot")
                    if not sw then error("no switch") end
                    sw:InvokeServer(_G.HKSpin.dumpSlot)
                end
                local _, cnt = pcall(function() return sc:InvokeServer() end)
                local st = _G.HKSpin.mode
                if st == "LuckyFirst" then
                    st = (cnt and cnt.Lucky or 0) > 0 and "Lucky" or "Normal"
                end
                if cnt and (cnt[st] or 0) <= 0 then error(st .. " habis") end
                local res = spin:InvokeServer(st)
                if type(res) ~= "table" then error("spin?") end
                _G.HKSpin.sessionRolls += 1
                local rar = tostring(res.Rarity)
                local cls = tostring(res.ClassName)
                _G.HKSpin.counts[rar] = (_G.HKSpin.counts[rar] or 0) + 1
                table.insert(_G.HKSpin.log,
                    "[" .. (RAR[rar] or "?") .. "] " .. st:sub(1, 1) .. ":"
                    .. rar .. " " .. cls)
                local want = _G.HKSpin.targetClass or ""
                local hitClass = want ~= "" and string.lower(cls) == string.lower(want)
                local hitRar = (_G.HKSpinRank[rar] or 0)
                    >= (_G.HKSpinRank[_G.HKSpin.targetRarity] or 6)
                if hitClass or hitRar then
                    if tl then pcall(function() tl:InvokeServer(ds) end) end
                    table.insert(_G.HKSpin.log,
                        "TARGET: " .. cls .. " (" .. rar .. ") dikunci.")
                    _G.HKSpin.on = false
                end
                refresh()
            end)
            if not okAll then
                table.insert(_G.HKSpin.log, "STOP: " .. tostring(err):sub(1, 60))
                _G.HKSpin.on = false
                refresh()
            end
        end
        task.wait(_G.HKSpin.delay)
    end
end)

print("[HK] spin siap")


-- Harta Karun Dungeon | UI Obsidian (mstudio45/deividcomsono fork)
-- Butuh _G.HK dari Farm.lua (jalan dulu) â€” kalau belum ada, dibuatkan default.
-- Buka/tutup menu: RightShift.

pcall(function()
    game.Players.LocalPlayer.PlayerGui:FindFirstChild("HK_UI"):Destroy()
end)
if _G.HKLib then
    pcall(function() _G.HKLib:Unload() end)
    _G.HKLib = nil
end

_G.HK = _G.HK or {
    hover = true, height = 6.5, chest = true,
    atk = true, skill = false, rate = 0.25,
    esp = true, loot = true,
    speed = 32, noclip = false, infjump = true, fly = false, flyspeed = 60,
    tick = 0, target = "none", stealth = true,
}

_G.HKSpin = _G.HKSpin or {
    on = false, mode = "LuckyFirst", delay = 1.2,
    targetRarity = "Exotic", targetClass = "", dumpSlot = 3,
    log = {}, counts = {}, sessionRolls = 0,
}
_G.HKSpinRank = _G.HKSpinRank or
    { Rare = 1, Epic = 2, Legendary = 3, Mythic = 4, Celestial = 5, Exotic = 6 }

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local lib = loadstring(game:HttpGet(repo .. "Library.lua"))()
_G.HKLib = lib

local Window = lib:CreateWindow({
    Title = "Harta Karun Hub",
    Footer = "dungeon farm",
    NotifySide = "Right",
    ShowCustomCursor = true,
})

-- ===== TAB FARM =====
local FarmTab = Window:AddTab("Farm", "swords")
local FarmL = FarmTab:AddLeftGroupbox("Hover Farm")
FarmL:AddToggle("HKHover", {
    Text = "Hover di atas bandit",
    Default = _G.HK.hover,
    Callback = function(v) _G.HK.hover = v end,
})
FarmL:AddSlider("HKHeight", {
    Text = "Tinggi hover",
    Default = math.min(_G.HK.height, 30), Min = 4, Max = 30, Rounding = 1,
    Callback = function(v) _G.HK.height = v end,
})
FarmL:AddToggle("HKChest", {
    Text = "Auto loot chest",
    Default = _G.HK.chest,
    Callback = function(v) _G.HK.chest = v end,
})

-- ===== TAB COMBAT =====
local CombatTab = Window:AddTab("Combat", "zap")
local C = CombatTab:AddLeftGroupbox("Auto Serang")
C:AddToggle("HKAtk", {
    Text = "Spam basic attack",
    Default = _G.HK.atk,
    Callback = function(v) _G.HK.atk = v end,
})
C:AddToggle("HKSkill", {
    Text = "Spam skill",
    Default = _G.HK.skill,
    Callback = function(v) _G.HK.skill = v end,
})
local C2 = CombatTab:AddLeftGroupbox("Kecepatan")
C2:AddSlider("HKRate", {
    Text = "Jeda attack",
    Default = _G.HK.rate, Min = 0.1, Max = 1, Rounding = 2, Suffix = "s",
    Callback = function(v) _G.HK.rate = v end,
})
local C3 = CombatTab:AddLeftGroupbox("Stealth")
C3:AddToggle("HKStealth", {
    Text = "Serang tanpa animasi",
    Default = _G.HK.stealth,
    Callback = function(v) _G.HK.stealth = v end,
})

-- ===== TAB VISUAL =====
local VisualTab = Window:AddTab("Visual", "eye")
local V = VisualTab:AddLeftGroupbox("ESP dan Loot")
V:AddToggle("HKEsp", {
    Text = "ESP nama + HP mob",
    Default = _G.HK.esp,
    Callback = function(v)
        _G.HK.esp = v
        if not v then
            for _, d in ipairs(workspace:GetDescendants()) do
                if d.Name == "HK_ESP" then
                    pcall(function() d:Destroy() end)
                end
            end
        end
    end,
})
V:AddToggle("HKLoot", {
    Text = "Auto loot chest dekat",
    Default = _G.HK.loot,
    Callback = function(v) _G.HK.loot = v end,
})
V:AddButton({
    Text = "Bersihkan semua ESP",
    Func = function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d.Name == "HK_ESP" then
                pcall(function() d:Destroy() end)
            end
        end
    end,
})

-- ===== TAB MOVEMENT =====
local MoveTab = Window:AddTab("Movement", "move")
local M = MoveTab:AddLeftGroupbox("Gerak")
M:AddToggle("HKNoclip", {
    Text = "Noclip",
    Default = _G.HK.noclip,
    Callback = function(v) _G.HK.noclip = v end,
})
M:AddToggle("HKInfJump", {
    Text = "Infinite jump",
    Default = _G.HK.infjump,
    Callback = function(v) _G.HK.infjump = v end,
})
M:AddToggle("HKFly", {
    Text = "Fly (WASD + Space/Ctrl)",
    Default = _G.HK.fly,
    Callback = function(v) _G.HK.fly = v end,
})
local M2 = MoveTab:AddRightGroupbox("Kecepatan")
M2:AddSlider("HKSpd", {
    Text = "Walk speed",
    Default = _G.HK.speed, Min = 16, Max = 100, Rounding = 0,
    Callback = function(v) _G.HK.speed = v end,
})
M2:AddSlider("HKFlySpd", {
    Text = "Fly speed",
    Default = _G.HK.flyspeed, Min = 20, Max = 150, Rounding = 0,
    Callback = function(v) _G.HK.flyspeed = v end,
})

-- ===== TAB MISC =====
local MiscTab = Window:AddTab("Misc", "package")
local B = MiscTab:AddLeftGroupbox("Aksi")
B:AddButton({
    Text = "Claim codes + free chest",
    Func = function()
        task.spawn(function()
            for _, c in ipairs({ "TOURNAMENT", "20MVISIT", "JACKAL", "45KLIKE", "SILVERINE", "CC_UPDATE2" }) do
                local ok, rf = pcall(function()
                    return game.ReplicatedStorage.Packages._Index["sleitnick_knit@1.7.0"]
                        .knit.Services.CodesService.RF.RedeemCode
                end)
                if ok and rf then pcall(function() rf:InvokeServer(c) end) end
                task.wait(0.3)
            end
            local ok2, rf2 = pcall(function()
                return game.ReplicatedStorage.Packages._Index["sleitnick_knit@1.7.0"]
                    .knit.Services.ChestService.RF.ClaimFreeChest
            end)
            if ok2 and rf2 then pcall(function() rf2:InvokeServer() end) end
            lib:Notify({ Title = "Claim", Description = "Selesai", Time = 3 })
        end)
    end,
})
B:AddButton({
    Text = "STOP SEMUA",
    Func = function()
        _G.HK.hover = false
        _G.HK.atk = false
        _G.HK.skill = false
        _G.HK.loot = false
        _G.HK.noclip = false
        _G.HK.fly = false
        local hum = game.Players.LocalPlayer.Character
            and game.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate = true end
        lib:Notify({ Title = "Harta Karun", Description = "Semua fitur dimatikan", Time = 3 })
    end,
})

-- ===== TAB SUMMON =====
local SummonTab = Window:AddTab("Summon", "dices")
local S = SummonTab:AddLeftGroupbox("Auto Spin")
S:AddSlider("HKSpinSlot", {
    Text = "Slot tukar (dump)",
    Default = _G.HKSpin.dumpSlot, Min = 1, Max = 6, Rounding = 0,
    Callback = function(v) _G.HKSpin.dumpSlot = v end,
})
S:AddDropdown("HKSpinMode", {
    Text = "Jenis putaran",
    Values = { "LuckyFirst", "Lucky", "Normal" },
    Default = 1,
    Callback = function(v) _G.HKSpin.mode = v end,
})
S:AddDropdown("HKSpinTarget", {
    Text = "Berhenti saat rarity >=", 
    Values = { "Exotic", "Celestial", "Mythic", "Legendary" },
    Default = 1,
    Callback = function(v) _G.HKSpin.targetRarity = v end,
})
S:AddInput("HKSpinClass", {
    Text = "Target class (kosong = semua)",
    Default = "",
    Finished = true,
    Callback = function(v) _G.HKSpin.targetClass = v end,
})
S:AddButton({
    Text = "START spin",
    Func = function() _G.HKSpin.on = true end,
})
S:AddButton({
    Text = "STOP spin",
    Func = function() _G.HKSpin.on = false end,
})
S:AddLabel("status", true, "HKSpinStatus")

-- ===== TAB UI SETTINGS =====
local UITab = Window:AddTab("UI Settings", "settings")
local MG = UITab:AddLeftGroupbox("Menu")
MG:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
    Default = "RightShift",
    NoUI = true,
    Text = "Menu keybind",
})
MG:AddButton("Unload UI", function() lib:Unload() end)
lib.ToggleKeybind = lib.Options.MenuKeybind

-- Watermark status target farm
pcall(function()
    lib:SetWatermarkVisibility(true)
    lib:SetWatermark("farm: ...")
end)
task.spawn(function()
    while not lib.Unloaded do
        pcall(function()
            lib:SetWatermark("farm: " .. tostring(_G.HK and _G.HK.target or "?"))
            local last = "belum putar"
            if _G.HKSpin and #_G.HKSpin.log > 0 then
                last = _G.HKSpin.log[#_G.HKSpin.log]
            end
            lib.Options.HKSpinStatus:SetText(
                "roll:" .. tostring(_G.HKSpin and _G.HKSpin.sessionRolls or 0)
                .. " | " .. tostring(last))
        end)
        task.wait(1)
    end
end)

lib:Notify({
    Title = "Harta Karun Hub",
    Description = "Semua tab terpasang. RightShift = buka/tutup.",
    Time = 5,
})
print("[HK] UI Obsidian aktif")
