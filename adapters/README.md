# XS integration adapters

XS-Dispatch and XS-MDT do not depend on each other. Each resource has
an internal provider and a stable registration API. Adapter resources should
be separate FiveM resources so core updates never overwrite compatibility code.

## Connect an MDT to XS-Dispatch

Register a sink during your adapter's server startup:

```lua
exports['XS-Dispatch']:RegisterMdtProvider('my-mdt', {
    resource = GetCurrentResourceName(),
    priority = 50,
    onCallCreated = function(call, envelope) end,
    onCallUpdated = function(call, envelope) end,
    onCallClosed = function(call, envelope) end,
    onStatus = function(source, status, envelope) end,
})
```

For calls originating in that MDT, use `SubmitProviderCall(action, call,
envelope)`. The envelope requires `origin`, `externalId`, and an increasing
`revision`. Supported actions are `created`, `updated`, and `closed`.

Identity-only MDTs can call:

```lua
exports['XS-Dispatch']:RegisterIdentityProvider('my-mdt', function(source, playerData)
    return { callsign = 'A-12', badge = '204', unitType = 'field' }
end)
```

## Connect a dispatch resource to XS-MDT

Register a provider with `exports['XS-MDT']:RegisterDispatchProvider`.
Required methods are `getActiveCalls`, `createCall`, `respond`,
`setCallStatus`, and `addCallNote`. See `dispatch_provider_template.lua`.

XS-MDT uses `Config.DispatchProvider = 'auto'` by default. It selects the
highest-priority running provider and immediately returns to internal CAD if
that resource stops.

## Suggested resource mappings

- ps-mdt / qb-mdt: translate their server call events into the MDT sink.
- lb-tablet: keep the adapter in a separate resource and translate its dispatch
  app callbacks into the same sink.
- Sonoran CAD: perform HTTP/API work inside its adapter; never place credentials
  in either XS resource.
- Other dispatch scripts: register the dispatch-provider template or configure
  `Config.DispatchAdapters` with their server export names.
