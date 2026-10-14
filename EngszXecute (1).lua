--[[
    ============================================================
    ENGSZXECUTE v1.0.0
    Menu utilitas Roblox untuk mobile - target: Delta Executor
    ============================================================

    CARA PASANG
    1. Buka Delta di HP, masuk ke game Roblox yang ingin dipakai.
    2. Buka tab Script/Editor Delta, tempel seluruh isi file ini.
    3. Tekan Execute. Logo bulat "EX" muncul; ketuk untuk buka/tutup menu.

    CARA PAKAI UI
    - Geser logo / header panel untuk memindahkan.
    - "-"  = minimize (hanya logo yang tampil)
    - Hide = sembunyikan semua; tab kecil "<" di tepi kanan layar
             akan memunculkan kembali.
    - "X"  = tutup menu (semua fitur dimatikan & dibersihkan).

    KETERBATASAN (baca)
    - Semua fitur berjalan di sisi CLIENT. Game dengan anti-cheat server
      dapat mengembalikan speed/jump, menarik posisi (rubber-band) atau
      melakukan kick. Itu di luar kendali script.
    - Fly   : memakai BodyVelocity/BodyGyro + PlatformStand. Bisa tidak
              bekerja pada game dengan karakter/kontrol kustom.
    - Speed/Jump : script menjaga nilai tetap terpasang, tetapi game
              yang mengubahnya tiap frame dapat "berebut" dengan script.
    - Teleport : memindahkan karakter secara lokal; game dengan
              validasi posisi di server bisa menolaknya.
    - Ghost : efek transparan hanya terlihat di layar ANDA (tidak
              direplikasi ke pemain lain). Pass-through mematikan
              CanCollide bagian karakter secara lokal (noclip).
    - Semua map : script tidak terikat map/game tertentu. Koordinat
              disimpan per map; aktifkan "Share list across all maps"
              di tab Coords untuk satu daftar di semua map.
    - Pemilik : OWNER_NAME = "EngssFx". Ubah LOCK_TO_OWNER = true di
              bagian atas jika script hanya boleh jalan di akunmu.
    - Penyimpanan : memakai writefile/readfile jika executor
              menyediakannya (file EngszXecute_Data.json). Jika tidak
              ada, data hanya bertahan selama sesi.
    - Suara UI memakai file suara bawaan klien Roblox; bila tidak ada
              di perangkat, suara tidak akan terdengar (tidak error).
    - Memakai executor melanggar Terms of Use Roblox dan dapat
              menyebabkan akun dibanned. Gunakan dengan risiko sendiri.
    ============================================================
]]

local VERSION = "1.0.0"

if not game:IsLoaded() then game.Loaded:Wait() end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local HttpService      = game:GetService("HttpService")
local CoreGui          = game:GetService("CoreGui")

while not Players.LocalPlayer do task.wait() end
local LocalPlayer = Players.LocalPlayer

-- KONFIGURASI PEMILIK
local OWNER_NAME = "EngssFx"   -- username Roblox pemilik script
local LOCK_TO_OWNER = false    -- true = script hanya jalan untuk akun OWNER_NAME
if LOCK_TO_OWNER and LocalPlayer.Name ~= OWNER_NAME then
    warn("[EngszXecute] Locked to " .. OWNER_NAME)
    return
end

local env = (type(getgenv) == "function" and getgenv()) or _G

-- Tutup instance lama (kalau script dieksekusi dua kali)
if type(env.EngszXecute) == "table" and type(env.EngszXecute.Destroy) == "function" then
    pcall(env.EngszXecute.Destroy)
end

local alive = true
local destroyAll -- didefinisikan di bagian paling bawah

----------------------------------------------------------------
-- 1. UTILITAS: Maid, helper, penyimpanan, konfigurasi
----------------------------------------------------------------
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({tasks = {}}, Maid) end
function Maid:Add(item) table.insert(self.tasks, item) return item end
function Maid:Clean()
    local list = self.tasks
    self.tasks = {}
    for i = #list, 1, -1 do
        local item = list[i]
        local kind = typeof(item)
        if kind == "RBXScriptConnection" then
            item:Disconnect()
        elseif kind == "Instance" then
            item:Destroy()
        elseif kind == "function" then
            pcall(item)
        end
    end
end

local Root = Maid.new() -- semua koneksi global & GUI

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
local function num(v) return tostring(math.floor(v * 100 + 0.5) / 100) end
local function round3(v) return math.floor(v * 1000 + 0.5) / 1000 end

-- Penyimpanan lokal (hanya bila executor menyediakan readfile/writefile)
local Storage = {
    file = "EngszXecute_Data.json",
    persistent = false,
    data = {settings = {}, coords = {}},
}
local saveQueued = false

function Storage.load()
    if type(readfile) ~= "function" or type(writefile) ~= "function" or type(isfile) ~= "function" then
        return
    end
    Storage.persistent = true
    local ok, raw = pcall(function()
        if isfile(Storage.file) then return readfile(Storage.file) end
    end)
    if ok and type(raw) == "string" and raw ~= "" then
        local ok2, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok2 and type(decoded) == "table" then
            if type(decoded.settings) == "table" then Storage.data.settings = decoded.settings end
            if type(decoded.coords) == "table" then Storage.data.coords = decoded.coords end
        end
    end
end

function Storage.flush()
    if not Storage.persistent then return end
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, Storage.data)
    if ok then pcall(writefile, Storage.file, encoded) end
end

function Storage.queue()
    if not Storage.persistent or saveQueued then return end
    saveQueued = true
    task.delay(1, function()
        saveQueued = false
        if alive then Storage.flush() end
    end)
end

local DEFAULTS = {accent = 1, transparency = 0.08, scale = 1, sound = true, logoX = 0.015, logoY = 0.2, sharedCoords = false}
local Cfg = {}
for k, v in pairs(DEFAULTS) do Cfg[k] = v end

local function cfgLoad()
    local saved = Storage.data.settings
    for k, v in pairs(DEFAULTS) do
        if type(saved[k]) == type(v) then Cfg[k] = saved[k] end
    end
    Cfg.accent = math.clamp(math.floor(Cfg.accent), 1, 5)
    Cfg.transparency = math.clamp(Cfg.transparency, 0, 0.6)
    Cfg.scale = math.clamp(Cfg.scale, 0.7, 1.3)
    Cfg.logoX = math.clamp(Cfg.logoX, 0, 1)
    Cfg.logoY = math.clamp(Cfg.logoY, 0, 1)
end

local function cfgSave()
    local copy = {}
    for k in pairs(DEFAULTS) do copy[k] = Cfg[k] end
    Storage.data.settings = copy
    Storage.queue()
end

local function cfgReset()
    for k, v in pairs(DEFAULTS) do Cfg[k] = v end
    cfgSave()
end

----------------------------------------------------------------
-- 2. THEME + HELPER UI
----------------------------------------------------------------
local Theme = {
    bg       = Color3.fromRGB(10, 10, 14),
    bg2      = Color3.fromRGB(17, 17, 24),
    card     = Color3.fromRGB(24, 24, 34),
    off      = Color3.fromRGB(52, 52, 68),
    text     = Color3.fromRGB(240, 240, 248),
    sub      = Color3.fromRGB(140, 140, 165),
    red      = Color3.fromRGB(240, 70, 80),
    green    = Color3.fromRGB(70, 210, 130),
    dangerBg = Color3.fromRGB(120, 30, 44),
    accents = {
        {name = "Red",     color = Color3.fromRGB(235, 52, 80)},
        {name = "Purple",  color = Color3.fromRGB(150, 84, 255)},
        {name = "Magenta", color = Color3.fromRGB(214, 64, 220)},
        {name = "Blue",    color = Color3.fromRGB(70, 140, 255)},
        {name = "Cyan",    color = Color3.fromRGB(40, 210, 230)},
    },
    painters = {},
}
function Theme.accent()
    return (Theme.accents[Cfg.accent] or Theme.accents[1]).color
