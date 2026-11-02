local Engine = {}
Engine.Holding = {}
Engine.Processed = setmetatable({}, { __mode = "k" })
Engine.NotePlan = setmetatable({}, { __mode = "k" })

-- ====================================================================
-- CONFIGURACIÓN DEL REGULADOR DINÁMICO 99.#%
-- ====================================================================
Engine.Config = {
    MaxAccuracy = 99.65,       -- Si el acc sube a >= 99.65%, programa un Great
    MinAccuracy = 99.10,       -- Si el acc cae a <= 99.10%, restringe a Perfect estricto
    InitialGreatNote = 22,     -- Fuerza el primer Great en la nota 22 para salir del 100%
    GreatCooldownSec = 3.0,    -- Tiempo mínimo entre Greats para no afectar acordes
    PerfectJitterMin = -7,     -- ms tarde en Perfect (sobre la barra)
    PerfectJitterMax = 2,      -- ms temprano en Perfect (sobre la barra)
}

Engine.Stats = {
    Perfects = 0,
    Greats = 0,
    Total = 0,
}
Engine.LastGreatTime = 0

-- Enumerador oficial de LiteriaR / RoBeats: Okay = 1, Great = 2, Perfect = 3, Miss = 4
local NoteResult = { Okay = 1, Great = 2, Perfect = 3, Miss = 4 }
pcall(function()
    local core = game.ReplicatedStorage:FindFirstChild("LiteriaRGameCore") or game.ReplicatedStorage:FindFirstChild("RobeatsGameCore")
    if core and core:FindFirstChild("Enums") and core.Enums:FindFirstChild("NoteResult") then
        local loaded = require(core.Enums.NoteResult)
        if type(loaded) == "table" and loaded.Perfect ~= nil then
            NoteResult = loaded
        end
    end
end)

local function isPerfect(rating)
    return rating == NoteResult.Perfect or rating == 3
end

local function isGreat(rating)
    return rating == NoteResult.Great or rating == 2
end

-- Duración exacta de nota sostenida en segundos
local function getNoteDurationSec(note)
    local dur = 0
    pcall(function()
        if note.get_duration then
            dur = note:get_duration()
        elseif note.get_hold_duration then
            dur = note:get_hold_duration()
        elseif note._duration then
            dur = note._duration
        end
    end)
    if type(dur) == "number" then
        if dur > 50 then return dur / 1000 end
        return dur
    end
    return 0
end

-- Lector robusto de distancia a la barra receptora en milisegundos
local function getTimeToEnd(note, audioMgr)
    local t = nil
    pcall(function()
        if note.get_time_to_end then
            t = note:get_time_to_end()
        end
    end)
    if t ~= nil and type(t) == "number" and math.abs(t) < 5000 then
        return t
    end

    pcall(function()
        local noteTime = note:get_time()
        local songTime = nil
        if audioMgr.get_song_time_ms then
            songTime = audioMgr:get_song_time_ms()
        elseif audioMgr.get_current_time_ms then
            songTime = audioMgr:get_current_time_ms()
        elseif audioMgr.get_time_ms then
            songTime = audioMgr:get_time_ms()
        end

        if noteTime and songTime then
            if songTime < 1000 and noteTime > 1000 then
                songTime = songTime * 1000
            end
            t = noteTime - songTime
        end
    end)

    return t
end

function Engine.calculate_accuracy()
    if Engine.Stats.Total == 0 then return 100 end
    local score = (Engine.Stats.Perfects * 1.0) + (Engine.Stats.Greats * 0.75)
    return (score / Engine.Stats.Total) * 100
end

