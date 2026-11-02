local Engine = {}
Engine.Holding = {}
Engine.Processed = setmetatable({}, { __mode = "k" })
Engine.NotePlan = setmetatable({}, { __mode = "k" })

-- AJUSTE DE PRECISIÓN FC:
-- 98 = ~98% de precisión con FC asegurado (2% de Greats)
-- 99 = ~99% de precisión con FC asegurado (1% de Greats)
Engine.Config = {
    PerfectChance = 98,
}

-- Enumerador oficial
local NoteResult = { Miss = 1, Okay = 2, Great = 3, Perfect = 4 }
pcall(function()
    NoteResult = require(game.ReplicatedStorage:WaitForChild("LiteriaRGameCore", 1).Enums.NoteResult)
end)
if not NoteResult or not NoteResult.Perfect then
    pcall(function()
        NoteResult = require(game.ReplicatedStorage:WaitForChild("RobeatsGameCore", 1).Enums.NoteResult)
    end)
end
if not NoteResult or not NoteResult.Perfect then
    NoteResult = { Miss = 1, Okay = 2, Great = 3, Perfect = 4 }
end

function Engine.releaseAll(trackSys)
    if trackSys then
        for tIdx = 1, 4 do
            pcall(function() trackSys:release_track_index(tIdx) end)
        end
    end
    table.clear(Engine.Holding)
    table.clear(Engine.NotePlan)
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

    -- 1. SOLTADO DE NOTAS SOSTENIDAS (Garantía de Combo)
    for tIdx, heldNote in pairs(Engine.Holding) do
        local shouldRelease = false
        pcall(function()
            if not heldNote or heldNote:should_remove() then
                shouldRelease = true
            else
                local canRelease, relRating = heldNote:test_release()
                if canRelease and (relRating == NoteResult.Perfect or relRating == 4 or relRating == NoteResult.Great or relRating == 3) then
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

            -- Asignación de veredicto por nota (98% Perfect / 2% Great)
            local target = Engine.NotePlan[note]
            if not target then
                target = (math.random(1, 100) <= Engine.Config.PerfectChance) and "Perfect" or "Great"
                Engine.NotePlan[note] = target
            end

            -- ====================================================
            -- NOTA SIMPLE (SingleNote)
            -- ====================================================
            if note.ClassName == "SingleNote" then
                local canHit, rating = note:test_hit()
                local timeToEnd = 999
                pcall(function() timeToEnd = note:get_time_to_end() end)

                local shouldHit = false

                if target == "Perfect" then
                    -- Impacto directo en ventana Perfect
                    if canHit and (rating == NoteResult.Perfect or rating == 4) then
                        shouldHit = true
                    -- Salvavidas de combo: si hubo lag, golpear antes de que salga de la barra
                    elseif canHit and timeToEnd <= -28 then
                        shouldHit = true
                    end
                elseif target == "Great" then
                    -- Impacto retrasado voluntario (~34 ms tarde) para forzar un Great limpio
                    if canHit and timeToEnd <= -34 and (rating == NoteResult.Great or rating == 3) then
                        shouldHit = true
                    -- Salvavidas: no permitir que caiga en Okay o Miss
                    elseif canHit and timeToEnd <= -48 then
                        shouldHit = true
                    end
                end

                if shouldHit then
                    Engine.Processed[note] = true

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

                    if target == "Perfect" then
                        if canHit and (rating == NoteResult.Perfect or rating == 4) then
                            shouldPress = true
                        end
                    elseif target == "Great" then
                        -- En notas largas se toma el Great temprano de entrada o Perfect si no hay margen
                        if canHit and (rating == NoteResult.Great or rating == 3 or rating == NoteResult.Perfect or rating == 4) then
                            shouldPress = true
                        end
                    end

                    if shouldPress then
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

return Engine