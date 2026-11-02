local Window = {}

function Window.create(onToggle)
    local CoreGui = game:GetService("CoreGui")
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local parent = pcall(function() return CoreGui end) and CoreGui or Players.LocalPlayer:WaitForChild("PlayerGui")

    if parent:FindFirstChild("LiteriaR_MiniAutoplay") then
        parent.LiteriaR_MiniAutoplay:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LiteriaR_MiniAutoplay"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = parent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 190, 0, 105)
    frame.Position = UDim2.new(0.5, -95, 0.12, 0)
    frame.BackgroundColor3 = Color3.fromRGB(18, 19, 23)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(40, 44, 52)
    stroke.Thickness = 1.2
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 22)
    title.Position = UDim2.new(0, 0, 0, 4)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "AUTOPLAY • 99% FC [F4]"
    title.TextColor3 = Color3.fromRGB(190, 195, 205)
    title.TextSize = 10
    title.Parent = frame

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(1, -20, 0, 32)
    toggleBtn.Position = UDim2.new(0, 10, 0, 28)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(215, 45, 55)
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.Text = "OFF"
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.TextSize = 12
    toggleBtn.AutoButtonColor = false
    toggleBtn.Parent = frame

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = toggleBtn

    local statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(1, -20, 0, 34)
    statsLabel.Position = UDim2.new(0, 10, 0, 64)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Font = Enum.Font.Code
    statsLabel.Text = "ACC: 100.00% | P:0 G:0"
    statsLabel.TextColor3 = Color3.fromRGB(120, 180, 255)
    statsLabel.TextSize = 10
    statsLabel.Parent = frame

    local isEnabled = false
    toggleBtn.MouseButton1Click:Connect(function()
        isEnabled = not isEnabled
        toggleBtn.Text = isEnabled and "ON" or "OFF"
        toggleBtn.BackgroundColor3 = isEnabled and Color3.fromRGB(35, 175, 70) or Color3.fromRGB(215, 45, 55)
        onToggle(isEnabled)
    end)

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.F4 or input.KeyCode == Enum.KeyCode.RightShift then
            frame.Visible = not frame.Visible
        end
    end)

    return {
        Gui = screenGui,
        StatsLabel = statsLabel
    }
end

return Window