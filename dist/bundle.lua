local __DARKLUA_BUNDLE_MODULES={cache={}::any}do do local function __modImpl()local Engine = {}
Engine.Holding = {}
Engine.Processed = setmetatable({}, { __mode = "k" })

-- Carga segura de los enumeradores del juego
local NoteResult = { Okay = 1, Great = 2, Perfect = 3, Miss = 4 }
pcall(function()
    NoteResult = require(game.ReplicatedStorage:WaitForChild("LiteriaRGameCore", 1).Enums.NoteResult)
end)
if not NoteResult or not NoteResult.Perfect then
    pcall(function()
        NoteResult = require(game.ReplicatedStorage:WaitForChild("RobeatsGameCore", 1).Enums.NoteResult)
    end)
end
if not NoteResult or not NoteResult.Perfect then
    NoteResult = { Okay = 1, Great = 2, Perfect = 3, Miss = 4 }
end

function Engine.releaseAll(trackSys)
    if trackSys then
        for tIdx = 1, 4 do
            pcall(function() trackSys:release_track_index(tIdx) end)
        end
    end
    table.clear(Engine.Holding)
end

function Engine.isAlive(ts)
    if not ts or type(ts) ~= "table" then return false end
    local ok, res = pcall(function()
        local t1 = ts:get_track(1)
        return t1 and t1.get_track_obj and t1:get_track_obj():IsDescendantOf(workspace)
    end)
    return ok and res == true
end

function Engine.findGame()
    local localElements = workspace:FindFirstChild("LocalElements")
    local proto = localElements and localElements:FindFirstChild("NoteTrackSystemProto")
    if not proto then return nil, nil end

    if not getgc then return nil, nil end

    local foundTS, foundAM = nil, nil
    for _, obj in ipairs(getgc(true)) do
        if type(obj) == "table" then
            if not foundTS and rawget(obj, "get_notes") and rawget(obj, "press_track_index") then
                if Engine.isAlive(obj) then
                    foundTS = obj
                end
            end
            if not foundAM and rawget(obj, "get_bgm") and rawget(obj, "get_mode") and rawget(obj, "load_song") then
                local ok, mode = pcall(function() return obj:get_mode() end)
                if ok and mode and mode >= 1 and mode <= 5 then
                    foundAM = obj
                end
            end
            if foundTS and foundAM then break end
        end
    end

    return foundTS, foundAM
end

function Engine.step(trackSys, audioMgr)
    local isPlaying, isFinished = false, false
    pcall(function()
        isPlaying = audioMgr:is_playing()
        isFinished = audioMgr:is_finished()
    end)

    if isFinished or not isPlaying then return isFinished end

    -- 1. Control de soltado exacto en notas sostenidas activas
    for tIdx, heldNote in pairs(Engine.Holding) do
        local shouldRelease = false
        pcall(function()
            if not heldNote or heldNote:should_remove() then
                shouldRelease = true
            else
                local canRelease, relRating = heldNote:test_release()
                -- Soltar únicamente cuando la cola esté en ventana Perfect o Great
                if canRelease and (relRating == NoteResult.Perfect or relRating == 3 or relRating == NoteResult.Great or relRating == 2) then
                    shouldRelease = true
                end
            end
        end)

        if shouldRelease then
            pcall(function() trackSys:release_track_index(tIdx) end)
            Engine.Holding[tIdx] = nil
        end
    end

    -- 2. Procesamiento de notas en pista
    local notesList
    pcall(function() notesList = trackSys:get_notes() end)
    if not notesList then return false end

    local count = 0
    pcall(function() count = notesList:count() end)
    if count == 0 then return false end

    for i = 1, count do
        local note
        pcall(function() note = notesList:get(i) end)

        if note and not note:should_remove() and not Engine.Processed[note] then
            local tIdx = note:get_track_index()

            -- NOTA SIMPLE (SingleNote)
            if note.ClassName == "SingleNote" then
                local canHit, rating = note:test_hit()

                -- Se impacta en cuanto el motor nativo confirme Perfect (o Great si hubo un pico de lag)
                if canHit and (rating == NoteResult.Perfect or rating == 3 or rating == NoteResult.Great or rating == 2) then
                    Engine.Processed[note] = true
                    
                    -- Asegurar que el receptor no esté bloqueado antes de registrar el impacto
                    pcall(function() trackSys:release_track_index(tIdx) end)
                    trackSys:press_track_index(tIdx)
                    
                    task.defer(function()
                        if not Engine.Holding[tIdx] then
                            pcall(function() trackSys:release_track_index(tIdx) end)
                        end
                    end)
                end

            -- NOTA SOSTENIDA (HeldNote)
            elseif note.ClassName == "HeldNote" then
                if not Engine.Holding[tIdx] then
                    local canHit, rating = note:test_hit()
                    if canHit and (rating == NoteResult.Perfect or rating == 3 or rating == NoteResult.Great or rating == 2) then
                        Engine.Processed[note] = true
                        Engine.Holding[tIdx] = note
                        
                        pcall(function() trackSys:release_track_index(tIdx) end)
                        trackSys:press_track_index(tIdx)
                    end
                end
            end
        end
    end

    return false
