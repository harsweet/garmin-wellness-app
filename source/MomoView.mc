import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class MomoView extends WatchUi.View {
    private var _model as MomoModel;
    private var _bitmap as Graphics.BitmapType or Null = null;
    private var _loadedPhase as Number = -1;
    private var _help as Boolean = false;
    private var _timer as Timer.Timer or Null = null;
    private var _animStep as Number = 0;
    private var _tickCount as Number = 0;
    private var _cachedHr as Number or Null = null;
    private var _cachedSteps as Number or Null = null;
    private var _cachedBb as Number or Null = null;
    private var _breaksToday as Number = 0;
    private var _contextLoaded as Boolean = false;

    const BG = 0x000000;
    const MUTED = 0xAAAAAA;

    function initialize(model as MomoModel) {
        View.initialize();
        _model = model;
    }

    function isShowingHelp() as Boolean {
        return _help;
    }

    function getAnimStep() as Number {
        return _animStep;
    }

    function toggleHelp() as Void {
        _help = !_help;
        WatchUi.requestUpdate();
    }

    function refresh() as Void {
        refreshContextCache();
        WatchUi.requestUpdate();
    }

    function onShow() as Void {
        refreshContextCache();
        startAnimTimer();
    }

    function onHide() as Void {
        stopAnimTimer();
        _bitmap = null;
        _loadedPhase = -1;
    }

    function onAnimTick() as Void {
        _animStep = (_animStep + 1) % 8;
        _tickCount += 1;
        if (_tickCount % 10 == 0) {
            refreshContextCache();
        }
        WatchUi.requestUpdate();
    }

    private function startAnimTimer() as Void {
        stopAnimTimer();
        _timer = new Timer.Timer();
        _timer.start(method(:onAnimTick), 450, true);
    }

    private function stopAnimTimer() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    function refreshContextCache() as Void {
        var activity = MomoSensors.readActivityInfo();
        _cachedSteps = activity["steps"] as Number or Null;
        _cachedHr = MomoSensors.readHeartRate();
        _cachedBb = MomoSensors.readBodyBattery();
        _breaksToday = MomoModel.getBreaksToday();
        _contextLoaded = true;
    }

    function setContextForTest(hr as Number or Null, steps as Number or Null, bb as Number or Null, breaksToday as Number) as Void {
        _cachedHr = hr;
        _cachedSteps = steps;
        _cachedBb = bb;
        _breaksToday = breaksToday;
        _contextLoaded = true;
    }

    function statusBanner() as String {
        if (!_contextLoaded) {
            refreshContextCache();
        }
        var stepStr = null as String or Null;
        if (_cachedSteps != null) {
            var s = _cachedSteps as Number;
            stepStr = s >= 1000 ? (s / 1000.0f).format("%.1f") + "k" : s.toString();
        }
        if (_cachedHr != null && stepStr != null) {
            return "HR " + _cachedHr + " · " + stepStr + " steps";
        }
        if (_cachedBb != null && _breaksToday > 0) {
            return "BB " + _cachedBb + " · " + _breaksToday + (_breaksToday == 1 ? " break" : " breaks");
        }
        if (_cachedHr != null && _breaksToday > 0) {
            return "HR " + _cachedHr + " · " + _breaksToday + (_breaksToday == 1 ? " break" : " breaks");
        }
        if (_cachedHr != null) {
            return "HR " + _cachedHr + " · " + _model.getTitle();
        }
        if (_cachedBb != null) {
            return "BB " + _cachedBb + " · " + _model.getTitle();
        }
        if (stepStr != null) {
            return stepStr + " steps · " + _model.getTitle();
        }
        if (_breaksToday > 0) {
            return _breaksToday + (_breaksToday == 1 ? " break" : " breaks") + " · " + _model.getTitle();
        }
        return "DEMO / " + _model.getTitle();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, BG);
        dc.clear();

        if (_help) {
            drawHelp(dc);
            return;
        }

        if (!_contextLoaded) {
            refreshContextCache();
        } else {
            _breaksToday = MomoModel.getBreaksToday();
        }

        if (_loadedPhase != _model.getPhase()) {
            // Hold only one mood bitmap in memory at a time.
            _bitmap = null;
            _bitmap = WatchUi.loadResource(_model.getBitmapId()) as Graphics.BitmapType;
            _loadedPhase = _model.getPhase();
        }

        var breath = _animStep <= 4 ? _animStep : 8 - _animStep;
        var bobOffsets = [0, -1, -2, -1, 0, 1, 1, 0] as Array<Number>;
        var bob = bobOffsets[_animStep];

        // The source images stay unchanged. A clipped viewport frames the mascot.
        dc.setClip(30, 64, 200, 100);
        dc.setColor(MomoUi.SURFACE, BG);
        dc.drawCircle(130, 114, 42 + breath);
        dc.setPenWidth(2);
        dc.setColor(_model.getAccent(), BG);
        dc.drawArc(130, 114, 46 + breath, Graphics.ARC_COUNTER_CLOCKWISE, 148, 212);
        dc.drawArc(130, 114, 46 + breath, Graphics.ARC_COUNTER_CLOCKWISE, 328, 32);
        dc.setPenWidth(1);

        if (_bitmap != null) {
            dc.drawBitmap(_model.getImageX(), _model.getImageY() + bob, _bitmap);
        }

        if (_breaksToday > 0) {
            dc.setColor(MomoUi.GOLD, BG);
            dc.fillCircle(206, 78, 10);
            dc.setColor(BG, MomoUi.GOLD);
            dc.drawText(206, 68, Graphics.FONT_XTINY, _breaksToday > 9 ? "9+" : _breaksToday.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setClip(0, 0, dc.getWidth(), dc.getHeight());

        dc.setColor(Graphics.COLOR_WHITE, BG);
        dc.drawText(130, 16, Graphics.FONT_SMALL, "momo", Graphics.TEXT_JUSTIFY_CENTER);
        MomoUi.text(dc, statusBanner(), 45, _model.getAccent());

        dc.setColor(Graphics.COLOR_WHITE, BG);
        drawRemark(dc, _model.getRemark());

        for (var i = 0; i < _model.PHASE_COUNT; i += 1) {
            dc.setColor(i == _model.getPhase() ? _model.getAccent() : 0x555555, BG);
            if (i == _model.getPhase()) {
                dc.fillRoundedRectangle(110 + i * 16, 245, 10, 4, 2);
            } else {
                dc.fillCircle(115 + i * 16, 247, 2);
            }
        }

        MomoUi.pill(dc, "START: next idea", 212);
    }

    private function drawRemark(dc as Graphics.Dc, remark as String) as Void {
        var lines = wrapRemark(dc, remark);
        var font = Graphics.FONT_XTINY;
        var lineHeight = dc.getFontHeight(font);
        var top = 168 + ((38 - lines.size() * lineHeight) / 2).toNumber();
        for (var i = 0; i < lines.size(); i += 1) {
            MomoUi.text(dc, lines[i], top + i * lineHeight, MomoUi.INK);
        }
    }

    function wrapRemark(dc as Graphics.Dc, remark as String) as Array<String> {
        var words = [] as Array<String>;
        var currentWord = "";
        for (var charIndex = 0; charIndex < remark.length(); charIndex += 1) {
            var character = remark.substring(charIndex, charIndex + 1);
            if (character.equals(" ")) {
                words.add(currentWord);
                currentWord = "";
            } else {
                currentWord += character;
            }
        }
        words.add(currentWord);
        var lines = [] as Array<String>;
        var line = "";
        var font = Graphics.FONT_XTINY;
        for (var wordIndex = 0; wordIndex < words.size(); wordIndex += 1) {
            var word = words[wordIndex];
            var candidate = line.length() == 0 ? word : line + " " + word;
            if (line.length() > 0 && dc.getTextWidthInPixels(candidate, font) > 208) {
                lines.add(line);
                line = word;
            } else {
                line = candidate;
            }
        }
        lines.add(line);
        return lines;
    }

    private function drawHelp(dc as Graphics.Dc) as Void {
        dc.setColor(0x55FFAA, BG);
        dc.drawText(130, 27, Graphics.FONT_SMALL, "Meet Momo", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, BG);
        var lines = ["START: next idea", "Tap Momo: new quip", "UP / DOWN: mood", "Hold UP: setup & menu", "BACK: return"];
        for (var i = 0; i < lines.size(); i += 1) {
            MomoUi.text(dc, lines[i], 68 + i * 24, MomoUi.INK);
        }
        dc.setColor(MUTED, BG);
        MomoUi.text(dc, "Sample day remarks", 207, MomoUi.MUTED);
    }
}
