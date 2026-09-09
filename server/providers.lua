DispatchProviders = { registered = {}, active = {} }
local MdtProviders = {}
local ProviderLinks, ProviderRevisions = {}, {}
local phoneCooldown = {}

local function started(resource) return not resource or GetResourceState(resource) == 'started' end

local function registerMdtProvider(id, provider)
    if type(id) ~= 'string' or type(provider) ~= 'table' then return false end
    provider.id, provider.priority = id, tonumber(provider.priority) or 0
    MdtProviders[id] = provider
    return true
end

exports('RegisterMdtProvider', registerMdtProvider)

local function adapterExport(resource, name, ...)
    if not name or not started(resource) then return false end
    local args = { ... }
    local ok, result = pcall(function() return exports[resource][name](table.unpack(args)) end)
    return ok and result or false
end

for _, adapter in ipairs(Config.MdtAdapters or {}) do
    local names = adapter.exports or {}
    registerMdtProvider(adapter.id, {
        resource=adapter.resource, priority=adapter.priority,
        onCallCreated=function(call, envelope) return adapterExport(adapter.resource, names.callCreated, call, envelope) end,
        onCallUpdated=function(call, envelope) return adapterExport(adapter.resource, names.callUpdated, call, envelope) end,
        onCallClosed=function(call, envelope) return adapterExport(adapter.resource, names.callClosed, call, envelope) end,
        onStatus=function(src, status, envelope) return adapterExport(adapter.resource, names.status, src, status, envelope) end,
    })
end

