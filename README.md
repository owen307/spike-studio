# Spike Prime Studio

<img src="assets/brand/sp-mark.png" width="96" alt="Spike Prime Studio mark: white SP letters and amber circuit traces">

Block coding, a teach recorder, and a Bluetooth link for hubs that run **SPIKE App 3** firmware. The app is SPIKE Prime compatible. The mark is an original SP monogram. It is not a LEGO logo, and the app does not ship official artwork.

The shared UI is Flutter. One codebase builds an Android debug APK and Flutter desktop (Linux, plus scripts for macOS and Windows). A labeled mock hub lets you use the editor with no radio.

## What works

- Word-block editor: events, motors, drive pairs, sensors, waits, wait-until, repeat, forever, if, variables, my blocks, comments, and a “together” group that starts simple motor moves at the same time.
- Undo and redo (80 snapshots). Desktop shortcuts: Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z, Ctrl/Cmd+Enter to download and run, Ctrl/Cmd+D to duplicate, Delete to remove the selection.
- Teach mode records motor positions on a timer (or when a motor moves at least 4°) and turns that trace into editable blocks. Relative mode emits `motor.run_for_degrees` plus waits. Absolute mode emits `motor.run_to_absolute_position`. The generated comment says this is a keyframe approximation, not a continuous curve.
- Project library with rename and duplicate. Projects stay in app storage.
- Import and export of `.spstudio.json` and `.spstudio` zip files (project JSON plus `program.py`). Export of the generated MicroPython file. `examples/getting_started.spstudio.json` round-trips the built-in sample.
- Hub page: battery, firmware label, and a port map with live meters. On the mock hub you can drag the meters. On a real hub the values come from device notifications.
- Scan, connect, disconnect, download `program.py` into a slot (0–19), start, and stop, using the SPIKE App 3 BLE service. Live telemetry is requested at about 200 ms.
- Android arm64 debug APK and a Linux x64 release bundle under `dist/`.

## What is next

- A session against a physical hub. The protocol matches the published App 3 client and the unit tests replay those byte layouts. This environment has no hub, so connect, upload, and telemetry have not been proven on hardware.
- High-priority COBS bytes (`0x01`) are not reassembled as a separate stream. The framer buffers until the `0x02` delimiter, which matches the simple official example and is enough for normal replies.
- Teach does not fit a spline. Absolute poses wrap inside −180°…179° and drop extra full turns.
- Pybricks and older Powered Up (LWP3) hubs are out of scope. If the App 3 service is missing, connect fails with that reason.
- No firmware updates, no sound library beyond a beep, and no full parity with the official block catalog.

## Run it

```bash
flutter pub get
flutter run -d linux          # desktop, mock hub by default
flutter run -d chrome         # same UI in a browser; radio needs a desktop or Android build
```

The first screen explains pairing. Continue, then stay on **Mock hub** if you have no hardware. Switch to **Radio** on the Hub page when you want a real scan.

## Bluetooth

Firmware assumption: **SPIKE App 3**. The hub must be running that app’s MicroPython firmware, not Pybricks and not a hub that only speaks LWP3.

1. Turn the hub on. Close the official app and any other phone that is already connected. A hub accepts one BLE central.
2. On Android, allow Nearby devices (scan and connect). On Android 11 and older, also allow Location. The system requires that before it returns scan results. This app does not track where you are. Location permission is limited to SDK 30 and below in the manifest. Scan is marked `neverForLocation` on newer Android.
3. Open Hub, choose Radio, and scan. Entries that advertise service `0000fd02-0000-1000-8000-00805f9b34fb` are marked confirmed. Names containing “spike”, “lego”, or “hub” are listed as likely.
4. Connect. The app writes without response to RX `0000fd02-0001-…` and subscribes to TX `0000fd02-0002-…`.
5. It sends InfoRequest (`0x00`), reads the hub name (`0x18`), and asks for device notifications every 200 ms (`0x28`).
6. Download and run from the header or with Ctrl/Cmd+Enter. The upload clears the chosen slot (`0x46`; a nack on an empty slot is ignored), sends `program.py` (`0x0C` then `0x10` chunks with a running CRC), then ProgramFlow start (`0x1E`). Stop sends ProgramFlow stop on the same slot.

