import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class MomoActivityView extends WatchUi.View {
    private var _activity as Dictionary;
    private var _mode as String;
    private var _client as MomoCalendarClient;
    private var _tracker as MomoActivityTracker;
    private var _state as Symbol = :scheduled;
    private var _timer as Timer.Timer or Null = null;
    private var _visible as Boolean = false;
    private var _started as Boolean = false;
    private var _completed as Boolean = false;
    private var _proof as Dictionary or Null = null;
    private var _pendingAction as String = "";
    private var _pendingHelpful as String = "";
    private var _message as String = "";

    function initialize(activity as Dictionary, mode as String) {
        View.initialize();
        _activity = activity;
        _mode = mode;
        _client = new MomoCalendarClient();
        var saved = Application.Storage.getValue("momoActivitySession");
        var progress = null;
        if (saved instanceof Dictionary && saved["origin"] instanceof String && saved["origin"].equals(_client.getServerUrl()) && saved["id"] instanceof String && saved["id"].equals(activity["id"])) {
            progress = saved;
            _started = saved["started"] == true;
            _completed = saved["completed"] == true;
            _proof = saved["proof"] instanceof Dictionary ? saved["proof"] as Dictionary : null;
        }
        _tracker = new MomoActivityTracker(activity, progress);
        var status = activity["status"];
        if (status instanceof String) {
            if (status.equals("running")) { _started = true; }
            if (status.equals("completed")) { _started = true; _completed = true; }
        }
        _state = _completed ? :feedback : (_started ? :running : :scheduled);
    }

    static function pending(origin as String) as Dictionary or Null {
        var saved = Application.Storage.getValue("momoActivitySession");
        if (saved instanceof Dictionary && saved["origin"] instanceof String && saved["origin"].equals(origin) && saved["activity"] instanceof Dictionary) {
            return saved as Dictionary;
        }
        return null;
    }

    function getState() as Symbol { return _state; }
    function getTracker() as MomoActivityTracker { return _tracker; }
    function setService(service as MomoCalendarClient) as Void { _client = service; }

    function save() as Void {
        var record = _tracker.snapshot();
        record["id"] = _activity["id"];
        record["activity"] = _activity;
        record["mode"] = _mode;
        record["origin"] = _client.getServerUrl();
        record["started"] = _started;
        record["completed"] = _completed;
        record["proof"] = _proof;
        Application.Storage.setValue("momoActivitySession", record);
    }

    function onShow() as Void {
        _visible = true;
        if (_state == :running) { startTimer(); }
    }

    function onHide() as Void {
        _visible = false;
        stopTimer();
        _tracker.pause();
        if (_state != :done) { save(); }
    }

    function dispose() as Void {
        onHide();
        _client.cancel();
    }

    private function startTimer() as Void {
        stopTimer();
        _tracker.resume(System.getTimer(), MomoActivityTracker.readSteps());
        if (_visible) {
            _timer = new Timer.Timer();
            _timer.start(method(:tick), 1000, true);
        }
    }

    private function stopTimer() as Void {
        if (_timer != null) { _timer.stop(); _timer = null; }
    }

    function tick() as Void {
        if (!_visible || _state != :running) { return; }
        _tracker.update(System.getTimer(), MomoActivityTracker.readSteps());
        if (_tracker.elapsedSeconds() % 10 == 0) { save(); }
        WatchUi.requestUpdate();
    }

    function select() as Void {
        if (_state == :scheduled) {
            _pendingAction = "start";
            _state = :saving;
            _client.startActivity(_activity["id"] as String, method(:handleStarted));
        } else if (_state == :running) {
            openOptions();
        } else if (_state == :feedback) {
            var menu = new WatchUi.Menu2({:title => "Did it help?"});
            menu.addItem(new WatchUi.MenuItem("Yes", null, :yes, null));
            menu.addItem(new WatchUi.MenuItem("Somewhat", null, :somewhat, null));
            menu.addItem(new WatchUi.MenuItem("No", null, :no, null));
            WatchUi.pushView(menu, new MomoActivityFeedbackDelegate(self), WatchUi.SLIDE_LEFT);
        } else if (_state == :error) {
            if (_pendingAction.equals("complete")) { sendCompletion(); }
            else if (_pendingAction.equals("feedback")) { sendFeedback(_pendingHelpful); }
            else { _state = :scheduled; select(); }
        } else if (_state == :done) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        WatchUi.requestUpdate();
    }

    function openOptions() as Void {
        if (_state != :running) { return; }
        var menu = new WatchUi.Menu2({:title => "Your break"});
        menu.addItem(new WatchUi.MenuItem("I'm done", _tracker.goalMet() ? "Goal reached" : "Mark it yourself", :finish, null));
        if (_mode.equals("demo")) {
            menu.addItem(new WatchUi.MenuItem("Simulate finish", "Demo data only", :simulate, null));
        }
        menu.addItem(new WatchUi.MenuItem("Keep going", null, :continue, null));
        WatchUi.pushView(menu, new MomoActivityOptionsDelegate(self), WatchUi.SLIDE_LEFT);
    }

    function requestFinish() as Void {
        if (_tracker.goalMet()) { finishActivity(false); }
        else {
            WatchUi.pushView(new WatchUi.Confirmation("Mark this activity done?\nSaved as self-reported."), new MomoActivityManualDelegate(self), WatchUi.SLIDE_LEFT);
        }
    }

    function finishActivity(simulate as Boolean) as Void {
        if (simulate && !_mode.equals("demo")) { return; }
        if (simulate) { _tracker.simulateFinish(); }
        var source = "self_report";
        if (_tracker.goalMet()) {
            source = _tracker.tracking().equals("steps") ? (_mode.equals("demo") ? "simulated_steps" : "steps") : (simulate ? "simulated_timer" : "timer");
        }
        _proof = {"source" => source, "steps" => _tracker.steps(), "elapsedSeconds" => _tracker.elapsedSeconds()};
        _pendingAction = "complete";
        save();
        sendCompletion();
    }

    private function sendCompletion() as Void {
        if (_proof == null) { return; }
        stopTimer();
        _tracker.pause();
        _state = :saving;
        _client.completeActivity(_activity["id"] as String, _proof["source"] as String, _proof["steps"] as Number, _proof["elapsedSeconds"] as Number, method(:handleCompleted));
        WatchUi.requestUpdate();
    }

    function sendFeedback(helpful as String) as Void {
        _pendingHelpful = helpful;
        _pendingAction = "feedback";
        _state = :saving;
        _client.feedback(_activity["id"] as String, helpful, method(:handleFeedback));
        WatchUi.requestUpdate();
    }

    function handleStarted(code as Number, data as Dictionary or Null) as Void {
        if (code >= 200 && code < 300 && data != null && data["activity"] instanceof Dictionary) {
            _activity = data["activity"] as Dictionary;
            _started = true;
            _state = :running;
            _pendingAction = "";
            save();
            if (_visible) { startTimer(); }
        } else { showError(data); }
        WatchUi.requestUpdate();
    }

    function handleCompleted(code as Number, data as Dictionary or Null) as Void {
        var status = data != null ? data["status"] : null;
        if (code >= 200 && code < 300 && status instanceof String && status.equals("completed")) {
            _completed = true;
            _state = :feedback;
            _pendingAction = "";
            save();
        } else { showError(data); }
        WatchUi.requestUpdate();
    }

    function handleFeedback(code as Number, data as Dictionary or Null) as Void {
        var status = data != null ? data["status"] : null;
        if (code >= 200 && code < 300 && status instanceof String && status.equals("recorded")) {
            _state = :done;
            _message = data["message"] instanceof String ? data["message"] as String : "Noted. Your future breaks just got smarter.";
            Application.Storage.deleteValue("momoActivitySession");
        } else { showError(data); }
        WatchUi.requestUpdate();
    }

    private function showError(data as Dictionary or Null) as Void {
        _state = :error;
        _message = data != null && data["message"] instanceof String ? data["message"] as String : "Connection paused. START retries safely.";
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        dc.drawText(130, 23, Graphics.FONT_SMALL, "Your little escape", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(_mode.equals("demo") ? 0xFFFF55 : 0x55FFAA, Graphics.COLOR_BLACK);
        dc.drawText(130, 54, Graphics.FONT_XTINY, _mode.equals("demo") ? "SIMULATED SESSION" : "ACTIVITY SESSION", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        var hint = "START: options";
        var title = _activity["title"] instanceof String ? _activity["title"] as String : "Your break";
        if (_state == :scheduled) {
            MomoActivityText.draw(dc, title, 92, 2);
            dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
            var label = _activity["label"] instanceof String ? _activity["label"] as String : "When you're ready";
            MomoActivityText.draw(dc, "Planned: " + label, 139, 2);
            hint = "START: begin when ready";
        } else if (_state == :running) {
            MomoActivityText.draw(dc, title, 84, 1);
            var remaining = _tracker.durationSeconds() - _tracker.elapsedSeconds();
            if (remaining < 0) { remaining = 0; }
            var seconds = remaining % 60;
            var clock = (remaining / 60).toNumber() + ":" + (seconds < 10 ? "0" : "") + seconds;
            dc.drawText(130, 112, Graphics.FONT_LARGE, clock, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
            var detail = _tracker.tracking().equals("steps") ? _tracker.steps() + " / " + _tracker.targetSteps() + " steps" : "A little space for yourself.";
            dc.drawText(130, 164, Graphics.FONT_XTINY, detail, Graphics.TEXT_JUSTIFY_CENTER);
            if (_tracker.goalMet()) { dc.drawText(130, 187, Graphics.FONT_XTINY, "Goal reached. Nice work.", Graphics.TEXT_JUSTIFY_CENTER); }
        } else if (_state == :feedback) {
            MomoActivityText.draw(dc, "You made room for yourself. Tiny high-five!", 94, 3);
            dc.drawText(130, 170, Graphics.FONT_XTINY, "Did that help?", Graphics.TEXT_JUSTIFY_CENTER);
            hint = "START: tell Momo";
        } else if (_state == :done) {
            MomoActivityText.draw(dc, _message, 98, 4);
            hint = "START: back to Momo";
        } else if (_state == :saving) {
            MomoActivityText.draw(dc, "One moment. Filing your tiny adventure...", 104, 3);
            hint = "Saving...";
        } else {
            MomoActivityText.draw(dc, _message, 94, 4);
            hint = "START: retry safely";
        }
        dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
        dc.drawText(130, 216, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class MomoActivityDelegate extends WatchUi.BehaviorDelegate {
    private var _view as MomoActivityView;
    function initialize(view as MomoActivityView) { BehaviorDelegate.initialize(); _view = view; }
    function onSelect() as Boolean { _view.select(); return true; }
    function onTap(event as WatchUi.ClickEvent) as Boolean { return onSelect(); }
    function onMenu() as Boolean { _view.openOptions(); return true; }
    function onBack() as Boolean { _view.dispose(); WatchUi.popView(WatchUi.SLIDE_RIGHT); return true; }
}

class MomoActivityOptionsDelegate extends WatchUi.Menu2InputDelegate {
    private var _view as MomoActivityView;
    function initialize(view as MomoActivityView) { Menu2InputDelegate.initialize(); _view = view; }
    function onSelect(item as WatchUi.MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        if (item.getId() == :simulate) { _view.finishActivity(true); }
        else if (item.getId() == :finish) { _view.requestFinish(); }
    }
}

class MomoActivityManualDelegate extends WatchUi.ConfirmationDelegate {
    private var _view as MomoActivityView;
    function initialize(view as MomoActivityView) { ConfirmationDelegate.initialize(); _view = view; }
    function onResponse(value as WatchUi.Confirm) as Boolean {
        if (value == WatchUi.CONFIRM_YES) { _view.finishActivity(false); }
        return true;
    }
}

class MomoActivityFeedbackDelegate extends WatchUi.Menu2InputDelegate {
    private var _view as MomoActivityView;
    function initialize(view as MomoActivityView) { Menu2InputDelegate.initialize(); _view = view; }
    function onSelect(item as WatchUi.MenuItem) as Void {
        var value = item.getId();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        _view.sendFeedback(value == :yes ? "yes" : (value == :somewhat ? "somewhat" : "no"));
    }
}
