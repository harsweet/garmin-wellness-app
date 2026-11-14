# Google Calendar bridge

This single-owner Google Apps Script deployment avoids creating an OAuth client or running a server for the real integration. Google stores and refreshes the owner's authorization. Momo checks the primary calendar's free/busy periods and creates an eight-minute walking event only after confirmation.

1. Create a standalone project at https://script.google.com/ and paste `Code.gs`.
2. Under Project Settings, enable **Show appsscript.json manifest file**. Replace its contents with `appsscript.json`. Set its `timeZone` to your own IANA time zone.
3. Confirm **Calendar API v3** appears under Services. The manifest includes it to enable the Calendar API in the default Google Cloud project. If using a standard Cloud project, enable the Google Calendar API in that project's Cloud console too.
4. Run `setupMomo` in the editor and authorize the requested Google scopes. The execution log shows a pairing code valid for 15 minutes. Running this function verifies Calendar API access; it does not create an event.
5. Choose **Deploy → New deployment → Web app**, **Execute as: Me**, **Who has access: Anyone**. Copy the `/exec` deployment URL into Momo's calendar configuration.
6. Enter the pairing code on the watch. Each code works once. Run `setupMomo` again if the code expires. Pairing a new watch replaces the prior watch token.

Use the `/exec` URL, not the editor `/dev` preview URL. Google Workspace administrator policies can prevent anonymous web app deployments; in that case this deployment route is unavailable for that account.

The deployment URL is a public endpoint, while every calendar operation requires a paired-watch token. `doGet` returns only general instructions. Pairing attempts are capped at six per code. Tokens are hashed in Script Properties, and expired suggestions are rejected. Keep the deployment URL and watch token private. `disconnectMomo` removes paired-watch access without deleting calendar events.

## JSON contract

Every call is a POST containing JSON. Apps Script ContentService returns HTTP 200 even for application errors, so check for an `error` property in the JSON. Errors include `{error, message, httpStatus}`.

```json
{"action":"pair","code":"123456"}
{"action":"status","token":"paired-token"}
{"action":"availability","token":"paired-token"}
{"action":"activities","token":"paired-token","slotId":"proposed-slot-id"}
```

Successful pairing returns `{token, mode:"google"}`. Status returns `{configured, connected, mode, timeZone}`. Availability returns `{connected, mode, checkedAt, busyNow, slots:[{id,label,start,end,durationMinutes}],message}`. Activity creation returns `{status:"created"|"already_created",label,eventUrl,mode}`.

Suggestions are eight minutes long, within the next 24 hours and between 08:00 and 20:00 in the script's time zone, with two-minute buffers around busy periods. A free calendar slot is an opportunity, not a guarantee that the wearer is available. The bridge rechecks availability before insertion, serializes local confirmations, and uses a deterministic Google event ID to recover uncertain writes without duplicates. Google Calendar does not offer an atomic free/busy-and-insert reservation, so unrelated calendar changes can still race that last check.

## Local simulator harness

The root project provides a separate local fixture calendar with the same JSON contract. It explicitly marks its responses as demo and never calls Google. Its successful tests do not validate live Google authorization or this Apps Script deployment.

The Apps Script globals used by `Code.gs` are: `PropertiesService.getScriptProperties().getProperty/setProperty`, `LockService.getScriptLock().tryLock/releaseLock`, `Utilities.getUuid`, `Utilities.computeDigest`, `Utilities.DigestAlgorithm.SHA_256`, `Utilities.Charset.UTF_8`, `Utilities.formatDate`, `Session.getScriptTimeZone`, `ScriptApp.getOAuthToken`, `UrlFetchApp.fetch`, `ContentService.createTextOutput`, `ContentService.MimeType.JSON`, and `console.log`.

`UrlFetchApp.fetch` responses need `getResponseCode()` and `getContentText()`. Formatting patterns used are `yyyy-MM-dd`, `HH`, `mm`, and `h:mm a`. Public helpers suitable for VM tests include `dispatchMomo_`, `findSlotsMomo_`, `normalizeBusyMomo_`, `createActivityMomo_`, and `pairMomo_`.
