import Toybox.Graphics;
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// The legacy bridge remains available for calendar-only response fixtures.
class MomoCalendarView extends MomoLegacyCalendarView {
    private var _service as MomoCalendarClient;
    private var _active as Boolean = false;
    private var _stage as Symbol = :loading;
    private var _idea as Dictionary or Null = null;
    private var _session as Dictionary or Null = null;
    private var _mode as String = "demo";
    private var _source as String = "fallback";
    private var _profileConfigured as Boolean = false;
    private var _page as Number = 0;
    private var _message as String = "";
    private var _pendingAccept as String or Null = null;
    private var _loaded as Boolean = false;
    private var _checkInMood as String = "unknown";
    private var _sensorClue as String = "";

    function initialize() {
        MomoLegacyCalendarView.initialize();
        _service = new MomoCalendarClient();
    }

    function getState() as Symbol { return _active ? _stage : MomoLegacyCalendarView.getState(); }
    function getSuggestion() as Dictionary or Null { return _idea; }
    function getAiSource() as String { return _source; }
    function getCheckInMood() as String { return _checkInMood; }
    function setCheckInMood(mood as String) as Void { _checkInMood = mood.length() > 0 ? mood : "unknown"; }
    function setService(service as MomoCalendarClient) as Void { _service = service; }

    function onShow() as Void {
        _mode = _service.getMode();
        var pending = MomoActivityView.pending(_service.getServerUrl());
        if (pending != null) {
            _active = true; _stage = :saved;
            _session = pending["activity"] as Dictionary;
            if (!_loaded) { refresh(); }
            return;
        }
        if (_stage == :saved && _session != null) { _session = null; _loaded = false; }
        if (!_loaded) { refresh(); }
    }

    function dispose() as Void { _service.cancel(); MomoLegacyCalendarView.dispose(); }

    private function computeSensorClue() as String {
        var hr = MomoSensors.readHeartRate();
        var stress = MomoSensors.readStress();
        var bb = MomoSensors.readBodyBattery();
        if (hr != null && bb != null) { return "LIVE · HR " + hr + " · BB " + bb; }
        if (hr != null && stress != null) { return "LIVE · HR " + hr + " · STR " + stress; }
        if (hr != null) { return "LIVE · HR " + hr; }
        if (bb != null) { return "LIVE · BB " + bb; }
        if (stress != null) { return "LIVE · STRESS " + stress; }
        return "";
    }

    function setSensorClueForTest(clue as String) as Void {
        _sensorClue = clue;
    }

    function refresh() as Void {
        _active = true; _loaded = true; _page = 0; _pendingAccept = null;
        if (!_service.hasServer()) { _stage = :unconfigured; }
        else if (!_service.hasToken()) { _stage = :unpaired; }
        else {
            _stage = :loading; _message = "Finding your next little escape...";
            _sensorClue = computeSensorClue();
            if (!_checkInMood.equals("unknown")) {
                _service.suggestionsWithMood(_checkInMood, method(:handleSuggestions));
            } else {
                _service.suggestions(method(:handleSuggestions));
            }
        }
        WatchUi.requestUpdate();
    }

    function handleAvailability(code as Number, data as Dictionary or Null) as Void {
        _active = false;
        MomoLegacyCalendarView.handleAvailability(code, data);
    }

    function moveSelection(direction as Number) as Void {
        if (!_active) { MomoLegacyCalendarView.moveSelection(direction); return; }
        if (_stage == :ready) {
            var count = _profileConfigured ? 2 : 3;
            _page = ((_page + direction) % count + count) % count;
            WatchUi.requestUpdate();
        }
    }

    function select() as Void {
        if (!_active) { MomoLegacyCalendarView.select(); return; }
        if (_stage == :loading) { return; }
        if (_stage == :ready) { openOptions(); }
        else if (_stage == :saved && _session != null) {
            var activity = new MomoActivityView(_session, _mode);
            WatchUi.pushView(activity, new MomoActivityDelegate(activity), WatchUi.SLIDE_LEFT);
        } else if (_pendingAccept != null) { acceptConfirmed(); }
        else { refresh(); }
    }

