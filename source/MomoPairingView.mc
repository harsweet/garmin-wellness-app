import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class MomoPairingView extends WatchUi.View {
    private var _digits as Array<Number> = [0, 0, 0, 0, 0, 0];
    private var _position as Number = 0;
    private var _client as MomoCalendarClient;
    private var _loading as Boolean = false;
    private var _error as String = "";

    function initialize() {
        View.initialize();
        _client = new MomoCalendarClient();
    }

    function getPosition() as Number { return _position; }
    function getCode() as String {
        var result = "";
        for (var i = 0; i < 6; i += 1) { result += _digits[i].toString(); }
        return result;
    }

    function adjust(direction as Number) as Void {
        if (!_loading) {
            _digits[_position] = (_digits[_position] + direction + 10) % 10;
            _error = "";
            WatchUi.requestUpdate();
        }
    }

    function next() as Void {
        if (_loading) { return; }
        if (_position < 5) {
            _position += 1;
            WatchUi.requestUpdate();
        } else {
            _loading = true;
            _error = "";
            WatchUi.requestUpdate();
            _client.pair(getCode(), method(:onPaired));
        }
    }

    function previous() as Boolean {
        if (_loading) { return true; }
        if (_position > 0) {
            _position -= 1;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function cancel() as Void { _client.cancel(); }

    function onPaired(code as Number, data as Dictionary or Null) as Void {
        _loading = false;
        if (code >= 200 && code < 300 && data != null && data["token"] instanceof String) {
            var mode = data["mode"] instanceof String ? data["mode"] as String : "google";
            _client.saveToken(data["token"] as String, mode);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else {
            _error = code < 0 ? "Service offline. Try again." : "Code expired? Run setup.";
            _position = 0;
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        MomoUi.clear(dc);
        MomoUi.drawStartTick(dc, MomoUi.MINT);
        MomoUi.heading(dc, "Pair Momo");
        MomoUi.text(dc, _client.isDemoServer() ? "DEMO CODE: 000000" : "Code from setupMomo", 54, MomoUi.MUTED);
        MomoUi.drawDivider(dc, 80, 124);

        var boxY = 98;
        var boxW = 26;
        var boxH = 44;
        var fontH = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var digitY = boxY + ((boxH - fontH) / 2).toNumber() - 1;
        for (var i = 0; i < 6; i += 1) {
            var boxX = 42 + i * 30;
            var cx = boxX + 13;
            var active = (i == _position);
            if (active) {
                dc.setColor(MomoUi.SURFACE, MomoUi.BG);
                dc.fillRoundedRectangle(boxX, boxY, boxW, boxH, 6);
                dc.setColor(MomoUi.MINT, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, digitY, Graphics.FONT_MEDIUM, _digits[i].toString(), Graphics.TEXT_JUSTIFY_CENTER);
                dc.setColor(MomoUi.MINT, MomoUi.BG);
                dc.fillRoundedRectangle(boxX + 4, boxY + boxH - 4, boxW - 8, 3, 1);
            } else {
                dc.setColor(MomoUi.EDGE, MomoUi.BG);
                dc.drawRoundedRectangle(boxX, boxY, boxW, boxH, 6);
                dc.setColor(MomoUi.INK, MomoUi.BG);
                dc.drawText(cx, digitY, Graphics.FONT_MEDIUM, _digits[i].toString(), Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        if (_error.length() > 0) {
            MomoUi.text(dc, _error, 158, MomoUi.CORAL);
        } else {
            MomoUi.text(dc, _loading ? "Pairing..." : "UP/DOWN: digit", 158, _loading ? MomoUi.MINT : MomoUi.MUTED);
        }
        MomoUi.text(dc, "BACK: previous", 182, MomoUi.MUTED);
        MomoUi.pill(dc, _loading ? "wait..." : (_position < 5 ? "next" : "connect"), 210);
    }
}

class MomoPairingDelegate extends WatchUi.BehaviorDelegate {
    private var _view as MomoPairingView;
    function initialize(view as MomoPairingView) { BehaviorDelegate.initialize(); _view = view; }
    function onNextPage() as Boolean { _view.adjust(-1); return true; }
    function onPreviousPage() as Boolean { _view.adjust(1); return true; }
    function onSelect() as Boolean { _view.next(); return true; }
    function onBack() as Boolean {
        if (!_view.previous()) { _view.cancel(); WatchUi.popView(WatchUi.SLIDE_RIGHT); }
        return true;
    }
}
