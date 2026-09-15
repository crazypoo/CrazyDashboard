# CrazyTrace Replay Fixtures

The fixture catalog is deterministic and does not access Bluetooth, ELM327, YMOBD, Jieli SDK, or a vehicle.

`PTReplayFixtureCatalog.swift` covers the Build 62 groups:

- XP400 lifecycle, authentication, credits, malformed input, and navigation.
- ELM327 initialization, PID, UDS, CAN monitor, timeout, and bus lease recovery.
- YMOBD detection, authentication, version, and firmware-check metadata.
- OTA state-only transitions. No OTA fixture executes a Jieli command.
- CAN event windows and combined XP400 + OBD traces.

The empty directories next to this catalog are reserved for later raw, consented fixtures. Raw captures must be redacted before they are committed.