end

return Engine end function __DARKLUA_BUNDLE_MODULES.a():typeof(__modImpl())local v=__DARKLUA_BUNDLE_MODULES.cache.a if not v then v={c=__modImpl()}__DARKLUA_BUNDLE_MODULES.cache.a=v end return v.c end end do local function __modImpl()
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
    frame.Size = UDim2.new(0, 180, 0, 85)
    frame.Position = UDim2.new(0.5, -90, 0.15, 0)
    frame.BackgroundColor3 = Color3.fromRGB(20, 21, 26)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(45, 48, 58)
    stroke.Thickness = 1.2
    stroke.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 22)
    label.Position = UDim2.new(0, 0, 0, 4)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.Text = "AUTOPLAY • [F4]"
    label.TextColor3 = Color3.fromRGB(200, 205, 215)
    label.TextSize = 11
    label.Parent = frame

    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(1, -20, 0, 36)
    toggleBtn.Position = UDim2.new(0, 10, 0, 34)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 60)
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.Text = "OFF"
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.TextSize = 13
    toggleBtn.AutoButtonColor = false
    toggleBtn.Parent = frame

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = toggleBtn

    local isEnabled = false
    toggleBtn.MouseButton1Click:Connect(function()
        isEnabled = not isEnabled
        if isEnabled then
            toggleBtn.Text = "ON"
            toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 75)
        else
            toggleBtn.Text = "OFF"
            toggleBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 60)
        end
        onToggle(isEnabled)
    end)

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.F4 or input.KeyCode == Enum.KeyCode.RightShift then
            frame.Visible = not frame.Visible
        end
    end)

    return screenGui
end

return Window end function __DARKLUA_BUNDLE_MODULES.b():typeof(__modImpl())local v=__DARKLUA_BUNDLE_MODULES.cache.b if not v then v={c=__modImpl()}__DARKLUA_BUNDLE_MODULES.cache.b=v end return v.c end end end
local RunService = game:GetService("RunService")
local Engine = __DARKLUA_BUNDLE_MODULES.a()
local Window = __DARKLUA_BUNDLE_MODULES.b()

local Autoplay = {
    Enabled = false,
    TrackSystem = nil,
    AudioManager = nil,
    Connection = nil,
}

local function stopPlayback()
    if Autoplay.Connection then
        Autoplay.Connection:Disconnect()
        Autoplay.Connection = nil
    end
    Engine.releaseAll(Autoplay.TrackSystem)
    table.clear(Engine.Processed)
    Autoplay.TrackSystem = nil
    Autoplay.AudioManager = nil
end

local function onRenderStep()
    if not Autoplay.Enabled then
        stopPlayback()
        return
    end

    if not Engine.isAlive(Autoplay.TrackSystem) or not Autoplay.AudioManager then
        stopPlayback()
        return
    end

    local finished = Engine.step(Autoplay.TrackSystem, Autoplay.AudioManager)
    if finished then
        stopPlayback()
    end
end

-- Supervisor pasivo para enganchar partidas
task.spawn(function()
    while true do
        task.wait(0.5)
        if Autoplay.Enabled and not Autoplay.Connection then
            local ts, am = Engine.findGame()
            if ts and am then
                Autoplay.TrackSystem = ts
                Autoplay.AudioManager = am
                Autoplay.Connection = RunService.RenderStepped:Connect(onRenderStep)
            end
        end
    end
end)

Window.create(function(enabled)
    Autoplay.Enabled = enabled
    if not enabled then
        stopPlayback()
    end
end)