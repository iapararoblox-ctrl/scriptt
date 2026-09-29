local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- Crear ScreenGui Principal
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ServerBrowserGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Icono Flotante para Reabrir
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.Size = UDim2.new(0, 50, 0, 50)
toggleButton.Position = UDim2.new(0.02, 0, 0.4, 0)
toggleButton.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Text = "🌐"
toggleButton.TextSize = 24
toggleButton.Visible = false
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim2.new(0, 12)
toggleCorner.Parent = toggleButton

-- Panel Principal
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0.85, 0, 0.7, 0) 
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
mainFrame.Parent = screenGui

local uiAspectRatio = Instance.new("UIAspectRatioConstraint")
uiAspectRatio.AspectRatio = 1.4
uiAspectRatio.AspectType = Enum.AspectType.FitWithinMaxSize
uiAspectRatio.Parent = mainFrame

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim2.new(0, 10)
frameCorner.Parent = mainFrame

-- Barra Superior
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
titleBar.Parent = mainFrame

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim2.new(0, 10)
titleCorner.Parent = titleBar

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(0.7, 0, 1, 0)
titleText.Position = UDim2.new(0.03, 0, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "Servidores Activos"
titleText.TextColor3 = Color3.fromRGB(255, 255, 255)
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.TextScaled = true
titleText.Parent = titleBar

-- Botón Cerrar
local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 30, 0, 30)
closeButton.Position = UDim2.new(0.98, -30, 0.5, -15)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextScaled = true
closeButton.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim2.new(0, 6)
closeCorner.Parent = closeButton

-- Contenedor de lista
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(0.94, 0, 0.8, 0)
scrollFrame.Position = UDim2.new(0.03, 0, 0.16, 0)
scrollFrame.BackgroundTransparency = 1
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent = mainFrame

local uiListLayout = Instance.new("UIListLayout")
uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
uiListLayout.Padding = UDim.new(0, 8)
uiListLayout.Parent = scrollFrame

-- Eventos de visibilidad
closeButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
    toggleButton.Visible = true
end)

toggleButton.MouseButton1Click:Connect(function()
    mainFrame.Visible = true
    toggleButton.Visible = false
end)

-- Función para Obtener y Mostrar Servidores Activos
local function loadServers()
    for _, child in pairs(scrollFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local placeId = game.PlaceId
    local currentJobId = game.JobId

    -- SOLUCIÓN 1: URL corregida a /servers/Public
    local success, response = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=25"
        return game:HttpGet(url)
    end)

    if success and response then
        local data = HttpService:JSONDecode(response)
        
        if data and data.data then
            for _, server in ipairs(data.data) do
                if server.id ~= currentJobId and server.playing < server.maxPlayers then
                    
                    local serverCard = Instance.new("Frame")
                    serverCard.Size = UDim2.new(1, 0, 0, 45)
                    serverCard.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
                    serverCard.Parent = scrollFrame

                    local cardCorner = Instance.new("UICorner")
                    cardCorner.CornerRadius = UDim2.new(0, 6)
                    cardCorner.Parent = serverCard

                    local infoText = Instance.new("TextLabel")
                    infoText.Size = UDim2.new(0.65, 0, 1, 0)
                    infoText.Position = UDim2.new(0.03, 0, 0, 0)
                    infoText.BackgroundTransparency = 1
                    infoText.Text = "Jugadores: " .. server.playing .. "/" .. server.maxPlayers .. " | Ping: " .. (server.ping or "N/A") .. "ms"
                    infoText.TextColor3 = Color3.fromRGB(220, 220, 220)
                    infoText.TextScaled = true
                    infoText.TextXAlignment = Enum.TextXAlignment.Left
                    infoText.Parent = serverCard

                    local joinButton = Instance.new("TextButton")
                    joinButton.Size = UDim2.new(0.28, 0, 0.7, 0)
                    joinButton.Position = UDim2.new(0.7, 0, 0.15, 0)
                    joinButton.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
                    joinButton.Text = "Unirse"
                    joinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                    joinButton.TextScaled = true
                    joinButton.Parent = serverCard

                    local joinCorner = Instance.new("UICorner")
                    joinCorner.CornerRadius = UDim2.new(0, 6)
                    joinCorner.Parent = joinButton

                    joinButton.MouseButton1Click:Connect(function()
                        joinButton.Text = "Teleport..."
                        TeleportService:TeleportToPlaceInstance(placeId, server.id, LocalPlayer)
                    end)
                end
            end

            -- SOLUCIÓN 2: Espera breve para que Roblox procese los tamaños antes de ajustar el Canvas
            task.wait(0.1)
            scrollFrame.CanvasSize = UDim2.new(0, 0, 0, uiListLayout.AbsoluteContentSize.Y + 10)
        end
    end
end

-- Cargar servidores
loadServers()
