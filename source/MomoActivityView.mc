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
    private var _animFrame as Number = 0;
    private var _lastSavedSec as Number = -1;
    private var _lastCueKey as Number = -1;
    private var _startHr as Number or Null = null;
    private var _startStress as Number or Null = null;
    private var _startElevation as Number or Null = null;
    private var _liveHr as Number or Null = null;
    private var _liveElevation as Number or Null = null;
    private var _endVitals as Dictionary or Null = null;

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
            if (saved["startVitals"] instanceof Dictionary) {
                var sv = saved["startVitals"] as Dictionary;
                _startHr = sv["hr"] instanceof Number ? sv["hr"] as Number : null;
                _startStress = sv["stress"] instanceof Number ? sv["stress"] as Number : null;
                _startElevation = sv["elevation"] instanceof Number ? sv["elevation"] as Number : null;
            }
        }
        _tracker = new MomoActivityTracker(activity, progress);
        var status = activity["status"];
        if (status instanceof String) {
            if (status.equals("running")) { _started = true; }
            if (status.equals("completed")) { _started = true; _completed = true; }
        }
        _state = _completed ? :feedback : (_started ? :running : :scheduled);
        if (_state == :running && _startHr == null && _startStress == null && _startElevation == null) {
            captureStartVitals();
        }
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
    function getProof() as Dictionary or Null { return _proof; }
    function setService(service as MomoCalendarClient) as Void { _client = service; }

    function setStartVitalsForTest(hr as Number or Null, stress as Number or Null, elevation as Number or Null) as Void {
        _startHr = hr;
        _startStress = stress;
        _startElevation = elevation;
    }

    private function captureStartVitals() as Void {
        var snap = MomoSensors.vitalsSnapshot();
        _startHr = snap["hr"] as Number or Null;
        _startStress = snap["stress"] as Number or Null;
        _startElevation = snap["elevation"] as Number or Null;
        _liveHr = _startHr;
        _liveElevation = _startElevation;
    }

    private function refreshLiveVitals() as Void {
        _liveHr = MomoSensors.readHeartRate();
        _liveElevation = MomoSensors.readElevation();
    }

    function save() as Void {
        var record = _tracker.snapshot();
        record["id"] = _activity["id"];
        record["activity"] = _activity;
        record["mode"] = _mode;
        record["origin"] = _client.getServerUrl();
        record["started"] = _started;
        record["completed"] = _completed;
        record["proof"] = _proof;
        record["startVitals"] = {"hr" => _startHr, "stress" => _startStress, "elevation" => _startElevation};
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
        refreshLiveVitals();
        if (_visible) {
            _timer = new Timer.Timer();
            _timer.start(method(:tick), 250, true);
        }
    }

    private function stopTimer() as Void {
        if (_timer != null) { _timer.stop(); _timer = null; }
    }

    function tick() as Void {
        if (!_visible || _state != :running) { return; }
        _animFrame = (_animFrame + 1) % 32;
        _tracker.update(System.getTimer(), MomoActivityTracker.readSteps());
        var sec = _tracker.elapsedSeconds();
        if (sec % 10 == 0 && sec != _lastSavedSec) {
            _lastSavedSec = sec;
            save();
        }
        if (_animFrame % 8 == 0) {
            refreshLiveVitals();
        }
        checkHapticCue();
        WatchUi.requestUpdate();
    }

    private function activityKind() as String {
        var kind = _activity["activityId"];
        return kind instanceof String ? kind as String : "rest";
    }

    private function checkHapticCue() as Void {
        var kind = activityKind();
        if (kind.equals("breathe")) {
            var phase = ((_tracker.elapsedMs() % 12000) / 4000).toNumber();
            if (phase != _lastCueKey) {
                _lastCueKey = phase;
                MomoSensors.vibrate(phase == 0 ? :inhale : (phase == 2 ? :exhale : :step));
            }
        } else if (kind.equals("stretch")) {
            var stepIdx = (_tracker.elapsedSeconds() / 30).toNumber() % 6;
            if (stepIdx != _lastCueKey) {
                _lastCueKey = stepIdx;
                MomoSensors.vibrate(:step);
            }
        } else if (kind.equals("eyes")) {
            var stepLen = (_tracker.durationSeconds() / 4).toNumber();
            if (stepLen < 15) { stepLen = 15; }
            var eyeIdx = (_tracker.elapsedSeconds() / stepLen).toNumber() % 4;
            if (eyeIdx != _lastCueKey) {
                _lastCueKey = eyeIdx;
                MomoSensors.vibrate(:step);
            }
        }
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
        var endSnap = MomoSensors.vitalsSnapshot();
        var vitals = {} as Dictionary;
        if (_startHr != null) { vitals["startHr"] = _startHr; }
        if (endSnap["hr"] instanceof Number) { vitals["endHr"] = endSnap["hr"]; }
        if (_startStress != null) { vitals["startStress"] = _startStress; }
        if (endSnap["stress"] instanceof Number) { vitals["endStress"] = endSnap["stress"]; }
        if (_startElevation != null && endSnap["elevation"] instanceof Number) {
            vitals["elevationGain"] = (endSnap["elevation"] as Number) - (_startElevation as Number);
        }
        _endVitals = vitals.size() > 0 ? vitals : null;
        _proof = {"source" => source, "steps" => _tracker.steps(), "elapsedSeconds" => _tracker.elapsedSeconds()};
        if (_endVitals != null) { _proof["vitals"] = _endVitals; }
        _pendingAction = "complete";
        save();
        sendCompletion();
    }

    private function sendCompletion() as Void {
        if (_proof == null) { return; }
        stopTimer();
        _tracker.pause();
        _state = :saving;
        _client.completeActivityWithVitals(_activity["id"] as String, _proof["source"] as String, _proof["steps"] as Number, _proof["elapsedSeconds"] as Number, _endVitals, method(:handleCompleted));
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
            _lastCueKey = -1;
            captureStartVitals();
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
            MomoModel.incrementBreaksToday();
            MomoSensors.vibrate(:celebrate);
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

    private function computeProgress() as Float {
        var duration = _tracker.durationSeconds();
        var progress = duration > 0 ? _tracker.elapsedSeconds().toFloat() / duration.toFloat() : 1.0f;
        if (_tracker.tracking().equals("steps") && _tracker.targetSteps() > 0) {
            var stepProgress = _tracker.steps().toFloat() / _tracker.targetSteps().toFloat();
            if (stepProgress < progress) { progress = stepProgress; }
        }
        if (progress < 0.0f) { progress = 0.0f; }
        if (progress > 1.0f) { progress = 1.0f; }
        return progress;
    }

    private function formatClock(remaining as Number) as String {
        var clamped = remaining < 0 ? 0 : remaining;
        var seconds = clamped % 60;
        return (clamped / 60).toNumber() + ":" + (seconds < 10 ? "0" : "") + seconds;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        MomoUi.clear(dc);
        var title = _activity["title"] instanceof String ? _activity["title"] as String : "A little space for you";
        var kind = activityKind();
        var coachLine = _activity["coachLine"] instanceof String ? _activity["coachLine"] as String : "";

        if (_state == :scheduled) {
            var accent = MomoUi.activityAccent(kind);
            MomoUi.drawStartTick(dc, accent);
            MomoUi.text(dc, _mode.equals("demo") ? "DEMO BREAK" : "READY TO BREAK", 22, accent);
            dc.setPenWidth(1);
            dc.setColor(MomoUi.SURFACE, MomoUi.BG);
            dc.drawCircle(130, 54, 14);
            MomoUi.drawIcon(dc, kind, 130, 54, accent);
            MomoUi.titleText(dc, title, 78, MomoUi.INK);
            var label = _activity["label"] instanceof String ? _activity["label"] as String : "When you're ready";
            MomoUi.text(dc, label, 108, MomoUi.MUTED);
            MomoUi.drawDivider(dc, 134, 140);
            var schedCue = coachLine.length() > 0 ? coachLine : "Take a quick reset";
            MomoUi.paragraph(dc, schedCue, 144, 2, MomoUi.MUTED);
            MomoUi.pill(dc, "begin", 216);
        } else if (_state == :running) {
            var remaining = _tracker.durationSeconds() - _tracker.elapsedSeconds();
            var clock = formatClock(remaining);
            var progress = computeProgress();

            if (kind.equals("breathe")) {
                var cycleMs = _tracker.elapsedMs() % 12000;
                var phase = (cycleMs / 4000).toNumber();
                var phaseFrac = (cycleMs % 4000).toFloat() / 4000.0f;
                var radius = 28;
                var phaseLabel = "INHALE";
                var ringColor = MomoUi.MINT;
                var discColor = MomoUi.SURFACE;
                if (phase == 0) {
                    radius = 28 + (26 * phaseFrac).toNumber();
                } else if (phase == 1) {
                    radius = 52 + ((_animFrame % 4) < 2 ? 2 : 0);
                    phaseLabel = "HOLD";
                    ringColor = MomoUi.GOLD;
                    discColor = MomoUi.SURFACE;
                } else {
                    radius = 54 - (26 * phaseFrac).toNumber();
                    phaseLabel = "EXHALE";
                    ringColor = MomoUi.LAVENDER;
                    discColor = MomoUi.DEEP;
                }
                MomoUi.drawBezelProgress(dc, progress, ringColor);
                MomoUi.text(dc, _mode.equals("demo") ? "DEMO · BREATHE" : "BREATHE", 22, MomoUi.MINT);
                dc.setPenWidth(1);
                dc.setColor(MomoUi.EDGE, MomoUi.BG);
                dc.drawCircle(130, 122, 58);
                dc.setColor(discColor, MomoUi.BG);
                dc.fillCircle(130, 122, radius - 3);
                dc.setPenWidth(5);
                dc.setColor(ringColor, MomoUi.BG);
                dc.drawCircle(130, 122, radius);
                dc.setPenWidth(1);
                dc.setColor(ringColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(130, 96, Graphics.FONT_XTINY, phaseLabel, Graphics.TEXT_JUSTIFY_CENTER);
                dc.setColor(MomoUi.INK, Graphics.COLOR_TRANSPARENT);
                dc.drawText(130, 116, Graphics.FONT_MEDIUM, clock, Graphics.TEXT_JUSTIFY_CENTER);
                var dotXs = [116, 130, 144] as Array<Number>;
                for (var i = 0; i < 3; i += 1) {
                    var isCurrent = (i == phase);
                    dc.setColor(isCurrent ? ringColor : MomoUi.EDGE, MomoUi.BG);
                    dc.fillCircle(dotXs[i], 195, isCurrent ? 3 : 2);
                }
            } else if (kind.equals("stretch")) {
                MomoUi.drawBezelProgress(dc, progress, MomoUi.PEACH);
                var stepsList = [
                    "Roll shoulders back",
                    "Gentle neck tilt",
                    "Reach for the sky",
                    "Unclench jaw & hands",
                    "Wrist circles",
                    "Deep sigh & shake"
                ] as Array<String>;
                var stepIdx = (_tracker.elapsedSeconds() / 30).toNumber() % 6;
                MomoUi.text(dc, "STRETCH · " + (stepIdx + 1) + "/6", 22, MomoUi.PEACH);
                for (var i = 0; i < 6; i += 1) {
                    var pipColor = i < stepIdx ? MomoUi.PEACH : (i == stepIdx ? MomoUi.INK : MomoUi.EDGE);
                    dc.setColor(pipColor, MomoUi.BG);
                    dc.fillRoundedRectangle(72 + i * 20, 48, 16, 4, 2);
                }
                MomoUi.titleText(dc, stepsList[stepIdx], 66, MomoUi.INK);
                dc.setColor(MomoUi.INK, MomoUi.BG);
                dc.drawText(130, 108, Graphics.FONT_LARGE, clock, Graphics.TEXT_JUSTIFY_CENTER);
                var stretchCue = coachLine.length() > 0 ? coachLine : "30s each · easy breath";
                MomoUi.text(dc, stretchCue, 168, MomoUi.MUTED);
            } else if (kind.equals("eyes")) {
                MomoUi.drawBezelProgress(dc, progress, MomoUi.LAVENDER);
                var eyeSteps = [
                    "Look 20 ft away",
                    "Slow blink x5",
                    "Soften shoulders",
                    "Rest eyes closed"
                ] as Array<String>;
                var stepLen = (_tracker.durationSeconds() / 4).toNumber();
                if (stepLen < 15) { stepLen = 15; }
                var eyeIdx = (_tracker.elapsedSeconds() / stepLen).toNumber() % 4;
                var pulse = (_animFrame % 8) < 4 ? (_animFrame % 4) : (4 - (_animFrame % 4));
                MomoUi.text(dc, "EYE RESET", 22, MomoUi.LAVENDER);
                dc.setPenWidth(1);
                dc.setColor(MomoUi.SURFACE, MomoUi.BG);
                dc.drawArc(130, 82, 31 + (pulse / 2).toNumber(), Graphics.ARC_COUNTER_CLOCKWISE, 42, 138);
                dc.setPenWidth(2);
                dc.setColor(MomoUi.LAVENDER, MomoUi.BG);
                dc.drawArc(130, 82, 26, Graphics.ARC_COUNTER_CLOCKWISE, 33, 147);
                dc.drawArc(130, 54, 26, Graphics.ARC_COUNTER_CLOCKWISE, 213, 327);
                dc.setPenWidth(1);
                dc.setColor(MomoUi.LAVENDER, MomoUi.BG);
                dc.fillCircle(130, 68, 7 + (pulse / 2).toNumber());
                dc.setColor(MomoUi.BG, MomoUi.BG);
                dc.fillCircle(130, 68, 3);
                dc.setColor(MomoUi.INK, MomoUi.BG);
                dc.fillCircle(132, 66, 1);
                MomoUi.titleText(dc, eyeSteps[eyeIdx], 98, MomoUi.INK);
                dc.setColor(MomoUi.INK, MomoUi.BG);
                dc.drawText(130, 130, Graphics.FONT_LARGE, clock, Graphics.TEXT_JUSTIFY_CENTER);
                var eyeDotXs = [112, 124, 136, 148] as Array<Number>;
                for (var i = 0; i < 4; i += 1) {
                    var isCurrent = (i == eyeIdx);
                    var isDone = (i < eyeIdx);
                    dc.setColor(isCurrent ? MomoUi.INK : (isDone ? MomoUi.LAVENDER : MomoUi.EDGE), MomoUi.BG);
                    dc.fillCircle(eyeDotXs[i], 186, isCurrent ? 3 : 2);
                }
            } else if (kind.equals("walk") || kind.equals("stairs") || kind.equals("sunlight")) {
                var arcColor = MomoUi.activityAccent(kind);
                MomoUi.drawBezelProgress(dc, progress, arcColor);
                MomoUi.drawIcon(dc, kind, 130, 34, arcColor);
                var kindLabel = kind.equals("stairs") ? "STAIRS" : (kind.equals("sunlight") ? "SUNLIGHT" : "WALK");
                MomoUi.text(dc, kindLabel, 50, arcColor);
                dc.setColor(MomoUi.INK, MomoUi.BG);
                dc.drawText(130, 72, Graphics.FONT_LARGE, clock, Graphics.TEXT_JUSTIFY_CENTER);
                MomoUi.drawDivider(dc, 128, 144);
                var metric = _tracker.tracking().equals("steps")
                    ? _tracker.steps() + " / " + _tracker.targetSteps() + " steps"
                    : (kind.equals("stairs") && _liveElevation != null
                        ? "Elev " + _liveElevation + "m"
                        : (kind.equals("sunlight") ? "Step into daylight" : _tracker.steps() + " steps"));
                if (_liveHr != null) {
                    var hrText = "" + _liveHr;
                    var metricW = dc.getTextWidthInPixels(metric, Graphics.FONT_XTINY);
                    var hrW = dc.getTextWidthInPixels(hrText, Graphics.FONT_XTINY);
                    var totalW = metricW + 10 + 12 + 4 + hrW;
                    if (totalW <= 198) {
                        var startX = 130 - (totalW / 2).toNumber();
                        var fontH = dc.getFontHeight(Graphics.FONT_XTINY);
                        dc.setColor(arcColor, MomoUi.BG);
                        dc.drawText(startX, 136, Graphics.FONT_XTINY, metric, Graphics.TEXT_JUSTIFY_LEFT);
                        var heartCx = startX + metricW + 16;
                        var heartCy = 136 + (fontH / 2).toNumber();
                        MomoUi.drawIcon(dc, "heart", heartCx, heartCy, MomoUi.CORAL);
                        dc.setColor(MomoUi.INK, MomoUi.BG);
                        dc.drawText(heartCx + 10, 136, Graphics.FONT_XTINY, hrText, Graphics.TEXT_JUSTIFY_LEFT);
                    } else {
                        MomoUi.text(dc, metric + " · HR " + _liveHr, 136, arcColor);
                    }
                } else {
                    MomoUi.text(dc, metric, 136, arcColor);
                }
                var cue = coachLine.length() > 0
                    ? coachLine
                    : (kind.equals("stairs") ? "One flight at a time." : (kind.equals("sunlight") ? "Soak in a little daylight." : "Light steps. Unplug a bit."));
                MomoUi.paragraph(dc, cue, 164, 2, MomoUi.MUTED);
            } else {
                MomoUi.drawBezelProgress(dc, progress, MomoUi.LAVENDER);
                MomoUi.text(dc, "QUIET REST", 22, MomoUi.LAVENDER);
                MomoUi.drawIcon(dc, "rest", 130, 56, MomoUi.LAVENDER);
                var pulse = (_animFrame % 8) < 4 ? (_animFrame % 4) : (4 - (_animFrame % 4));
                dc.setPenWidth(1);
                dc.setColor(MomoUi.SURFACE, MomoUi.BG);
                dc.drawArc(130, 110, 62 + pulse, Graphics.ARC_COUNTER_CLOCKWISE, 155, 205);
                dc.drawArc(130, 110, 62 + pulse, Graphics.ARC_COUNTER_CLOCKWISE, 335, 25);
                dc.setColor(MomoUi.LAVENDER, MomoUi.BG);
                dc.drawArc(130, 110, 52 + pulse, Graphics.ARC_COUNTER_CLOCKWISE, 160, 200);
                dc.drawArc(130, 110, 52 + pulse, Graphics.ARC_COUNTER_CLOCKWISE, 340, 20);
                dc.setColor(MomoUi.INK, MomoUi.BG);
                dc.drawText(130, 86, Graphics.FONT_LARGE, clock, Graphics.TEXT_JUSTIFY_CENTER);
                var restCue = coachLine.length() > 0 ? coachLine : "Quiet rest. Shoulders down.";
                MomoUi.paragraph(dc, restCue, 154, 2, MomoUi.MUTED);
            }
            MomoUi.pill(dc, _tracker.goalMet() ? "finish" : "options", 218);
        } else if (_state == :feedback) {
            MomoUi.drawSparkles(dc, _animFrame);
            MomoUi.drawIcon(dc, "check", 130, 62, MomoUi.MINT);
            MomoUi.titleText(dc, "Nice reset!", 92, MomoUi.MINT);
            MomoUi.paragraph(dc, "How did that break feel?", 128, 2, MomoUi.INK);
            MomoUi.pill(dc, "tell Momo", 216);
        } else if (_state == :done) {
            MomoUi.drawSparkles(dc, _animFrame);
            MomoUi.drawIcon(dc, "check", 130, 58, MomoUi.GOLD);
            MomoUi.titleText(dc, "Noted!", 86, MomoUi.MINT);
            MomoUi.paragraph(dc, _message, 120, 3, MomoUi.INK);
            MomoUi.pill(dc, "done", 216);
        } else if (_state == :saving) {
            MomoUi.heading(dc, "Saving");
            MomoUi.drawDivider(dc, 58, 120);
            MomoUi.paragraph(dc, "Filing your break...", 104, 3, MomoUi.MUTED);
            MomoUi.pill(dc, "saving...", 216);
        } else {
            MomoUi.drawStartTick(dc, MomoUi.CORAL);
            MomoUi.heading(dc, "Paused");
            MomoUi.drawDivider(dc, 58, 120);
            MomoUi.paragraph(dc, _message, 86, 4, MomoUi.INK);
            MomoUi.pill(dc, "retry", 216);
        }
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
