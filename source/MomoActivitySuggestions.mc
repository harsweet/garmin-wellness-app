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

    function initialize() {
        MomoLegacyCalendarView.initialize();
        _service = new MomoCalendarClient();
    }

    function getState() as Symbol { return _active ? _stage : MomoLegacyCalendarView.getState(); }
    function getSuggestion() as Dictionary or Null { return _idea; }
    function getAiSource() as String { return _source; }
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

    function refresh() as Void {
        _active = true; _loaded = true; _page = 0; _pendingAccept = null;
        if (!_service.hasServer()) { _stage = :unconfigured; }
        else if (!_service.hasToken()) { _stage = :unpaired; }
        else {
            _stage = :loading; _message = "Finding your next little escape...";
            _service.suggestions(method(:handleSuggestions));
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
        var menu = new WatchUi.Menu2({:title => "What do you think?"});
        menu.addItem(new WatchUi.MenuItem("Let's go", "Reserve this break", :accept, null));
        menu.addItem(new WatchUi.MenuItem("Later", "Give me some room", :snooze, null));
        menu.addItem(new WatchUi.MenuItem("Something else", "Try a different idea", :alternative, null));
        menu.addItem(new WatchUi.MenuItem("Why this?", null, :why, null));
        if (!_profileConfigured) { menu.addItem(new WatchUi.MenuItem("Personalize Momo", "Setup on your computer", :profile, null)); }
        WatchUi.pushView(menu, new MomoSuggestionOptionsDelegate(self), WatchUi.SLIDE_LEFT);
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
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        dc.drawText(130, 23, Graphics.FONT_SMALL, "Momo suggests", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(_mode.equals("demo") ? 0xFFFF55 : 0x55FFAA, Graphics.COLOR_BLACK);
        var badge = _source.equals("grok") ? "GROK" : "SCRIPTED";
        badge += _mode.equals("demo") ? " / DEMO" : " / CALENDAR";
        dc.drawText(130, 54, Graphics.FONT_XTINY, badge, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        var hint = "START: refresh";
        if (_stage == :ready && _idea != null) {
            if (_page == 0) {
                MomoActivityText.draw(dc, _idea["title"] as String, 83, 1);
                dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
                MomoActivityText.draw(dc, _idea["label"] as String, 105, 1);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                var quip = _idea["quip"] instanceof String ? _idea["quip"] as String : "A little space for yourself?";
                MomoActivityText.draw(dc, quip, 130, 4);
            } else if (_page == 1) {
                var reason = _idea["reason"] instanceof String ? _idea["reason"] as String : "This activity fits your free time and preferences.";
                MomoActivityText.draw(dc, reason, 94, 4);
            } else {
                MomoActivityText.draw(dc, "Open Momo setup on your computer. Your goals and preferences will shape future ideas.", 94, 5);
            }
            hint = "START: choices";
        } else if (_stage == :saved && _session != null) {
            MomoActivityText.draw(dc, _mode.equals("demo") ? "Demo break saved." : "Your break is booked.", 92, 2);
            var label = _session["label"] instanceof String ? _session["label"] as String : "Your planned break";
            MomoActivityText.draw(dc, label, 139, 2);
            hint = "START: begin / resume";
        } else if (_stage == :unconfigured) {
            MomoActivityText.draw(dc, "Start Momo's service on your computer, then rebuild the watch app.", 94, 4);
        } else if (_stage == :unpaired) {
            MomoActivityText.draw(dc, "Connect your calendar on your computer, then pair the watch.", 94, 4);
        } else {
            MomoActivityText.draw(dc, _message, 94, 4);
            if (_stage == :loading) { hint = "One moment..."; }
            else if (_pendingAccept != null) { hint = "START: retry safely"; }
        }
        dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
        dc.drawText(130, 216, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
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