    function openOptions() as Void {
        if (!_active || _stage != :ready || _idea == null) {
            if (getState() != :loading) { refresh(); }
            return;
        }
        var choices = new MomoChoiceView("Your move", actionChoices(), method(:onAction));
        WatchUi.pushView(choices, new MomoChoiceDelegate(choices), WatchUi.SLIDE_LEFT);
    }

    function actionChoices() as Array<Dictionary> {
        return [{"id" => :accept, "label" => "Let's go", "detail" => "Review & save this break"},
            {"id" => :mood, "label" => "How I feel", "detail" => "Fried, Okay, or Wired"},
            {"id" => :snooze, "label" => "Later", "detail" => "Give me breathing room"},
            {"id" => :alternative, "label" => "Something else", "detail" => "Find a different idea"},
            {"id" => :why, "label" => "Why this?", "detail" => "What Momo considered"},
            {"id" => :profile, "label" => "Setup", "detail" => "Update your preferences"}];
    }

    function onAction(id as Symbol) as Void {
        if (id == :accept) { requestAccept(); }
        else if (id == :mood) { openMoodPicker(); }
        else if (id == :snooze) { decide("snooze"); }
        else if (id == :alternative) { decide("alternative"); }
        else { showDetails(id == :profile); }
    }

    function openMoodPicker() as Void {
        var moods = new MomoChoiceView("How do you feel?", [
            {"id" => :fried, "label" => "Fried", "detail" => "Low battery, need gentle"},
            {"id" => :okay, "label" => "Okay", "detail" => "Steady, open to a reset"},
            {"id" => :wired, "label" => "Wired", "detail" => "Restless, need to move"}
        ], method(:onMoodSelected));
        WatchUi.pushView(moods, new MomoChoiceDelegate(moods), WatchUi.SLIDE_LEFT);
    }

    function onMoodSelected(id as Symbol) as Void {
        _checkInMood = id == :fried ? "fried" : (id == :wired ? "wired" : "okay");
        refresh();
    }

    function showDetails(profile as Boolean) as Void {
        if (profile) {
            _loaded = false;
            var onboarding = new MomoOnboardingView();
            onboarding.setReturnToPrevious(true);
            WatchUi.pushView(onboarding, new MomoOnboardingDelegate(onboarding), WatchUi.SLIDE_LEFT);
            return;
        }
        _page = 1;
        WatchUi.requestUpdate();
    }

    function requestAccept() as Void {
        if (_idea == null) { return; }
        var question = (_mode.equals("demo") ? "Save a DEMO break?\n" : "Schedule this break?\n") + (_idea["title"] as String) + "\n" + (_idea["label"] as String);
        WatchUi.pushView(new WatchUi.Confirmation(question), new MomoSuggestionConfirmationDelegate(self), WatchUi.SLIDE_LEFT);
    }

    // Only called after the user accepts the native confirmation dialog.
    function acceptConfirmed() as Void {
        if (_pendingAccept == null && _idea != null) { _pendingAccept = _idea["id"] as String; }
        if (_pendingAccept == null) { return; }
        _stage = :loading; _message = "Reserving a little time for you...";
        _service.decide(_pendingAccept, "accept", method(:handleAccepted));
        WatchUi.requestUpdate();
    }

    function decide(decision as String) as Void {
        if (_idea == null || !(_idea["id"] instanceof String)) { return; }
        _stage = :loading;
        _message = decision.equals("snooze") ? "Giving you some breathing room..." : "Finding a different little adventure...";
        _service.decide(_idea["id"] as String, decision, decision.equals("snooze") ? method(:handleSnoozed) : method(:handleSuggestions));
        WatchUi.requestUpdate();
    }

