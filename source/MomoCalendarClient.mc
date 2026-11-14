import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Google Apps Script runs the calendar integration in the user's Google account.
// Only its revocable device token is stored on the watch.
class MomoCalendarClient {
    private var _callback as Method or Null = null;
    private var _timer as Timer.Timer or Null = null;
    private var _requestId as Number = 0;

    function initialize() {}

    function getServerUrl() as String {
        // Simulator properties survive rebuilds. A generated demo build must use
        // its current endpoint even if the original HTTP address was saved before.
        var builtIn = WatchUi.loadResource(Rez.Strings.CalendarBuildServerUrl) as String;
        var value = builtIn.length() > 0 ? builtIn : Application.Properties.getValue("CalendarServerUrl");
        var url = value instanceof String && value.length() > 0 ? value : "";
        while (url.length() > 0 && url.substring(url.length() - 1, url.length()).equals("/")) {
            url = url.substring(0, url.length() - 1);
        }
        return url;
    }

    function hasServer() as Boolean {
        var url = getServerUrl();
        // Loopback is only for the explicitly labelled simulator adapter.
        if (isDemoServer()) {
            return true;
        }
        var prefix = "https://script.google.com/macros/s/";
        return url.length() > prefix.length() + 5 &&
            url.substring(0, prefix.length()).equals(prefix) &&
            url.substring(url.length() - 5, url.length()).equals("/exec");
    }

    function isDemoServer() as Boolean {
        var url = getServerUrl();
        var suffix = ".trycloudflare.com";
        var hosted = ".vercel.app";
        return url.equals("http://127.0.0.1:8787") || url.equals("http://localhost:8787") ||
            (url.length() > suffix.length() + 8 && url.substring(0, 8).equals("https://") &&
            url.substring(url.length() - suffix.length(), url.length()).equals(suffix)) ||
            (url.length() > hosted.length() + 8 && url.substring(0, 8).equals("https://") &&
            url.substring(url.length() - hosted.length(), url.length()).equals(hosted));
    }

    function hasToken() as Boolean {
        // The loopback adapter contains only fixtures and requires no account.
        if (isDemoServer()) { return true; }
        var token = Application.Storage.getValue("calendarToken");
        var origin = Application.Storage.getValue("calendarTokenOrigin");
        return token instanceof String && token.length() > 0 && origin instanceof String && origin.equals(getServerUrl());
    }

    function forgetToken() as Void {
        Application.Storage.deleteValue("calendarToken");
        Application.Storage.deleteValue("calendarTokenOrigin");
        Application.Storage.deleteValue("calendarMode");
    }

    function pair(code as String, callback as Method) as Void {
        request("pair", {"code" => code}, callback, false);
    }

    function availability(callback as Method) as Void {
        request("availability", {}, callback, true);
    }

    function createActivity(slotId as String, callback as Method) as Void {
        request("activities", {"slotId" => slotId}, callback, true);
    }

    function suggestions(callback as Method) as Void {
        request("suggestions", {"context" => MomoActivityTracker.context(isDemoServer())}, callback, true);
    }

    function status(callback as Method) as Void {
        request("status", {}, callback, true);
    }

    function onboarding(callback as Method) as Void {
        request("onboarding", {}, callback, true);
    }

    function onboardingFresh(callback as Method) as Void {
        request("onboarding", {"fresh" => true}, callback, true);
    }

    function decide(suggestionId as String, decision as String, callback as Method) as Void {
        request("decide", {"suggestionId" => suggestionId, "decision" => decision}, callback, true);
    }

    function startActivity(activityId as String, callback as Method) as Void {
        request("start", {"activityId" => activityId}, callback, true);
    }

    function completeActivity(activityId as String, source as String, steps as Number, elapsedSeconds as Number, callback as Method) as Void {
        request("complete", {"activityId" => activityId, "source" => source, "steps" => steps, "elapsedSeconds" => elapsedSeconds}, callback, true);
    }

    function feedback(activityId as String, helpful as String, callback as Method) as Void {
        request("feedback", {"activityId" => activityId, "helpful" => helpful}, callback, true);
    }

    function getAccessToken() as String {
        if (isDemoServer()) {
            var value = WatchUi.loadResource(Rez.Strings.CalendarBuildAccessToken) as String;
            return value.length() > 0 ? value : "momo-demo";
        }
        var token = Application.Storage.getValue("calendarToken");
        return token instanceof String ? token : "";
    }

    function getMode() as String {
        if (isDemoServer()) { return "demo"; }
        var mode = Application.Storage.getValue("calendarMode");
        return mode instanceof String ? mode : "";
    }

    function saveToken(token as String, mode as String) as Void {
        Application.Storage.setValue("calendarToken", token);
        Application.Storage.setValue("calendarTokenOrigin", getServerUrl());
        Application.Storage.setValue("calendarMode", mode);
    }

    // Invalidate callbacks when the user leaves. An event write may already have
    // reached Google; backend idempotency handles retrying the same slot safely.
    function cancel() as Void {
        _requestId += 1;
        _callback = null;
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    private function request(action as String, body as Dictionary, callback as Method, authenticated as Boolean) as Void {
        cancel();
        if (!hasServer()) {
            callback.invoke(400, {"error" => "unconfigured", "message" => "Add your script URL in app settings."});
            return;
        }
        _callback = callback;
        body["action"] = action;
        var headers = {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON};
        if (authenticated) {
            var token = getAccessToken();
            if (!(token instanceof String) || !hasToken()) {
                _callback = null;
                callback.invoke(401, {"error" => "unpaired", "message" => "Pair your watch again."});
                return;
            }
            body["token"] = token;
        }
        _timer = new Timer.Timer();
        _timer.start(method(:onTimeout), 20000, false);
        try {
            Communications.makeWebRequest(getServerUrl(), body, {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => headers,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
                :context => _requestId
            }, method(:onResponse));
        } catch (error) {
            finish(-1, {"error" => "network", "message" => "Could not reach calendar."});
        }
    }

    function onResponse(code as Number, data as Communications.ContentType or Null, context as Object) as Void {
        if (!(context instanceof Number) || context != _requestId || _callback == null) {
            return;
        }
        if (!(data instanceof Dictionary)) {
            finish(code, null);
            return;
        }
        var payload = data as Dictionary;
        // Apps Script ContentService responses use HTTP 200 even for errors.
        if (code >= 200 && code < 300 && payload["error"] != null) {
            if (payload["httpStatus"] instanceof Number) {
                code = payload["httpStatus"] as Number;
            } else if (payload["status"] instanceof Number) {
                code = payload["status"] as Number;
            } else {
                var error = payload["error"];
                if (error instanceof String && (error.equals("unauthorized") || error.equals("unpaired") || error.equals("invalid_token") || error.equals("invalid_code"))) {
                    code = 401;
                } else if (error instanceof String && error.equals("conflict")) {
                    code = 409;
                } else if (error instanceof String && error.equals("expired")) {
                    code = 410;
                } else {
                    code = 503;
                }
            }
        }
        if (code == 401) {
            forgetToken();
        }
        finish(code, payload);
    }

    function onTimeout() as Void {
        finish(-2, {"error" => "timeout", "message" => "Calendar took too long."});
        _requestId += 1;
    }

    private function finish(code as Number, data as Dictionary or Null) as Void {
        var callback = _callback;
        _callback = null;
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        if (callback != null) {
            callback.invoke(code, data);
        }
    }
}
