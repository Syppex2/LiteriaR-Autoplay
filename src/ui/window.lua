local Window = {}

function Window.create(onToggle)
    local CoreGui = game:GetService("CoreGui")
    local Players = game:GetService("Players")
    local parent = pcall(function() return CoreGui end) and CoreGui or Players.LocalPlayer:WaitForChild("PlayerGui")
    
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoplayUI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = parent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 90)
    frame.Position = UDim2.new(0.5, -100, 0.2, 0)
    frame.BackgroundColor3 = Color3.fromRGB(24, 25, 30)
    frame.Active = true
    frame.Draggable = true
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 40)
    btn.Position = UDim2.new(0, 10, 0, 35)
    btn.BackgroundColor3 = Color3.fromRGB(220, 50, 60)
    btn.Text = "AUTOPLAY: OFF"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.Parent = frame

    local state = false
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.Text = state and "AUTOPLAY: ON" or "AUTOPLAY: OFF"
        btn.BackgroundColor3 = state and Color3.fromRGB(40, 180, 75) or Color3.fromRGB(220, 50, 60)
        onToggle(state)
    end)

    return {
        Gui = screenGui,
        Frame = frame
    }
end

return Window