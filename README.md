<h1 align="center">XS-Dispatch</h1>

<p align="center">Multi-department live dispatch and responder tracking for <strong>QBox</strong> and <strong>QBCore</strong>.</p>

<p align="center">
  <a href="https://github.com/XyraL/XS-Dispatch/releases"><img src="https://img.shields.io/github/v/release/XyraL/XS-Dispatch?style=flat-square&color=55e2ad&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/framework-QBox%20%7C%20QBCore-55dcff?style=flat-square" alt="framework">
  <img src="https://img.shields.io/badge/status-beta-f5a524?style=flat-square" alt="status: beta">
  <img src="https://img.shields.io/badge/price-free-30d158?style=flat-square" alt="price">
  <a href="https://discord.gg/XRURAw4TM2"><img src="https://img.shields.io/badge/support-discord-5865F2?style=flat-square" alt="support"></a>
</p>

<p align="center">
  <a href="https://github.com/XyraL/XS-Dispatch/releases">Releases</a> &nbsp;·&nbsp;
  <a href="https://discord.gg/XRURAw4TM2">Support</a>
</p>

---

> **Beta.** Still being worked on, so expect rough edges. If you hit one, tell
> me on [Discord](https://discord.gg/XRURAw4TM2) and I will get it sorted.

## Features

- Police, EMS, and Fire departments with independent job lists, colors, statuses, alert identities, and map blips
- Vehicle-aware unit tracking: foot, patrol vehicle, motorcycle, bicycle, boat, helicopter, and plane
- Per-department visibility rules for mutual aid or isolated radio networks
- Shared multi-department incidents
- P1/P2/P3 call priority, live elapsed timers, GPS routing, responding units, and call clearing
- Department-aware responder console with live unit telemetry
- Panic key and civilian `/911` command
- Server-side position validation and authorization
- QBox/QBCore auto-detecting bridge
- Server export for other resources
- Quick responder overlay with one-key response (`Y`) and toggle (`U`)
- Per-incident operational groups and generated TAC radio channels
- Optional `pma-voice` channel joining (`I`)
- Automatic En Route / On Scene status detection with hysteresis
- Advanced tracking states: assignment highlighting, out-of-service dimming, operation and radio labels
- ACE-protected Integration Studio with persistent custom call presets
- Versioned provider API for phone, MDT, voice, and future adapters
- Custom call-field registry with text, person, vehicle, patient, hazard, and checklist primitives
- Generic bidirectional phone contract and caller-update hook
- MDT lifecycle events and record linking without direct database access
- Multi-member operational units with leaders, callsigns, vehicles, and capabilities
- Delta-based live unit synchronization
- Restart recovery for active calls and call numbering

## Requirements

- `ox_lib`
- `qbx_core` or `qb-core`

Start after the framework and dependencies:

```cfg
ensure XS-Dispatch
```

The default console key is **F6** and panic key is **F5**. Both are rebindable in GTA settings. These defaults deliberately avoid XS-MDT's existing F10/F11 bindings.

To allow Integration Studio access:

```cfg
add_ace group.admin xs.dispatch.integrations allow
```

Custom presets are stored in `data/integrations.json`. The studio cannot overwrite built-in call types.

## Compatibility architecture

External resources should integrate through providers and exports rather than editing XS-Dispatch. Provider registration:

```lua
exports['XS-Dispatch']:RegisterProvider('phone', 'my-phone', {
    sendStatus = function(call, status) end,
    sendMessage = function(call, message) end,
})
```

Rich call fields can be extended at runtime:

```lua
exports['XS-Dispatch']:RegisterFieldType('alarm_zone', {
    label = 'Alarm Zone',
    icon = 'sensor',
})
```

Call lifecycle API:

```lua
exports['XS-Dispatch']:UpdateCall(callId, { priority = 1 })
exports['XS-Dispatch']:AddCallNote(callId, {
    author = 'Bank Alarm',
    text = 'Rear motion sensor activated.',
})
exports['XS-Dispatch']:LinkMdtRecord(callId, 'XS-MDT', incidentId)
```

Phone adapters submit emergency data with `SubmitPhoneEmergency` or the server event `XS-Dispatch:server:phoneEmergency`. They can listen for `XS-Dispatch:provider:phone:callerUpdate` to deliver responder messages back to callers.

MDT adapters consume `XS-Dispatch:provider:mdt:callCreated` and `XS-Dispatch:provider:mdt:callClosed`. XS-Dispatch never reads another resource's database tables.

MDTs can supply responder callsigns without XS-Dispatch knowing their schema:

```lua
exports['XS-Dispatch']:RegisterIdentityProvider('my-mdt', function(source)
    return exports['my-mdt']:GetDispatchIdentity(source)
end)
```

The identity must return `{ callsign, badge?, unitType? }`. Export-based MDTs can also be added to `Config.MdtIdentityAdapters`. Resolution order is registered MDT provider, framework metadata, saved Dispatch profile, then generated fallback. XS-MDT support is included natively.

## Operational units

The server callbacks `createUnit`, `joinUnit`, and `leaveUnit` support multi-member patrols, ambulance crews, engine companies, and specialist teams. Units may carry capability IDs such as `als_medical`, `fire_suppression`, `air_support`, or `supervisor`. UI management for these primitives is the next unit-system phase.


## Creating calls

Server-side resources can create fully customized calls:

```lua
local callId, call = exports['XS-Dispatch']:CreateCall({
    type = 'fire',
    title = 'Commercial Structure Fire',
    description = 'Multiple callers report smoke from the roof.',
    priority = 1,
    departments = { 'fire', 'ems', 'police' },
    coords = vector3(215.4, -810.2, 30.7),
    street = 'San Andreas Avenue',
    caller = 'Automatic Alarm',
    sprite = 436,
    color = 1,
})
```

Other server exports:

```lua
exports['XS-Dispatch']:GetCall(callId)
exports['XS-Dispatch']:GetActiveCalls()
```

Events are also emitted for integrations:

```lua
AddEventHandler('XS-Dispatch:server:callCreated', function(call) end)
AddEventHandler('XS-Dispatch:server:callClosed', function(call, closedBy) end)
```

## Unique department tracking

Each entry in `Config.Departments` controls:

- Framework jobs belonging to that department
- Departments whose units it can see
- GTA blip color
- Separate blip sprites for every vehicle category
- Allowed operational statuses
- UI identity and alert tone name

This lets Fire apparatus remain visually distinct from EMS ambulances and Police patrol units, even when all three respond to the same incident.

## Operational radio

Every incident receives an operation ID and TAC channel. With `pma-voice` running, assigned responders can press **I** to join that channel. Automatic channel switching is disabled by default so XS-Dispatch does not unexpectedly pull players away from their existing radio channel; enable it with `Config.Radio.autoJoinOperations`.

## Documentation

Full setup guide, requirements and troubleshooting:
**[xyralscripts.dev/docs-xs-dispatch](https://xyralscripts.dev/docs-xs-dispatch)**

## Support

- **Found a bug?** [Open an issue](https://github.com/XyraL/XS-Dispatch/issues)
- **Need setup help?** [Join the Discord](https://discord.gg/XRURAw4TM2) — check the setup guide first, it usually has the answer

## My other scripts

All free, all source-available.

| Script | What it is |
|---|---|
| **[XS-CriminalTablet](https://github.com/XyraL/XS-CriminalTablet)** | modular criminal device for QBox and QBCore — gang ops, blackmarket and boosting in one encrypted tablet. |
| **[XS-MDT](https://github.com/XyraL/XS-MDT)** | multi-department MDT for QBox — police, EMS and fire with live CAD, records, patient care and a live unit map. |
| **[XS-AdminMenu](https://github.com/XyraL/XS-AdminMenu)** | advanced admin suite for QBox and QBCore — player management, bans, reports, inventory tools and entity inspection. |
| **[XS-Drone](https://github.com/XyraL/XS-Drone)** | deployable police drone for QBox and QBCore — smooth flight, thermal, spotlight, tracker darts and real counterplay. |
| **[XS-Trucking](https://github.com/XyraL/XS-Trucking)** | civilian trucking job for QBox and QBCore — live route map, truck ownership, fuel and maintenance, and companies. |
| **[XS-MultiCharacter](https://github.com/XyraL/XS-MultiCharacter)** | cinematic character selection for QBox and QBCore — identity dossiers, saved appearances, spawn cameras and configurable slots. |

## License

Free to use on any server you own or operate, including commercial ones.
**Do not redistribute or resell** — see [LICENSE](LICENSE) for the full terms.
