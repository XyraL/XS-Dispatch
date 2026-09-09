local Calls, Units, Sequence, panicCooldown, civilianCooldown = {}, {}, 0, {}, {}
local Integrations = {}
local Profiles, IdentityProviders = {}, {}
local FieldTypes = {
    text = { label = 'Text' }, person = { label = 'Person' }, vehicle = { label = 'Vehicle' },
    patient = { label = 'Patient' }, hazard = { label = 'Hazard' }, checklist = { label = 'Checklist' },
}

local function saveState()
    if not Config.Persistence.enabled then return end
    SaveResourceFile(GetCurrentResourceName(), Config.Persistence.stateFile, json.encode({ sequence = Sequence, calls = Calls }), -1)
end

local function loadState()
    if not Config.Persistence.enabled then return end
    local raw = LoadResourceFile(GetCurrentResourceName(), Config.Persistence.stateFile)
    if not raw or raw == '' then return end
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == 'table' then Calls, Sequence = data.calls or {}, tonumber(data.sequence) or 0 end
end

local function loadProfiles()
    local raw = LoadResourceFile(GetCurrentResourceName(), Config.Profiles.file)
    if not raw or raw == '' then return end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then Profiles = decoded end
end

local function saveProfiles()
    SaveResourceFile(GetCurrentResourceName(), Config.Profiles.file, json.encode(Profiles), -1)
end

local function usableIdentity(value)
    if value == nil then return nil end
    local text = tostring(value):gsub('^%s*(.-)%s*$', '%1')
    local normalized = text:upper()
    if text == '' or normalized == 'N/A' or normalized == 'NA' or normalized == 'NONE'
        or normalized == 'NO CALLSIGN' or normalized == 'NOT SET' or normalized == 'UNKNOWN' then return nil end
    return text
end

local function resolveIdentity(src, pd, dept)
    -- Native XS-MDT fast path. This is evaluated on every resolution, so
    -- either resource may be restarted without losing the adapter.
    if GetResourceState('XS-MDT') == 'started' then
        local ok, result = pcall(function() return exports['XS-MDT']:GetDispatchIdentity(src) end)
        if ok and type(result) == 'table' and usableIdentity(result.callsign) then
            return {
                callsign = usableIdentity(result.callsign), badge = usableIdentity(result.badge),
                unitType = result.unitType or 'field', source = 'XS-MDT',
            }
        end
    end
    for _, provider in ipairs(IdentityProviders) do
        local ok, result = pcall(provider.resolve, src, pd)
        if ok and type(result) == 'table' and usableIdentity(result.callsign) then
            result.callsign = usableIdentity(result.callsign)
            result.badge = usableIdentity(result.badge)
            result.source = provider.name
            return result
        end
    end
    local metadata = pd.metadata or {}
    local saved = Profiles[pd.citizenid] or {}
    local frameworkCallsign, savedCallsign = usableIdentity(metadata.callsign), usableIdentity(saved.callsign)
    local callsign = frameworkCallsign or savedCallsign or (Config.Departments[dept].short .. '-' .. src)
    return { callsign = callsign, badge = usableIdentity(metadata.badge) or usableIdentity(saved.badge), unitType = saved.unitType or 'field', source = frameworkCallsign and 'framework' or savedCallsign and 'dispatch' or 'generated' }
end

local function loadIntegrations()
    if not Config.IntegrationStudio.enabled then return end
    local raw = LoadResourceFile(GetCurrentResourceName(), Config.IntegrationStudio.saveFile)
    if not raw or raw == '' then return end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then Integrations = decoded end
end

local function saveIntegrations()
    SaveResourceFile(GetCurrentResourceName(), Config.IntegrationStudio.saveFile, json.encode(Integrations), -1)
end

local function integrationPreset(id)
    local custom = Integrations[id]
    if custom then return custom end
    return Config.CallTypes[id]
end

loadIntegrations()
loadState()
loadProfiles()

local function departmentFor(job)
    for id, department in pairs(Config.Departments) do
        if department.jobs[job] then return id, department end
    end
end

