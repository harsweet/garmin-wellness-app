# Momo

A native **fēnix 7 Pro / Connect IQ** wellness companion with phone onboarding and a Node backend. The calendar contains demo meetings; calendar writes and completion simulations are labeled **DEMO**.

## Run locally

Requires Node 22+, Garmin Connect IQ SDK 9.1.0, its fēnix 7 Pro device profile, and a Garmin developer key.

```sh
npm install
cp .env.example .env
```

Keep an existing `.env` rather than overwriting it. Set `XAI_API_KEY` there to enable Grok; `XAI_MODEL` defaults to `grok-4.7`. Without a key, or when the provider fails, Momo uses **SCRIPTED** suggestions. Keys stay on the server and are excluded from Git.

Start the service in one terminal:

```sh
npm run calendar:demo
```

Wait for **HTTPS demo ready**, then launch the watch in another:

```sh
./scripts/ciq.sh run
```

Garmin requires HTTPS, so the local command starts a temporary Cloudflare Tunnel and configures the watch build automatically. It downloads `cloudflared` on the first macOS run; an existing binary can be supplied through `CLOUDFLARED`. Keep the service running. Restarting it changes the temporary hostname, so rebuild the watch afterward. Generated settings and the separate watch access token live in gitignored `.local/` and `resources-fenix7pro/`; saved simulator settings cannot override the current generated URL.

## Try the full experience

1. Momo always starts on setup: a QR on the first page, a four-digit code and setup URL on the next.
2. Scan the QR, or open `/setup` and type the four-digit code. Choose your goals and optionally add context. No name or account details are required. New profiles use the phone's time zone automatically.
3. Save on the phone. The watch checks every three seconds and continues once this pairing is saved. Reopen **Setup** from the watch's hold-UP menu to edit the same device; launching the app again after a completed pairing registers a new device.
4. Press **START** on Momo for a personalized activity. UP/DOWN switches detail pages; START offers **Let's go**, **Later**, or **Something else** in a compact action picker. Hold UP opens the home menu, including **Setup**.
5. Accepting requires confirmation before adding a demo calendar event. Later snoozes suggestions for thirty minutes. Alternatives avoid repeating the activity where possible.
6. Start the accepted activity. The watch tracks foreground time and observed daily-step deltas. Hold UP during a demo activity for **Simulate finish**, or explicitly self-report completion.
7. Answer whether it helped. Acceptance, completion, snooze, and helpfulness counts influence future activity ranking.

Walking, gentle stretching, breathing, and quiet rest are supported. Goals, saved context (up to 1,000 characters), activity history, and calendar availability inform Grok's choice and short, humorous line. Profile constraints determine eligible activities; Grok cannot invent arbitrary activities or book anything without acceptance. Updating goals or context invalidates old suggestions. Meeting titles are excluded from the model prompt. Recommendations are cached and provider requests throttled. Existing profiles keep their prior activity and accessibility preferences when using the simplified form.

Phone QR links and four-digit codes are one-time, expire after ten minutes, and grant a browser session scoped to one wearer. Using either invalidates the other. Short-code attempts are rate limited; only hashes are stored. That session can edit its own profile and read private demo data, but cannot invoke paid AI calls or impersonate the watch. Goals, context, feedback, and demo bookings persist on the backend across restarts; relevant profile details and aggregate feedback are included in Grok requests.

## Admin and separate watches

Open **http://127.0.0.1:8787/admin** on the development computer. The page leads with how to register a watch. Local access opens the watch room directly; public/tunnel access requires the key in `.local/admin-token` (or `MOMO_ADMIN_TOKEN`). Admin sessions use an HttpOnly cookie; phone setup sessions do not grant admin access.

Each paired watch is its own row: goals, saved context, completions, accepts, snoozes, and helpful / not-helpful ratings. Completing setup on the phone is what identifies the device — codes are one-time, and the phone cannot save goals until it claims a QR or four-digit code. **Pair another watch** mints a new device with its own QR/code; **Show on this simulator** points the current watch connection at that device. Launching Momo after a watch is already paired mints a new device automatically.

Local data is stored in gitignored `.local/workspace.json`; the previous single-user `.local/demo-calendar.json` is migrated automatically on first launch. Existing profile context and activity history are preserved.

The three home-screen moods and their day remarks remain selectable demo states. Activity tracking pauses when its screen is hidden; this version does not provide background tracking, sleep analysis, or verified health outcomes. Simulator completion evidence is labeled simulated. Suggestions are requested in the app; all-day background notifications are not implemented.

## Deploy to Vercel

Use **one Vercel project + Upstash Redis**. The function serves the phone UI, admin, and watch API; Redis persists the workspace and separate wearer profiles, QR/code sessions, suggestions, demo meetings, bookings, and feedback across cold starts.

1. Import this GitHub repository into Vercel. Select **Other** as the framework preset and the repository root as the root directory. `vercel.json` routes requests to `api/index.mjs`.
2. Add **Upstash Redis** through the project's Storage/Marketplace integration and connect it to the project. The adapter accepts `UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN`, or legacy `KV_REST_API_URL` / `KV_REST_API_TOKEN` names.
3. Add `XAI_API_KEY`, optional `XAI_MODEL`, `MOMO_DEVICE_TOKEN`, and `MOMO_ADMIN_TOKEN` to Vercel's server environment. Use the local `.local/demo-device-token` and `.local/admin-token` values for the matching watch and admin. The Grok and admin keys must never go in watch resources.
4. Set `MOMO_PUBLIC_URL` to the stable production HTTPS URL, then redeploy. Otherwise the adapter uses Vercel's system production URL. Use the public production deployment; Vercel login protection must allow the watch's API requests. Momo authenticates its own requests.
5. Configure that deployment URL locally and rebuild:

```sh
node scripts/calendar-url.mjs https://your-project.vercel.app
./scripts/ciq.sh run
```

If changing `MOMO_DEVICE_TOKEN`, update the local `.env` with the same value before configuring/rebuilding. The deployment fails closed when credentials or persistent storage are missing. Redis leases prevent concurrent function instances from duplicating writes. Neither Vercel nor Upstash credentials are needed for the local file-backed demo.

Deployment configuration and mocked cold-start/storage tests are included. A live Vercel deployment still requires your Vercel project and Redis connection; a live Grok call requires a filled API key.

References: [Vercel storage integrations](https://vercel.com/docs/marketplace-storage), [Upstash Vercel setup](https://upstash.com/docs/redis/howto/vercelintegration), [xAI Responses API](https://docs.x.ai/developers/rest-api-reference/inference/responses).

## Verification

```sh
npm run calendar:test
./scripts/ciq.sh test
npm run calendar:smoke
# With XAI_API_KEY configured in the running service, require a real Grok reply:
REQUIRE_GROK=1 npm run calendar:smoke
```

The Node tests cover calendar conflicts, personalization, model validation/fallback, QR access, and serverless persistence. Native tests use the simulator's fonts and graphics to verify screens, controls, QR geometry, confirmation, timers, and step resets. The smoke test requires the local demo to run and intentionally creates/completes a demo activity; it refuses live Google URLs. `REQUIRE_GROK=1` also fails if the actual suggestion uses scripted fallback. A cached successful Grok suggestion may be reused.

`./scripts/ciq.sh build` creates `bin/Momo.prg`. Build artifacts, `.env`, generated connection settings, local state, and signing keys are ignored by Git. The standalone Google Apps Script bridge under `integrations/google-calendar/` is preparation for a later real-calendar phase and is not used by this demo.
