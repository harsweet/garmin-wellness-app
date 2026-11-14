import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class MomoView extends WatchUi.View {
    private var _model as MomoModel;
    private var _bitmap as Graphics.BitmapType or Null = null;
    private var _loadedPhase as Number = -1;
    private var _help as Boolean = false;

    const BG = 0x000000;
    const MUTED = 0xAAAAAA;

    function initialize(model as MomoModel) {
        View.initialize();
        _model = model;
    }

    function isShowingHelp() as Boolean {
        return _help;
    }

    function toggleHelp() as Void {
        _help = !_help;
        WatchUi.requestUpdate();
    }

    function refresh() as Void {
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        _bitmap = null;
        _loadedPhase = -1;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, BG);
        dc.clear();

        if (_help) {
            drawHelp(dc);
            return;
        }

        if (_loadedPhase != _model.getPhase()) {
            // Hold only one mood bitmap in memory at a time.
            _bitmap = null;
            _bitmap = WatchUi.loadResource(_model.getBitmapId()) as Graphics.BitmapType;
            _loadedPhase = _model.getPhase();
        }

        // The source images stay unchanged. A clipped viewport frames the mascot.
        dc.setClip(30, 64, 200, 100);
        if (_bitmap != null) {
            dc.drawBitmap(_model.getImageX(), _model.getImageY(), _bitmap);
        }
        dc.setClip(0, 0, dc.getWidth(), dc.getHeight());

        dc.setColor(Graphics.COLOR_WHITE, BG);
        dc.drawText(130, 16, Graphics.FONT_SMALL, "momo", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(_model.getAccent(), BG);
        MomoUi.text(dc, "DEMO / " + _model.getTitle(), 45, _model.getAccent());

        dc.setColor(Graphics.COLOR_WHITE, BG);
        drawRemark(dc, _model.getRemark());

        // Three touch targets match the three demo phases; no invented health score.
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