    function handleSuggestions(code as Number, data as Dictionary or Null) as Void {
        _active = true; _page = 0;
        if (code >= 200 && code < 300 && data != null) {
            _mode = data["mode"] instanceof String ? data["mode"] as String : _mode;
            _source = data["aiSource"] instanceof String && data["aiSource"].equals("grok") ? "grok" : "fallback";
            _profileConfigured = data["profileConfigured"] == true;
            var checkIn = data["checkIn"];
            if (checkIn instanceof Dictionary && checkIn["id"] instanceof String && checkIn["title"] instanceof String) {
                _idea = null; _session = checkIn as Dictionary; _stage = :saved;
                var activity = new MomoActivityView(_session, _mode); activity.save();
                WatchUi.requestUpdate();
                return;
            } else if (data.hasKey("checkIn") && checkIn == null) {
                Application.Storage.deleteValue("momoActivitySession");
                _session = null;
            }
            var idea = data["suggestion"];
            if (idea instanceof Dictionary && idea["id"] instanceof String && idea["title"] instanceof String && idea["label"] instanceof String) {
                _idea = idea as Dictionary; _stage = :ready;
            } else {
                _idea = null; _stage = :empty;
                _message = data["message"] instanceof String ? data["message"] as String : "No suitable gaps right now. We can check later.";
            }
        } else { fail(code, data); }
        WatchUi.requestUpdate();
    }

    function handleSnoozed(code as Number, data as Dictionary or Null) as Void {
        var status = data != null ? data["status"] : null;
        if (code >= 200 && code < 300 && status instanceof String && status.equals("snoozed")) {
            _stage = :snoozed;
            _message = "Got it. A little space for you. Check back when you're ready.";
        } else { fail(code, data); }
        WatchUi.requestUpdate();
    }

    function handleAccepted(code as Number, data as Dictionary or Null) as Void {
        var status = data != null ? data["status"] : null;
        if (code >= 200 && code < 300 && data != null && status instanceof String && (status.equals("created") || status.equals("already_created")) && data["activity"] instanceof Dictionary) {
            _pendingAccept = null;
            _session = data["activity"] as Dictionary;
            var session = new MomoActivityView(_session, _mode); session.save();
            _stage = :saved;
        } else {
            if (code == 409 || code == 410) { _pendingAccept = null; _idea = null; }
            fail(code, data);
        }
        WatchUi.requestUpdate();
    }

