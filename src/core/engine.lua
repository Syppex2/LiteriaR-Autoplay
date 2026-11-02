local Engine = {}
Engine.Holding = {}
Engine.Processed = setmetatable({}, { __mode = "k" })
Engine.NotePlan = setmetatable({}, { __mode = "k" })

-- ====================================================================
-- CONFIGURACIÓN DE ACCURACY Y HUMANIZACIÓN
-- ====================================================================
Engine.Config = {
    -- Umbral de precisión: si el accuracy supera este número, se fuerza un Great
    -- (Ej: 99.5, 99.7 o 99.9 según tu preferencia)
    TargetAccuracy = 99.6,

    -- Cantidad de notas iniciales en Perfect antes de permitir el primer Great
    MinNotesBeforeGreat = 30,

    -- Enfriamiento en segundos entre Greats (evita dos Greats seguidos en ráfagas)
    GreatCooldown = 4.0,

    -- Variación humanizada de milisegundos para notas PERFECT (Jitter natural)
    PerfectJitterMin = -12, -- ms tarde
    PerfectJitterMax = 8,   -- ms temprano
}

Engine.Stats = {
    Perfects = 0,
    Greats = 0,
    Total = 0,
}
Engine.LastGreatTime = 0

-- Enumeradores nativos de RoBeats / LiteriaR
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

function Engine.getAccuracy()
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

    -- 1. SOLTADO DE NOTAS SOSTENIDAS (Siempre en Perfect para asegurar combo)
    for tIdx, heldNote in pairs(Engine.Holding) do
        local shouldRelease = false
        pcall(function()
            if not heldNote or heldNote:should_remove() then
                shouldRelease = true
            else
                local canRelease, relRating = heldNote:test_release()
                if canRelease and (isPerfect(relRating) or isGreat(relRating)) then
                    shouldRelease = true
                end
            end
        end)

        if shouldRelease then
            pcall(function() trackSys:release_track_index(tIdx) end)
            Engine.Holding[tIdx] = nil
        end
    end

    -- 2. PROCESAMIENTO DE NOTAS
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

            -- Planificación y calibración de impacto por nota
            local plan = Engine.NotePlan[note]
            if not plan then
                local currentAcc = Engine.getAccuracy()
                local canTriggerGreat = (Engine.Stats.Total >= Engine.Config.MinNotesBeforeGreat)
                    and (currentAcc >= Engine.Config.TargetAccuracy)
                    and (tick() - Engine.LastGreatTime >= Engine.Config.GreatCooldown)
                    and (note.ClassName == "SingleNote")

                if canTriggerGreat then
                    plan = {
                        Type = "Great",
                        TargetMs = -36, -- Retraso a -36 ms para forzar Late Great limpio
                    }
                    Engine.LastGreatTime = tick()
                else
                    -- Jitter humanizado dentro de la ventana Perfect
                    local jitter = math.random(Engine.Config.PerfectJitterMin, Engine.Config.PerfectJitterMax)
                    plan = {
                        Type = "Perfect",
                        TargetMs = jitter,
                    }
                end
                Engine.NotePlan[note] = plan
            end

            local timeToEnd = nil
            pcall(function()
                if note.get_time_to_end then
                    timeToEnd = note:get_time_to_end()
                elseif note.get_time and audioMgr.get_current_time_ms then
                    timeToEnd = note:get_time() - audioMgr:get_current_time_ms()
                end
            end)

            -- ====================================================
            -- NOTA SIMPLE (SingleNote)
            -- ====================================================
            if note.ClassName == "SingleNote" then
                local canHit, rating = note:test_hit()
                local shouldHit = false

                if canHit then
                    if plan.Type == "Perfect" then
                        -- Impacta cuando llega al milisegundo humanizado asignado
                        if isPerfect(rating) and (timeToEnd == nil or timeToEnd <= plan.TargetMs) then
                            shouldHit = true
                        -- Salvavidas anti-lag: nunca dejar escapar la nota
                        elseif timeToEnd ~= nil and timeToEnd <= -26 and (isPerfect(rating) or isGreat(rating)) then
                            shouldHit = true
                        end
                    elseif plan.Type == "Great" then
                        -- Espera a que cruce ligeramente el receptor para el Great seguro
                        if timeToEnd ~= nil and timeToEnd <= plan.TargetMs and (isGreat(rating) or isPerfect(rating)) then
                            shouldHit = true
                        -- Salvavidas para evitar caer en Okay o Miss
                        elseif timeToEnd ~= nil and timeToEnd <= -46 then
                            shouldHit = true
                        end
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

            -- ====================================================
            -- NOTA SOSTENIDA (HeldNote)
            -- ====================================================
            elseif note.ClassName == "HeldNote" then
                if not Engine.Holding[tIdx] then
                    local canHit, rating = note:test_hit()
                    local shouldPress = false

                    if canHit then
                        -- Las notas sostenidas se activan en Perfect directo sobre la barra
                        if isPerfect(rating) and (timeToEnd == nil or timeToEnd <= 0) then
                            shouldPress = true
                        elseif timeToEnd ~= nil and timeToEnd <= -26 and (isPerfect(rating) or isGreat(rating)) then
                            shouldPress = true
                        end
                    end

                    if shouldPress then
                        Engine.Processed[note] = true
                        Engine.Holding[tIdx] = note

                        Engine.Stats.Perfects = Engine.Stats.Perfects + 1
                        Engine.Stats.Total = Engine.Stats.Total + 1

                        pcall(function() trackSys:release_track_index(tIdx) end)
                        trackSys:press_track_index(tIdx)
                    end
                end
            end
        end
    end

    return false
end

return Engine