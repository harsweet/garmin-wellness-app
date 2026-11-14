# Momo

A native Connect IQ app for the **fēnix 7 Pro**, featuring three moods of Momo and playful, stubbed remarks about the day.

Momo's three moods and remarks remain demo content. The calendar now uses sample meetings and saved walking breaks through a demo service. The app requests Communications permission for that connection. AI, real sensor readings, Google account access, notifications, and activity verification remain outside this demo.

## Calendar demo — no Google account needed

Requires Node 22+ and the Garmin SDK. Start the calendar in one terminal:

```sh
npm run calendar:demo
```

Wait for **HTTPS demo ready**, then launch the watch in a second terminal:

```sh
./scripts/ciq.sh run
```

**Hold UP** on Momo to open Calendar. Use UP / DOWN to select one of three available eight-minute walks, press START, and confirm. The walk is added only after confirmation. View the sample meetings and saved walks at http://127.0.0.1:8787; it updates automatically.

Garmin rejects plain HTTP requests, including in the simulator. The demo command downloads Cloudflare's `cloudflared` helper on its first macOS run and creates a temporary public HTTPS URL serving only sample calendar data. No Google account or Cloudflare account is required. The URL lasts while the demo command runs and changes on restart, so rebuild/relaunch the watch after restarting it. An installed helper can be specified with `CLOUDFLARED`.

The default time zone is America/Edmonton; set `MOMO_TIME_ZONE` before starting the demo to change it. Suggestions are between 08:00 and 20:00, include two-minute buffers, and expire after ten minutes. New conflicts are checked before saving; retries cannot duplicate a saved walk. Walks persist in `.local/demo-calendar.json`, and sample meetings are refreshed on service startup. Momo shows a **DEMO CALENDAR** badge throughout. These events do not touch Google Calendar.

The generated URL override lives in gitignored `resources-fenix7pro/`. Generated builds use that embedded URL ahead of saved app settings, so old HTTP addresses or expired demo URLs cannot override a newly built demo. Builds without an embedded URL use the editable calendar URL setting. The standalone Google Apps Script bridge in `integrations/google-calendar/` is preparation for a later live-account phase; it is not used or live-tested by this demo.

## Run

Install Garmin's Connect IQ SDK, its fēnix 7 Pro device profile, and a Java runtime. Select an SDK in SDK Manager, then run:

```sh
./scripts/ciq.sh build
./scripts/ciq.sh run
```

The build is written to `bin/Momo.prg`. The run command opens the Garmin simulator and launches the fēnix 7 Pro app. Its terminal process remains attached while the app runs.

The script uses the SDK selected in `~/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg`. Override it with `CIQ_SDK_PATH`. For signing, it uses `CIQ_DEVELOPER_KEY`, an existing `~/Documents/developer_key`, or generates a private, gitignored development key under `.local/`.

The VS Code tasks provide the same build/run/test commands. The optional Monkey C launch configuration requires Garmin's Monkey C extension and its developer-key setting.

## Controls

- **UP / DOWN:** cycle through sleepy, chill, and thriving Momo.
- **START / tap Momo:** show another stubbed remark.
- **Swipe:** change mood.
- **Tap a bottom dot:** choose a mood directly.
- **Hold UP:** open Calendar.
- **Hold the screen:** open the controls/help screen.
- **BACK:** close help or exit the app.

The three character images in `assets/momo/` are the supplied originals. Garmin's resource compiler scales them for the watch display.

## Tests

```sh
./scripts/ciq.sh test
```

This builds and runs the Monkey C tests in the fēnix 7 Pro simulator, with results in `bin/test-results.log`. SDK 9.1.0 sometimes returns a nonzero exit code after passing tests; the script requires the runner's explicit passing summary.

Calendar checks:

```sh
npm run calendar:test
npm run calendar:smoke
```

The smoke test requires the demo service to be running. It launches a separate native test app in the simulator and uses the actual watch networking client to fetch slots, save one **demo** walk, and retry the same request. It intentionally adds one sample walk to the demo calendar. It refuses live Google URLs.
