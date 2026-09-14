-- Harta Karun Hub | single-file loader
-- Cara pakai di executor: loadstring(game:HttpGet("https://raw.githubusercontent.com/haytinahyzina-bot/HartaKarunHub/main/HartaKarunHub.lua"))()

-- Harta Karun Dungeon | Farm v4 (tulis ulang bersih)
-- Satu scanner + satu hover + attack/skill/ESP/stealth/gate.
-- Semua fitur DEFAULT OFF, nyalakan dari dashboard.
-- Auto-load saat teleport (queue_on_teleport).

pcall(function()
    queue_on_teleport('loadstring(game:HttpGet("https://raw.githubusercontent.com/haytinahyzina-bot/HartaKarunHub/main/HartaKarunHub.lua"))()')
end)

_G.HK = _G.HK or {}
_G.HK.hover = false
_G.HK.height = _G.HK.height or 6.5
_G.HK.chest = false
_G.HK.atk = false
_G.HK.atkRange = _G.HK.atkRange or 15
_G.HK.skill = false
_G.HK.rate = _G.HK.rate or 0.25
_G.HK.esp = false
_G.HK.loot = true
_G.HK.speed = 28
_G.HK.noclip = false
_G.HK.infjump = false
_G.HK.fly = false
_G.HK.flyspeed = _G.HK.flyspeed or 60
_G.HK.tick = 0
_G.HK.target = "none"
_G.HK.stealth = false

-- Pengecualian hover (nama model). NPC quest / dummy / pemain di-skip otomatis.
_G.HKBlock = _G.HKBlock or { "Galran", "BananitaDolphinita", "Forge Archon", "Awakened Devil", "Rig" }
_G.HKZone = { room = nil }
_G.HKTarget = nil
_G.HKAltarDone = _G.HKAltarDone or {}

-- Tombol skill (1-4) + heal (5). Ubah sesukamu.
_G.HKSkillKeys = _G.HKSkillKeys or { "One", "Two", "Three", "Four" }
_G.HK.autoHeal = false

-- ID animasi ayunan (stealth). Damage tetap masuk (server-side).
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
local HKVIM = nil
pcall(function() HKVIM = game:GetService("VirtualInputManager") end)

local function getGen()
    for _, c in ipairs(workspace:GetChildren()) do
        if string.find(c.Name, "Generated") then
            return c
        end
    end
    return nil
end

local function mobAlive(m)
    for _, n in ipairs(_G.HKBlock) do
        if m.Name == n then
            return false
        end
    end
    local fn = m:GetFullName()
    if string.find(fn, "Dialogue_NPCS")
        or string.find(fn, "Combat_Dummies")
        or string.find(fn, "PlayerModels") then
        return false
    end
    local hum = m:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        return true
    end
    local st = m:GetAttribute("State")
    if m:GetAttribute("CanAttack") == true and st ~= "Dead" then
        return true
    end
    if m:GetAttribute("HealthOverride") ~= nil and st ~= "Dead" then
        return true
    end
    return false
end

local function mobHP(m)
    local hum = m:FindFirstChildOfClass("Humanoid")
    if hum then
        return hum.Health
    end
    local ov = m:GetAttribute("HealthOverride")
    if type(ov) == "number" then
        return ov
    end
    return 1e9
end

local function mobPart(m)
    return m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso")
end