end
function Theme.paint(fn) -- daftarkan fungsi yang diwarnai ulang saat aksen berubah
    table.insert(Theme.painters, fn)
    fn(Theme.accent())
end
function Theme.apply()
    local c = Theme.accent()
    for _, fn in ipairs(Theme.painters) do pcall(fn, c) end
end

local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end
local function corner(inst, r)
    return new("UICorner", {CornerRadius = UDim.new(0, r)}, inst)
end
local function stroke(inst, color, thickness, transparency)
    return new("UIStroke", {
        Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, inst)
end
local orderCounter = setmetatable({}, {__mode = "k"})
local function nextOrder(p)
    orderCounter[p] = (orderCounter[p] or 0) + 1
    return orderCounter[p]
end
local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end
local function sameInput(input, held)
    return input == held
        or (held.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseButton1)
end

local function getGuiParent()
    if type(gethui) == "function" then
        local ok, h = pcall(gethui)
        if ok and typeof(h) == "Instance" then return h end
    end
    local ok = pcall(function()
        local probe = Instance.new("Folder")
        probe.Parent = CoreGui
        probe:Destroy()
    end)
    if ok then return CoreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local UI = {state = "open", activeTab = "movement", refs = {}}

----------------------------------------------------------------
-- 3. NOTIFIKASI + SUARA
----------------------------------------------------------------
local Notify = {counter = 0}

function Notify.init(gui)
    Notify.holder = new("Frame", {
        Name = "Toasts", AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -72), Size = UDim2.fromOffset(300, 150),
        BackgroundTransparency = 1, ZIndex = 100,
    }, gui)
    new("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 4),
    }, Notify.holder)
end

function Notify.push(text, kind)
    local holder = Notify.holder
    if not holder then return end
    Notify.counter = Notify.counter + 1
    local color = (kind == "err" and Theme.red) or (kind == "ok" and Theme.green) or Theme.accent()

    -- maksimal 3 toast sekaligus
    local toasts = {}
    for _, c in ipairs(holder:GetChildren()) do
        if c:IsA("Frame") then table.insert(toasts, c) end
    end
    if #toasts >= 3 then
        table.sort(toasts, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
        toasts[1]:Destroy()
    end

    local toast = new("Frame", {
        AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Theme.bg, BackgroundTransparency = 1,
        BorderSizePixel = 0, LayoutOrder = Notify.counter,
    }, holder)
    corner(toast, 8)
    local st = stroke(toast, color, 1.2, 1)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
    }, toast)
    local lbl = new("TextLabel", {
        AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1, Text = tostring(text),
        Font = Enum.Font.GothamMedium, TextSize = 12,
        TextColor3 = Theme.text, TextTransparency = 1,
    }, toast)

    local fadeIn = TweenInfo.new(0.18)
    TweenService:Create(toast, fadeIn, {BackgroundTransparency = 0.08}):Play()
    TweenService:Create(lbl, fadeIn, {TextTransparency = 0}):Play()
    TweenService:Create(st, fadeIn, {Transparency = 0.1}):Play()

    task.delay(2.4, function()
        if not toast.Parent then return end
        local fadeOut = TweenInfo.new(0.25)
        TweenService:Create(toast, fadeOut, {BackgroundTransparency = 1}):Play()
        TweenService:Create(lbl, fadeOut, {TextTransparency = 1}):Play()
        TweenService:Create(st, fadeOut, {Transparency = 1}):Play()
        task.delay(0.3, function()
            if toast.Parent then toast:Destroy() end
        end)
    end)
end

local Sfx = {}
function Sfx.init(gui)
    Sfx.sound = new("Sound", {
        Name = "UIClick", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35,
    }, gui)
end
function Sfx.click()
    if Cfg.sound and Sfx.sound then
        pcall(function() Sfx.sound:Play() end)
    end
end

----------------------------------------------------------------
-- 4. KARAKTER (respawn handler terpusat)
----------------------------------------------------------------
local Char = {handlers = {}}

function Char.get()
    local char = LocalPlayer.Character
    if not char or not char.Parent then return nil, "Character not found" end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil, "Humanoid not found" end
    if hum.Health <= 0 then return nil, "Character is dead" end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil, "HumanoidRootPart not found" end
    return {char = char, hum = hum, root = root}
end

function Char.onSpawn(fn) table.insert(Char.handlers, fn) end

local function handleCharacter(char)
    task.spawn(function()
        local hum = char:WaitForChild("Humanoid", 10)
        local root = char:WaitForChild("HumanoidRootPart", 10)
        if not alive or not hum or not root or LocalPlayer.Character ~= char then return end
        for _, fn in ipairs(Char.handlers) do
            local ok, err = pcall(fn, char, hum, root)
            if not ok then warn("[EngszXecute] " .. tostring(err)) end
        end
    end)
end

function Char.start()
    Root:Add(LocalPlayer.CharacterAdded:Connect(handleCharacter))
    if LocalPlayer.Character then handleCharacter(LocalPlayer.Character) end
end

----------------------------------------------------------------
-- 5. FITUR: FLY
----------------------------------------------------------------
local Fly = {enabled = false, speed = 50, up = false, down = false, maid = Maid.new()}

local function getControls()
    if Fly.controlsTried then return Fly.controls end
    Fly.controlsTried = true
    pcall(function()
        local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
        local module = scripts and scripts:FindFirstChild("PlayerModule")
        if module then Fly.controls = require(module):GetControls() end
    end)
    return Fly.controls
end

-- return: maju(-1..1), kanan(-1..1)
local function readMoveInput(hum, camCF)
    local controls = getControls()
    if controls then
        local ok, v = pcall(controls.GetMoveVector, controls)
        if ok and typeof(v) == "Vector3" and (math.abs(v.X) + math.abs(v.Z)) > 0.01 then
            return -v.Z, v.X
        end
    end
    local move = hum.MoveDirection
    if move.Magnitude < 0.01 then return 0, 0 end
    local look = camCF.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then return 0, 0 end
    flat = flat.Unit
    local right = flat:Cross(Vector3.new(0, 1, 0))
    return move:Dot(flat), move:Dot(right)
end

function Fly.detach()
    Fly.maid:Clean()
end

function Fly.attach(p)
    Fly.detach()
    local hum, root = p.hum, p.root

    local prevPlatformStand = hum.PlatformStand
    hum.PlatformStand = true
    Fly.maid:Add(function()
        if hum.Parent then hum.PlatformStand = prevPlatformStand end
        if root.Parent then root.AssemblyLinearVelocity = Vector3.zero end
    end)

    local bv = Instance.new("BodyVelocity")
    bv.Name = "EngszFlyVelocity"
    bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bv.Velocity = Vector3.zero
    bv.Parent = root
    Fly.maid:Add(bv)

    local bg = Instance.new("BodyGyro")
    bg.Name = "EngszFlyGyro"
    bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    bg.P = 9000
    bg.D = 500
    bg.CFrame = root.CFrame
    bg.Parent = root
    Fly.maid:Add(bg)

    Fly.maid:Add(hum.Died:Connect(function() Fly.detach() end))

    Fly.maid:Add(RunService.RenderStepped:Connect(function(dt)
        if not hum.Parent or not root.Parent then
            Fly.detach()
            return
        end
        local cam = workspace.CurrentCamera
        if not cam then return end
        local camCF = cam.CFrame
        local fwd, rgt = readMoveInput(hum, camCF)
        local vertical = (Fly.up and 1 or 0) - (Fly.down and 1 or 0)
        local dir = camCF.LookVector * fwd + camCF.RightVector * rgt + Vector3.new(0, vertical, 0)
        if dir.Magnitude > 1 then dir = dir.Unit end
        bv.Velocity = bv.Velocity:Lerp(dir * Fly.speed, math.min(1, dt * 14))

        local look = camCF.LookVector
        local flat = Vector3.new(look.X, 0, look.Z)
        if flat.Magnitude > 0.01 then
            bg.CFrame = CFrame.new(Vector3.zero, flat.Unit)
        end
    end))
