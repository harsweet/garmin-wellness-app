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
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(130, 30, Graphics.FONT_SMALL, "Pair Momo", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
        dc.drawText(130, 72, Graphics.FONT_XTINY, _client.isDemoServer() ? "DEMO CODE: 000000" : "Code from setupMomo", Graphics.TEXT_JUSTIFY_CENTER);
        for (var i = 0; i < 6; i += 1) {
            var x = 65 + i * 26;
            dc.setColor(i == _position ? 0x55FFAA : Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(x, 108, Graphics.FONT_MEDIUM, _digits[i].toString(), Graphics.TEXT_JUSTIFY_CENTER);
            if (i == _position) { dc.fillRectangle(x - 9, 142, 18, 3); }
        }
        dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
        dc.drawText(130, 163, Graphics.FONT_XTINY, _loading ? "Pairing..." : "UP / DOWN: change digit", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(130, 188, Graphics.FONT_XTINY, _error.length() > 0 ? _error : "START: next / connect", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(130, 214, Graphics.FONT_XTINY, "BACK: previous digit", Graphics.TEXT_JUSTIFY_CENTER);
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