-- Scanner: tiap 0.5 dtk petakan mob hidup ke room, prioritaskan
-- darah terendah di room aktif. Di luar Generated tetap dilirik
-- (maks 600 stud) supaya event tidak ke-skip total.
task.spawn(function()
    while true do
        pcall(function()
            local hrp = P.Character and P.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local chars = {}
                for _, pl in ipairs(game.Players:GetPlayers()) do
                    if pl.Character then
                        chars[pl.Character] = true
                    end
                end
                local gen = getGen()
                local rooms = {}
                if gen then
                    for _, c in ipairs(gen:GetChildren()) do
                        local n = string.match(c.Name, "^Room_(%d+)$")
                        if n and c:IsA("Model") then
                            local ok, piv = pcall(function() return c:GetPivot() end)
                            if ok then
                                rooms[tonumber(n)] = piv.Position
                            end
                        end
                    end
                end
                local byRoom = {}
                local best, bestRoom, bd = nil, nil, 1e9
                for _, d in ipairs(workspace:GetDescendants()) do
                    if d:IsA("Model") and d ~= P.Character and not chars[d] then
                        if mobAlive(d) then
                            local th = mobPart(d)
                            if th then
                                local dist = (th.Position - hrp.Position).Magnitude
                                if dist < 600 then
                                    local rn, rd = 0, 1e9
                                    for n, pos in pairs(rooms) do
                                        local dxz = Vector2.new(
                                            th.Position.X - pos.X,
                                            th.Position.Z - pos.Z).Magnitude
                                        if dxz < rd then
                                            rn, rd = n, dxz
                                        end
                                    end
                                    byRoom[rn] = byRoom[rn] or {}
                                    table.insert(byRoom[rn], { m = d, hp = mobHP(d) })
                                    if dist < bd then
                                        best, bestRoom, bd = d, rn, dist
                                    end
                                end
                            end
                        end
                    end
                end
                local cur = _G.HKZone.room
                local tgt = nil
                if cur and byRoom[cur] and #byRoom[cur] > 0 then
                    table.sort(byRoom[cur], function(a, b) return a.hp < b.hp end)
                    tgt = byRoom[cur][1]
                elseif best then
                    _G.HKZone.room = bestRoom
                    tgt = { m = best, hp = mobHP(best) }
                else
                    _G.HKZone.room = nil
                end
                _G.HKTarget = tgt and tgt.m or nil
                if tgt then
                    _G.HK.target = "R" .. tostring(_G.HKZone.room) .. " "
                        .. tgt.m.Name .. " hp" .. tostring(math.floor(tgt.hp))
                else
                    _G.HK.target = "no mob"
                end
            end
        end)
        task.wait(0.5)
    end
end)

-- Loop utama: speed lock + noclip + fly + hover tidur.
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
    if mob and mob.Parent and not mobAlive(mob) then
        mob = nil
    end
    if _G.HK.hover and mob then
        local th = mobPart(mob)
        if th then
            hum.AutoRotate = false
            local h = _G.HK.height
            if h > 30 then
                h = 30
            end
            if h < 4 then
                h = 4
            end
            hrp.CFrame = CFrame.new(th.Position + Vector3.new(0, h, 0), th.Position)
            hrp.Velocity = Vector3.new()
            hrp.RotVelocity = Vector3.new()
        end
    else
        hum.AutoRotate = true
        if mob then
            _G.HK.target = mob.Name .. " (hover off)"
        end
    end
end)

-- Attack: hanya kalau target dalam jarak atkRange.
task.spawn(function()
    while true do
        if _G.HK.atk then
            pcall(function()
                local mob = _G.HKTarget
                local hrp = P.Character and P.Character:FindFirstChild("HumanoidRootPart")
                if mob and mob.Parent and hrp then
                    local th = mobPart(mob)
                    if th and (th.Position - hrp.Position).Magnitude <= (_G.HK.atkRange or 15) then
                        Inputs.Attack:FireServer()
                    end
                end
            end)
        end
        task.wait(_G.HK.rate)
    end
end)

-- Skill via hotkey (1-4): hanya kalau target dalam jarak. Heal (5) saat HP<40%.
task.spawn(function()
    while true do
        if _G.HK.skill and HKVIM then
            pcall(function()
                local mob = _G.HKTarget
                local hrp = P.Character and P.Character:FindFirstChild("HumanoidRootPart")
                local inRange = false
                if mob and mob.Parent and hrp then
                    local th = mobPart(mob)
                    if th and (th.Position - hrp.Position).Magnitude <= (_G.HK.atkRange or 15) then
                        inRange = true
                    end
                end
                if inRange then
                    for _, kn in ipairs(_G.HKSkillKeys or {}) do
                        if not _G.HK.skill then
                            break
                        end
                        HKVIM:SendKeyEvent(true, Enum.KeyCode[kn], false, game)
                        task.wait(0.05)
                        HKVIM:SendKeyEvent(false, Enum.KeyCode[kn], false, game)
                        task.wait(1.5)
                    end
                end
            end)
        end
        task.wait(0.5)
    end
end)