end

function Fly.set(on, silent)
    if on == Fly.enabled then return true end
    if on then
        local p, err = Char.get()
        if not p then
            Notify.push("Fly failed: " .. tostring(err), "err")
            return false
        end
        Fly.enabled = true
        Fly.attach(p)
        UI.setFlyPad(true)
        if not silent then Notify.push("Fly Enabled", "ok") end
    else
        Fly.enabled = false
        Fly.detach()
        Fly.up, Fly.down = false, false
        UI.setFlyPad(false)
        if not silent then Notify.push("Fly Disabled", "info") end
    end
    return true
end

Char.onSpawn(function(char, hum, root)
    Fly.detach()
    if Fly.enabled then Fly.attach({char = char, hum = hum, root = root}) end
end)

----------------------------------------------------------------
-- 6. FITUR: WALKSPEED
----------------------------------------------------------------
local Speed = {enabled = false, value = 50, default = 16, maid = Maid.new()}

function Speed.apply()
    if not Speed.enabled then return end
    local p = Char.get()
    if p and p.hum.WalkSpeed ~= Speed.value then p.hum.WalkSpeed = Speed.value end
end
function Speed.set(v)
    Speed.value = math.clamp(v, 0, 500)
    Speed.enabled = true
    Speed.apply()
end
function Speed.disable()
    Speed.enabled = false
    local p = Char.get()
    if p then p.hum.WalkSpeed = Speed.default end
end
function Speed.reset()
    Speed.disable()
    Speed.value = Speed.default
end

Char.onSpawn(function(char, hum)
    Speed.maid:Clean()
    Speed.default = hum.WalkSpeed -- nilai asli game pada karakter baru
    Speed.maid:Add(hum:GetPropertyChangedSignal("WalkSpeed"):Connect(Speed.apply))
    Speed.apply()
end)

----------------------------------------------------------------
-- 7. FITUR: JUMPPOWER (mendukung JumpPower & JumpHeight)
----------------------------------------------------------------
local Jump = {enabled = false, value = 100, default = 50, orig = nil, maid = Maid.new()}

local function powerToHeight(p) return (p * p) / (2 * workspace.Gravity) end
local function heightToPower(h) return math.sqrt(2 * workspace.Gravity * h) end

function Jump.apply()
    if not Jump.enabled then return end
    local p = Char.get()
    if not p then return end
    local hum = p.hum
    if hum.UseJumpPower then
        if hum.JumpPower ~= Jump.value then hum.JumpPower = Jump.value end
    else
        local h = powerToHeight(Jump.value)
        if math.abs(hum.JumpHeight - h) > 0.001 then hum.JumpHeight = h end
    end
end
function Jump.restore()
    local p = Char.get()
    if not p or not Jump.orig then return end
    if p.hum.UseJumpPower then
        p.hum.JumpPower = Jump.orig.power
    else
        p.hum.JumpHeight = Jump.orig.height
    end
end
function Jump.set(v)
    Jump.value = math.clamp(v, 0, 1000)
    Jump.enabled = true
    Jump.apply()
end
function Jump.disable()
    Jump.enabled = false
    Jump.restore()
end
function Jump.reset()
    Jump.disable()
    Jump.value = Jump.default
end

Char.onSpawn(function(char, hum)
    Jump.maid:Clean()
    Jump.orig = {power = hum.JumpPower, height = hum.JumpHeight, usePower = hum.UseJumpPower}
    Jump.default = hum.UseJumpPower and hum.JumpPower or heightToPower(hum.JumpHeight)
    Jump.maid:Add(hum:GetPropertyChangedSignal("JumpPower"):Connect(Jump.apply))
    Jump.maid:Add(hum:GetPropertyChangedSignal("JumpHeight"):Connect(Jump.apply))
    Jump.maid:Add(hum:GetPropertyChangedSignal("UseJumpPower"):Connect(Jump.apply))
    Jump.apply()
end)

----------------------------------------------------------------
-- 8. FITUR: GHOST MODE (transparan + pass-through lokal)
----------------------------------------------------------------
local Ghost = {
    enabled = false, noclip = true, transparency = 0.6,
    orig = setmetatable({}, {__mode = "k"}), collide = {},
    maid = Maid.new(), noclipMaid = Maid.new(),
}

local function ghostable(inst) return inst:IsA("BasePart") or inst:IsA("Decal") end

function Ghost.trackVisual(inst)
    if not ghostable(inst) or Ghost.orig[inst] ~= nil then return end
    Ghost.orig[inst] = inst.Transparency
    inst.Transparency = math.max(inst.Transparency, Ghost.transparency)
end

function Ghost.setVisual(on)
    Ghost.maid:Clean()
    if on then
        local char = LocalPlayer.Character
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do Ghost.trackVisual(d) end
        Ghost.maid:Add(char.DescendantAdded:Connect(function(d)
            if Ghost.enabled then Ghost.trackVisual(d) end
        end))
    else
        for inst, v in pairs(Ghost.orig) do
            if inst.Parent then inst.Transparency = v end
        end
        Ghost.orig = setmetatable({}, {__mode = "k"})
    end
end

function Ghost.setTransparency(v)
    Ghost.transparency = v
    if Ghost.enabled then
        for inst, o in pairs(Ghost.orig) do
            if inst.Parent then inst.Transparency = math.max(o, v) end
        end
    end
end

function Ghost.trackCollide(part)
    if part:IsA("BasePart") and Ghost.collide[part] == nil then
        Ghost.collide[part] = part.CanCollide
    end
end

function Ghost.setNoclip(on)
    Ghost.noclipMaid:Clean()
    if on then
        local char = LocalPlayer.Character
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do Ghost.trackCollide(d) end
        Ghost.noclipMaid:Add(char.DescendantAdded:Connect(Ghost.trackCollide))
        Ghost.noclipMaid:Add(RunService.Stepped:Connect(function()
            for part in pairs(Ghost.collide) do
                if part.Parent and part.CanCollide then part.CanCollide = false end
            end
        end))
    else
        for part, v in pairs(Ghost.collide) do
            if part.Parent then part.CanCollide = v end
        end
        Ghost.collide = {}
    end
end

function Ghost.set(on)
    Ghost.enabled = on
    Ghost.setVisual(on)
    Ghost.setNoclip(on and Ghost.noclip)
end

function Ghost.setNoclipOption(on)
    Ghost.noclip = on
    if Ghost.enabled then Ghost.setNoclip(on) end
end

Char.onSpawn(function()
    Ghost.maid:Clean()
    Ghost.noclipMaid:Clean()
    Ghost.orig = setmetatable({}, {__mode = "k"})
    Ghost.collide = {}
    if Ghost.enabled then
        Ghost.setVisual(true)
        Ghost.setNoclip(Ghost.noclip)
    end
end)

----------------------------------------------------------------
-- 9. FITUR: KOORDINAT & TELEPORT
----------------------------------------------------------------
local Coords = {list = {}, previous = nil}

-- "global" = satu daftar untuk semua map; selain itu daftar per PlaceId
function Coords.key()
    return Cfg.sharedCoords and "global" or tostring(game.PlaceId)