local function playerInfo(src)
    local player = Framework.GetPlayer(src)
    if not player then return end
    local pd = player.PlayerData
    local dept = departmentFor(pd.job and pd.job.name)
    if not dept or (Config.OnDutyOnly and not pd.job.onduty) then return end
    local char = pd.charinfo or {}
    return player, pd, dept, ((char.firstname or '') .. ' ' .. (char.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
end

local function departmentSet(list)
    local set = {}
    for _, id in ipairs(list or {}) do if Config.Departments[id] then set[id] = true end end
    return set
end

local function recipients(departments)
    local wanted = departmentSet(departments)
    local out = {}
    for src, player in pairs(Framework.GetPlayers()) do
        local pd = player.PlayerData
        local id = departmentFor(pd.job and pd.job.name)
        if id and wanted[id] and (not Config.OnDutyOnly or pd.job.onduty) then out[#out + 1] = src end
    end
    return out
end

local function sanitizeCall(data, creator)
    data = type(data) == 'table' and data or {}
    local preset = integrationPreset(data.type or 'custom') or Config.CallTypes.custom
    local coords = data.coords or (creator and GetEntityCoords(GetPlayerPed(creator)))
    if not coords then return nil, 'Missing coordinates' end
    local departments = data.departments or preset.departments
    if type(departments) ~= 'table' or #departments == 0 then return nil, 'Missing departments' end
    Sequence = Sequence + 1
    return {
        id = ('C%04d'):format(Sequence),
        type = tostring(data.type or 'custom'):sub(1, 32),
        code = tostring(data.code or preset.code):sub(1, 16),
        title = tostring(data.title or preset.label):sub(1, 80),
        description = tostring(data.description or 'No additional details.'):sub(1, 500),
        priority = math.max(1, math.min(3, tonumber(data.priority or preset.priority) or 2)),
        departments = departments,
        coords = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0 },
        street = tostring(data.street or 'Unknown location'):sub(1, 100),
        caller = tostring(data.caller or 'Dispatch'):sub(1, 80),
        anonymous = data.anonymous == true,
        sprite = tonumber(data.sprite or preset.sprite) or 280,
        color = tonumber(data.color or preset.color) or 1,
        status = 'active', notes = {}, units = {}, createdAt = os.time(), updatedAt = os.time(),
        origin = tostring(data.origin or 'XS-Dispatch'), externalId = data.externalId,
        providerRevision = tonumber(data.providerRevision) or 0, revision = 1,
        operation = {
            id = ('OP-%04d'):format(Sequence),
            label = tostring(data.operationLabel or data.title or preset.label):sub(1, 80),
            channel = Config.Radio.operationChannelBase + (Sequence % Config.Radio.operationChannelRange),
        },
        fields = type(data.fields) == 'table' and data.fields or {},
    }
end

local function publicState(dept)
    local calls, units = {}, {}
    for _, call in pairs(Calls) do
        if call.status == 'active' and departmentSet(call.departments)[dept] then calls[#calls + 1] = call end
    end
    local visibility = Config.Departments[dept] and Config.Departments[dept].sees or {}
    for _, unit in pairs(Units) do
        if visibility[unit.department] and os.time() - unit.updatedAt <= Config.UnitTimeout then units[#units + 1] = unit end
    end
    table.sort(calls, function(a, b) return a.priority == b.priority and a.createdAt > b.createdAt or a.priority < b.priority end)
    return { calls = calls, units = units, department = dept, departments = Config.Departments, canManageIntegrations = false }
end

local function pushState()
    for src in pairs(Framework.GetPlayers()) do
        local _, _, dept = playerInfo(src)
        if dept then
            local result = publicState(dept)
            result.canManageIntegrations = Config.IntegrationStudio.enabled and IsPlayerAceAllowed(src, Config.IntegrationStudio.adminAce)
            TriggerClientEvent('XS-Dispatch:client:state', src, result)
        end
    end
end

local function pushDelta(kind, payload)
    for src in pairs(Framework.GetPlayers()) do
        local _, _, dept = playerInfo(src)
        if dept then
            local allowed = true
            if kind:find('unit:', 1, true) == 1 then
                allowed = Config.Departments[dept].sees[payload.department] == true
            elseif kind:find('call:', 1, true) == 1 then
                allowed = departmentSet(payload.departments)[dept] == true
            end
            if allowed then TriggerClientEvent('XS-Dispatch:client:delta', src, { kind = kind, payload = payload }) end
        end
    end
end

local function createCall(data, creator)
    local active = 0
    for _, existing in pairs(Calls) do if existing.status == 'active' then active = active + 1 end end
    if active >= Config.MaxActiveCalls then return nil, 'Call limit reached' end
    local call, err = sanitizeCall(data, creator)
    if not call then return nil, err end
    Calls[call.id] = call
    for _, src in ipairs(recipients(call.departments)) do TriggerClientEvent('XS-Dispatch:client:newCall', src, call) end
    pushState()
    TriggerEvent('XS-Dispatch:server:callCreated', call)
    pushDelta('call:upsert', call); saveState()
    return call.id, call
end

exports('CreateCall', function(data) return createCall(data, nil) end)
exports('GetCall', function(id) return Calls[tostring(id)] end)
exports('GetActiveCalls', function() return Calls end)
exports('RegisterFieldType', function(id, definition)
    id = tostring(id or ''):lower():gsub('[^%w_%-]', '')
    if id == '' or type(definition) ~= 'table' then return false end
    FieldTypes[id] = definition; return true
end)
exports('GetFieldTypes', function() return FieldTypes end)
exports('UpdateCall', function(id, patch)
    local call = Calls[tostring(id)]
    if not call or type(patch) ~= 'table' then return false end
    for _, key in ipairs({ 'title', 'description', 'priority', 'street', 'fields' }) do if patch[key] ~= nil then call[key] = patch[key] end end
    call.updatedAt = os.time(); call.revision = (call.revision or 0) + 1; pushDelta('call:upsert', call); TriggerEvent('XS-Dispatch:server:callUpdated', call); saveState(); return true, call
end)
exports('SetCallStatus', function(source, id, status)
    local call = Calls[tostring(id)]
    if not call then return false end
    status = tostring(status or 'active')
    call.updatedAt = os.time(); call.revision = (call.revision or 0) + 1
    if status == 'completed' or status == 'cancelled' or status == 'closed' then
        call.status, call.closedAt = status == 'cancelled' and 'cancelled' or 'closed', os.time()
        for cid in pairs(call.units or {}) do
            if Units[cid] then Units[cid].callId, Units[cid].operationId, Units[cid].radioChannel = nil, nil, nil end
        end
        pushDelta('call:remove', call)
        TriggerEvent('XS-Dispatch:server:callClosed', call, source)
    else
        call.status = status
        pushDelta('call:upsert', call)
        TriggerEvent('XS-Dispatch:server:callUpdated', call)
    end
    saveState(); return true
end)
exports('AddCallNote', function(id, note)
    local call = Calls[tostring(id)]
    if not call then return false end
    local entry = type(note) == 'table' and note or { text = note }
    call.notes[#call.notes + 1] = { text = tostring(entry.text or ''), author = entry.author or 'Integration', createdAt = os.time() }
    call.updatedAt = os.time(); call.revision = (call.revision or 0) + 1; pushDelta('call:upsert', call); TriggerEvent('XS-Dispatch:server:callUpdated', call); saveState(); return true
end)

lib.callback.register('XS-Dispatch:server:getState', function(source)
    local _, _, dept = playerInfo(source)
    if not dept then return nil end
    local result = publicState(dept)
    result.canManageIntegrations = Config.IntegrationStudio.enabled and IsPlayerAceAllowed(source, Config.IntegrationStudio.adminAce)
    return result
end)

lib.callback.register('XS-Dispatch:server:getProfile', function(source)
    local _, pd, dept = playerInfo(source)
    if not dept then return nil end
    local resolved = resolveIdentity(source, pd, dept)
    resolved.saved = Profiles[pd.citizenid] or {}
    return resolved
end)

lib.callback.register('XS-Dispatch:server:saveProfile', function(source, data)
    local _, pd, dept = playerInfo(source)
    if not dept or type(data) ~= 'table' then return false, 'Unauthorized' end
    local callsign = tostring(data.callsign or ''):gsub('[^%w%-%s]', ''):sub(1, Config.Profiles.callsignMaxLength)
    local badge = tostring(data.badge or ''):gsub('[^%w%-]', ''):sub(1, Config.Profiles.badgeMaxLength)
    local unitType = tostring(data.unitType or 'field'):lower():gsub('[^%w_%-]', ''):sub(1, 24)
    if callsign == '' then return false, 'Callsign is required' end
    Profiles[pd.citizenid] = { callsign = callsign, badge = badge, unitType = unitType, updatedAt = os.time() }
    saveProfiles()
    if Units[pd.citizenid] then
        local identity = resolveIdentity(source, pd, dept)
        Units[pd.citizenid].callsign, Units[pd.citizenid].badge, Units[pd.citizenid].unitType = identity.callsign, identity.badge, identity.unitType
        pushDelta('unit:upsert', Units[pd.citizenid])
    end
    return true, resolveIdentity(source, pd, dept)
end)

local function respondUnit(source, callId)
    local _, pd, dept, name = playerInfo(source)
    local call = Calls[tostring(callId)]
    if not call or not departmentSet(call.departments)[dept] then return false, 'Call unavailable' end
    call.units[pd.citizenid] = { citizenid = pd.citizenid, source = source, name = name, department = dept }
    call.updatedAt = os.time(); call.revision = (call.revision or 0) + 1
    if Units[pd.citizenid] then
        Units[pd.citizenid].callId = call.id
        Units[pd.citizenid].operationId = call.operation.id
        Units[pd.citizenid].radioChannel = call.operation.channel
        Units[pd.citizenid].status = Config.AutoStatus.enRouteStatus
    end
    pushState()
    TriggerEvent('XS-Dispatch:server:callUpdated', call)
    return true, call
end

lib.callback.register('XS-Dispatch:server:respond', respondUnit)
exports('RespondUnit', respondUnit)

lib.callback.register('XS-Dispatch:server:leaveCall', function(source, callId)
    local _, pd, dept = playerInfo(source)
    local call = Calls[tostring(callId)]
    if not dept or not call then return false end
    call.units[pd.citizenid] = nil
    if Units[pd.citizenid] then
        Units[pd.citizenid].callId, Units[pd.citizenid].operationId, Units[pd.citizenid].radioChannel = nil, nil, nil
        Units[pd.citizenid].status = Config.AutoStatus.availableByDepartment[dept] or Config.Departments[dept].statuses[1]
    end
    call.updatedAt = os.time(); call.revision = (call.revision or 0) + 1; pushState(); TriggerEvent('XS-Dispatch:server:callUpdated', call); return true
end)

lib.callback.register('XS-Dispatch:server:clearCall', function(source, callId)
    local _, _, dept = playerInfo(source)
    local call = Calls[tostring(callId)]
    if not dept or not call or not departmentSet(call.departments)[dept] then return false end
    call.status, call.closedAt, call.updatedAt = 'closed', os.time(), os.time(); call.revision = (call.revision or 0) + 1
    for cid in pairs(call.units) do
        if Units[cid] then
            local unitDept = Units[cid].department
            Units[cid].callId, Units[cid].operationId, Units[cid].radioChannel = nil, nil, nil
            Units[cid].status = Config.AutoStatus.availableByDepartment[unitDept] or Config.Departments[unitDept].statuses[1]
        end
    end
    pushState(); TriggerEvent('XS-Dispatch:server:callClosed', call, source)
    pushDelta('call:remove', call); saveState()
    return true
end)

lib.callback.register('XS-Dispatch:server:getIntegrations', function(source)
    if not Config.IntegrationStudio.enabled or not IsPlayerAceAllowed(source, Config.IntegrationStudio.adminAce) then return nil end
    return Integrations
end)

lib.callback.register('XS-Dispatch:server:saveIntegration', function(source, data)
    if not Config.IntegrationStudio.enabled or not IsPlayerAceAllowed(source, Config.IntegrationStudio.adminAce) then return false, 'Forbidden' end
    if type(data) ~= 'table' then return false, 'Invalid data' end
    local id = tostring(data.id or ''):lower():gsub('[^%w_%-]', ''):sub(1, 32)
    if id == '' or Config.CallTypes[id] then return false, 'Invalid or reserved ID' end
    local departments = {}
    for _, dept in ipairs(data.departments or {}) do if Config.Departments[dept] then departments[#departments + 1] = dept end end
    if #departments == 0 then return false, 'Choose at least one department' end
    Integrations[id] = {
        label = tostring(data.label or id):sub(1, 80), code = tostring(data.code or 'CALL'):sub(1, 16),
        priority = math.max(1, math.min(3, tonumber(data.priority) or 2)), departments = departments,
        sprite = math.max(1, tonumber(data.sprite) or 280), color = math.max(0, tonumber(data.color) or 5),
    }
    saveIntegrations(); return true, Integrations[id]
end)

lib.callback.register('XS-Dispatch:server:deleteIntegration', function(source, id)
    if not Config.IntegrationStudio.enabled or not IsPlayerAceAllowed(source, Config.IntegrationStudio.adminAce) then return false end
    id = tostring(id or '')
    if not Integrations[id] then return false end
    Integrations[id] = nil; saveIntegrations(); return true
end)

local function setUnitStatus(source, status, skipProvider)
    local _, pd, dept = playerInfo(source)
    if not dept then return false end
    status = ((Config.StatusAliases[dept] or {})[status]) or status
    local allowed = false
    for _, candidate in ipairs(Config.Departments[dept].statuses) do if candidate == status then allowed = true break end end
    if not allowed then return false end
    Units[pd.citizenid] = Units[pd.citizenid] or { citizenid = pd.citizenid, source = source, department = dept }
    Units[pd.citizenid].status, Units[pd.citizenid].updatedAt = status, os.time()
    pushState()
    if not skipProvider and DispatchProviders and DispatchProviders.PushUnitStatus then
        DispatchProviders.PushUnitStatus(source, status, { origin='XS-Dispatch' })
    end
    return true
end

lib.callback.register('XS-Dispatch:server:setStatus', setUnitStatus)
exports('SetUnitStatus', setUnitStatus)

RegisterNetEvent('XS-Dispatch:server:position', function(data)
    local src = source
    local _, pd, dept, name = playerInfo(src)
    if not dept or type(data) ~= 'table' then return end
    local pedCoords = GetEntityCoords(GetPlayerPed(src))
    local sent = vector3(tonumber(data.x) or 0, tonumber(data.y) or 0, tonumber(data.z) or 0)
    if #(pedCoords - sent) > 50.0 then sent = pedCoords end
    local unit = Units[pd.citizenid] or {}
    unit.citizenid, unit.source, unit.name, unit.department = pd.citizenid, src, name, dept
    local identity = resolveIdentity(src, pd, dept)
    unit.job, unit.callsign, unit.badge, unit.unitType, unit.identitySource = pd.job.name, identity.callsign, identity.badge, identity.unitType, identity.source
    unit.coords = { x = sent.x, y = sent.y, z = sent.z }
    unit.heading, unit.vehicleClass, unit.vehicleLabel = tonumber(data.heading) or 0, data.vehicleClass or 'foot', data.vehicleLabel
    unit.status, unit.updatedAt = unit.status or Config.Departments[dept].statuses[1], os.time()
    Units[pd.citizenid] = unit
    pushDelta('unit:upsert', unit)
end)

RegisterNetEvent('XS-Dispatch:server:panic', function()
    local src = source
    local _, pd, dept, name = playerInfo(src)
    if not dept or (panicCooldown[src] or 0) > os.time() then return end
    panicCooldown[src] = os.time() + Config.Panic.cooldownSeconds
    local coords = GetEntityCoords(GetPlayerPed(src))
    local departments = dept == 'fire' and { 'fire', 'ems' } or { dept }
    createCall({ type = dept == 'police' and 'officer_backup' or (dept == 'ems' and 'medical' or 'fire'), title = name .. ' activated PANIC', description = 'Emergency activation from an on-duty responder.', priority = 1, departments = departments, coords = coords, caller = name }, src)
end)

RegisterNetEvent('XS-Dispatch:server:civilianCall', function(callType, message, street)
    if not Config.AllowCivilianCommands then return end
    local src = source
    if (civilianCooldown[src] or 0) > os.time() then return end
    local player = Framework.GetPlayer(src)
    if not player or type(message) ~= 'string' or #message < 3 then return end
    civilianCooldown[src] = os.time() + 30
    local pd, coords = player.PlayerData, GetEntityCoords(GetPlayerPed(src))
    local char = pd.charinfo or {}
    -- Network clients may only create the public emergency preset. Rich/custom
    -- calls must use the server export so clients cannot spoof department alerts.
    createCall({ type = '911', description = message, coords = coords, street = street, caller = (char.firstname or '') .. ' ' .. (char.lastname or '') }, src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    for cid, unit in pairs(Units) do if unit.source == src then Units[cid] = nil; pushDelta('unit:remove', unit) end end
    panicCooldown[src] = nil; pushState()
    civilianCooldown[src] = nil
end)

CreateThread(function()
    while true do Wait(Config.Persistence.saveIntervalSeconds * 1000); saveState() end
end)

AddEventHandler('onResourceStop', function(resource) if resource == GetCurrentResourceName() then saveState() end end)

XSDispatchCore = {
    version = 1,
    createCall = createCall,
    getCall = function(id) return Calls[tostring(id)] end,
    getCalls = function() return Calls end,
    pushDelta = pushDelta,
    fieldTypes = FieldTypes,
    getUnits = function() return Units end,
    setUnitData = function(citizenid, patch)
        local unit = Units[citizenid]
        if not unit then return false end
        for key, value in pairs(patch or {}) do unit[key] = value end
        pushDelta('unit:upsert', unit); return true
    end,
}

exports('RegisterIdentityProvider', function(name, resolve)
    if type(name) ~= 'string' or type(resolve) ~= 'function' then return false end
    IdentityProviders[#IdentityProviders + 1] = { name = name, resolve = resolve }
    return true
end)

CreateThread(function()
    while true do
        Wait(60000)
        local cutoff = os.time() - Config.CallRetentionMinutes * 60
        for id, call in pairs(Calls) do if call.status == 'closed' and (call.closedAt or 0) < cutoff then Calls[id] = nil end end
        for cid, unit in pairs(Units) do if os.time() - unit.updatedAt > Config.UnitTimeout * 3 then Units[cid] = nil end end
    end
end)
