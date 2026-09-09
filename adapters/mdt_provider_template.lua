-- Copy into a separate adapter resource and translate TODO sections to the
-- target MDT. XS-Dispatch continues running if this adapter/MDT stops.
CreateThread(function()
    exports['XS-Dispatch']:RegisterMdtProvider('my-mdt', {
        resource = GetCurrentResourceName(), priority = 50,
        onCallCreated = function(call, envelope) -- TODO
        end,
        onCallUpdated = function(call, envelope) -- TODO
        end,
        onCallClosed = function(call, envelope) -- TODO
        end,
        onStatus = function(source, status, envelope) -- TODO
        end,
    })

    exports['XS-Dispatch']:RegisterIdentityProvider('my-mdt', function(source)
        -- TODO: query callsign/badge from the target MDT
        return nil
    end)
end)

local revisions = {}
local function submit(action, externalCall)
    local id = tostring(externalCall.id)
    revisions[id] = (revisions[id] or 0) + 1
    return exports['XS-Dispatch']:SubmitProviderCall(action, externalCall, {
        origin = GetCurrentResourceName(), externalId = id, revision = revisions[id],
    })
end