end

function Coords.load()
    local saved = Storage.data.coords[Coords.key()]
    Coords.list = {}
    if type(saved) == "table" then
        for _, e in ipairs(saved) do
            if type(e) == "table" and type(e.x) == "number" and type(e.y) == "number"
                and type(e.z) == "number" then
                table.insert(Coords.list, {name = tostring(e.name or "Location"), x = e.x, y = e.y, z = e.z})
            end
        end
    end
end

function Coords.persist()
    Storage.data.coords[Coords.key()] = Coords.list
    Storage.queue()
    if UI.refreshCoords then UI.refreshCoords() end
end

local function fmtCoords(e) return string.format("%.2f, %.2f, %.2f", e.x, e.y, e.z) end

function Coords.save(name)
    local p, err = Char.get()
    if not p then
        Notify.push("Save failed: " .. tostring(err), "err")
        return false
    end
    local pos = p.root.Position
    name = trim(name)
    if name == "" then name = "Location " .. (#Coords.list + 1) end
    table.insert(Coords.list, {name = name, x = round3(pos.X), y = round3(pos.Y), z = round3(pos.Z)})
    Coords.persist()
    Notify.push("Coordinate Saved: " .. name, "ok")
    return true
end

function Coords.teleport(entry)
    local p, err = Char.get()
    if not p then
        Notify.push("Teleport Failed: " .. tostring(err), "err")
        return false
    end
    local before = p.root.CFrame
    local rotation = before - before.Position
    local ok = pcall(function()
        p.char:PivotTo(CFrame.new(entry.x, entry.y, entry.z) * rotation)
        p.root.AssemblyLinearVelocity = Vector3.zero
        p.root.AssemblyAngularVelocity = Vector3.zero
    end)
    if ok then
        Coords.previous = before
        Notify.push("Teleport Successful: " .. entry.name, "ok")
        return true
    end
    Notify.push("Teleport Failed: could not move character", "err")
    return false
end

function Coords.back()
    if not Coords.previous then
        Notify.push("Teleport Failed: no previous position", "err")
        return false
    end
    local p, err = Char.get()
    if not p then
        Notify.push("Teleport Failed: " .. tostring(err), "err")
        return false
    end
    local current = p.root.CFrame
    local ok = pcall(function()
        p.char:PivotTo(Coords.previous)
        p.root.AssemblyLinearVelocity = Vector3.zero
    end)
    if ok then
        Coords.previous = current -- tekan lagi untuk bolak-balik
        Notify.push("Teleport Successful: previous position", "ok")
        return true
    end
    Notify.push("Teleport Failed: could not move character", "err")
    return false
end

function Coords.copy(entry)
    local fn = setclipboard or toclipboard
    if type(fn) ~= "function" then
        Notify.push("Clipboard not supported: " .. fmtCoords(entry), "err")
        return
    end
    if pcall(fn, fmtCoords(entry)) then
        Notify.push("Coordinates copied", "ok")
    else
        Notify.push("Copy failed", "err")
    end
end

function Coords.rename(entry, newName)
    entry.name = newName
    Storage.data.coords[Coords.key()] = Coords.list
    Storage.queue()
    Notify.push("Renamed: " .. newName, "info")
end

function Coords.delete(entry)
    for i, e in ipairs(Coords.list) do
        if e == entry then
            table.remove(Coords.list, i)
            break
        end
    end
    Coords.persist()
    Notify.push("Deleted: " .. entry.name, "info")
end

----------------------------------------------------------------
-- 10. KOMPONEN UI
----------------------------------------------------------------
function UI.viewport()
    local s = UI.gui and UI.gui.AbsoluteSize or Vector2.zero
    if s.X <= 0 or s.Y <= 0 then
        local cam = workspace.CurrentCamera
        s = cam and cam.ViewportSize or Vector2.new(800, 400)
    end
    return s
end

local function placeAt(target, px, py, size)
    local vp = UI.viewport()
    size = size or target.AbsoluteSize
    px = math.clamp(px, 0, math.max(0, vp.X - size.X))
    py = math.clamp(py, 0, math.max(0, vp.Y - size.Y))
    target.Position = UDim2.fromScale(px / vp.X, py / vp.Y)
end

-- Drag + tap untuk touch maupun mouse (posisi disimpan dalam scale layar)
local function makeDraggable(handle, target, opts)
    opts = opts or {}
    local dragInput, startMouse, startPos, moved
    handle.InputBegan:Connect(function(input)
        if isPress(input) then
            dragInput = input
            startMouse = Vector2.new(input.Position.X, input.Position.Y)
            startPos = target.AbsolutePosition
            moved = false
        end
    end)
    Root:Add(UserInputService.InputChanged:Connect(function(input)
        if not dragInput then return end
        local match = input == dragInput
            or (dragInput.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseMovement)
        if not match then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - startMouse
        if not moved and delta.Magnitude >= 8 then moved = true end
        if moved then placeAt(target, startPos.X + delta.X, startPos.Y + delta.Y) end
    end))
    Root:Add(UserInputService.InputEnded:Connect(function(input)
        if dragInput and sameInput(input, dragInput) then
            dragInput = nil
            if moved then
                if opts.onDropped then opts.onDropped() end
            elseif opts.onTap then
                opts.onTap()
            end
        end
    end))
end

local function section(page, text)
    local lbl = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1,
        Text = string.upper(text), Font = Enum.Font.GothamBold, TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.sub,
        LayoutOrder = nextOrder(page),
    }, page)
    Theme.paint(function(c) lbl.TextColor3 = c end)
    return lbl
end

local function note(page, text)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Text = text, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Theme.sub,
        LayoutOrder = nextOrder(page),
    }, page)
end

function UI.button(parent, text, style, onClick, opts)
    opts = opts or {}
    local btn = new("TextButton", {
        Size = opts.size or UDim2.new(1, 0, 0, 32), BackgroundColor3 = Theme.off,
        BorderSizePixel = 0, Text = text, Font = Enum.Font.GothamBold,
        TextSize = opts.textSize or 12, TextColor3 = Theme.text,
        AutoButtonColor = true, LayoutOrder = opts.order or 0,
    }, parent)
    corner(btn, 8)
    if style == "accent" then
        Theme.paint(function(c) btn.BackgroundColor3 = c end)
    elseif style == "accentStatic" then
        btn.BackgroundColor3 = Theme.accent()
    elseif style == "danger" then
        btn.BackgroundColor3 = Theme.dangerBg
    end
    btn.MouseButton1Click:Connect(function()
        Sfx.click()
        onClick()
    end)
    return btn
end

function UI.toggle(page, text, initial, onChange)
    local obj = {}
    local state = initial and true or false
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Theme.card, BorderSizePixel = 0,
        AutoButtonColor = false, Text = "", LayoutOrder = nextOrder(page),
    }, page)
    corner(row, 8)
    new("TextLabel", {
        Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -64, 1, 0),
        BackgroundTransparency = 1, Text = text, TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.text,
    }, row)
    local pill = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(40, 20), BackgroundColor3 = Theme.off, BorderSizePixel = 0,
    }, row)
    corner(pill, 10)
    local dot = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, pill)
    corner(dot, 7)

    local function render(animate)
        local color = state and Theme.accent() or Theme.off
        local pos = state and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        if animate then
            local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
            TweenService:Create(pill, info, {BackgroundColor3 = color}):Play()
            TweenService:Create(dot, info, {Position = pos}):Play()
        else
            pill.BackgroundColor3 = color
            dot.Position = pos
        end
    end
    Theme.paint(function() render(false) end)

    function obj.Set(v, silent)
        state = v and true or false
        render(true)
        if not silent and onChange then
            local res = onChange(state)
            if res == false then -- aksi gagal: kembalikan switch
                state = not state
                render(true)
            end
        end
    end
    function obj.Get() return state end
    row.MouseButton1Click:Connect(function()
        Sfx.click()
        obj.Set(not state)
    end)
    return obj
