local isOpen, currentState, latestCall, quickVisible = false, nil, nil, false

local function streetName(coords)
    local street, crossing = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local name = GetStreetNameFromHashKey(street)
    if crossing and crossing ~= 0 then name = name .. ' / ' .. GetStreetNameFromHashKey(crossing) end
    return name
end

local function refresh(open)
    local nextState = lib.callback.await('XS-Dispatch:server:getState', false)
    if not nextState then
        if open then lib.notify({ title = 'XS-Dispatch', description = 'You must be an on-duty responder.', type = 'error' }) end
        return false
    end
    currentState = nextState; RenderTracking(nextState); nextState.mySource = GetPlayerServerId(PlayerId())
    SendNUIMessage({ action = 'state', payload = nextState })
    SendNUIMessage({ action = 'quickState', payload = nextState })
    return true
end

local function myUnit()
    if not currentState then return nil end
    local mySource = GetPlayerServerId(PlayerId())
    for _, unit in ipairs(currentState.units or {}) do if unit.source == mySource then return unit end end
end

local function findCall(id)
    if not currentState then return nil end
    for _, call in ipairs(currentState.calls or {}) do if call.id == id then return call end end
end

local function assignedCall()
    local unit = myUnit()
    return unit and unit.callId and findCall(unit.callId) or nil
end

local function showQuick(value)
    if not Config.QuickOverlay.enabled then return end
    quickVisible = value
    SendNUIMessage({ action = 'quickVisible', payload = value })
    if value and currentState then SendNUIMessage({ action = 'quickState', payload = currentState }) end
end

local function respond(call)
    if not call then return false end
    local ok, accepted = lib.callback.await('XS-Dispatch:server:respond', false, call.id)
    if ok then
        local routed = RouteCall(accepted)
        showQuick(false)
        if routed then
            lib.notify({ title = 'Dispatch Route', description = ('GPS set to %s'):format(accepted.street or accepted.title), type = 'success' })
        end
        if Config.Radio.autoJoinOperations then
            TriggerEvent('XS-Dispatch:client:joinOperationRadio', accepted.operation.channel)
        end
    end
    return ok
end

local function setOpen(value)
    if value and not refresh(true) then return end
    isOpen = value; SetNuiFocus(value, value); SendNUIMessage({ action = value and 'open' or 'close' })
end

RegisterCommand('xs_dispatch', function() setOpen(not isOpen) end, false)
RegisterKeyMapping('xs_dispatch', 'XS-Dispatch Console', 'keyboard', Config.OpenKey)
RegisterCommand('xs_dispatch_panic', function() TriggerServerEvent('XS-Dispatch:server:panic') end, false)
RegisterKeyMapping('xs_dispatch_panic', 'XS-Dispatch Panic Button', 'keyboard', Config.Panic.key)
RegisterCommand('xs_dispatch_quick', function() showQuick(not quickVisible) end, false)
RegisterKeyMapping('xs_dispatch_quick', 'XS-Dispatch Quick Responder', 'keyboard', Config.QuickOverlayKey)
RegisterCommand('xs_dispatch_respond', function() respond(latestCall or assignedCall()) end, false)
RegisterKeyMapping('xs_dispatch_respond', 'XS-Dispatch Respond To Latest Call', 'keyboard', Config.QuickRespondKey)
RegisterCommand('xs_dispatch_radio', function()
    local call = assignedCall()
    if call and call.operation then TriggerEvent('XS-Dispatch:client:joinOperationRadio', call.operation.channel) end
end, false)
RegisterKeyMapping('xs_dispatch_radio', 'XS-Dispatch Join Operation Radio', 'keyboard', Config.RadioKey)

RegisterCommand('911', function(_, args)
    local message = table.concat(args, ' ')
    if #message < 3 then return lib.notify({ description = 'Usage: /911 [emergency]', type = 'error' }) end
    local coords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('XS-Dispatch:server:civilianCall', '911', message, streetName(coords))
    lib.notify({ title = '911', description = 'Your emergency call was submitted.', type = 'success' })
end, false)

RegisterNetEvent('XS-Dispatch:client:state', function(nextState)
    currentState = nextState; RenderTracking(nextState); nextState.mySource = GetPlayerServerId(PlayerId())
    if isOpen then SendNUIMessage({ action = 'state', payload = nextState }) end
    SendNUIMessage({ action = 'quickState', payload = nextState })
    if Config.QuickOverlay.showWhileAssigned then showQuick(assignedCall() ~= nil or quickVisible) end
end)

