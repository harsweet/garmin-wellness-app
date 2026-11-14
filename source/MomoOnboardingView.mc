import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class MomoOnboardingView extends WatchUi.View {
    private var _client as MomoCalendarClient;
    private var _state as Symbol = :loading;
    private var _qr as Array<String> = [];
    private var _message as String = "Opening your Momo setup...";
    private var _timer as Timer.Timer or Null = null;
    private var _visible as Boolean = false;
    private var _polling as Boolean = false;
    private var _polls as Number = 0;
    private var _returnToPrevious as Boolean = false;

    function initialize() { View.initialize(); _client = new MomoCalendarClient(); }
    function getState() as Symbol { return _state; }
    function setService(client as MomoCalendarClient) as Void { _client = client; }
    function setReturnToPrevious(value as Boolean) as Void { _returnToPrevious = value; }

    function onShow() as Void {
        _visible = true;
        if (_qr.size() == 0 && _state != :ready) { refresh(); }
        else if (_state == :ready) { enterMomo(); }
        else { startPolling(); }
    }

    function onHide() as Void {
        _visible = false;
        if (_timer != null) { _timer.stop(); _timer = null; }
        _client.cancel(); _polling = false;
    }

    function refresh() as Void {
        _polling = false;
        if (!_client.hasServer()) {
            _state = :error; _message = "Start Momo's service on your computer, then rebuild the watch app.";
        } else {
            _state = :loading; _message = "Opening your Momo setup...";
            _client.onboarding(method(:handleOnboarding));
        }
        WatchUi.requestUpdate();
    }

    function handleOnboarding(code as Number, data as Dictionary or Null) as Void {
        if (code >= 200 && code < 300 && data != null && data["profileConfigured"] == true) {
            _state = :ready;
            if (_visible) { enterMomo(); }
        } else if (code >= 200 && code < 300 && data != null && setQr(data["qr"])) {
            _state = :qr; _polls = 0;
            if (_visible) { startPolling(); }
        } else {
            _state = :error;
            _message = "Setup is offline. Check Momo's service, then press START.";
        }
        WatchUi.requestUpdate();
    }

    function setQr(value as Object or Null) as Boolean {
        _qr = [];
        if (!(value instanceof Array)) { return false; }
        var rows = value as Array;
        if (rows.size() < 21 || rows.size() > 77) { return false; }
        for (var y = 0; y < rows.size(); y += 1) {
            var row = rows[y];
            if (!(row instanceof String) || row.length() != rows.size()) { _qr = []; return false; }
            for (var x = 0; x < row.length(); x += 1) {
                var pixel = row.substring(x, x + 1);
                if (!pixel.equals("0") && !pixel.equals("1")) { _qr = []; return false; }
            }
            _qr.add(row);
        }
        return true;
    }

    function qrGeometry() as Dictionary {
        var pixels = (176 / (_qr.size() + 8)).toNumber();
        var size = (_qr.size() + 8) * pixels;
        return {"moduleSize" => pixels, "size" => size, "x" => ((260 - size) / 2).toNumber(), "y" => (49 + (176 - size) / 2).toNumber()};
    }

    private function startPolling() as Void {
        if (_timer != null) { _timer.stop(); }
        _timer = new Timer.Timer();
        _timer.start(method(:poll), 10000, true);
    }

    function poll() as Void {
        if (_polling || !_visible) { return; }
        _polls += 1;
        if (_polls >= 60) { refresh(); return; }
        _polling = true;
        _client.status(method(:handleStatus));
    }

    function handleStatus(code as Number, data as Dictionary or Null) as Void {
        _polling = false;
        if (code >= 200 && code < 300 && data != null && data["profileConfigured"] == true) {
            _state = :ready;
            if (_visible) { enterMomo(); }
        }
    }

    function enterMomo() as Void {
        onHide();
        if (_returnToPrevious) { WatchUi.popView(WatchUi.SLIDE_RIGHT); return; }
        var model = new MomoModel();
        var view = new MomoView(model);
        WatchUi.switchToView(view, new MomoDelegate(view, model), WatchUi.SLIDE_IMMEDIATE);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK); dc.clear();
        dc.drawText(130, 16, Graphics.FONT_SMALL, "Set up Momo", Graphics.TEXT_JUSTIFY_CENTER);
        if (_state == :qr) {
            var geometry = qrGeometry();
            var scale = geometry["moduleSize"] as Number;
            var left = geometry["x"] as Number;
            var top = geometry["y"] as Number;
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.fillRectangle(left, top, geometry["size"], geometry["size"]);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
            for (var y = 0; y < _qr.size(); y += 1) {
                for (var x = 0; x < _qr.size(); x += 1) {
                    if (_qr[y].substring(x, x + 1).equals("1")) {
                        dc.fillRectangle(left + (x + 4) * scale, top + (y + 4) * scale, scale, scale);
                    }
                }
            }
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawText(130, 230, Graphics.FONT_XTINY, "START: I finished", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            MomoActivityText.draw(dc, _state == :ready ? "You're set. Momo is ready." : _message, 93, 5);
            dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
            dc.drawText(130, 211, Graphics.FONT_XTINY, "START: retry", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(130, 232, Graphics.FONT_XTINY, "BACK: skip for now", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

class MomoOnboardingDelegate extends WatchUi.BehaviorDelegate {
    private var _view as MomoOnboardingView;
    function initialize(view as MomoOnboardingView) { BehaviorDelegate.initialize(); _view = view; }
    function onSelect() as Boolean { _view.refresh(); return true; }
    function onBack() as Boolean { _view.enterMomo(); return true; }
}