end

-- cfg: label, min, max, hardMax, value, decimals, onChange, onCommit, onReset
function UI.slider(page, cfg)
    local obj = {}
    local decimals = cfg.decimals or 0
    local hardMax = cfg.hardMax or cfg.max
    local value = cfg.value

    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = Theme.card,
        BorderSizePixel = 0, LayoutOrder = nextOrder(page),
    }, page)
    corner(card, 8)
    new("TextLabel", {
        Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -140, 0, 22),
        BackgroundTransparency = 1, Text = cfg.label, TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.text,
    }, card)
    local box = new("TextBox", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6),
        Size = UDim2.fromOffset(56, 22), BackgroundColor3 = Theme.bg2, BorderSizePixel = 0,
        ClearTextOnFocus = false, Text = "", Font = Enum.Font.GothamBold,
        TextSize = 12, TextColor3 = Theme.text,
    }, card)
    corner(box, 6)
    if cfg.onReset then
        local rb = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -70, 0, 6),
            Size = UDim2.fromOffset(48, 22), BackgroundColor3 = Theme.off, BorderSizePixel = 0,
            Text = "Reset", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Theme.text,
        }, card)
        corner(rb, 6)
        rb.MouseButton1Click:Connect(function()
            Sfx.click()
            cfg.onReset()
        end)
    end

    local track = new("Frame", {
        Position = UDim2.new(0, 12, 0, 43), Size = UDim2.new(1, -24, 0, 6),
        BackgroundColor3 = Theme.off, BorderSizePixel = 0,
    }, card)
    corner(track, 3)
    local fill = new("Frame", {Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0}, track)
    corner(fill, 3)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 16),
        Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, track)
    corner(knob, 8)
    Theme.paint(function(c) fill.BackgroundColor3 = c end)

    -- area sentuh lebar supaya mudah digeser dengan jari
    local hit = new("TextButton", {
        Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
    }, card)

    local function render()
        local r = math.clamp((value - cfg.min) / (cfg.max - cfg.min), 0, 1)
        fill.Size = UDim2.new(r, 0, 1, 0)
        knob.Position = UDim2.new(r, 0, 0.5, 0)
        box.Text = string.format("%." .. decimals .. "f", value)
    end

    function obj.Set(v, silent)
        v = math.clamp(v, cfg.min, hardMax)
        local m = 10 ^ decimals
        value = math.floor(v * m + 0.5) / m
        render()
        if not silent and cfg.onChange then cfg.onChange(value) end
    end
    function obj.Get() return value end
    render()

    local dragInput
    local function updateFrom(input)
        local w = track.AbsoluteSize.X
        if w <= 0 then return end
        local r = math.clamp((input.Position.X - track.AbsolutePosition.X) / w, 0, 1)
        obj.Set(cfg.min + (cfg.max - cfg.min) * r)
    end
    hit.InputBegan:Connect(function(input)
        if isPress(input) then
            dragInput = input
            page.ScrollingEnabled = false -- cegah halaman ikut scroll saat geser slider
            updateFrom(input)
        end
    end)
    Root:Add(UserInputService.InputChanged:Connect(function(input)
        if dragInput and (input == dragInput
            or (dragInput.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            updateFrom(input)
        end
    end))
    Root:Add(UserInputService.InputEnded:Connect(function(input)
        if dragInput and sameInput(input, dragInput) then
            dragInput = nil
            page.ScrollingEnabled = true
            if cfg.onCommit then cfg.onCommit(value) end
        end
    end))
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then
            obj.Set(n)
            if cfg.onCommit then cfg.onCommit(value) end
        else
            render()
        end
    end)
    return obj
end

----------------------------------------------------------------
-- 11. HALAMAN-HALAMAN
----------------------------------------------------------------
local function buildMovement(page)
    section(page, "Fly")
    UI.refs.flyToggle = UI.toggle(page, "Fly", false, function(on)
        return Fly.set(on)
    end)
    UI.slider(page, {
        label = "Fly Speed", min = 10, max = 200, hardMax = 500, value = Fly.speed,
        onChange = function(v) Fly.speed = v end,
    })
    note(page, "Joystick terbang ke arah kamera. Gunakan pad ▲ ▼ (bisa digeser) untuk naik/turun.")

    section(page, "WalkSpeed")
    local speedToggle, speedSlider
    speedToggle = UI.toggle(page, "Custom WalkSpeed", false, function(on)
        if on then
            Speed.set(Speed.value)
            Notify.push("WalkSpeed Updated: " .. num(Speed.value), "ok")
        else
            Speed.disable()
            Notify.push("WalkSpeed restored: " .. num(Speed.default), "info")
        end
    end)
    speedSlider = UI.slider(page, {
        label = "WalkSpeed", min = 0, max = 200, hardMax = 500, value = Speed.value,
        onChange = function(v)
            Speed.set(v)
            speedToggle.Set(true, true)
        end,
        onCommit = function(v) Notify.push("WalkSpeed Updated: " .. num(v), "ok") end,
        onReset = function()
            Speed.reset()
            speedToggle.Set(false, true)
            speedSlider.Set(Speed.default, true)
            Notify.push("WalkSpeed Updated: reset to " .. num(Speed.default), "ok")
        end,
    })

    section(page, "JumpPower")
    local jumpToggle, jumpSlider
    jumpToggle = UI.toggle(page, "Custom JumpPower", false, function(on)
        if on then
            Jump.set(Jump.value)
            Notify.push("JumpPower Updated: " .. num(Jump.value), "ok")
        else
            Jump.disable()
            Notify.push("JumpPower restored: " .. num(Jump.default), "info")
        end
    end)
    jumpSlider = UI.slider(page, {
        label = "JumpPower", min = 0, max = 300, hardMax = 1000, value = Jump.value,
        onChange = function(v)
            Jump.set(v)
            jumpToggle.Set(true, true)
        end,
        onCommit = function(v) Notify.push("JumpPower Updated: " .. num(v), "ok") end,
        onReset = function()
            Jump.reset()
            jumpToggle.Set(false, true)
            jumpSlider.Set(Jump.default, true)
            Notify.push("JumpPower Updated: reset to " .. num(Jump.default), "ok")
        end,
    })
    note(page, "Karakter ber-JumpHeight dikonversi otomatis dari nilai JumpPower.")
end

local function buildCoords(page)
    section(page, "Current Position")
    local posCard = new("Frame", {
        Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Theme.card,
        BorderSizePixel = 0, LayoutOrder = nextOrder(page),
    }, page)
    corner(posCard, 8)
    local posLabel = new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "-",
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.text,
    }, posCard)
    UI.refs.posLabel = posLabel

    UI.refs.sharedToggle = UI.toggle(page, "Share list across all maps", Cfg.sharedCoords, function(on)
        Cfg.sharedCoords = on
        cfgSave()
        Coords.load()
        UI.refreshCoords()
        Notify.push(on and "Coordinates: shared on all maps" or "Coordinates: this map only", "info")
    end)

    section(page, "Save Position")
    local nameCard = new("Frame", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Theme.card,
        BorderSizePixel = 0, LayoutOrder = nextOrder(page),
    }, page)
    corner(nameCard, 8)
    local nameBox = new("TextBox", {
        Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0),
        BackgroundTransparency = 1, Text = "", PlaceholderText = "Location name (optional)",
        PlaceholderColor3 = Theme.sub, ClearTextOnFocus = false,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, nameCard)
    UI.button(page, "Save Position", "accent", function()
        if Coords.save(nameBox.Text) then nameBox.Text = "" end
    end, {order = nextOrder(page)})
    UI.button(page, "Return to Previous Position", "neutral", function()
        Coords.back()
    end, {order = nextOrder(page)})

    local savedTitle = section(page, "Saved Locations")
    local listFrame = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, LayoutOrder = nextOrder(page),
    }, page)
    new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, listFrame)

    function UI.refreshCoords()
        for _, c in ipairs(listFrame:GetChildren()) do
            if not c:IsA("UIListLayout") then c:Destroy() end
        end
        savedTitle.Text = "SAVED LOCATIONS (" .. #Coords.list .. ")"
        if #Coords.list == 0 then
            new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
                Text = "No saved locations yet.", Font = Enum.Font.Gotham,
                TextSize = 11, TextColor3 = Theme.sub,
            }, listFrame)
            return
        end
        for index, entry in ipairs(Coords.list) do
            local row = new("Frame", {
                Size = UDim2.new(1, 0, 0, 86), BackgroundColor3 = Theme.card,
                BorderSizePixel = 0, LayoutOrder = index,
            }, listFrame)
            corner(row, 8)
            local nameField = new("TextBox", {
                Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 0, 22),
                BackgroundColor3 = Theme.bg2, BorderSizePixel = 0, Text = entry.name,
                ClearTextOnFocus = false, Font = Enum.Font.GothamBold, TextSize = 12,
                TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left,
            }, row)
            corner(nameField, 6)
            new("UIPadding", {PaddingLeft = UDim.new(0, 8)}, nameField)
            nameField.FocusLost:Connect(function()
                local t = trim(nameField.Text)
                if t == "" or t == entry.name then
                    nameField.Text = entry.name
                else
                    Coords.rename(entry, t)
                end
            end)
            new("TextLabel", {
                Position = UDim2.fromOffset(10, 31), Size = UDim2.new(1, -20, 0, 16),
                BackgroundTransparency = 1, Text = "X, Y, Z:  " .. fmtCoords(entry),
                TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham,
                TextSize = 11, TextColor3 = Theme.sub,
            }, row)
            local btnRow = new("Frame", {
                Position = UDim2.fromOffset(8, 52), Size = UDim2.new(1, -16, 0, 28),
                BackgroundTransparency = 1,
            }, row)
            new("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }, btnRow)
            local bsize = UDim2.new(0.25, -3, 1, 0)
            UI.button(btnRow, "TP", "accentStatic", function()
                UI.confirm('Teleport to "' .. entry.name .. '"?', function() Coords.teleport(entry) end)
            end, {size = bsize, order = 1, textSize = 11})
            UI.button(btnRow, "Copy", "neutral", function() Coords.copy(entry) end,
                {size = bsize, order = 2, textSize = 11})
            UI.button(btnRow, "Rename", "neutral", function() nameField:CaptureFocus() end,
                {size = bsize, order = 3, textSize = 11})
            UI.button(btnRow, "Delete", "danger", function()
                UI.confirm('Delete "' .. entry.name .. '"?', function() Coords.delete(entry) end)
            end, {size = bsize, order = 4, textSize = 11})
        end
    end
    Theme.paint(function() UI.refreshCoords() end) -- warna tombol TP ikut aksen
end

local function buildGhost(page)
    section(page, "Ghost Mode")
    UI.refs.ghostToggle = UI.toggle(page, "Ghost Mode", false, function(on)
        if on then
            local p, err = Char.get()
            if not p then
                Notify.push("Ghost Mode failed: " .. tostring(err), "err")
                return false
            end
        end
        Ghost.set(on)
        Notify.push(on and "Ghost Mode Enabled" or "Ghost Mode Disabled", on and "ok" or "info")
    end)
    UI.slider(page, {
        label = "Ghost Transparency", min = 0.1, max = 0.9, value = Ghost.transparency,
        decimals = 2, onChange = Ghost.setTransparency,
    })
    UI.toggle(page, "Pass through objects (noclip)", true, function(on)
        Ghost.setNoclipOption(on)
    end)
    note(page, "Efek transparan hanya terlihat di layar kamu. Pass-through bersifat lokal; sebagian game bisa menolaknya. Semua properti dikembalikan saat Ghost Mode dimatikan.")
end

local function buildSettings(page)
    section(page, "Appearance")
    UI.refs.transSlider = UI.slider(page, {
        label = "Panel Transparency", min = 0, max = 0.6, value = Cfg.transparency, decimals = 2,
        onChange = function(v)
            Cfg.transparency = v
            UI.main.BackgroundTransparency = v
        end,
        onCommit = cfgSave,
    })
    UI.refs.scaleSlider = UI.slider(page, {
        label = "Menu Size", min = 0.7, max = 1.3, value = Cfg.scale, decimals = 2,
        onChange = function(v)
            Cfg.scale = v
            UI.applyAppearance()
        end,
        onCommit = cfgSave,
    })

    -- warna aksen
    local accCard = new("Frame", {
        Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Theme.card,
        BorderSizePixel = 0, LayoutOrder = nextOrder(page),
    }, page)
    corner(accCard, 8)
    new("TextLabel", {
        Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 18),
        BackgroundTransparency = 1, Text = "Accent Color", TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.text,
    }, accCard)
    local swatches = {}
    for i, a in ipairs(Theme.accents) do
        local sw = new("TextButton", {
            Position = UDim2.fromOffset(10 + (i - 1) * 34, 24), Size = UDim2.fromOffset(24, 24),
            BackgroundColor3 = a.color, Text = "", AutoButtonColor = false, BorderSizePixel = 0,
        }, accCard)
        corner(sw, 12)
        swatches[i] = stroke(sw, Color3.new(1, 1, 1), 2, 1)
        sw.MouseButton1Click:Connect(function()
            Sfx.click()
            Cfg.accent = i
            Theme.apply()
            cfgSave()
        end)
    end
    Theme.paint(function()
        for i, s in ipairs(swatches) do s.Transparency = (i == Cfg.accent) and 0 or 1 end
    end)

    -- posisi awal logo
    local logoCard = new("Frame", {
        Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = Theme.card,
        BorderSizePixel = 0, LayoutOrder = nextOrder(page),
    }, page)
    corner(logoCard, 8)
    new("TextLabel", {
        Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 18),
        BackgroundTransparency = 1, Text = "Logo Start Position", TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Theme.text,
    }, logoCard)
    local presetRow = new("Frame", {
        Position = UDim2.fromOffset(8, 26), Size = UDim2.new(1, -16, 0, 28), BackgroundTransparency = 1,
    }, logoCard)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, presetRow)
    local function preset(right, mid)
        local vp = UI.viewport()
        Cfg.logoX = right and ((vp.X - 56) / vp.X) or 0.015
        Cfg.logoY = mid and 0.45 or 0.2
        UI.applyLogoPos()
        cfgSave()
    end
    local psize = UDim2.new(0.25, -3, 1, 0)
    UI.button(presetRow, "Top L", "neutral", function() preset(false, false) end, {size = psize, order = 1, textSize = 11})
    UI.button(presetRow, "Top R", "neutral", function() preset(true, false) end, {size = psize, order = 2, textSize = 11})
    UI.button(presetRow, "Mid L", "neutral", function() preset(false, true) end, {size = psize, order = 3, textSize = 11})
    UI.button(presetRow, "Mid R", "neutral", function() preset(true, true) end, {size = psize, order = 4, textSize = 11})

    section(page, "Sound")
    UI.refs.soundToggle = UI.toggle(page, "UI Sounds", Cfg.sound, function(on)
        Cfg.sound = on
        cfgSave()
    end)

    UI.button(page, "Reset Settings", "danger", function()
        cfgReset()
        Theme.apply()
        UI.applyAppearance()
        UI.applyLogoPos()
        UI.refs.transSlider.Set(Cfg.transparency, true)
        UI.refs.scaleSlider.Set(Cfg.scale, true)
        UI.refs.soundToggle.Set(Cfg.sound, true)
        UI.refs.sharedToggle.Set(Cfg.sharedCoords, true)
        Coords.load()
        UI.refreshCoords()
        Notify.push("Settings Reset", "ok")
    end, {order = nextOrder(page)})

    section(page, "About")
    note(page, "EngszXecute v" .. VERSION .. "\nOwner: " .. OWNER_NAME .. "\nTarget: Roblox mobile / Delta Executor\nStorage: "
        .. (Storage.persistent and "saved to file (persistent)" or "session only (no file access)"))
