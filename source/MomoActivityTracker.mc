import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Graphics;

// Counts only samples observed while this activity view is visible. Daily steps
// are context, not evidence that the user is stressed, sedentary, or unwell.
class MomoActivityTracker {
    private var _elapsedMs as Number = 0;
    private var _steps as Number = 0;
    private var _lastTick as Number or Null = null;
    private var _lastSteps as Number or Null = null;
    private var _durationSeconds as Number;
    private var _stepTarget as Number;
    private var _tracking as String;

    function initialize(activity as Dictionary, saved as Dictionary or Null) {
        var duration = activity["durationMinutes"];
        _durationSeconds = duration instanceof Number && duration > 0 ? duration * 60 : 120;
        var target = activity["stepTarget"];
        _stepTarget = target instanceof Number && target > 0 ? target : 100;
        var tracking = activity["tracking"];
        _tracking = tracking instanceof String ? tracking : "timer";
        if (saved != null) {
            var elapsed = saved["elapsedSeconds"];
            var steps = saved["steps"];
            if (elapsed instanceof Number && elapsed >= 0) { _elapsedMs = elapsed * 1000; }
            if (steps instanceof Number && steps >= 0) { _steps = steps; }
        }
    }

    static function readSteps() as Number or Null {
        try {
            var value = ActivityMonitor.getInfo().steps;
            return value instanceof Number && value >= 0 ? value : null;
        } catch (error) { return null; }
    }

    static function context(demo as Boolean) as Dictionary {
        return MomoSensors.snapshot(demo, "unknown");
    }

    static function contextWithMood(demo as Boolean, mood as String) as Dictionary {
        return MomoSensors.snapshot(demo, mood);
    }

    function resume(nowMs as Number, dailySteps as Number or Null) as Void {
        _lastTick = nowMs;
        _lastSteps = dailySteps;
    }

    function pause() as Void {
        _lastTick = null;
        _lastSteps = null;
    }

    function update(nowMs as Number, dailySteps as Number or Null) as Void {
        var observed = false;
        if (_lastTick != null) {
            var delta = nowMs - _lastTick;
            // A suspended view is not a recorded foreground session.
            if (delta >= 0 && delta <= 5000) { _elapsedMs += delta; observed = true; }
        }
        _lastTick = nowMs;
        if (observed && dailySteps != null && _lastSteps != null && dailySteps >= _lastSteps) {
            _steps += dailySteps - _lastSteps;
        }
        // A midnight reset, unavailable reading, or resume starts a new baseline.
        _lastSteps = dailySteps;
    }

    function elapsedMs() as Number { return _elapsedMs; }
    function elapsedSeconds() as Number { return (_elapsedMs / 1000).toNumber(); }
    function steps() as Number { return _steps; }
    function durationSeconds() as Number { return _durationSeconds; }
    function targetSteps() as Number { return _stepTarget; }
    function tracking() as String { return _tracking; }
    function goalMet() as Boolean {
        return elapsedSeconds() >= _durationSeconds && (!_tracking.equals("steps") || _steps >= _stepTarget);
    }
    function simulateFinish() as Void {
        _elapsedMs = _durationSeconds * 1000;
        _steps = _tracking.equals("steps") ? _stepTarget : _steps;
    }
    function snapshot() as Dictionary { return {"elapsedSeconds" => elapsedSeconds(), "steps" => _steps}; }
}

module MomoActivityText {
    function wrap(dc as Graphics.Dc, text as String, width as Number) as Array<String> {
        var lines = [] as Array<String>;
        var line = "";
        var word = "";
        for (var i = 0; i <= text.length(); i += 1) {
            var character = i < text.length() ? text.substring(i, i + 1) : " ";
            if (character.equals(" ")) {
                var candidate = line.length() > 0 ? line + " " + word : word;
                if (dc.getTextWidthInPixels(candidate, Toybox.Graphics.FONT_XTINY) > width && line.length() > 0) {
                    lines.add(line); line = word;
                } else { line = candidate; }
                word = "";
            } else { word += character; }
        }
        if (line.length() > 0) { lines.add(line); }
        return lines;
    }

    function draw(dc as Graphics.Dc, text as String, top as Number, maxLines as Number) as Void {
        var lines = wrap(dc, text, 202);
        for (var i = 0; i < lines.size() && i < maxLines; i += 1) {
            dc.drawText(130, top + i * 21, Toybox.Graphics.FONT_XTINY, lines[i], Toybox.Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