local function selectedMdts()
    local configured, selected = Config.Providers.mdt or 'auto', {}
    for id, provider in pairs(MdtProviders) do
        if started(provider.resource) and (configured == 'auto' or configured == id) then selected[#selected + 1] = provider end
    end
    return selected
end

local function deliver(method, ...)
    for _, provider in ipairs(selectedMdts()) do
        if type(provider[method]) == 'function' then pcall(provider[method], ...) end
    end
end

function DispatchProviders.PushUnitStatus(src, status, envelope)
    deliver('onStatus', src, status, envelope or { origin='XS-Dispatch' })
end

function DispatchProviders.Health()
    local active, registered = {}, {}
    for _, provider in ipairs(selectedMdts()) do active[#active + 1] = provider.id end
    for id, provider in pairs(MdtProviders) do
        registered[#registered + 1] = { id=id, resource=provider.resource, running=started(provider.resource) }
    end
    return { mdtMode=Config.Providers.mdt or 'auto', activeMdts=active, phone=Config.Providers.phone, registeredMdts=registered }
end

exports('GetIntegrationStatus', function() return DispatchProviders.Health() end)

-- Stable bidirectional ingress. Provider revisions reject reflected or stale
-- changes and external IDs retain the relationship with the XS-Dispatch call.
exports('SubmitProviderCall', function(action, data, envelope)
    if type(data) ~= 'table' then return false, 'invalid call' end
    envelope = type(envelope) == 'table' and envelope or {}
    local origin = tostring(envelope.origin or data.origin or 'external')
    if origin == 'XS-Dispatch' then return false, 'loop rejected' end
    local externalId = tostring(envelope.externalId or data.externalId or data.id or '')
    if externalId == '' then return false, 'external id required' end
    local key, revision = origin .. ':' .. externalId, tonumber(envelope.revision) or 1
    if revision <= (ProviderRevisions[key] or 0) then return false, 'stale revision' end
    ProviderRevisions[key] = revision

    if action == 'created' then
        data.origin, data.externalId, data.providerRevision = origin, externalId, revision
        local id, call = XSDispatchCore.createCall(data, nil)
        if call then ProviderLinks[key] = id end
        return id, call
    end
    local id = ProviderLinks[key]
    if not id then return false, 'call link missing' end
    local linked = XSDispatchCore.getCall(id)
    if linked then linked.providerRevision = revision end
    if action == 'closed' then return exports['XS-Dispatch']:SetCallStatus(0, id, 'closed') end
    return exports['XS-Dispatch']:UpdateCall(id, data)
end)

lib.callback.register('XS-Dispatch:server:getIntegrationHealth', function(source)
    if not Config.IntegrationStudio.enabled or not IsPlayerAceAllowed(source, Config.IntegrationStudio.adminAce) then return nil end
    local health = DispatchProviders.Health()
    health.framework, health.dispatchApi, health.providerLinks = Framework.Kind(), XSDispatchCore.version, 0
    for _ in pairs(ProviderLinks) do health.providerLinks = health.providerLinks + 1 end
    return health
end)

CreateThread(function()
    Wait(0)
    for id, call in pairs(XSDispatchCore.getCalls()) do
        if call.origin and call.origin ~= 'XS-Dispatch' and call.externalId then
            local key = tostring(call.origin) .. ':' .. tostring(call.externalId)
            ProviderLinks[key], ProviderRevisions[key] = id, tonumber(call.providerRevision) or 0
        end
    end
    registerMdtProvider('XS-MDT', {
        resource='XS-MDT', priority=100,
        onStatus=function(src, status, envelope)
            return adapterExport('XS-MDT', 'SetDispatchStatus', src, status, envelope)
        end,
    })
    exports['XS-Dispatch']:RegisterIdentityProvider('XS-MDT', function(src)
        if GetResourceState('XS-MDT') ~= 'started' then return nil end
        local ok, identity = pcall(function() return exports['XS-MDT']:GetDispatchIdentity(src) end)
        return ok and identity or nil
    end)
    for _, adapter in ipairs(Config.MdtIdentityAdapters or {}) do
        exports['XS-Dispatch']:RegisterIdentityProvider(adapter.resource, function(src)
            if GetResourceState(adapter.resource) ~= 'started' then return nil end
            local ok, identity = pcall(function() return exports[adapter.resource][adapter.export](src) end)
            return ok and identity or nil
        end)
    end
end)

exports('RegisterProvider', function(category, name, provider)
    if type(category) ~= 'string' or type(name) ~= 'string' or type(provider) ~= 'table' then return false end
    DispatchProviders.registered[category] = DispatchProviders.registered[category] or {}
    DispatchProviders.registered[category][name] = provider
    if Config.Providers[category] == name then DispatchProviders.active[category] = provider end
    return true
end)

exports('GetProvider', function(category) return DispatchProviders.active[category] end)

-- Stable generic phone contract. Phone adapters translate their native events
-- to this event and can listen for reply/status events below.
RegisterNetEvent('XS-Dispatch:server:phoneEmergency', function(data)
    local src = source
    if type(data) ~= 'table' or type(data.message) ~= 'string' then return end
    if src <= 0 or #data.message < 3 or #data.message > 500 then return end
    if (phoneCooldown[src] or 0) > os.time() then return end
    phoneCooldown[src] = os.time() + 30
    local coords = GetEntityCoords(GetPlayerPed(src))
    XSDispatchCore.createCall({
        type = '911', description = data.message, caller = data.caller or 'Phone caller',
        coords = coords, street = data.street, fields = data.fields,
    }, src)
end)

AddEventHandler('playerDropped', function() phoneCooldown[source] = nil end)

exports('SubmitPhoneEmergency', function(data) return XSDispatchCore.createCall(data, nil) end)
exports('SendCallerUpdate', function(callId, message)
    local call = XSDispatchCore.getCall(callId)
    if not call then return false end
    TriggerEvent('XS-Dispatch:provider:phone:callerUpdate', call, tostring(message))
    return true
end)

-- MDTs consume these events or call these exports. XS-MDT can use the
-- same contract without dispatch core knowing its database schema.
AddEventHandler('XS-Dispatch:server:callCreated', function(call)
    deliver('onCallCreated', call, { origin='XS-Dispatch', revision=call.revision })
    TriggerEvent('XS-Dispatch:provider:mdt:callCreated', call)
end)
AddEventHandler('XS-Dispatch:server:callClosed', function(call, closedBy)
    deliver('onCallClosed', call, { origin='XS-Dispatch', revision=call.revision })
    TriggerEvent('XS-Dispatch:provider:mdt:callClosed', call, closedBy)
end)
AddEventHandler('XS-Dispatch:server:callUpdated', function(call)
    deliver('onCallUpdated', call, { origin='XS-Dispatch', revision=call.revision })
    TriggerEvent('XS-Dispatch:provider:mdt:callUpdated', call)
end)
exports('LinkMdtRecord', function(callId, provider, recordId)
    local call = XSDispatchCore.getCall(callId)
    if not call then return false end
    call.mdtLinks = call.mdtLinks or {}
    call.mdtLinks[#call.mdtLinks + 1] = { provider = provider, recordId = recordId }
    XSDispatchCore.pushDelta('call:upsert', call); return true
end)