end

----------------------------------------------------------------
-- 12. BUILD UI UTAMA
----------------------------------------------------------------
local PANEL_W, PANEL_H = 340, 252
local LOGO_SIZE = 46

local TABS = {
    {id = "movement", icon = "🏃", name = "Move",   build = buildMovement},
    {id = "coords",   icon = "📍", name = "Coords", build = buildCoords},
    {id = "ghost",    icon = "👻", name = "Ghost",  build = buildGhost},
    {id = "settings", icon = "⚙️", name = "Config", build = buildSettings},
}

function UI.effectiveScale()
    local vp = UI.viewport()
    return math.min(Cfg.scale, vp.X / (PANEL_W + 16), vp.Y / (PANEL_H + 16))
end

function UI.reclamp(target, size)
    local vp = UI.viewport()
    placeAt(target, target.Position.X.Scale * vp.X, target.Position.Y.Scale * vp.Y, size)
end

function UI.applyAppearance()
    UI.main.BackgroundTransparency = Cfg.transparency
    UI.scaler.Scale = UI.effectiveScale()
    UI.reclamp(UI.main, Vector2.new(PANEL_W, PANEL_H) * UI.scaler.Scale)
end

function UI.applyLogoPos()
    local vp = UI.viewport()
    placeAt(UI.logo, Cfg.logoX * vp.X, Cfg.logoY * vp.Y, Vector2.new(LOGO_SIZE, LOGO_SIZE))
