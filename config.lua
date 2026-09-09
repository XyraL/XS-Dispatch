Config = {}

Config.OpenKey = 'F6'
Config.QuickRespondKey = 'Y'
Config.QuickOverlayKey = 'U'
Config.RadioKey = 'I'
Config.OnDutyOnly = true
Config.PositionInterval = 1500
Config.UnitTimeout = 12
Config.CallRetentionMinutes = 30
Config.MaxActiveCalls = 100
Config.AllowCivilianCommands = true

-- Visibility is department based. Add "all" to show every responder.
Config.Departments = {
    police = {
        label = 'Law Enforcement', short = 'LEO', color = '#54a7ff', blipColor = 3,
        jobs = { police = true, sheriff = true, statepolice = true, swat = true },
        sees = { police = true, ems = true, fire = true },
        statuses = { '10-8 Available', '10-6 Busy', '10-7 Out of Service', 'En Route', 'On Scene', 'Transporting' },
        sprites = { foot = 1, car = 56, motorcycle = 226, bicycle = 348, boat = 427, helicopter = 64, plane = 307 },
        alertTone = 'police',
    },
    ems = {
        label = 'Emergency Medical', short = 'EMS', color = '#43e0c1', blipColor = 2,
        jobs = { ambulance = true, ems = true, doctor = true },
        sees = { police = true, ems = true, fire = true },
        statuses = { 'Available', 'En Route', 'On Scene', 'Treating', 'Transporting', 'At Hospital', 'Out of Service' },
        sprites = { foot = 153, car = 61, motorcycle = 226, bicycle = 348, boat = 427, helicopter = 64, plane = 307 },
        alertTone = 'ems',
    },
    fire = {
        label = 'Fire & Rescue', short = 'FIRE', color = '#ff654f', blipColor = 1,
        jobs = { fire = true, firefighter = true },
        sees = { police = true, ems = true, fire = true },
        statuses = { 'Available', 'En Route', 'On Scene', 'Staging', 'Fire Attack', 'Rescue', 'Returning', 'Out of Service' },
        sprites = { foot = 436, car = 436, motorcycle = 226, bicycle = 348, boat = 427, helicopter = 64, plane = 307 },
        alertTone = 'fire',
    },
}

Config.CallTypes = {
    ['911'] = { label = 'Emergency Call', code = '911', priority = 2, departments = { 'police', 'ems', 'fire' }, sprite = 280, color = 1 },
    shots_fired = { label = 'Shots Fired', code = '10-71', priority = 1, departments = { 'police' }, sprite = 110, color = 1 },
    officer_backup = { label = 'Officer Requests Backup', code = '10-78', priority = 1, departments = { 'police' }, sprite = 161, color = 1 },
    medical = { label = 'Medical Emergency', code = 'MED-1', priority = 1, departments = { 'ems' }, sprite = 153, color = 2 },
    fire = { label = 'Structure Fire', code = 'FIRE-1', priority = 1, departments = { 'fire', 'ems', 'police' }, sprite = 436, color = 1 },
    rescue = { label = 'Technical Rescue', code = 'RESCUE', priority = 1, departments = { 'fire', 'ems' }, sprite = 436, color = 47 },
    tow = { label = 'Tow Request', code = '311-TOW', priority = 3, departments = { 'police' }, sprite = 68, color = 5 },
    custom = { label = 'Dispatch Call', code = 'CALL', priority = 2, departments = { 'police' }, sprite = 280, color = 5 },
}

Config.CallBlip = { scale = 0.9, routeColor = 5, flashPriorityOne = true }
Config.Panic = { cooldownSeconds = 20, key = 'F5' }

Config.QuickOverlay = {
    enabled = true,
    alertSeconds = 12,
    showWhileAssigned = false,
}

Config.AutoStatus = {
    enabled = true,
    arrivalRadius = 65.0,
    leaveRadius = 110.0,
    arrivalStatus = 'On Scene',
    enRouteStatus = 'En Route',
    availableByDepartment = {
        police = '10-8 Available',
        ems = 'Available',
        fire = 'Available',
    },
}

Config.StatusAliases = {
    police = {
        ['10-8'] = '10-8 Available', ['10-8 Available'] = '10-8 Available',
        ['10-6'] = '10-6 Busy', ['10-6 Busy'] = '10-6 Busy',
        ['10-7'] = '10-7 Out of Service', ['10-7 Out of Service'] = '10-7 Out of Service',
        ['Code 4'] = 'On Scene',
    },
    ems = { ['10-8'] = 'Available', ['10-6'] = 'Out of Service' },
    fire = { ['10-8'] = 'Available', ['10-6'] = 'Out of Service' },
}

Config.Radio = {
    enabled = true,
    resource = 'pma-voice',
    autoJoinOperations = false,
    operationChannelBase = 500,
    operationChannelRange = 300,
}

Config.IntegrationStudio = {
    enabled = true,
    adminAce = 'xs.dispatch.integrations',
    saveFile = 'data/integrations.json',
}

Config.Providers = {
    phone = 'generic',
    mdt = 'auto',
}

-- Add any MDT that exposes a server identity function returning a table with
-- callsign and optional badge/unitType. No core edits are needed.
Config.MdtIdentityAdapters = {
    -- { resource = 'my-mdt', export = 'GetDispatchIdentity' },
}

-- Optional full MDT sinks. Dispatch remains fully operational when none are
-- present. Third-party MDTs can also register at runtime via RegisterMdtProvider.
Config.MdtAdapters = {
    -- { id='ps-mdt', resource='ps-mdt', priority=60, exports={
    --   identity='GetDispatchIdentity', callCreated='CreateDispatchCall',
    --   callUpdated='UpdateDispatchCall', callClosed='CloseDispatchCall', status='SetUnitStatus' } },
}

Config.Persistence = {
    enabled = true,
    stateFile = 'data/state.json',
    saveIntervalSeconds = 30,
}

Config.Profiles = {
    file = 'data/profiles.json',
    callsignMaxLength = 20,
    badgeMaxLength = 16,
}