function Engine.releaseAll(trackSys)
    if trackSys then
        for tIdx = 1, 4 do
            pcall(function() trackSys:release_track_index(tIdx) end)
        end
    end
    table.clear(Engine.Holding)
    table.clear(Engine.NotePlan)
    table.clear(Engine.Processed)
    Engine.Stats.Perfects = 0
    Engine.Stats.Greats = 0
    Engine.Stats.Total = 0
    Engine.LastGreatTime = 0
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

    -- ====================================================================
    -- 1. GESTIÓN ASÍNCRONA DE NOTAS SOSTENIDAS (HeldNotes)
    -- ====================================================================
    for tIdx, holdData in pairs(Engine.Holding) do
        local heldNote = holdData.Note
        local shouldRelease = false

        local isDead = false
        pcall(function()
            if not heldNote or heldNote:should_remove() then
                isDead = true
            end
        end)

        if isDead then
            shouldRelease = true
        else
            local canRelease, relRating = false, 0
            pcall(function()
                if heldNote.test_release then
                    canRelease, relRating = heldNote:test_release()
                end
            end)

            -- Soltado en ventana Perfect al llegar al receptor
            if canRelease and isPerfect(relRating) then
                shouldRelease = true
            -- Salvavidas si cruza la barra para proteger el Full Combo
            elseif canRelease and isGreat(relRating) and (tick() - holdData.StartTime) >= (holdData.Duration * 0.88) then
                shouldRelease = true
            -- Salvavidas por tiempo de duración
            elseif holdData.Duration > 0 and (tick() - holdData.StartTime) >= holdData.Duration then
                shouldRelease = true
            end
        end

        if shouldRelease then
            pcall(function() trackSys:release_track_index(tIdx) end)
            Engine.Holding[tIdx] = nil
        end
    end

    -- ====================================================================
    -- 2. EVALUACIÓN Y HITSCAN SOBRE EL RECEPTOR
    -- ====================================================================
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

            -- Planificador de Accuracy en tiempo real
            local plan = Engine.NotePlan[note]
            if not plan then
                local currentAcc = Engine.calculate_accuracy()
                local totalNotes = Engine.Stats.Total
                local now = tick()

                local isInitialDrop = (totalNotes == Engine.Config.InitialGreatNote)
                local isAboveCeiling = (totalNotes > Engine.Config.InitialGreatNote)
                    and (currentAcc >= Engine.Config.MaxAccuracy)
                    and (now - Engine.LastGreatTime >= Engine.Config.GreatCooldownSec)

                -- Solo las SingleNotes pueden ser Great; HeldNotes siempre van a Perfect
                local allowGreat = (note.ClassName == "SingleNote")
                    and (currentAcc > Engine.Config.MinAccuracy)
                    and (isInitialDrop or isAboveCeiling)

                if allowGreat then
                    plan = {
                        Type = "Great",
                        TargetMs = -35, -- Retardo controlado sobre la barra
                    }
                    Engine.LastGreatTime = now
                else
                    plan = {
                        Type = "Perfect",
                        TargetMs = math.random(Engine.Config.PerfectJitterMin, Engine.Config.PerfectJitterMax),
                    }
                end
                Engine.NotePlan[note] = plan
            end

            -- ====================================================
            -- NOTA SIMPLE (SingleNote)
            -- ====================================================
            if note.ClassName == "SingleNote" then
                local canHit, rating = false, 0
                pcall(function() canHit, rating = note:test_hit() end)

                if canHit then
                    local timeToEnd = getTimeToEnd(note, audioMgr)
                    local shouldHit = false

                    if plan.Type == "Perfect" then
                        if timeToEnd ~= nil then
                            if isPerfect(rating) and timeToEnd <= plan.TargetMs then
                                shouldHit = true
                            elseif timeToEnd <= -22 and (isPerfect(rating) or isGreat(rating)) then
                                shouldHit = true
                            end
                        else
                            if isPerfect(rating) then shouldHit = true end
                        end
                    elseif plan.Type == "Great" then
                        if timeToEnd ~= nil then
                            if timeToEnd <= plan.TargetMs and (isGreat(rating) or isPerfect(rating)) then
                                shouldHit = true
                            elseif timeToEnd <= -45 then
                                shouldHit = true
                            end
                        else
                            if isGreat(rating) or isPerfect(rating) then shouldHit = true end
                        end
                    end

                    if shouldHit then
                        Engine.Processed[note] = true

                        if plan.Type == "Perfect" then
                            Engine.Stats.Perfects = Engine.Stats.Perfects + 1
                        else
                            Engine.Stats.Greats = Engine.Stats.Greats + 1
                        end
                        Engine.Stats.Total = Engine.Stats.Total + 1

                        pcall(function() trackSys:release_track_index(tIdx) end)
                        trackSys:press_track_index(tIdx)

                        task.defer(function()
                            if not Engine.Holding[tIdx] then
                                pcall(function() trackSys:release_track_index(tIdx) end)
                            end
                        end)
                    end
                end

            -- ====================================================
            -- NOTA SOSTENIDA (HeldNote)
            -- ====================================================
            elseif note.ClassName == "HeldNote" then
                if not Engine.Holding[tIdx] then
                    local canHit, rating = false, 0
                    pcall(function() canHit, rating = note:test_hit() end)

                    if canHit then
                        local timeToEnd = getTimeToEnd(note, audioMgr)
                        local shouldPress = false

                        -- La cabeza de la HeldNote se activa en Perfect directo sobre la barra
                        if timeToEnd ~= nil then
                            if isPerfect(rating) and timeToEnd <= 2 then
                                shouldPress = true
                            elseif timeToEnd <= -20 and (isPerfect(rating) or isGreat(rating)) then
                                shouldPress = true
                            end
                        else
                            if isPerfect(rating) then shouldPress = true end
                        end

                        if shouldPress then
                            Engine.Processed[note] = true
                            local durSec = getNoteDurationSec(note)

                            -- Registrado asíncrono para no bloquear los demás carriles
                            Engine.Holding[tIdx] = {
                                Note = note,
                                StartTime = tick(),
                                Duration = durSec,
                            }

                            Engine.Stats.Perfects = Engine.Stats.Perfects + 1
                            Engine.Stats.Total = Engine.Stats.Total + 1

                            pcall(function() trackSys:release_track_index(tIdx) end)
                            trackSys:press_track_index(tIdx)
                        end
                    end
                end
            end
        end
    end

    return false
end

return Engine