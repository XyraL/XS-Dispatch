-- Patching the registrar rather than each call site gives every NUI callback
-- in the resource two guarantees, including any added later:
--
-- 1. Each handler runs in its own thread. FiveM will not dispatch the next
--    NUI callback while the current one is still yielding.
-- 2. A nil payload is sent as `false`. cb(nil) sends no response body at all,
--    leaving the page's fetch pending forever.
if not IsDuplicityVersion() and type(RegisterNUICallback) == 'function' then
    local _registerNUI = RegisterNUICallback

    RegisterNUICallback = function(name, handler)
        return _registerNUI(name, function(data, cb)
            CreateThread(function()
                handler(data, function(payload, ...)
                    if payload == nil then payload = false end
                    cb(payload, ...)
                end)
            end)
        end)
    end
end

Framework = Framework or {}

local side = IsDuplicityVersion() and 'server' or 'client'
local kind, core

local function detect()
    if GetResourceState('qbx_core') == 'started' then kind = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then kind = 'qbcore'; core = exports['qb-core']:GetCoreObject()
    else error(('[XS-Dispatch] No supported framework found on %s.'):format(side)) end
end

detect()

function Framework.GetPlayer(src)
    if side ~= 'server' then return nil end
    if kind == 'qbox' then return exports.qbx_core:GetPlayer(src) end
    return core.Functions.GetPlayer(src)
end

function Framework.GetPlayerData()
    if side ~= 'client' then return nil end
    if kind == 'qbox' then return exports.qbx_core:GetPlayerData() end
    return core.Functions.GetPlayerData()
end

function Framework.GetPlayers()
    local result = {}
    for _, raw in ipairs(GetPlayers()) do
        local src = tonumber(raw)
        local player = Framework.GetPlayer(src)
        if player then result[src] = player end
    end
    return result
end

function Framework.Kind() return kind end
