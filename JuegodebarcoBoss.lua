---------------------------------------------------------------
-- UI (compacta, táctil)
---------------------------------------------------------------
local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local BG = Color3.fromRGB(18, 20, 28)
local CARD = Color3.fromRGB(30, 33, 46)
local GREEN = Color3.fromRGB(80, 200, 130)
local RED = Color3.fromRGB(225, 85, 95)
local TEXT = Color3.fromRGB(240, 242, 250)
local MUTED = Color3.fromRGB(140, 146, 170)

local gui = mk("ScreenGui", { Name = "BossHunterUI", ResetOnSpawn = false }, LocalPlayer:WaitForChild("PlayerGui"))
local main = mk("Frame", {
    Size = UDim2.fromOffset(150, 108), Position = UDim2.new(0, 8, 0.3, 0),
    BackgroundColor3 = BG, BorderSizePixel = 0, Active = true, Draggable = true,
}, gui)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, main)

mk("TextLabel", {
    Size = UDim2.new(1, -28, 0, 14), Position = UDim2.new(0, 6, 0, 4),
    BackgroundTransparency = 1, Text = "Bosses", TextColor3 = TEXT,
    TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local statusLbl = mk("TextLabel", {
    Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, 18),
    BackgroundTransparency = 1, TextColor3 = MUTED, TextSize = 8,
    Font = Enum.Font.Gotham, TextTruncate = Enum.TextTruncate.AtEnd,
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local function boton(pos, size, color, textSize, onClick)
    local b = mk("TextButton", {
        Position = pos, Size = size, BackgroundColor3 = color,
        TextColor3 = TEXT, TextSize = textSize, Font = Enum.Font.GothamBold, BorderSizePixel = 0,
    }, main)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    b.Activated:Connect(onClick)
    return b
end

local bossBtn = boton(UDim2.new(0, 6, 0, 34), UDim2.new(1, -12, 0, 22), CARD, 9, function()
    bossIndex = bossIndex % #BOSSES + 1
end)

local toggleBtn = boton(UDim2.new(0, 6, 0, 60), UDim2.new(1, -12, 0, 26), GREEN, 10, function()
    cazando = not cazando
    if not cazando then
        setHover(false)
        setStatus("Caza detenida")
    end
end)

local killsLbl = mk("TextLabel", {
    Size = UDim2.new(1, -12, 0, 12), Position = UDim2.new(0, 6, 0, 90),
    BackgroundTransparency = 1, TextColor3 = TEXT, TextSize = 8, Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local closeBtn = boton(UDim2.new(1, -20, 0, 3), UDim2.fromOffset(17, 17), RED, 9, function()
    closed = true
    cazando = false
    setHover(false)
    gui:Destroy()
end)
closeBtn.Text = "✕"