    private function fail(code as Number, data as Dictionary or Null) as Void {
        _stage = :error;
        if (code == 409 || code == 410) { _message = "That slot changed. Let's find another."; }
        else if (code == 401) { _message = "Service updated? Rebuild and relaunch Momo."; }
        else if (_pendingAccept != null) { _message = "Check your calendar. START retries safely."; }
        else { _message = data != null && data["message"] instanceof String ? data["message"] as String : "Momo is offline. Is the service running?"; }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        if (!_active) { MomoLegacyCalendarView.onUpdate(dc); return; }
        MomoUi.clear(dc); MomoUi.heading(dc, "A little escape");
        var badge = _source.equals("grok") ? "GROK" : "SCRIPTED";
        badge += _mode.equals("demo") ? " / DEMO" : " / CALENDAR";
        MomoUi.text(dc, badge, 56, MomoUi.MINT);
        var hint = "START: refresh";
        if (_stage == :ready && _idea != null) {
            if (_page == 0) {
                var clue = _sensorClue;
                if (clue.length() == 0 && !_checkInMood.equals("unknown")) {
                    clue = "MOOD · " + _checkInMood.toUpper();
                }
                if (clue.length() > 0) {
                    MomoUi.text(dc, clue, 75, MomoUi.LAVENDER);
                    MomoUi.text(dc, _idea["title"] as String, 95, MomoUi.INK);
                    MomoUi.text(dc, _idea["label"] as String, 115, MomoUi.MUTED);
                    var quip = _idea["quip"] instanceof String ? _idea["quip"] as String : "A little space for yourself?";
                    MomoUi.paragraph(dc, quip, 135, 3, MomoUi.INK);
                } else {
                    MomoUi.text(dc, _idea["title"] as String, 89, MomoUi.INK);
                    MomoUi.text(dc, _idea["label"] as String, 111, MomoUi.MUTED);
                    var quip = _idea["quip"] instanceof String ? _idea["quip"] as String : "A little space for yourself?";
                    MomoUi.paragraph(dc, quip, 131, 4, MomoUi.INK);
                }
            } else if (_page == 1) {
                MomoUi.text(dc, "WHY THIS BREAK?", 88, MomoUi.MINT);
                var reason = _idea["reason"] instanceof String ? _idea["reason"] as String : "This fits your free time and preferences.";
                var coachLine = _idea["coachLine"] instanceof String ? _idea["coachLine"] as String : "";
                if (coachLine.length() > 0) {
                    MomoUi.paragraph(dc, reason, 114, 2, MomoUi.INK);
                    MomoUi.paragraph(dc, coachLine, 162, 2, MomoUi.GOLD);
                } else {
                    MomoUi.paragraph(dc, reason, 121, 4, MomoUi.INK);
                }
            } else {
                MomoUi.text(dc, "MAKE IT YOURS", 91, MomoUi.MINT);
                MomoUi.paragraph(dc, "Using default preferences. Choose Setup to tell Momo what works for you.", 123, 4, MomoUi.INK);
            }
            hint = "START: choices";
            dc.setColor(MomoUi.EDGE, MomoUi.BG);
            dc.fillCircle(237, 125 + _page * 7, 2);
        } else if (_stage == :saved && _session != null) {
            MomoUi.text(dc, _mode.equals("demo") ? "DEMO BREAK SAVED" : "YOUR BREAK IS BOOKED", 91, MomoUi.MINT);
            MomoUi.paragraph(dc, _session["title"] as String, 122, 2, MomoUi.INK);
            var label = _session["label"] instanceof String ? _session["label"] as String : "When you're ready";
            MomoUi.paragraph(dc, label, 169, 2, MomoUi.MUTED);
            hint = "START: your break";
        } else if (_stage == :unconfigured) {
            MomoUi.paragraph(dc, "Momo is offline. Connect the service and try again.", 103, 4, MomoUi.INK);
        } else if (_stage == :unpaired) {
            MomoUi.paragraph(dc, "Connect your calendar, then pair your watch.", 103, 4, MomoUi.INK);
        } else {
            MomoUi.paragraph(dc, _message, 103, 4, MomoUi.INK);
            if (_stage == :loading) { hint = "One moment..."; }
            else if (_pendingAccept != null) { hint = "START: retry safely"; }
        }
        MomoUi.pill(dc, hint, 215);
    }

}

class MomoCalendarDelegate extends WatchUi.BehaviorDelegate {
    private var _view as MomoCalendarView;
    function initialize(view as MomoCalendarView) { BehaviorDelegate.initialize(); _view = view; }
    function onSelect() as Boolean { _view.select(); return true; }
    function onNextPage() as Boolean { _view.moveSelection(1); return true; }
    function onPreviousPage() as Boolean { _view.moveSelection(-1); return true; }
    function onTap(event as WatchUi.ClickEvent) as Boolean { return onSelect(); }
    function onBack() as Boolean { _view.dispose(); WatchUi.popView(WatchUi.SLIDE_RIGHT); return true; }
    function onMenu() as Boolean { _view.openOptions(); return true; }
}

class MomoSuggestionOptionsDelegate extends WatchUi.Menu2InputDelegate {
    private var _view as MomoCalendarView;
    function initialize(view as MomoCalendarView) { Menu2InputDelegate.initialize(); _view = view; }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId(); WatchUi.popView(WatchUi.SLIDE_RIGHT);
        if (id == :accept) { _view.requestAccept(); }
        else if (id == :snooze) { _view.decide("snooze"); }
        else if (id == :alternative) { _view.decide("alternative"); }
        else { _view.showDetails(id == :profile); }
    }
}

class MomoSuggestionConfirmationDelegate extends WatchUi.ConfirmationDelegate {
    private var _view as MomoCalendarView;
    function initialize(view as MomoCalendarView) { ConfirmationDelegate.initialize(); _view = view; }
    function onResponse(value as WatchUi.Confirm) as Boolean {
        if (value == WatchUi.CONFIRM_YES) { _view.acceptConfirmed(); }
        return true;
    }
}
