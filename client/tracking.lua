local unitBlips, callBlips, state = {}, {}, nil

local function vehicleClass()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return 'foot', nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    local class = GetVehicleClass(vehicle)
    if class == 8 then return 'motorcycle', GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) end
    if class == 13 then return 'bicycle', GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) end
    if class == 14 then return 'boat', GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) end
    if class == 15 then return 'helicopter', GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) end
    if class == 16 then return 'plane', GetDisplayNameFromVehicleModel(GetEntityModel(vehicle)) end
    return 'car', GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
end

local function removeMissing(collection, seen)
    for id, blip in pairs(collection) do
        if not seen[id] then if DoesBlipExist(blip) then RemoveBlip(blip) end; collection[id] = nil end
    end
end

local function nameBlip(blip, label)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(label); EndTextCommandSetBlipName(blip)
end

function RenderTracking(nextState)
    state = nextState
    local mySource = GetPlayerServerId(PlayerId())
    local myCallId
    for _, candidate in ipairs(state.units or {}) do if candidate.source == mySource then myCallId = candidate.callId break end end
    local seenUnits = {}
    for _, unit in ipairs(state.units or {}) do
        if unit.source ~= mySource then
            seenUnits[unit.citizenid] = true
            local dept = Config.Departments[unit.department]
            local blip = unitBlips[unit.citizenid]
            if not blip or not DoesBlipExist(blip) then blip = AddBlipForCoord(unit.coords.x, unit.coords.y, unit.coords.z); unitBlips[unit.citizenid] = blip end
            SetBlipCoords(blip, unit.coords.x, unit.coords.y, unit.coords.z)
            SetBlipSprite(blip, dept.sprites[unit.vehicleClass] or dept.sprites.foot)
            local sameOperation = myCallId and unit.callId == myCallId
            local unavailable = tostring(unit.status or ''):lower():find('out of service', 1, true) ~= nil
            SetBlipColour(blip, dept.blipColor); SetBlipScale(blip, sameOperation and 1.0 or 0.84); SetBlipAlpha(blip, unavailable and 105 or 255); SetBlipAsShortRange(blip, false)
            SetBlipRotation(blip, math.floor(unit.heading or 0)); ShowHeadingIndicatorOnBlip(blip, true)
            SetBlipFlashes(blip, unit.panic == true)
            local radio = unit.radioChannel and (' · TAC ' .. unit.radioChannel) or ''
            local assigned = unit.callId and (' · ' .. unit.callId) or ''
            nameBlip(blip, ('[%s] %s · %s%s%s'):format(dept.short, unit.callsign or unit.name, unit.status or 'Available', assigned, radio))
        end
    end
    removeMissing(unitBlips, seenUnits)

    local seenCalls = {}
    for _, call in ipairs(state.calls or {}) do
        seenCalls[call.id] = true
        local blip = callBlips[call.id]
        if not blip or not DoesBlipExist(blip) then blip = AddBlipForCoord(call.coords.x, call.coords.y, call.coords.z); callBlips[call.id] = blip end
        SetBlipSprite(blip, call.sprite); SetBlipColour(blip, call.color); SetBlipScale(blip, Config.CallBlip.scale); SetBlipAsShortRange(blip, false)
        SetBlipFlashes(blip, Config.CallBlip.flashPriorityOne and call.priority == 1)
        nameBlip(blip, ('%s · %s'):format(call.code, call.title))
    end
    removeMissing(callBlips, seenCalls)
end

function RouteCall(call)
    if not call or not call.coords then return false end

    -- Waypoint routing does not depend on the call blip existing yet. This is
    -- the reliable path immediately after accepting a newly-created call.
    SetNewWaypoint(call.coords.x + 0.0, call.coords.y + 0.0)

    local blip = callBlips[call.id]
    if not blip or not DoesBlipExist(blip) then
        blip = AddBlipForCoord(call.coords.x, call.coords.y, call.coords.z or 0.0)
        callBlips[call.id] = blip
        SetBlipSprite(blip, call.sprite or 280)
        SetBlipColour(blip, call.color or 1)
        SetBlipScale(blip, Config.CallBlip.scale)
        SetBlipAsShortRange(blip, false)
        nameBlip(blip, ('%s · %s'):format(call.code or 'CALL', call.title or 'Dispatch Call'))
    end
    for _, other in pairs(callBlips) do SetBlipRoute(other, false) end
    SetBlipRoute(blip, true); SetBlipRouteColour(blip, Config.CallBlip.routeColor)
    return true
end

CreateThread(function()
    while true do
        Wait(Config.PositionInterval)
        local pd = Framework.GetPlayerData()
        if pd and pd.job then
            local department
            for id, value in pairs(Config.Departments) do if value.jobs[pd.job.name] then department = id break end end
            if department and (not Config.OnDutyOnly or pd.job.onduty) then
                local ped, coords = PlayerPedId(), GetEntityCoords(PlayerPedId())
                local class, label = vehicleClass()
                TriggerServerEvent('XS-Dispatch:server:position', { x = coords.x, y = coords.y, z = coords.z, heading = GetEntityHeading(ped), vehicleClass = class, vehicleLabel = label })
            elseif state then RenderTracking({ units = {}, calls = {}, department = nil }) end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, blip in pairs(unitBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
    for _, blip in pairs(callBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
end)
