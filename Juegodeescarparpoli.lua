-- ========================================================
-- AUTOFARM & UTILITIES GUI - ROBLOX
-- Creado a partir del volcado de instancias del juego
-- ========================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- Remotos del juego identificados
local Remotes = {
    ClaimEarnings = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Server"):WaitForChild("ClaimEarnings"),
    ClaimAllEarnings = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Server"):WaitForChild("ClaimAllEarnings"),
    Rebirth = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Server"):WaitForChild("Rebirth"),
    ClaimSpeedBoost = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Server"):WaitForChild("ClaimSpeedBoost")
}

-- Variables de Estado
local AutoClaim = false
local AutoSteal = false
local AutoRebirth = false

-- ========================================================
-- CREACIÓN DE INTERFAZ GRÁFICA (GUI)
-- ========================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CustomGameHub"
ScreenGui.ResetOnSpawn = false

-- Intentar colocar en CoreGui para mayor protección en ejecutores
local Success, _ = pcall(function()
    ScreenGui.Parent = game:GetService("CoreGui")
end)
if not Success then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 220, 0, 310)
MainFrame.Position = UDim2.new(0.05, 0, 0.3, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true -- Permite mover la ventana
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(0, 170, 255)
UIStroke.Thickness = 2
UIStroke.Parent = MainFrame

-- Título
local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(1, 0, 0, 35)
Title.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
Title.Text = "HUB DE JUEGO v1.0"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 14
Title.Font = Enum.Font.SourceSansBold
Title.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 8)
TitleCorner.Parent = Title

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Parent = MainFrame
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 6)
UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

Title.LayoutOrder = 0

-- Función Auxiliar para Crear Botones
local function CreateButton(text, order, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0.9, 0, 0, 35)
    Btn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    Btn.Text = text
    Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    Btn.TextSize = 13
    Btn.Font = Enum.Font.SourceSansSemibold
    Btn.LayoutOrder = order
    Btn.Parent = MainFrame

    local BtnCorner = Instance.new("UICorner")
    BtnCorner.CornerRadius = UDim.new(0, 6)
    BtnCorner.Parent = Btn

    Btn.MouseButton1Click:Connect(function()
        callback(Btn)
    end)
    return Btn
end

-- ========================================================
-- FUNCIONES Y BOTONES
-- ========================================================

-- 1. Auto Recolectar Ganancias (Claim Cash)
CreateButton("Auto Claim Cash: OFF", 1, function(btn)
    AutoClaim = not AutoClaim
    btn.Text = "Auto Claim Cash: " .. (AutoClaim and "ON" or "OFF")
    btn.BackgroundColor3 = AutoClaim and Color3.fromRGB(0, 150, 75) or Color3.fromRGB(45, 45, 55)
    
    task.spawn(function()
        while AutoClaim do
            pcall(function()
                Remotes.ClaimAllEarnings:FireServer()
                Remotes.ClaimEarnings:FireServer()
            end)
            task.wait(1.5)
        end
    end)
end)

-- 2. Auto Robar / Recoger Items Cercanos
CreateButton("Auto Robar (Steal): OFF", 2, function(btn)
    AutoSteal = not AutoSteal
    btn.Text = "Auto Robar (Steal): " .. (AutoSteal and "ON" or "OFF")
    btn.BackgroundColor3 = AutoSteal and Color3.fromRGB(0, 150, 75) or Color3.fromRGB(45, 45, 55)
    
    task.spawn(function()
        while AutoSteal do
            pcall(function()
                for _, desc in ipairs(Workspace:GetDescendants()) do
                    if desc:IsA("ProximityPrompt") and desc.Enabled then
                        if desc.ActionText == "Steal?" or desc.ActionText == "Pickup" or desc.ObjectText == "Steal?" then
                            fireproximityprompt(desc)
                        end
                    end
                end
            end)
            task.wait(0.5)
        end
    end)
end)

-- 3. Teleport a Plot / Base Propia
CreateButton("Teleport a Mi Plot", 3, function()
    local character = LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        local plots = Workspace:FindFirstChild("Plots")
        if plots then
            for _, plot in ipairs(plots:GetChildren()) do
                local spawnpoint = plot:FindFirstChild("Spawnpoint")
                if spawnpoint then
                    -- Teletransportar al punto de aparición de la parcela
                    character.HumanoidRootPart.CFrame = spawnpoint.CFrame + Vector3.new(0, 3, 0)
                    break
                end
            end
        end
    end
end)

-- 4. Auto Rebirth
CreateButton("Auto Rebirth: OFF", 4, function(btn)
    AutoRebirth = not AutoRebirth
    btn.Text = "Auto Rebirth: " .. (AutoRebirth and "ON" or "OFF")
    btn.BackgroundColor3 = AutoRebirth and Color3.fromRGB(0, 150, 75) or Color3.fromRGB(45, 45, 55)
    
    task.spawn(function()
        while AutoRebirth do
            pcall(function()
                Remotes.Rebirth:FireServer()
            end)
            task.wait(3)
        end
    end)
end)

-- 5. reclamar Boost de Velocidad
CreateButton("Reclamar Speed Boost", 5, function()
    pcall(function()
        Remotes.ClaimSpeedBoost:FireServer()
    end)
end)

print("¡GUI cargada correctamente!")
