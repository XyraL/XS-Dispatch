local Teams, teamSequence = {}, 0

local function identity(source)
    local player = Framework.GetPlayer(source)
    if not player then return end
    return player.PlayerData.citizenid, player.PlayerData
end

local function departmentFor(pd)
    local job = pd and pd.job
    if not job or (Config.OnDutyOnly and not job.onduty) then return nil end
    for id, department in pairs(Config.Departments) do
        if department.jobs[job.name] then return id end
    end
end

local function safeCapabilities(values)
    local result = {}
    for _, value in ipairs(type(values) == 'table' and values or {}) do
        local id = tostring(value):lower():gsub('[^%w_%-]', ''):sub(1, 32)
        if id ~= '' and #result < 16 then result[#result + 1] = id end
    end
    return result
end

lib.callback.register('XS-Dispatch:server:createUnit', function(source, data)
    local cid, pd = identity(source)
    if not cid or type(data) ~= 'table' then return false end
    local department = departmentFor(pd)
    if not department then return false end
    teamSequence = teamSequence + 1
    local id = ('U%03d'):format(teamSequence)
    Teams[id] = {
        id = id, callsign = tostring(data.callsign or id):sub(1, 20), leader = cid,
        department = department, type = tostring(data.type or 'field'):lower():gsub('[^%w_%-]', ''):sub(1, 24),
        vehicleNetId = tonumber(data.vehicleNetId), capabilities = safeCapabilities(data.capabilities),
        members = { [cid] = { source = source, role = 'leader' } },
        createdAt = os.time(),
    }
    XSDispatchCore.setUnitData(cid, { teamId = id, callsign = Teams[id].callsign, capabilities = Teams[id].capabilities })
    return true, Teams[id]
end)

lib.callback.register('XS-Dispatch:server:joinUnit', function(source, id)
    local cid, pd = identity(source); local team = Teams[tostring(id)]
    if not cid or not team or departmentFor(pd) ~= team.department then return false end
    team.members[cid] = { source = source, role = 'member' }
    XSDispatchCore.setUnitData(cid, { teamId = team.id, callsign = team.callsign, capabilities = team.capabilities })
    return true, team
end)

lib.callback.register('XS-Dispatch:server:leaveUnit', function(source)
    local cid = identity(source)
    if not cid then return false end
    for id, team in pairs(Teams) do
        if team.members[cid] then
            team.members[cid] = nil; XSDispatchCore.setUnitData(cid, { teamId = false, capabilities = {} })
            if not next(team.members) then Teams[id] = nil end
            return true
        end
    end
    return false
end)

exports('GetOperationalUnits', function() return Teams end)

AddEventHandler('playerDropped', function()
    local dropped = source
    for id, team in pairs(Teams) do
        for cid, member in pairs(team.members) do
            if member.source == dropped then team.members[cid] = nil end
        end
        if not next(team.members) then
            Teams[id] = nil
        elseif not team.members[team.leader] then
            local nextLeader, member = next(team.members)
            team.leader = nextLeader
            member.role = 'leader'
        end
    end
end)
