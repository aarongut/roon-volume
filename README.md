# Roon Volume

A personal macOS menu-bar app that routes the normal volume and mute keys to your selected Roon outputs while they are playing.

## Build

Requires Apple Silicon, macOS 13 or later, Swift 6 command-line tools, and Node **24.21.0** at build time.

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

Mute toggles the selected outputs together: if any is unmuted, mute all; otherwise unmute all. Outputs without mute feedback cannot use mute. Numeric and dB outputs use native relative steps; incremental controls use relative ±1. The overlay shows Roon's reported values, not an estimated new volume.

The helper drops repeats while a command is pending. It rejects stale targets and does not replay requests after reconnection. A press held across a disconnect remains consumed until release; the next press returns to normal routing. Other media keys are unaffected.

## Validation

```sh
bash scripts/test.sh
```

Automated tests cover automatic routing, simultaneous playback, grouping, excluded outputs, fixed volume, mute, incremental volume, stale connections, repeat backpressure, and partial failures. Actual keyboard interception, Roon authorization, sleep/wake, and device response need an interactive check on your Mac.

Try each room independently, then both separately, then grouped. Check that a routed key changes Roon volume without changing Mac volume; pause playback and verify Mac volume works again. Hold a key briefly, test mute, and restart Roon to confirm recovery without delayed volume changes. If key capture fails, check Accessibility permission and other apps intercepting media keys. Secure input or a locked session may prevent interception.

The app bundle identifier and Roon extension ID are `tech.frat.roon-volume`. Authorization and diagnostics are stored in `~/Library/Application Support/RoonVolume/`; preferences use the `tech.frat.roon-volume` defaults domain. Saved output selections and preferences from the original identifier are migrated automatically on first launch. Changing identifiers requires enabling the extension again in Roon and granting macOS Accessibility access to the new app identity. If launch at login was enabled, disable the old entry in System Settings → General → Login Items, then enable it again from the updated app. The helper log is reset on helper launch. Quit stops the helper and removes the event tap. This version is locally signed for personal use; public distribution, notarization, Intel support, updates, and playback controls are outside its scope.

Locally signed updates change the app's signing requirement, which can invalidate Accessibility access. If keys stop working after rebuilding, turn Roon Volume off and back on in Accessibility settings. If necessary, remove the old entry and add the rebuilt app at its current path. The app reports missing access on startup and retries automatically. `status.json` in Application Support records permission, event-tap, and Roon connection status without authorization tokens. If you have a code-signing certificate, set `ROON_SIGNING_IDENTITY` to its identity when building to use a consistent signing identity across updates.

## Architecture

Swift owns the menu, permission flow, event tap, press routing, and volume overlay. A child Node process uses the official Roon API for discovery, pairing, zone subscriptions, and transport control. Newline-delimited JSON over stdin/stdout carries configuration, snapshots, commands, and results; there is no HTTP server. Dependency revisions and transitive dependencies are pinned in `helper/package-lock.json`.

Roon libraries are Apache-2.0 licensed; bundled dependencies retain their license files. Node's license is included in the packaged resources.
