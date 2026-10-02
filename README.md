# Roon Volume

A personal macOS menu-bar app that routes the normal volume and mute keys to your selected Roon outputs while they are playing.

## Build

Requires Apple Silicon, macOS 13 or later, Swift **6.4** command-line tools (including SwiftPM's native build system), and Node **24.21.0** at build time. This is the toolchain used to build and test this project; older Swift 6 toolchains are not validated.

```sh
cd helper
npm ci --ignore-scripts
cd ..
bash scripts/build.sh
```

The result is `dist/Roon Volume.app`. It includes the Node executable and all helper dependencies; Node is not required on the machine running the app. `ROON_NODE_PATH` can specify the build-time runtime. The packaging script checks its version and signs the runtime and app locally. Keep the app at a stable path after granting Accessibility access; rebuilding may require granting access again.

## Setup

1. Launch `dist/Roon Volume.app` and look for the speaker icon in the menu bar.
2. Grant Accessibility access in System Settings → Privacy & Security → Accessibility. The app retries key capture after permission is granted.
3. Enable **Roon Volume** in Roon Settings → Extensions. Allow local network access if prompted.
4. Select your 8C and WiiM in **Controlled outputs**. Output IDs, rather than names, are saved.
5. Optionally enable **Launch at login**. For ongoing use, copy the app to `~/Applications` before enabling this.

When one eligible zone plays, volume keys control that zone's configured outputs. When the 8C and WiiM are grouped, both change by one native step. Other grouped outputs are excluded. When both rooms play independently, choose the preferred room in **When both rooms play**; without a preference, keys are consumed and an overlay asks you to choose. When nothing eligible plays, Roon disconnects, or **Use Mac volume** is enabled, normal Mac volume behavior applies.

Mute toggles the selected outputs together: if any is unmuted, mute all; otherwise unmute all. Outputs without mute feedback cannot use mute. Numeric and dB outputs use native relative steps; incremental controls use relative ±1. The overlay shows Roon's reported values, not an estimated new volume. On macOS 26 and later it uses a compact native Liquid Glass capsule with a speaker icon and short fades; older macOS versions use a blurred HUD background. Reduce Motion disables the fades, and feedback updates do not extend the 1.5-second display timeout.

The helper drops repeats while a command is pending. Pipe writes run on a background queue with a bounded backlog and a 100 ms write deadline; a stalled pipe causes the helper to terminate and reconnect rather than block the event tap. It rejects stale targets and does not replay requests after reconnection. A press held across a disconnect remains consumed until release; the next press returns to normal routing. Other media keys are unaffected. Restart delays grow from 3 seconds to a maximum of 60 seconds, resetting after 30 seconds of stable runtime.

## Theater / miniDSP Tide16

On first discovery, **Theater Audio** is automatically selected and mapped to the Tide16 at **10.0.0.130**. The app resolves that name once and saves the stable Roon output ID. **Configure Tide16…** in the speaker menu lets you change the IP address or hostname, choose a different Roon output, or remove the mapping. A DHCP reservation keeps the IP stable; a Pi-hole DNS record is also supported.

While the mapped output plays, volume keys change the Tide16 master volume by **0.5 dB**, and mute controls the Tide16. Chromecast volume is left at its existing setting. The overlay uses actual Tide16 feedback, including changes from its remote or front panel. The mapping works with fixed-volume Roon outputs and follows the same grouping and room preference rules as the other outputs. Use **When multiple rooms play** to choose between independently playing rooms.

The helper connects directly to the [official Tide16 WebSocket API](https://docs.minidsp.com/product-manuals/tide16/websocket-api/index.html) on port 5555; Home Assistant is not required. It reads current state before each change, drops repeats while waiting, and never replays commands after reconnecting. When disconnected or in Dirac measurement mode, the mapped output is unavailable for key routing; the app never falls back to changing Chromecast volume. The menu shows the Tide16 connection status. If macOS prompts, allow **Roon Volume** local-network access in System Settings → Privacy & Security → Local Network. Actual device response still requires an interactive check after launching the app.

Tests also cover Tide16 step sizes and bounds, live feedback, calibration, timeout handling, grouped control, and configuration changes during pending commands.

## Validation

```sh
bash scripts/test.sh
```

Automated tests cover automatic routing, simultaneous playback, grouping, excluded outputs, fixed volume, mute, incremental volume, stale connections, repeat backpressure, partial failures, press ownership across disconnects, generation pinning, and repeat throttling. Seek-only and irrelevant now-playing changes are suppressed; snapshots carry only routing and volume fields. Menus are built when opened, and volume feedback never extends the overlay's hide timer. Actual keyboard interception, Roon authorization, sleep/wake, and device response need an interactive check on your Mac.

Try each room independently, then both separately, then grouped. Check that a routed key changes Roon volume without changing Mac volume; pause playback and verify Mac volume works again. Hold a key briefly, test mute, and restart Roon to confirm recovery without delayed volume changes. If key capture fails, check Accessibility permission and other apps intercepting media keys. Secure input or a locked session may prevent interception.

The app bundle identifier and Roon extension ID are `tech.frat.roon-volume`. Authorization and diagnostics are stored in `~/Library/Application Support/RoonVolume/`; preferences use the `tech.frat.roon-volume` defaults domain. Saved output selections and preferences from the original identifier are migrated automatically on first launch. Changing identifiers requires enabling the extension again in Roon and granting macOS Accessibility access to the new app identity. If launch at login was enabled, disable the old entry in System Settings → General → Login Items, then enable it again from the updated app. The previous helper log is retained as `helper.log.1` on each launch; all parent file handles are closed on termination. Quit stops the helper and removes the event tap. This version is locally signed for personal use; public distribution, notarization, Intel support, updates, and playback controls are outside its scope.

Locally signed updates change the app's signing requirement, which can invalidate Accessibility access. If keys stop working after rebuilding, turn Roon Volume off and back on in Accessibility settings. If necessary, remove the old entry and add the rebuilt app at its current path. The app reports missing access on startup and retries automatically. `status.json` in Application Support records permission, event-tap, and Roon connection status without authorization tokens and is written only when that status changes. If you have a code-signing certificate, set `ROON_SIGNING_IDENTITY` to its identity when building to use a consistent signing identity across updates.

## Architecture

Swift owns the menu, permission flow, event tap, press routing, and volume overlay. A child Node process uses the official Roon API for discovery, pairing, zone subscriptions, and transport control. Newline-delimited JSON over stdin/stdout carries configuration, snapshots, commands, and results; there is no HTTP server. Dependency revisions and transitive dependencies are pinned in `helper/package-lock.json`.

Roon libraries are Apache-2.0 licensed; bundled dependencies retain their license files. Node's license is included in the packaged resources.
