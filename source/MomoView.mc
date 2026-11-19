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
        var accent = _model.getAccent();
        var cx = 130;
        var cy = 112;

        // 1. Render the mascot inside a square clip, then carve corners into a circular medallion.
        dc.setClip(80, 62, 100, 100);
        if (_bitmap != null) {
            dc.drawBitmap(_model.getImageX(), _model.getImageY() + bob, _bitmap);
        }
        dc.setClip(0, 0, dc.getWidth(), dc.getHeight());

        // Erase square JPEG corners cleanly into pure MIP black.
        dc.setColor(BG, BG);
        dc.setPenWidth(18);
        dc.drawCircle(cx, cy, 56);
        dc.setPenWidth(16);
        dc.drawCircle(cx, cy, 68);
        dc.setPenWidth(1);

        // 2. Frame the circular portrait with an inner rim + animated breathing halo.
        dc.setColor(MomoUi.EDGE, BG);
        dc.drawCircle(cx, cy, 48);
        var haloR = 51 + (breath / 2).toNumber();
        dc.setPenWidth(3);
        dc.setColor(accent, BG);
        dc.drawCircle(cx, cy, haloR);
        dc.setPenWidth(2);
        dc.setColor(MomoUi.SURFACE, BG);
        dc.drawArc(cx, cy, 56 + breath, Graphics.ARC_COUNTER_CLOCKWISE, 150, 210);
        dc.drawArc(cx, cy, 56 + breath, Graphics.ARC_COUNTER_CLOCKWISE, 330, 30);
        dc.setPenWidth(1);

        // 3. Dock breaks-today badge cleanly on the 2 o'clock rim of the portrait.
        if (_breaksToday > 0) {
            var bx = 166;
            var by = 76;
            dc.setColor(BG, BG);
            dc.fillCircle(bx, by, 12);
            dc.setColor(MomoUi.GOLD, BG);
            dc.fillCircle(bx, by, 10);
            var badgeText = _breaksToday > 9 ? "9+" : _breaksToday.toString();
            var fh = dc.getFontHeight(Graphics.FONT_XTINY);
            dc.setColor(BG, MomoUi.GOLD);
            dc.drawText(bx, by - (fh / 2).toNumber(), Graphics.FONT_XTINY, badgeText, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // 4. Crisp top wordmark + live telemetry line.
        MomoUi.drawStartTick(dc, accent);
        dc.setColor(Graphics.COLOR_WHITE, BG);
        dc.drawText(130, 12, Graphics.FONT_SMALL, "momo", Graphics.TEXT_JUSTIFY_CENTER);

        var banner = statusBanner();
        var bannerW = dc.getTextWidthInPixels(banner, Graphics.FONT_XTINY);
        if (_cachedHr != null && bannerW < 154) {
            MomoUi.drawIcon(dc, "heart", 130 - (bannerW / 2).toNumber() - 10, 48, MomoUi.CORAL);
        }
        MomoUi.text(dc, banner, 39, accent);

        // 5. Two-line remark, sleek bottom capsule, and mood indicator dots.
        dc.setColor(Graphics.COLOR_WHITE, BG);
        drawRemark(dc, _model.getRemark());

        MomoUi.pill(dc, "next idea", 214);

        for (var i = 0; i < _model.PHASE_COUNT; i += 1) {
            dc.setColor(i == _model.getPhase() ? accent : MomoUi.EDGE, BG);
            if (i == _model.getPhase()) {
                dc.fillRoundedRectangle(109 + i * 16, 244, 12, 4, 2);
            } else {
                dc.fillCircle(115 + i * 16, 246, 2);
            }
        }
    }

    private function drawRemark(dc as Graphics.Dc, remark as String) as Void {
        var lines = wrapRemark(dc, remark);
        var font = Graphics.FONT_XTINY;
        var lineHeight = dc.getFontHeight(font);
        var top = 171 + ((38 - lines.size() * lineHeight) / 2).toNumber();
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