end

function UI.setState(s)
    UI.state = s
    UI.main.Visible = (s == "open")
    UI.logo.Visible = (s ~= "hidden")
    UI.edge.Visible = (s == "hidden")
    if s == "hidden" then
        UI.edge.Position = UDim2.new(1, 0, math.clamp(UI.logo.Position.Y.Scale, 0, 0.85), 0)
    end
    if s ~= "open" then UI.overlay.Visible = false end
end

function UI.build()
    local gui = new("ScreenGui", {
        Name = "EngszXecute", ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    gui.Parent = getGuiParent()
    UI.gui = gui
    Root:Add(gui)

    local waited = 0
    while gui.AbsoluteSize.X <= 0 and waited < 2 do waited = waited + task.wait() end

    Sfx.init(gui)
    Notify.init(gui)

    -- Panel utama
    local main = new("Frame", {
        Name = "Panel", Size = UDim2.fromOffset(PANEL_W, PANEL_H), BackgroundColor3 = Theme.bg,
        BackgroundTransparency = Cfg.transparency, BorderSizePixel = 0, Active = true,
        ClipsDescendants = true,
    }, gui)
    UI.main = main
    UI.scaler = new("UIScale", {Scale = UI.effectiveScale()}, main)
    corner(main, 12)
    local mainStroke = stroke(main, Theme.accent(), 1.5, 0.35)
    Theme.paint(function(c) mainStroke.Color = c end)
    do
        local vp = UI.viewport()
        local w = PANEL_W * UI.scaler.Scale
        main.Position = UDim2.fromScale(math.max(0, (vp.X - w) / 2 / vp.X), 0.04)
    end

    -- Header (area drag)
    local header = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Theme.bg2, BorderSizePixel = 0,
    }, main)
    local title = new("TextLabel", {
        Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 170, 1, 0),
        BackgroundTransparency = 1, RichText = true, Text = "", Font = Enum.Font.GothamBlack,
        TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.text,
    }, header)
    Theme.paint(function(c)
        title.Text = 'ENGSZ<font color="#' .. c:ToHex() .. '">XECUTE</font>  <font size="9" color="#8a8aa0">v'
            .. VERSION .. "</font>"
    end)
    local function headerBtn(text, w, xFromRight, bg, onClick)
        local b = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, xFromRight, 0.5, 0),
            Size = UDim2.fromOffset(w, 22), BackgroundColor3 = bg, Text = text,
            TextColor3 = Theme.text, Font = Enum.Font.GothamBold, TextSize = 11,
            AutoButtonColor = true, BorderSizePixel = 0,
        }, header)
        corner(b, 6)
        b.MouseButton1Click:Connect(function()
            Sfx.click()
            onClick()
        end)
        return b
    end
    headerBtn("X", 26, -8, Theme.dangerBg, function()
        UI.confirm("Close EngszXecute? All features will be turned off.", function() destroyAll() end)
    end)
    headerBtn("Hide", 38, -40, Theme.off, function() UI.setState("hidden") end)
    headerBtn("-", 26, -84, Theme.off, function() UI.setState("minimized") end)

    -- Body: sidebar + konten
    local body = new("Frame", {
        Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34), BackgroundTransparency = 1,
    }, main)
    local sidebar = new("Frame", {
        Size = UDim2.new(0, 54, 1, 0), BackgroundColor3 = Theme.bg2, BorderSizePixel = 0,
    }, body)
    new("UIListLayout", {
        Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, sidebar)
    new("UIPadding", {PaddingTop = UDim.new(0, 6)}, sidebar)
    local content = new("Frame", {
        Position = UDim2.fromOffset(54, 0), Size = UDim2.new(1, -54, 1, 0),
        BackgroundTransparency = 1, ClipsDescendants = true,
    }, body)

    local pages, tabButtons = {}, {}
    local function selectTab(id)
        UI.activeTab = id
        for tid, p in pairs(pages) do p.Visible = (tid == id) end
        for tid, t in pairs(tabButtons) do t(tid == id) end
    end

    for i, t in ipairs(TABS) do
        local page = new("ScrollingFrame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
            Visible = false,
        }, content)
        Theme.paint(function(c) page.ScrollBarImageColor3 = c end)
        new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, page)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8),
        }, page)
        pages[t.id] = page

        local b = new("TextButton", {
            Size = UDim2.fromOffset(46, 44), BackgroundColor3 = Theme.card, BackgroundTransparency = 1,
            Text = "", AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = i,
        }, sidebar)
        corner(b, 8)
        new("TextLabel", {
            Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1, Text = t.icon, TextSize = 18, Font = Enum.Font.GothamMedium,
            TextColor3 = Theme.text,
        }, b)
        local nameL = new("TextLabel", {
            Position = UDim2.fromOffset(0, 29), Size = UDim2.new(1, 0, 0, 12),
            BackgroundTransparency = 1, Text = t.name, TextSize = 9, Font = Enum.Font.GothamBold,
            TextColor3 = Theme.sub,
        }, b)
        local bar = new("Frame", {
            Position = UDim2.new(0, 0, 0.5, -11), Size = UDim2.fromOffset(3, 22),
            BorderSizePixel = 0, Visible = false,
        }, b)
        corner(bar, 2)
        local function render(active)
            b.BackgroundTransparency = active and 0 or 1
            bar.Visible = active
            nameL.TextColor3 = active and Theme.accent() or Theme.sub
        end
        tabButtons[t.id] = render
        Theme.paint(function(c)
            bar.BackgroundColor3 = c
            render(UI.activeTab == t.id)
        end)
        b.MouseButton1Click:Connect(function()
            Sfx.click()
            selectTab(t.id)
        end)
        t.build(page)
    end

    -- Dialog konfirmasi (di dalam panel)
    local overlay = new("Frame", {
        Name = "Confirm", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.4, Visible = false, Active = true, ZIndex = 50, BorderSizePixel = 0,
    }, main)
    UI.overlay = overlay
    local card = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(250, 112), BackgroundColor3 = Theme.card, BorderSizePixel = 0,
    }, overlay)
    corner(card, 10)
    local cardStroke = stroke(card, Theme.accent(), 1.2, 0.3)
    Theme.paint(function(c) cardStroke.Color = c end)
    local msg = new("TextLabel", {
        Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 54), BackgroundTransparency = 1,
        Text = "", TextWrapped = true, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = Theme.text,
    }, card)
    local pending
    UI.button(card, "Yes", "accent", function()
        overlay.Visible = false
        local cb = pending
        pending = nil
        if cb then cb() end
    end, {size = UDim2.new(0.5, -16, 0, 30), order = 1}).Position = UDim2.new(0, 12, 1, -40)
    UI.button(card, "Cancel", "neutral", function()
        pending = nil
        overlay.Visible = false
    end, {size = UDim2.new(0.5, -16, 0, 30), order = 2}).Position = UDim2.new(0.5, 4, 1, -40)
    function UI.confirm(text, onYes)
        msg.Text = text
        pending = onYes
        overlay.Visible = true
    end

    makeDraggable(header, main)

    -- Logo mengambang
    local logo = new("TextButton", {
        Name = "Logo", Size = UDim2.fromOffset(LOGO_SIZE, LOGO_SIZE), BackgroundColor3 = Theme.bg,
        Position = UDim2.fromScale(Cfg.logoX, Cfg.logoY), Text = "EX", Font = Enum.Font.GothamBlack,
        TextSize = 17, TextColor3 = Theme.text, AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 5,
    }, gui)
    UI.logo = logo
    corner(logo, LOGO_SIZE / 2)
    local logoStroke = stroke(logo, Theme.accent(), 2, 0)
    Theme.paint(function(c)
        logoStroke.Color = c
        logo.TextColor3 = c
    end)
    makeDraggable(logo, logo, {
        onTap = function()
            Sfx.click()
            UI.setState(UI.state == "open" and "minimized" or "open")
        end,
        onDropped = function()
            Cfg.logoX = logo.Position.X.Scale
            Cfg.logoY = logo.Position.Y.Scale
            cfgSave()
        end,
    })

    -- Tab kecil di tepi layar untuk memunculkan kembali saat di-hide
    local edge = new("TextButton", {
        Name = "ShowTab", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0.2, 0),
        Size = UDim2.fromOffset(22, 56), BackgroundColor3 = Theme.bg, BackgroundTransparency = 0.25,
        Text = "<", Font = Enum.Font.GothamBlack, TextSize = 16, TextColor3 = Theme.text,
        AutoButtonColor = false, BorderSizePixel = 0, Visible = false, ZIndex = 5,
    }, gui)
    UI.edge = edge
    corner(edge, 8)
    local edgeStroke = stroke(edge, Theme.accent(), 1.5, 0.2)
    Theme.paint(function(c) edgeStroke.Color = c end)
    edge.MouseButton1Click:Connect(function()
        Sfx.click()
        UI.setState("open")
    end)

    -- Pad naik/turun untuk Fly (bisa digeser lewat handle atas)
    local pad = new("Frame", {
        Name = "FlyPad", Size = UDim2.fromOffset(56, 124), Position = UDim2.fromScale(0.85, 0.3),
        BackgroundColor3 = Theme.bg, BackgroundTransparency = 0.12, BorderSizePixel = 0,
        Visible = false, Active = true,
    }, gui)
    corner(pad, 10)
    local padStroke = stroke(pad, Theme.accent(), 1.5, 0.3)
    Theme.paint(function(c) padStroke.Color = c end)
    local grip = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, Text = "• • •",
        Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Theme.sub,
    }, pad)
    makeDraggable(grip, pad)
    local function holdButton(text, y, setter)
        local b = new("TextButton", {
            Position = UDim2.fromOffset(4, y), Size = UDim2.fromOffset(48, 44),
            BackgroundColor3 = Theme.off, BorderSizePixel = 0, Text = text,
            Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Theme.text, AutoButtonColor = false,
        }, pad)
        corner(b, 8)
        local held
        local function release()
            if held then
                held = nil
                setter(false)
            end
            b.BackgroundColor3 = Theme.off
        end
        b.InputBegan:Connect(function(input)
            if isPress(input) then
                held = input
                setter(true)
                b.BackgroundColor3 = Theme.accent()
            end
        end)
        Root:Add(UserInputService.InputEnded:Connect(function(input)
            if held and sameInput(input, held) then release() end
        end))
        return release
    end
    local releaseUp = holdButton("▲", 18, function(v) Fly.up = v end)
    local releaseDown = holdButton("▼", 72, function(v) Fly.down = v end)
    function UI.setFlyPad(visible)
        pad.Visible = visible
        if not visible then
            releaseUp()
            releaseDown()
        end
    end

    -- Update posisi live (ringan: 4x per detik, hanya saat tab Coords terlihat)
    local acc = 0
    Root:Add(RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        if UI.state == "open" and UI.activeTab == "coords" then
            local p = Char.get()
            UI.refs.posLabel.Text = p and string.format("X: %.1f   Y: %.1f   Z: %.1f",
                p.root.Position.X, p.root.Position.Y, p.root.Position.Z) or "Character not available"
        end
    end))

    -- Hotkey cadangan untuk PC (RightShift)
    Root:Add(UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.RightShift then
            UI.setState(UI.state == "open" and "hidden" or "open")
        end
    end))

    -- Layar berubah ukuran / rotasi
    Root:Add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        UI.applyAppearance()
        UI.applyLogoPos()
        UI.reclamp(pad, Vector2.new(56, 124))
    end))

    selectTab("movement")
    UI.applyLogoPos()
    UI.setState("open")