task.spawn(function()
    while true do
        if _G.HK.autoHeal and HKVIM then
            pcall(function()
                local hum = P.Character and P.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth < 0.4 then
                    HKVIM:SendKeyEvent(true, Enum.KeyCode.Five, false, game)
                    task.wait(0.05)
                    HKVIM:SendKeyEvent(false, Enum.KeyCode.Five, false, game)
                end
            end)
        end
        task.wait(2)
    end
end)

-- Infinite jump.
UIS.JumpRequest:Connect(function()
    if _G.HK.infjump and P.Character then
        local hum = P.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- ESP: merah = Humanoid, oranye = attribute (Lv + State).
task.spawn(function()
    while true do
        if _G.HK.esp then
            pcall(function()
                for _, d in ipairs(workspace:GetDescendants()) do
                    if d:IsA("Model") and d ~= P.Character and not d:FindFirstChild("HK_ESP") then
                        local skip = false
                        for _, pl in ipairs(game.Players:GetPlayers()) do
                            if pl.Character == d then
                                skip = true
                                break
                            end
                        end
                        local label, color = nil, Color3.new(1, 0.35, 0.35)
                        if not skip then
                            local hum = d:FindFirstChildOfClass("Humanoid")
                            if hum and hum.Health > 0 then
                                label = d.Name .. " " .. tostring(math.floor(hum.Health))
                            elseif mobAlive(d) then
                                label = d.Name .. " Lv" .. tostring(d:GetAttribute("Level"))
                                    .. " " .. tostring(d:GetAttribute("State"))
                                color = Color3.new(1, 0.6, 0.2)
                            end
                        end
                        if label then
                            local ador = mobPart(d)
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

-- Stealth: potong ayunan pre-render. Damage tetap masuk (server-side).
RS.RenderStepped:Connect(function()
    if not (_G.HK and _G.HK.stealth) then
        return
    end
    local ch = P.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local anim = hum and hum:FindFirstChildOfClass("Animator")
    if not anim then
        return
    end
    for _, tr in ipairs(anim:GetPlayingAnimationTracks()) do
        local id = tr.Animation and tr.Animation.AnimationId or ""
        local num = string.match(id, "(%d+)")
        if num and _G.HKSwingIds[num] then
            pcall(function() tr:Stop(0) end)
        end
    end
end)

-- Gate loop: gate bersih -> chest se-room -> altar berkah -> room berikut.
-- Altar terpakai dicatat per sesi.
_G.HKAltarDone = _G.HKAltarDone or {}
task.spawn(function()
    while true do
        if _G.HK.chest and _G.HKTarget == nil then
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
                                if ok then
                                    table.insert(rooms, { n = tonumber(n), pos = piv.Position })
                                end
                            end
                        end
                        table.sort(rooms, function(a, b) return a.n < b.n end)
                        local function roomOf(pos)
                            local rn, rd = 0, 1e9
                            for _, r in ipairs(rooms) do
                                local dxz = Vector2.new(
                                    pos.X - r.pos.X, pos.Z - r.pos.Z).Magnitude
                                if dxz < rd then
                                    rn, rd = r.n, dxz
                                end
                            end
                            return rn
                        end
                        local cur = _G.HKZone.room
                        -- Chest BERURUTAN per room (gate 1 dulu!): ada chest
                        -- altar yang cuma bisa dibuka kalau chest gate
                        -- sebelumnya sudah diambil. Tiap chest DITUNGGU
                        -- sampai benar kebuka (Enabled=false) baru lanjut.
                        local byRoom = {}
                        for _, d in ipairs(gen:GetDescendants()) do
                            if d:IsA("ProximityPrompt") and d.Enabled
                                and string.find(string.lower(d.ActionText), "loot") then
                                local m = d.Parent
                                while m and not m:IsA("Model") do
                                    m = m.Parent
                                end
                                if m then
                                    local ok, piv = pcall(function() return m:GetPivot() end)
                                    if ok then
                                        local rn = roomOf(piv.Position)
                                        byRoom[rn] = byRoom[rn] or {}
                                        table.insert(byRoom[rn], { m = m, pr = d, piv = piv })
                                    end
                                end
                            end
                        end
                        local order = {}
                        for rn in pairs(byRoom) do
                            table.insert(order, rn)
                        end
                        table.sort(order)
                        local tgt, pr = nil, nil
                        if #order > 0 then
                            local first = byRoom[order[1]]
                            table.sort(first, function(a, b)
                                local da = (a.piv.Position - hrp.Position).Magnitude
                                local db = (b.piv.Position - hrp.Position).Magnitude
                                return da < db
                            end)
                            tgt, pr = first[1].m, first[1].pr
                        end
                        if tgt and pr then
                            local piv = tgt:GetPivot()
                            hrp.CFrame = CFrame.new(piv.X, piv.Y + 4, piv.Z + 2)
                            hrp.Velocity = Vector3.new()
                            for i = 1, 10 do
                                task.wait(0.7)
                                if not pr.Enabled then
                                    break
                                end
                                pcall(function() fireproximityprompt(pr) end)
                                if _G.HKTarget ~= nil then
                                    break
                                end
                            end
                        else
                            local altar, apr, abd = nil, nil, 1e9
                            for _, d in ipairs(gen:GetDescendants()) do
                                if d:IsA("ProximityPrompt") and d.Enabled
                                    and string.find(string.lower(d.ActionText), "bless") then
                                    local m = d.Parent
                                    while m and not m:IsA("Model") do
                                        m = m.Parent
                                    end
                                    if m and not _G.HKAltarDone[m:GetFullName()] then
                                        local ok, piv = pcall(function() return m:GetPivot() end)
                                        if ok then
                                            local dist = (piv.Position - hrp.Position).Magnitude
                                            if dist < abd then
                                                altar, abd, apr = m, dist, d
                                            end
                                        end
                                    end
                                end
                            end
                            if altar and apr then
                                _G.HKAltarDone[altar:GetFullName()] = true
                                local piv = altar:GetPivot()
                                hrp.CFrame = CFrame.new(piv.X, piv.Y + 4, piv.Z + 2)
                                hrp.Velocity = Vector3.new()
                                task.wait(0.6)
                                pcall(function() fireproximityprompt(apr) end)
                            elseif cur then
                                local nxt = nil
                                for _, r in ipairs(rooms) do
                                    if r.n > cur and (not nxt or r.n < nxt.n) then
                                        nxt = r
                                    end
                                end
                                if not nxt then
                                    nxt = rooms[1]
                                end
                                if nxt then
                                    hrp.CFrame = CFrame.new(nxt.pos.X, nxt.pos.Y + 5, nxt.pos.Z)
                                    hrp.Velocity = Vector3.new()
                                end
                            end
                        end
                    end
                end
            end)
        end
        task.wait(2)
    end
end)

-- Anti AFK.
pcall(function()
    local VU = game:GetService("VirtualUser")
    P.Idled:Connect(function()
        VU:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VU:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end)

print("[HK] farm v4 aktif (semua OFF)")


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


-- Harta Karun Dungeon | Full-auto dungeon loop
-- LOBBY -> queue solo -> farm (sistem hover) -> complete (klaim sebisanya)
-- -> replay -> ulangi. Semua panggilan berisiko di-pcall, server mengabaikan
-- yang tidak valid. Default MATI, nyalakan dari tab Misc.
-- _G.HKAuto = { on=false, dungeon="Bandits Den", diff="Normal" }

_G.HKAuto = _G.HKAuto or { on = false, dungeon = "Bandits Den", diff = "Normal" }
_G.HKAutoPick = _G.HKAutoPick == nil and true or _G.HKAutoPick

task.spawn(function()
    local function getRF(s, n)
        local ok, rf = pcall(function()
            return game.ReplicatedStorage.Packages._Index["sleitnick_knit@1.7.0"]
                .knit.Services[s].RF[n]
        end)
        if ok then return rf end
    end
    local sessRF = getRF("DungeonRunService", "GetSessionInfo")
    local soloRF = getRF("DungeonQueueService", "RequestStartSoloRun")
    local replayRF = getRF("DungeonRunService", "RequestReplay")
    local selRF = getRF("DungeonRunService", "SelectChests")
    local state = "idle"
    local idleTicks = 0
    while true do
        if _G.HKAuto.on and sessRF then
            pcall(function()
                local ok, s = pcall(function() return sessRF:InvokeServer() end)
                local inRun = ok and type(s) == "table" and s.LocationId ~= nil
                if not inRun then
                    state = "lobby"
                    if soloRF and _G.HKAuto.dungeon then
                        pcall(function()
                            soloRF:InvokeServer(_G.HKAuto.dungeon, _G.HKAuto.diff)
                        end)
                    end
                else
                    local phase = tostring(s.Phase)
                    if phase == "Combat" then
                        state = "farming"
                        idleTicks = 0
                    else
                        state = "done:" .. phase
                        idleTicks += 1
                        if idleTicks == 2 and selRF then
                            pcall(function() selRF:InvokeServer() end)
                        end
                        if idleTicks >= 4 and replayRF then
                            pcall(function() replayRF:InvokeServer() end)
                            idleTicks = 0
                        end
                    end
                end
                _G.HKAuto.state = state
            end)
        end
        task.wait(10)
    end
end)

print("[HK] auto dungeon siap (mati default)")

-- Auto-pick: altar berkah pilih acak, hadiah boss/mid-run ambil semua.
-- Mendengarkan event server -> client (tanpa hook), lalu jawab RF-nya.
task.spawn(function()
    local svc = game.ReplicatedStorage.Packages._Index["sleitnick_knit@1.7.0"].knit.Services
    local function rf(sname, fname)
        local ok, r = pcall(function() return svc[sname].RF[fname] end)
        if ok then
            return r
        end
    end
    local function findOptions(t)
        if type(t) ~= "table" then
            return nil
        end
        local n, arr = 0, true
        for k, v in pairs(t) do
            n += 1
            if type(k) ~= "number" or type(v) ~= "table" then
                arr = false
            end
        end
        if arr and n > 0 then
            return t
        end
        for _, v in pairs(t) do
            if type(v) == "table" then
                local r = findOptions(v)
                if r then
                    return r
                end
            end
        end
        return nil
    end
    local function optId(opt)
        for _, k in ipairs({ "Id", "ID", "Index", "Name", "BuffId", "ChestId", "Key" }) do
            if opt[k] ~= nil and type(opt[k]) ~= "table" then
                return opt[k]
            end
        end
        return nil
    end
    local function hookPick(sname, ename, rfName, multi)
        local ok, re = pcall(function() return svc[sname].RE[ename] end)
        if not (ok and re) then
            return
        end
        pcall(function()
            re.OnClientEvent:Connect(function(...)
                local args = { ... }
                _G.HKSnoop = _G.HKSnoop or {}
                if not _G.HKAutoPick then
                    return
                end
                local opts = nil
                for _, a in ipairs(args) do
                    opts = findOptions(a)
                    if opts then
                        break
                    end
                end
                if not opts then
                    return
                end
                local ids = {}
                for _, o in ipairs(opts) do
                    local id = optId(o)
                    if id ~= nil then
                        table.insert(ids, id)
                    end
                end
                if #ids == 0 then
                    return
                end
                task.wait(1)
                local rfn = rf(sname, rfName)
                if rfn then
                    if multi then
                        pcall(function() rfn:InvokeServer(ids) end)
                    else
                        pcall(function() rfn:InvokeServer(ids[math.random(1, #ids)]) end)
                    end
                end
            end)
        end)
    end
    hookPick("DungeonBuffService", "BuffSelection", "SelectBuff", false)
    hookPick("DungeonRunService", "BossLootChests", "SelectChests", true)
    hookPick("DungeonRunService", "MidRunChestSelection", "SelectMidRunChests", true)
end)


-- Harta Karun Dungeon | UI Obsidian (mstudio45/deividcomsono fork)
-- Butuh _G.HK dari Farm.lua (jalan dulu) Ã¢â‚¬â€ kalau belum ada, dibuatkan default.
-- Buka/tutup menu: RightShift.

pcall(function()
    game.Players.LocalPlayer.PlayerGui:FindFirstChild("HK_UI"):Destroy()
end)
if _G.HKLib then
    pcall(function() _G.HKLib:Unload() end)
    _G.HKLib = nil
end

_G.HK.hover = false
_G.HK.atk = false
_G.HK.skill = false
_G.HK.esp = false
_G.HK.loot = false
_G.HK.chest = false
_G.HK.stealth = false
_G.HK.infjump = false
_G.HK.height = _G.HK.height or 6.5
_G.HK.rate = _G.HK.rate or 0.25
_G.HK.atkRange = _G.HK.atkRange or 15
_G.HK.speed = _G.HK.speed or 32
_G.HK.flyspeed = _G.HK.flyspeed or 60
_G.HK.noclip = false
_G.HK.fly = false

_G.HKSpin = _G.HKSpin or {
    on = false, mode = "LuckyFirst", delay = 1.2,
    targetRarity = "Exotic", targetClass = "", dumpSlot = 3,
    log = {}, counts = {}, sessionRolls = 0,
}
_G.HKSpinRank = _G.HKSpinRank or
    { Rare = 1, Epic = 2, Legendary = 3, Mythic = 4, Celestial = 5, Exotic = 6 }

_G.HKAuto = _G.HKAuto or { on = false, dungeon = "Bandits Den", diff = "Normal" }

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
    Text = "Auto skill (tombol 1-4)",
    Default = _G.HK.skill,
    Callback = function(v) _G.HK.skill = v end,
})
C:AddToggle("HKHeal", {
    Text = "Auto heal (tombol 5, HP<40%)",
    Default = _G.HK.autoHeal == true,
    Callback = function(v) _G.HK.autoHeal = v end,
})
C:AddSlider("HKAtkRange", {
    Text = "Jarak serang",
    Default = _G.HK.atkRange or 15, Min = 5, Max = 40, Rounding = 0, Suffix = "st",
    Callback = function(v) _G.HK.atkRange = v end,
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
        _G.HKAuto.on = false
        local hum = game.Players.LocalPlayer.Character
            and game.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.AutoRotate = true end
        lib:Notify({ Title = "Harta Karun", Description = "Semua fitur dimatikan", Time = 3 })
    end,
})
local A = MiscTab:AddLeftGroupbox("Full Auto")
A:AddToggle("HKAutoRun", {
    Text = "Full-auto dungeon loop",
    Default = false,
    Callback = function(v) _G.HKAuto.on = v end,
})
A:AddDropdown("HKAutoDiff", {
    Text = "Difficulty",
    Values = { "Easy", "Normal" },
    Default = 2,
    Callback = function(v) _G.HKAuto.diff = v end,
})
A:AddLabel("status auto", true, "HKAutoStatus")
A:AddToggle("HKAutoPick", {
    Text = "Auto pick buff + chest",
    Default = _G.HKAutoPick ~= false,
    Callback = function(v) _G.HKAutoPick = v end,
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
            pcall(function()
                lib.Options.HKAutoStatus:SetText(
                    "auto:" .. tostring(_G.HKAuto and _G.HKAuto.state or "-"))
            end)
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
