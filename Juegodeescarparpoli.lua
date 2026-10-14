local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

-- Configuración de tu servicio
local KEY_LINK = "https://work.ink/3539/key-system"
local VALIDATE_URL = "https://work.ink/_api/v2/token/isValid/"

-- Función de validación con la API
local function isValidKey(key)
    if not key or key == "" then return false end
    
    local success, response = pcall(function()
        return game:HttpGet(VALIDATE_URL .. key)
    end)
    
    if success and response then
        local decodeSuccess, data = pcall(function()
            return HttpService:JSONDecode(response)
        end)
        
        if decodeSuccess and data then
            return data.valid == true or data.isValid == true
        elseif response:find('"valid":true') or response:find('"isValid":true') then
            return true
        end
    end
    return false
end

-- =========================================================
-- DISEÑO DE LA INTERFAZ MEJORADA (MODERNA / OSCURA)
-- =========================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WorkInkKeySystemPro"
ScreenGui.Parent = CoreGui

-- Fondo semi-transparente para oscurecer la pantalla de atrás
local BlurBackground = Instance.new("Frame")
BlurBackground.Size = UDim2.new(1, 0, 1, 0)
BlurBackground.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
BlurBackground.BackgroundTransparency = 0.5
BlurBackground.Parent = ScreenGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 420, 0, 240)
MainFrame.Position = UDim2.new(0.5, -210, 0.5, -120)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

-- Borde brillante decorativo
local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(88, 101, 242)
UIStroke.Thickness = 1.5
UIStroke.Transparency = 0.3
UIStroke.Parent = MainFrame

-- Título con estilo
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 50)
Title.Text = "  🔒 Sistema de Verificación - Auto Mob Farm"
Title.TextColor3 = Color3.fromRGB(240, 240, 255)
Title.TextSize = 16
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.BackgroundTransparency = 1
Title.Position = UDim2.new(0, 20, 0, 0)
Title.Parent = MainFrame

-- Línea divisoria elegante
local Divider = Instance.new("Frame")
Divider.Size = UDim2.new(1, -40, 0, 1)
Divider.Position = UDim2.new(0, 20, 0, 50)
Divider.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
Divider.BorderSizePixel = 0
Divider.Parent = MainFrame

-- Caja de Texto (TextBox) para la Key
local TextBox = Instance.new("TextBox")
TextBox.Size = UDim2.new(1, -40, 0, 45)
TextBox.Position = UDim2.new(0, 20, 0, 75)
TextBox.PlaceholderText = "Introduce tu Key aquí..."
TextBox.Text = ""
TextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
TextBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 140)
TextBox.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
TextBox.Font = Enum.Font.Gotham
TextBox.TextSize = 14
TextBox.Parent = MainFrame

local TextBoxCorner = Instance.new("UICorner")
TextBoxCorner.CornerRadius = UDim.new(0, 8)
TextBoxCorner.Parent = TextBox

local TextBoxStroke = Instance.new("UIStroke")
TextBoxStroke.Color = Color3.fromRGB(50, 50, 65)
TextBoxStroke.Parent = TextBox

-- Botón Verificar (Color Azul Neón)
local VerifyBtn = Instance.new("TextButton")
VerifyBtn.Size = UDim2.new(0.48, 0, 0, 40)
VerifyBtn.Position = UDim2.new(0, 20, 0, 135)
VerifyBtn.Text = "Verificar Key"
VerifyBtn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
VerifyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
VerifyBtn.Font = Enum.Font.GothamBold
VerifyBtn.TextSize = 14
VerifyBtn.Parent = MainFrame

local VerifyCorner = Instance.new("UICorner")
VerifyCorner.CornerRadius = UDim.new(0, 8)
VerifyCorner.Parent = VerifyBtn

-- Botón Obtener Link (Gris Oscuro)
local GetKeyBtn = Instance.new("TextButton")
GetKeyBtn.Size = UDim2.new(0.48, 0, 0, 40)
GetKeyBtn.Position = UDim2.new(0.52, -20, 0, 135)
GetKeyBtn.Text = "Copiar Enlace"
GetKeyBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
GetKeyBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
GetKeyBtn.Font = Enum.Font.GothamMedium
GetKeyBtn.TextSize = 14
GetKeyBtn.Parent = MainFrame

local GetKeyCorner = Instance.new("UICorner")
GetKeyCorner.CornerRadius = UDim.new(0, 8)
GetKeyCorner.Parent = GetKeyBtn

-- Mensaje de Estado
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -40, 0, 25)
StatusLabel.Position = UDim2.new(0, 20, 0, 190)
StatusLabel.Text = "Obtén tu key completando los pasos del enlace"
StatusLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
StatusLabel.TextSize = 12
StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = MainFrame

-- Funciones de animación simple para los botones
local function applyHover(btn, originalColor, hoverColor)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = hoverColor}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = originalColor}):Play()
    end)
end

applyHover(VerifyBtn, Color3.fromRGB(88, 101, 242), Color3.fromRGB(108, 121, 255))
applyHover(GetKeyBtn, Color3.fromRGB(35, 35, 45), Color3.fromRGB(48, 48, 60))

-- Copiar enlace al portapapeles
GetKeyBtn.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard(KEY_LINK)
        StatusLabel.Text = "✔ ¡Enlace copiado al portapapeles con éxito!"
        StatusLabel.TextColor3 = Color3.fromRGB(80, 250, 123)
    else
        StatusLabel.Text = "Enlace: " .. KEY_LINK
    end
end)

-- Acción del botón Verificar
VerifyBtn.MouseButton1Click:Connect(function()
    local enteredKey = TextBox.Text
    StatusLabel.Text = "⏳ Comprobando clave con Work.ink..."
    StatusLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
    
    task.spawn(function()
        if isValidKey(enteredKey) then
            StatusLabel.Text = "✔ ¡Key Válida! Iniciando script..."
            StatusLabel.TextColor3 = Color3.fromRGB(80, 250, 123)
            task.wait(1)
            
            ScreenGui:Destroy() -- Cierra la ventana de la key
            
            -------------------------------------------------------------
            -- PEGA AQUÍ EL CÓDIGO DE TU SCRIPT PRINCIPAL (AUTO FARM) --
            -------------------------------------------------------------
            print("¡Script ejecutado correctamente!")
            
        else
            StatusLabel.Text = "✖ Key incorrecta o expirada. Genera una nueva."
            StatusLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
        end
    end)
end)