Desktop Bluetooth needs BlueZ (`bluetoothd` running) and permission to open the adapter. `flutter_blue_plus` is called with `License.nonprofit`.

Generated Python targets the App 3 modules: `motor`, `motor_pair`, `runloop`, `color_sensor`, `distance_sensor`, `force_sensor`, and `hub` (`port`, `button`, `light`, `light_matrix`, `sound`, `motion_sensor`).

## Teach mode and matches

Teach is for authoring. You move the robot by hand, keep the timeline you want, and turn it into blocks you can edit. A match program has to be autonomous: download it, start it, and leave the robot alone. Do not drive the robot from this app during a match.

Sampling defaults: 100 ms grid, 8° noise floor, 200 ms minimum hold. Recording itself stores a sample about every 40 ms, or sooner when any motor moves at least 4°. Several motors that move in the same stretch become one “together” block. A still stretch becomes `runloop.sleep_ms`.

## Projects

| File | Contents |
| --- | --- |
| `name.spstudio.json` | Pretty JSON, format `spstudio` version 1 |
| `name.spstudio` | Zip with `project.json` and `program.py` |
| `name.py` | Generated MicroPython only |

The library saves projects locally (`shared_preferences`). Export also writes a copy under the documents folder `spike_prime_studio/exports` when the platform allows it, and offers a save dialog.

```bash
dart run bin/dump_sample.dart   # refreshes examples/getting_started.*
flutter test
```

## Build

Artifacts already in this tree:

- `dist/spike-prime-studio-arm64-debug.apk` — Android arm64 debug
- `dist/spike-prime-studio-linux-x64.tar.gz` — Linux x64 release bundle

Rebuild:

```bash
./scripts/build_android_apk.sh    # needs ANDROID_HOME and an SDK
./scripts/build_linux.sh          # clang, cmake, ninja, GTK, liblzma, libbluetooth
./scripts/build_macos.sh          # macOS only
./scripts/build_windows.sh        # Windows only
```

The debug APK is for sideloading. It is not a Play Store release. On the phone, allow install from the source you use, then install the APK. The first launch asks for the Bluetooth permissions above.

Linux bundle:

```bash
mkdir -p /tmp/spike-studio
tar -xzf dist/spike-prime-studio-linux-x64.tar.gz -C /tmp/spike-studio
/tmp/spike-studio/spike_prime_studio
```

## References

Protocol code follows the public SPIKE App 3 documents and the Python example client, not a guessed framing:

- [LEGO/spike-prime-docs](https://github.com/LEGO/spike-prime-docs) — `examples/python/app.py`, `cobs.py`, `crc.py`, `messages.py`, and `tests/test_cobs.py`
- [SPIKE Prime docs site](https://lego.github.io/spike-prime-docs/)

`test/protocol_test.dart` checks CRC, three official COBS vectors, the 17-byte info struct, a device-notification payload, the `program.py` upload header, and the upload message order.

LWP3 (service `00001623`, characteristic `00001624`) is the older Powered Up radio. App 3 does not use it to download MicroPython. See the [LEGO Wireless Protocol docs](https://lego.github.io/lego-ble-wireless-protocol-docs/) and [Pybricks technical-info](https://github.com/pybricks/technical-info) ([Pybricks BLE profile](https://github.com/pybricks/technical-info/blob/master/pybricks-ble-profile.md), [assigned numbers](https://github.com/pybricks/technical-info/blob/master/assigned-numbers.md)). Pybricks hubs speak that profile, not the App 3 service, and are not supported here.

## Layout

- `lib/src/model` — projects and the block catalog
- `lib/src/codegen/python_gen.dart` — MicroPython
- `lib/src/protocol` — COBS, CRC, messages, upload session
- `lib/src/hub` — mock hub and the BLE hub (`ble_hub_stub.dart` keeps web builds off `dart:io`)
- `lib/src/teach` — timeline to blocks
- `lib/src/ui` — library, blocks, teach, hub, Python
