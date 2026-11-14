# Chair Cartel

Your chair runs a criminal empire. Take a short break to rob it.

A three-stage Monkey C watch game for **Fenix 7 Pro** (`fenix7pro`, 260 × 260,
API 5.2), built with **Connect IQ SDK 9.1.0** for the Tech Thursday x Garmin
hackathon. The differentiator is an ordered sequence of physical mini-games:
movement charges a tool, wrist turns solve a combination, and heading plus
stillness complete extraction.

## Run

```sh
./scripts/ciq.sh run
```

Or open the project in VS Code and press **F5** with the official Garmin
Monkey C extension. Select **Run Chair Heist (Fenix 7 Pro)**. VS Code uses the
SDK selected in Garmin SDK Manager; keep **9.1.0** selected. The shell helper
explicitly finds and checks that version.

The app opens in clearly labeled **DEMO** mode. It does not automatically
pretend that your computer is providing physical sensor readings.

## Controls

| Button | Briefing | During a mission | Debrief |
| --- | --- | --- | --- |
| START, upper right | Deploy | In DEMO, inject the current action | Helpful / then next heist |
| UP, middle left | Toggle DEMO / LIVE | Optional stairs route during charging, if altitude is available | — |
| DOWN, lower left | Open stash | — | Not helpful / then stash |
| BACK, lower right | Exit | Abort to briefing | Return to briefing |

## Simulator walkthrough

1. Leave **DEMO** selected and press **START** to deploy.
2. **Charge gadget:** press START six times. Each press injects four walking
   steps; the gadget charges after 24 steps.
3. **Crack safe:** press START to turn toward the highlighted target. The
   combination is **clockwise to 45°, counterclockwise to −30°, clockwise to
   60°**. Each press turns 15°. Stop and hold for half a second at each target
   to latch its pin. Follow the live dial and three pin indicators.
4. **Align antenna:** press START to turn toward **EAST / 90°** in 15° steps.
   Hold within 15° of east for one second.
5. **Quiet extraction:** press START for a stillness sample, then wait four
   seconds. Movement resets the stillness countdown.
6. Receive **100 loot**, answer whether the break helped with START or DOWN,
   and repeat. The stash and feedback survive app restarts.

Demo deliberately has **no GPS fix and no solar reading**. The indoor route
remains fully playable; those inputs never gate completion. Demo loot, runs,
and ratings are saved separately from live physical breaks.

## Live sensor roles

Choose LIVE with UP on the briefing, then deploy. Sensor listeners only run
during the mission and stop on completion, abort, or screen hide.

| Sensor | Mechanic |
| --- | --- |
| Accelerometer | Debounced motion peaks count walking steps; stillness seals extraction |
| Gyroscope | Integrates wrist turns into the ordered safe dial |
| Compass | Aligns the antenna east; includes visible heading and hold progress |
| GPS | Adds a live excursion distance; no fix uses the indoor walking route |
| Barometric altitude | UP offers an optional 3m stairs route; altitude gain can add 25 loot |
| Heart rate | Shows effort feedback; elevated readings insert a quiet rest branch |
| Solar intensity | Available outdoor intensity can add 25 loot; no reading simply skips it |

Missing live motion, gyro, or compass readings never count as success.
The heart-rate rest branch asks for quiet time; there is no requirement to
raise heart rate or reach a target pulse. The model is a gameplay prototype,
and motion thresholds and gyro direction still need validation on a real watch.

The simulator demonstrates the complete flow through explicit demo samples.
It does not validate physical sensor accuracy. This is a foreground app;
background break reminders are not implemented.

## Saved progress

A versioned local Application.Storage record tracks loot, completed sessions,
and helpful/not-helpful responses in separate live and demo ledgers.
A mission awards once, and its feedback is counted once. GPS coordinates are
used transiently to calculate distance; no route or raw sensor data is saved
or transmitted. The app requests only Sensor and Positioning permissions.

## Build and tests

```sh
./scripts/ciq.sh build
./scripts/ciq.sh test
```

Build output is `bin/ChairHeist.prg`. Tests use Garmin's Run No Evil framework
in the Fenix simulator. Test code is excluded from regular builds.
Build artifacts and developer keys are ignored by Git.

The helper finds SDK 9.1.0 under
`~/Library/Application Support/Garmin/ConnectIQ/Sdks/` and reuses
`~/Documents/developer_key`. Override if needed:

```sh
CIQ_SDK_PATH="/path/to/connectiq-sdk-mac-9.1.0-..." \
CIQ_DEVELOPER_KEY="/path/to/developer_key" ./scripts/ciq.sh run
```

## Code map

- `source/HeistMission.mc`: stage sequence, hold/reset rules, rewards, feedback, storage.
- `source/HeistSensors.mc`: live sensors, availability/freshness checks, demo injection.
- `source/WellnessView.mc`: native watch graphics, villain chair, dial and compass UI.
- `source/WellnessDelegate.mc`: physical button mapping.
- `source/WellnessApp.mc`: app lifecycle and sensor cleanup.
- `manifest.xml`: Fenix 7 Pro target and permissions.
