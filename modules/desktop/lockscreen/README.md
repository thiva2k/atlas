# desktop/lockscreen

Installs the Atlas lock-screen HUD, a Plasma look-and-feel package
(`org.atlas.hud`), at
`$XDG_DATA_HOME/plasma/look-and-feel/org.atlas.hud/` (user scope, no root).
Installing does **not** change which lock-screen theme is active — Atlas
never overwrites `kscreenlockerrc` on `install`.

## Activating

`atlas activate desktop/lockscreen` reversibly switches
`kscreenlockerrc [Greeter] Theme` to `org.atlas.hud`, recording whatever
theme was active before (write-once escrow, per RFC-0029). The new theme
takes effect at the **next lock**, not live — `kscreenlocker_greet` reads
`Theme` only when it spawns.

## Reverting

- `atlas deactivate desktop/lockscreen` restores the prior theme exactly (or
  removes the `Theme` key if none was set before).
- Manual escape (from a TTY, or if the greeter won't come up): run
  `kwriteconfig6 --file kscreenlockerrc --group Greeter --key Theme --delete`
  and lock again. With no `Theme` key, kscreenlocker falls back to its
  default look-and-feel package — a broken or unavailable Atlas QML never
  leaves the machine unable to lock/unlock, it just falls back to the
  system default locker.

## Honesty note on verification

This QML was written directly against the real kscreenlocker greeter
reference on this machine
(`/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/`) —
the auth wiring (`authenticator.respond()`, `Connections { target:
authenticator }`, `succeeded`/`failed`/`promptForSecretChanged`) is copied
structurally from that reference. There is no `qmllint`/`qml6`/
`kscreenlocker_greet` available in the environment that built this module,
so the QML could **not** be executed or type-checked before shipping. Treat
the first real lock as the actual test, always with the revert path above
ready, and prefer running it first in a separate session/VT you can recover
from (`loginctl lock-session`, or a nested Plasma session) if available.

See `docs/rfcs/RFC-0035-lockscreen-hud.md` for the full design and testing
rationale.
