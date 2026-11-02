local Engine = {}
Engine.Holding = {}
Engine.Processed = setmetatable({}, { __mode = "k" })
Engine.NotePlan = setmetatable({}, { __mode = "k" })

-- ====================================================================
-- REGULADOR DINÁMICO 99.#% CON BLINDAJE DE HELD NOTES
-- ====================================================================
Engine.Config = {
    MaxAccuracy = 99.65,       -- Si el acc sube de aquí, fuerza un Great en nota simple
    MinAccuracy = 99.15,       -- Si cae de aquí, solo permite Perfects para recuperar
    InitialGreatNote = 25,     -- Nota en la que mete el primer Great para romper el 100%
    GreatCooldownSec = 3.5,    -- Segundos mínimos de distancia entre Greats
    PerfectJitterMin = -8,     -- Jitter: ms tarde en Perfect
    PerfectJitterMax = 5,      -- Jitter: ms temprano en Perfect
}

Engine.Stats = {
    Perfects = 0,
    Greats = 0,
    Total = 0,
}
Engine.LastGreatTime = 0

-- Enumeradores oficiales del juego
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

local function getNoteDuration(note)
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
    return dur or 0
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

    local curTime = 0
    local okTime = pcall(function() curTime = audioMgr:get_current_time_ms() end)
    if not okTime or not curTime then return false end

    -- ====================================================================
    -- 1. SOLTADO DE NOTAS SOSTENIDAS (Calibrado en la cola exacta)
    -- ====================================================================
    for tIdx, heldNote in pairs(Engine.Holding) do
        local shouldRelease = false
        local dur = getNoteDuration(heldNote)
        local headTime = 0
        pcall(function() headTime = heldNote:get_time() end)
        local tailTime = headTime + dur
        local tailTimeToHit = tailTime - curTime

        local canRelease, relRating = false, 0
        pcall(function()
            if heldNote.test_release then
                canRelease, relRating = heldNote:test_release()
            end
        end)

        pcall(function()
            if not heldNote or heldNote:should_remove() then
                shouldRelease = true
            -- Solo suelta cuando la cola toca el receptor (tailTimeToHit <= 0) dentro de ventana Perfect/Great
            elseif tailTimeToHit <= 0 and (canRelease or isPerfect(relRating) or isGreat(relRating)) then
                shouldRelease = true
            -- Salvavidas de lag antes de que salga de la barra
            elseif tailTimeToHit <= -26 and (canRelease or isPerfect(relRating) or isGreat(relRating)) then
                shouldRelease = true
            elseif tailTimeToHit <= -45 then
                shouldRelease = true
            end
        end)

        if shouldRelease then
            pcall(function() trackSys:release_track_index(tIdx) end)
            Engine.Holding[tIdx] = nil
        end
    end

    -- ====================================================================
    -- 2. EVALUACIÓN Y GOLPEO DE NOTAS ENTRANTES
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

            -- Tiempo de la cabeza al receptor (sin usar get_time_to_end en HeldNotes)
            local noteHeadTime = 0
            pcall(function() noteHeadTime = note:get_time() end)
            local headTimeToHit = noteHeadTime - curTime

            -- Plan de impacto (los Greats SOLO se asignan a notas simples)
            local plan = Engine.NotePlan[note]
            if not plan then
                local currentAcc = Engine.getAccuracy()
                local totalNotes = Engine.Stats.Total
                local now = tick()

                local mustDropInitial = (totalNotes == Engine.Config.InitialGreatNote)
                local isAboveCeiling = (totalNotes > Engine.Config.InitialGreatNote)
                    and (currentAcc >= Engine.Config.MaxAccuracy)
                    and (now - Engine.LastGreatTime >= Engine.Config.GreatCooldownSec)

                local allowGreat = (note.ClassName == "SingleNote")
                    and (currentAcc > Engine.Config.MinAccuracy)
                    and (mustDropInitial or isAboveCeiling)

                if allowGreat then
                    plan = {
                        Type = "Great",
                        TargetMs = -35,
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

            -- ----------------------------------------------------------------
            -- NOTA SIMPLE (SingleNote)
            -- ----------------------------------------------------------------
            if note.ClassName == "SingleNote" then
                local canHit, rating = note:test_hit()
                local shouldHit = false

                if canHit then
                    if plan.Type == "Perfect" then
                        if isPerfect(rating) and headTimeToHit <= plan.TargetMs then
                            shouldHit = true
                        elseif headTimeToHit <= -25 and (isPerfect(rating) or isGreat(rating)) then
                            shouldHit = true
                        end
                    elseif plan.Type == "Great" then
                        if headTimeToHit <= plan.TargetMs and (isGreat(rating) or isPerfect(rating)) then
                            shouldHit = true
                        elseif headTimeToHit <= -45 then
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

            -- ----------------------------------------------------------------
            -- NOTA SOSTENIDA (HeldNote)
            -- ----------------------------------------------------------------
            elseif note.ClassName == "HeldNote" then
                if not Engine.Holding[tIdx] then
                    local canHit, rating = note:test_hit()
                    local shouldPress = false

                    if canHit then
                        -- La cabeza de la nota sostenida se activa SIEMPRE en Perfect sobre la barra
                        if isPerfect(rating) and headTimeToHit <= 0 then
                            shouldPress = true
                        elseif headTimeToHit <= -24 and (isPerfect(rating) or isGreat(rating)) then
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