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
            var feedback = new MomoChoiceView("Did it help?", [
                {"id" => :yes, "label" => "Yes", "detail" => "More of this, please"},
                {"id" => :somewhat, "label" => "Somewhat", "detail" => "A little better"},
                {"id" => :no, "label" => "No", "detail" => "Let's try something else"}], method(:onFeedbackChoice));
            WatchUi.pushView(feedback, new MomoChoiceDelegate(feedback), WatchUi.SLIDE_LEFT);
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
        var items = [{"id" => :finish, "label" => "I'm done", "detail" => _tracker.goalMet() ? "Goal reached" : "Mark it yourself"}] as Array<Dictionary>;
        if (_mode.equals("demo")) { items.add({"id" => :simulate, "label" => "Simulate finish", "detail" => "Demo data only"}); }
        items.add({"id" => :continue, "label" => "Keep going", "detail" => "Back to your break"});
        var choices = new MomoChoiceView("Your break", items, method(:onActivityChoice));
        WatchUi.pushView(choices, new MomoChoiceDelegate(choices), WatchUi.SLIDE_LEFT);
    }

    function onActivityChoice(id as Symbol) as Void {
        if (id == :simulate) { finishActivity(true); }
        else if (id == :finish) { requestFinish(); }
    }

    function onFeedbackChoice(id as Symbol) as Void {
        sendFeedback(id == :yes ? "yes" : (id == :somewhat ? "somewhat" : "no"));
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
        MomoUi.clear(dc); MomoUi.heading(dc, "Your break");
        MomoUi.text(dc, _mode.equals("demo") ? "SIMULATED / DEMO" : "ACTIVITY SESSION", 58, MomoUi.MINT);
        var hint = "START: options";
        var title = _activity["title"] instanceof String ? _activity["title"] as String : "A little space for you";
        if (_state == :scheduled) {
            MomoUi.paragraph(dc, title, 96, 2, MomoUi.INK);
            var label = _activity["label"] instanceof String ? _activity["label"] as String : "When you're ready";
            MomoUi.paragraph(dc, label, 153, 2, MomoUi.MUTED);
            hint = "START: begin";
        } else if (_state == :running) {
            MomoUi.text(dc, title, 90, MomoUi.INK);
            var remaining = _tracker.durationSeconds() - _tracker.elapsedSeconds();
            if (remaining < 0) { remaining = 0; }
            var seconds = remaining % 60;
            var clock = (remaining / 60).toNumber() + ":" + (seconds < 10 ? "0" : "") + seconds;
            dc.setColor(MomoUi.INK, MomoUi.BG);
            dc.drawText(130, 115, Graphics.FONT_LARGE, clock, Graphics.TEXT_JUSTIFY_CENTER);
            var detail = _tracker.tracking().equals("steps") ? _tracker.steps() + " / " + _tracker.targetSteps() + " steps" : "Breathe. You've got time.";
            MomoUi.text(dc, detail, 170, MomoUi.MUTED);
            var progress = _tracker.elapsedSeconds().toFloat() / _tracker.durationSeconds();
            if (_tracker.tracking().equals("steps") && _tracker.targetSteps() > 0) {
                var stepProgress = _tracker.steps().toFloat() / _tracker.targetSteps();
                if (stepProgress < progress) { progress = stepProgress; }
            }
            if (progress > 1) { progress = 1; }
            dc.setColor(MomoUi.EDGE, MomoUi.BG); dc.fillRoundedRectangle(52, 197, 156, 4, 2);
            if (progress > 0) { dc.setColor(MomoUi.MINT, MomoUi.BG); dc.fillRoundedRectangle(52, 197, (156 * progress).toNumber(), 4, 2); }
            if (_tracker.goalMet()) { hint = "START: finish"; }
        } else if (_state == :feedback) {
            MomoUi.text(dc, "TINY HIGH-FIVE!", 94, MomoUi.MINT);
            MomoUi.paragraph(dc, "You made room for yourself. How did that feel?", 128, 3, MomoUi.INK);
            hint = "START: tell Momo";
        } else if (_state == :done) {
            MomoUi.text(dc, "NOTED, HUMAN.", 94, MomoUi.MINT);
            MomoUi.paragraph(dc, _message, 128, 3, MomoUi.INK);
            hint = "START: back";
        } else if (_state == :saving) {
            MomoUi.paragraph(dc, "Filing your tiny adventure...", 109, 3, MomoUi.INK);
            hint = "Saving...";
        } else {
            MomoUi.paragraph(dc, _message, 103, 4, MomoUi.INK);
            hint = "START: retry";
        }
        MomoUi.pill(dc, hint, 215);
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