end

----------------------------------------------------------------
-- 13. SHUTDOWN & START
----------------------------------------------------------------
destroyAll = function()
    if not alive then return end
    pcall(Fly.set, false, true)
    pcall(Speed.disable)
    pcall(Jump.disable)
    pcall(Ghost.set, false)
    pcall(Storage.flush)
    alive = false
    Speed.maid:Clean()
    Jump.maid:Clean()
    Fly.maid:Clean()
    Ghost.maid:Clean()
    Ghost.noclipMaid:Clean()
    Root:Clean() -- semua koneksi global + ScreenGui
    if type(env.EngszXecute) == "table" and env.EngszXecute.Destroy == destroyAll then
        env.EngszXecute = nil
    end
end

Storage.load()
cfgLoad()
Coords.load()

local built, buildErr = pcall(UI.build)
if not built then
    warn("[EngszXecute] UI failed to build: " .. tostring(buildErr))
    destroyAll()
    return
end

Char.start()
env.EngszXecute = {Destroy = destroyAll, Version = VERSION}
if LocalPlayer.Name == OWNER_NAME or LocalPlayer.DisplayName == OWNER_NAME then
    Notify.push("Welcome, " .. OWNER_NAME .. "  |  EngszXecute v" .. VERSION, "ok")
else
    Notify.push("EngszXecute v" .. VERSION .. " loaded", "ok")
end
