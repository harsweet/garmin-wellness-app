import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import path from 'node:path';

// Runs the production client against LOCAL DEMO fixtures only. Never targets Google.
const root = fileURLToPath(new URL('../', import.meta.url));
const sdk = process.env.CIQ_SDK_PATH || (await readFile(path.join(homedir(), 'Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg'), 'utf8')).trim();
const key = process.env.CIQ_DEVELOPER_KEY || path.join(homedir(), 'Documents/developer_key');
const endpoint = JSON.parse(await readFile(path.join(root, '.local/calendar-endpoint.json'), 'utf8'));
if (endpoint.mode !== 'demo' || !/^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/.test(endpoint.url)) {
  throw new Error('Start npm run calendar:demo first to configure the HTTPS demo endpoint.');
}
await mkdir(path.join(root, '.local/calendar-smoke'), { recursive: true });
const source = `import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
class MomoCalendarSmokeApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }
    function getInitialView() {
        // Reproduce the stale simulator setting reported by the user.
        Application.Properties.setValue("CalendarServerUrl", "http://127.0.0.1:8787");
        return [new MomoCalendarSmokeView()];
    }
}
class MomoCalendarSmokeView extends WatchUi.View {
    var client;
    var suggestionId;
    var activity;
    function initialize() { View.initialize(); client = new MomoCalendarClient(); }
    function onShow() {
        if (!client.getServerUrl().equals("${endpoint.url}")) {
            fail("saved HTTP setting overrode the current HTTPS demo URL"); return;
        }
        System.println("CALENDAR_SMOKE: current HTTPS URL overrides saved HTTP setting");
        client.onboarding(method(:gotOnboarding));
    }
    function fail(message) { System.println("CALENDAR_SMOKE_FAIL: " + message); System.exit(); }
    function gotOnboarding(code, data) {
        if (code != 200 || data == null || !(data["qr"] instanceof Array) || data["qr"].size() < 21) {
            fail("onboarding code=" + code); return;
        }
        System.println("CALENDAR_SMOKE: received scannable onboarding QR rows");
        client.suggestions(method(:gotSuggestion));
    }
    function gotSuggestion(code, data) {
        if (code != 200 || data == null || !(data["suggestion"] instanceof Dictionary)) {
            fail("suggestions code=" + code + "; finish any pending demo activity first"); return;
        }
        suggestionId = data["suggestion"]["id"];
        System.println("CALENDAR_SMOKE: suggestion source=" + data["aiSource"]);
        // This explicit automated test accepts only a local demo activity.
        client.decide(suggestionId, "accept", method(:created));
    }
    function created(code, data) {
        if (code != 200 || data == null || !data["status"].equals("created") || !data["mode"].equals("demo")) {
            fail("create code=" + code); return;
        }
        activity = data["activity"];
        System.println("CALENDAR_SMOKE: created local demo walk");
        client.decide(suggestionId, "accept", method(:retried));
    }
    function retried(code, data) {
        if (code != 200 || data == null || !data["status"].equals("already_created")) {
            fail("idempotent retry code=" + code); return;
        }
        client.startActivity(activity["id"], method(:started));
    }
    function started(code, data) {
        if (code != 200 || data == null || !(data["activity"] instanceof Dictionary)) {
            fail("start code=" + code); return;
        }
        var source = activity["tracking"].equals("steps") ? "simulated_steps" : "simulated_timer";
        client.completeActivity(activity["id"], source, activity["stepTarget"], activity["durationMinutes"] * 60, method(:completed));
    }
    function completed(code, data) {
        if (code != 200 || data == null || !data["status"].equals("completed")) {
            fail("complete code=" + code); return;
        }
        client.feedback(activity["id"], "yes", method(:rated));
    }
    function rated(code, data) {
        if (code != 200 || data == null || !data["status"].equals("recorded")) {
            fail("feedback code=" + code); return;
        }
        System.println("CALENDAR_SMOKE_PASS: QR, suggestion, accept, retry, start, simulated completion, feedback");
        System.exit();
    }
}
`;
await writeFile(path.join(root, '.local/calendar-smoke/Smoke.mc'), source);
const original = await readFile(path.join(root, 'manifest.xml'), 'utf8');
await writeFile(path.join(root, '.local/calendar-smoke-manifest.xml'), original.replace('entry="MomoApp"', 'entry="MomoCalendarSmokeApp"').replace('8ec561a2c052478bb47de99f4e02683d', '2a514567d650421991a225378cf88014'));
await writeFile(path.join(root, '.local/calendar-smoke.jungle'), 'project.manifest = calendar-smoke-manifest.xml\nbase.sourcePath = ../source;calendar-smoke\nbase.resourcePath = ../resources\nfenix7pro.resourcePath = ../resources;../resources-fenix7pro\n');
const result = spawnSync(path.join(sdk, 'bin/monkeyc'), ['-f', '.local/calendar-smoke.jungle', '-d', 'fenix7pro', '-y', key, '-o', 'bin/Momo-calendar-smoke.prg', '-w'], { cwd: root, stdio: 'inherit' });
if (result.status !== 0) process.exit(result.status || 1);
spawnSync(path.join(sdk, 'bin/connectiq'), [], { stdio: 'inherit' });
const child = spawn(path.join(sdk, 'bin/monkeydo'), [path.join(root, 'bin/Momo-calendar-smoke.prg'), 'fenix7pro'], { cwd: root });
let log = '';
child.stdout.on('data', chunk => { log += chunk; process.stdout.write(chunk); });
child.stderr.on('data', chunk => { log += chunk; process.stderr.write(chunk); });
const timeout = setTimeout(() => child.kill('SIGTERM'), 60_000);
child.on('exit', () => {
  clearTimeout(timeout);
  process.exitCode = log.includes('CALENDAR_SMOKE_PASS:') && !log.includes('CALENDAR_SMOKE_FAIL:') ? 0 : 1;
});
