import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class MomoOnboardingView extends WatchUi.View {
    private var _client as MomoCalendarClient;
    private var _state as Symbol = :loading;
    private var _qr as Array<String> = [];
    private var _message as String = "Opening your setup...";
    private var _timer as Timer.Timer or Null = null;
    private var _visible as Boolean = false;
    private var _polling as Boolean = false;
    private var _polls as Number = 0;
    private var _returnToPrevious as Boolean = false;
    private var _fresh as Boolean = false;
    private var _issued as Boolean = false;
    private var _issuedConfigured as Boolean = false;
    private var _issuedRevision as Number = 0;
    private var _issuedUserId as String = "";
    private var _code as String = "";
    private var _setupUrl as String = "";
    private var _page as Number = 0;

    function initialize() { View.initialize(); _client = new MomoCalendarClient(); }
    function getState() as Symbol { return _state; }
    function getCode() as String { return _code; }
    function getPage() as Number { return _page; }
    function setService(client as MomoCalendarClient) as Void { _client = client; }
    // Only launch setup may request a new device; menu setup reuses this one.
    function setFresh(value as Boolean) as Void { _fresh = value; }
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
            _state = :error; _message = "Momo is offline. Reconnect the service and try again.";
        } else {
            _state = :loading; _message = "Opening your setup...";
            if (_fresh && !_issued) { _client.onboardingFresh(method(:handleOnboarding)); }
            else { _client.onboarding(method(:handleOnboarding)); }
        }
        WatchUi.requestUpdate();
    }

    function setupFinished(data as Dictionary) as Boolean {
        if (!_issued || data["profileConfigured"] != true) { return false; }
        var userId = data["userId"] instanceof String ? data["userId"] as String : _issuedUserId;
        if (!userId.equals(_issuedUserId)) { return false; }
        if (!_issuedConfigured) { return true; }
        var revision = data["profileRevision"];
        return revision instanceof Number && revision > _issuedRevision;
    }

    private function markReady() as Void {
        _state = :ready;
        if (_visible) { enterMomo(); }
    }

    function handleOnboarding(response as Number, data as Dictionary or Null) as Void {
        if (response >= 200 && response < 300 && data != null) {
            if (setQr(data["qr"])) {
                // Compare saves against this setup session, never an old profile.
                if (!_issued) {
                    _issued = true;
                    _issuedConfigured = data["profileConfigured"] == true;
                    _issuedRevision = data["profileRevision"] instanceof Number ? data["profileRevision"] as Number : 0;
                    _issuedUserId = data["userId"] instanceof String ? data["userId"] as String : "";
                }
                _page = 0;
                _code = validCode(data["code"]) ? data["code"] as String : "";
                _setupUrl = data["setupUrl"] instanceof String ? data["setupUrl"] as String : "";
                _state = :qr; _polls = 0;
                if (_visible) { startPolling(); }
            } else { showOffline(); }
        } else { showOffline(); }
        WatchUi.requestUpdate();
    }

    private function showOffline() as Void {
        _state = :error;
        _message = "Setup is offline. Check the service, then try again.";
    }

    function validCode(value as Object or Null) as Boolean {
        if (!(value instanceof String) || value.length() != 4) { return false; }
        for (var i = 0; i < 4; i += 1) {
            if ("0123456789".find(value.substring(i, i + 1)) == null) { return false; }
        }
        return true;
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
        var pixels = (168 / (_qr.size() + 8)).toNumber();
        var size = (_qr.size() + 8) * pixels;
        return {"moduleSize" => pixels, "size" => size, "x" => ((260 - size) / 2).toNumber(), "y" => (49 + (168 - size) / 2).toNumber()};
    }

    function movePage() as Void {
        if (_state == :qr) { _page = 1 - _page; WatchUi.requestUpdate(); }
    }

    function select() as Void {
        // Polling checks completion; START also refreshes an expired QR/code.
        refresh();
    }

    private function startPolling() as Void {
        if (_timer != null) { _timer.stop(); }
        _timer = new Timer.Timer();
        _timer.start(method(:poll), 3000, true);
    }

    function poll() as Void {
        if (_polling || !_visible || _state != :qr) { return; }
        _polls += 1;
        if (_polls >= 200) { refresh(); return; }
        _polling = true;
        _client.status(method(:handleStatus));
    }

    function handleStatus(response as Number, data as Dictionary or Null) as Void {
        _polling = false;
        if (response >= 200 && response < 300 && data != null && setupFinished(data)) { markReady(); }
    }

    function enterMomo() as Void {
        onHide();
        if (_returnToPrevious) { WatchUi.popView(WatchUi.SLIDE_RIGHT); return; }
        var model = new MomoModel();
        var view = new MomoView(model);
        WatchUi.switchToView(view, new MomoDelegate(view, model), WatchUi.SLIDE_IMMEDIATE);
    }

    private function drawQr(dc as Graphics.Dc) as Void {
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
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        MomoUi.clear(dc);
        if (_state == :qr && _page == 0) {
            dc.setColor(MomoUi.INK, MomoUi.BG);
            dc.drawText(130, 17, Graphics.FONT_SMALL, "Scan QR or...", Graphics.TEXT_JUSTIFY_CENTER);
            drawQr(dc);
            MomoUi.text(dc, "UP/DOWN: code", 219, MomoUi.MINT);
        } else if (_state == :qr) {
            MomoUi.heading(dc, "Or enter code");
            MomoUi.text(dc, "at this setup URL", 65, MomoUi.MUTED);
            dc.setColor(MomoUi.MINT, MomoUi.BG);
            dc.drawText(130, 90, Graphics.FONT_LARGE, _code.length() > 0 ? _code : "----", Graphics.TEXT_JUSTIFY_CENTER);
            var displayUrl = _setupUrl;
            if (displayUrl.length() > 8 && displayUrl.substring(0, 8).equals("https://")) { displayUrl = displayUrl.substring(8, displayUrl.length()); }
            MomoUi.paragraph(dc, displayUrl.length() > 0 ? displayUrl : "Scan the QR on the other page.", 145, 3, MomoUi.INK);
            MomoUi.text(dc, "UP/DOWN: QR", 217, MomoUi.MUTED);
        } else {
            MomoUi.heading(dc, "Set up Momo");
            MomoUi.paragraph(dc, _state == :ready ? "You're set. Momo is ready." : _message, 88, 4, MomoUi.INK);
            MomoUi.pill(dc, _state == :loading ? "Connecting..." : "START: retry", 194);
            MomoUi.text(dc, "BACK: skip", 227, MomoUi.MUTED);
        }
    }
}

class MomoOnboardingDelegate extends WatchUi.BehaviorDelegate {
    private var _view as MomoOnboardingView;
    function initialize(view as MomoOnboardingView) { BehaviorDelegate.initialize(); _view = view; }
    function onSelect() as Boolean { _view.select(); return true; }
    function onNextPage() as Boolean { _view.movePage(); return true; }
    function onPreviousPage() as Boolean { _view.movePage(); return true; }
    function onTap(event as WatchUi.ClickEvent) as Boolean { _view.movePage(); return true; }
    function onBack() as Boolean { _view.enterMomo(); return true; }
}
