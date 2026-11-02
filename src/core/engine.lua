local Engine = {}
Engine.Holding = {}
Engine.Processed = setmetatable({}, { __mode = "k" })
Engine.NotePlan = setmetatable({}, { __mode = "k" })

-- Calibración de Full Combo:
-- 99 = 99% Perfect, 1% Late Great (FC garantizado)
-- 98 = 98% Perfect, 2% Late Great (FC garantizado)
Engine.Config = {
    PerfectChance = 99,
}

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

    -- 1. SOLTADO DE NOTAS SOSTENIDAS (En el receptor)
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

            local target = Engine.NotePlan[note]
            if not target then
                target = (math.random(1, 100) <= Engine.Config.PerfectChance) and "Perfect" or "Great"
                Engine.NotePlan[note] = target
            end

            -- Obtener la distancia exacta en milisegundos a la barra
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
                    if target == "Perfect" then
                        -- Solo presiona cuando la nota toca físicamente la barra (timeToEnd <= 0)
                        if isPerfect(rating) and (timeToEnd == nil or timeToEnd <= 0) then
                            shouldHit = true
                        -- Salvavidas de FC ante caídas de FPS
                        elseif timeToEnd ~= nil and timeToEnd <= -26 and (isPerfect(rating) or isGreat(rating)) then
                            shouldHit = true
                        end
                    elseif target == "Great" then
                        -- Late Great: se deja pasar ligeramente la barra (-35 ms) para no registrarlo arriba
                        if timeToEnd ~= nil and timeToEnd <= -35 and (isGreat(rating) or isPerfect(rating)) then
                            shouldHit = true
                        end
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

                    if canHit then
                        if target == "Perfect" then
                            if isPerfect(rating) and (timeToEnd == nil or timeToEnd <= 0) then
                                shouldPress = true
                            elseif timeToEnd ~= nil and timeToEnd <= -26 and (isPerfect(rating) or isGreat(rating)) then
                                shouldPress = true
                            end
                        elseif target == "Great" then
                            if timeToEnd ~= nil and timeToEnd <= -35 and (isGreat(rating) or isPerfect(rating)) then
                                shouldPress = true
                            end
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