RegisterNetEvent('XS-Dispatch:client:delta', function(delta)
    if not currentState or type(delta) ~= 'table' then return end
    local kind, payload = delta.kind, delta.payload
    local collection = kind and kind:find('unit:', 1, true) == 1 and currentState.units or currentState.calls
    if not collection or not payload then return end
    local key = collection == currentState.units and 'citizenid' or 'id'
    local index
    for i, item in ipairs(collection) do if item[key] == payload[key] then index = i break end end
    if kind:find(':remove', 1, true) then
        if index then table.remove(collection, index) end
    elseif index then collection[index] = payload else collection[#collection + 1] = payload end
    RenderTracking(currentState); currentState.mySource = GetPlayerServerId(PlayerId())
    if isOpen then SendNUIMessage({ action = 'state', payload = currentState }) end
    SendNUIMessage({ action = 'quickState', payload = currentState })
end)

RegisterNetEvent('XS-Dispatch:client:newCall', function(call)
    latestCall = call
    SendNUIMessage({ action = 'alert', payload = call })
    if Config.QuickOverlay.enabled then
        showQuick(true)
        SetTimeout(Config.QuickOverlay.alertSeconds * 1000, function()
            if not assignedCall() then showQuick(false) end
        end)
    end
    lib.notify({ title = ('P%d · %s'):format(call.priority, call.code), description = call.title .. ' — ' .. call.street, type = call.priority == 1 and 'error' or 'inform', duration = call.priority == 1 and 9000 or 6000 })
end)

RegisterNUICallback('close', function(_, cb) setOpen(false); cb(true) end)
RegisterNUICallback('respond', function(data, cb)
    cb({ ok = respond(findCall(data.id) or latestCall) })
end)
RegisterNUICallback('route', function(data, cb)
    local routed = false
    if currentState then
        for _, call in ipairs(currentState.calls) do
            if call.id == data.id then routed = RouteCall(call); break end
        end
    end
    if routed then lib.notify({ title = 'Dispatch Route', description = 'GPS route updated.', type = 'success' }) end
    cb({ ok = routed })
end)
RegisterNUICallback('clear', function(data, cb) cb({ ok = lib.callback.await('XS-Dispatch:server:clearCall', false, data.id) }) end)
RegisterNUICallback('status', function(data, cb) cb({ ok = lib.callback.await('XS-Dispatch:server:setStatus', false, data.status) }) end)
RegisterNUICallback('leaveCall', function(data, cb)
    local ok = lib.callback.await('XS-Dispatch:server:leaveCall', false, data.id)
    if ok then showQuick(false) end
    cb({ ok = ok })
end)
RegisterNUICallback('joinRadio', function(data, cb)
    local channel = tonumber(data.channel)
    if channel then TriggerEvent('XS-Dispatch:client:joinOperationRadio', channel) end
    cb({ ok = channel ~= nil })
end)
RegisterNUICallback('getIntegrations', function(_, cb) cb(lib.callback.await('XS-Dispatch:server:getIntegrations', false) or {}) end)
RegisterNUICallback('getIntegrationHealth', function(_, cb) cb(lib.callback.await('XS-Dispatch:server:getIntegrationHealth', false) or {}) end)
RegisterNUICallback('saveIntegration', function(data, cb)
    local ok, result = lib.callback.await('XS-Dispatch:server:saveIntegration', false, data)
    cb({ ok = ok, result = result })
end)
RegisterNUICallback('deleteIntegration', function(data, cb) cb({ ok = lib.callback.await('XS-Dispatch:server:deleteIntegration', false, data.id) }) end)
RegisterNUICallback('getProfile', function(_, cb) cb(lib.callback.await('XS-Dispatch:server:getProfile', false) or {}) end)
RegisterNUICallback('saveProfile', function(data, cb)
    local ok, result = lib.callback.await('XS-Dispatch:server:saveProfile', false, data)
    if ok then refresh(false) end
    cb({ ok = ok, result = result })
end)
RegisterNUICallback('routeUnit', function(data, cb)
    if currentState then
        for _, unit in ipairs(currentState.units or {}) do
            if unit.citizenid == data.citizenid and unit.coords then
                SetNewWaypoint(unit.coords.x + 0.0, unit.coords.y + 0.0)
                cb({ ok = true }); return
            end
        end
    end
    cb({ ok = false })
end)

RegisterNetEvent('XS-Dispatch:client:joinOperationRadio', function(channel)
    if not Config.Radio.enabled or GetResourceState(Config.Radio.resource) ~= 'started' then
        return lib.notify({ title = 'Operational Radio', description = 'Voice integration is unavailable.', type = 'error' })
    end
    if Config.Radio.resource == 'pma-voice' then
        exports['pma-voice']:setRadioChannel(tonumber(channel))
        lib.notify({ title = 'Operational Radio', description = ('Joined TAC %s'):format(channel), type = 'success' })
    end
end)

CreateThread(function()
    local arrivedAt
    while true do
        Wait(1500)
        if Config.AutoStatus.enabled then
            local call, unit = assignedCall(), myUnit()
            if call and unit then
                local distance = #(GetEntityCoords(PlayerPedId()) - vector3(call.coords.x, call.coords.y, call.coords.z))
                if distance <= Config.AutoStatus.arrivalRadius and unit.status == Config.AutoStatus.enRouteStatus then
                    lib.callback.await('XS-Dispatch:server:setStatus', false, Config.AutoStatus.arrivalStatus)
                    arrivedAt = call.id
                elseif distance > Config.AutoStatus.leaveRadius and arrivedAt == call.id and unit.status == Config.AutoStatus.arrivalStatus then
                    lib.callback.await('XS-Dispatch:server:setStatus', false, Config.AutoStatus.enRouteStatus)
                    arrivedAt = nil
                end
            else arrivedAt = nil end
        end
    end
end)

CreateThread(function() Wait(2500); refresh(false) end)
