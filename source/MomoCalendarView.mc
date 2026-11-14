import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class MomoCalendarView extends WatchUi.View {
    private var _client as MomoCalendarClient;
    private var _loaded as Boolean = false;
    private var _state as Symbol = :unpaired;
    private var _mode as String = "";
    private var _slots as Array<Dictionary> = [];
    private var _selected as Number = 0;
    private var _busyNow as Boolean = false;
    private var _message as String = "";
    private var _savedLabel as String = "";
    private var _pendingSlot as String or Null = null;

    function initialize() {
        View.initialize();
        _client = new MomoCalendarClient();
    }

    function onShow() as Void {
        _mode = _client.isDemoServer() ? "demo" : _client.getMode();
        if (!_client.hasServer()) {
            _state = :unconfigured;
        } else if (!_loaded && _client.hasToken()) {
            refresh();
        }
    }

    function dispose() as Void {
        _client.cancel();
    }

    function getState() as Symbol {
        return _state;
    }

    function getSelectedIndex() as Number {
        return _selected;
    }

    function getSelectedSlot() as Dictionary or Null {
        return _slots.size() > 0 ? _slots[_selected] : null;
    }

    function refresh() as Void {
        _loaded = true;
        _pendingSlot = null;
        if (!_client.hasServer()) {
            _state = :unconfigured;
            WatchUi.requestUpdate();
            return;
        } else if (!_client.hasToken()) {
            _state = :unpaired;
            WatchUi.requestUpdate();
            return;
        }
        _state = :loading;
        _message = "Finding room for you...";
        WatchUi.requestUpdate();
        _client.availability(method(:handleAvailability));
    }

    function moveSelection(direction as Number) as Void {
        if (_state == :ready && _slots.size() > 0) {
            _selected = ((_selected + direction) % _slots.size() + _slots.size()) % _slots.size();
            WatchUi.requestUpdate();
        }
    }

    function select() as Void {
        if (_state == :loading) {
            return;
        }
        if (_state == :unconfigured) {
            refresh();
        } else if (_state == :unpaired) {
            _loaded = false;
            var view = new MomoPairingView();
            WatchUi.pushView(view, new MomoPairingDelegate(view), WatchUi.SLIDE_LEFT);
        } else if (_state == :ready) {
            var slot = getSelectedSlot();
            if (slot != null) {
                var label = slot["label"] as String;
                var question = "Add an 8-minute walk?\n" + label;
                if (_mode.equals("demo")) {
                    question = "Save a DEMO walk?\n" + label;
                }
                WatchUi.pushView(new WatchUi.Confirmation(question), new MomoCalendarConfirmationDelegate(self), WatchUi.SLIDE_LEFT);
            }
        } else if (_pendingSlot != null) {
            // Retries use the original server-issued slot ID, avoiding duplicates.
            createConfirmedActivity();
        } else {
            refresh();
        }
    }

    function createConfirmedActivity() as Void {
        if (_pendingSlot == null) {
            var slot = getSelectedSlot();
            if (slot == null || !(slot["id"] instanceof String)) {
                refresh();
                return;
            }
            _pendingSlot = slot["id"] as String;
        }
        _state = :loading;
        _message = "Saving your little escape...";
        WatchUi.requestUpdate();
        _client.createActivity(_pendingSlot, method(:handleCreated));
    }

    function handleAvailability(code as Number, data as Dictionary or Null) as Void {
        _slots = [];
        _selected = 0;
        if (code == 401) {
            _loaded = false;
            _state = :unpaired;
        } else if (code >= 200 && code < 300 && data != null) {
            _mode = data["mode"] instanceof String ? data["mode"] as String : "";
            _busyNow = data["busyNow"] == true;
            if (data["connected"] == false) {
                _state = :not_connected;
            } else if (data["slots"] instanceof Array) {
                var values = data["slots"] as Array;
                for (var i = 0; i < values.size() && _slots.size() < 3; i += 1) {
                    var slot = values[i];
                    if (slot instanceof Dictionary && slot["id"] instanceof String && slot["label"] instanceof String) {
                        _slots.add(slot);
                    }
                }
                _state = _slots.size() > 0 ? :ready : :empty;
            } else {
                _state = :error;
                _message = "Calendar reply was incomplete.";
            }
        } else {
            setError(code);
        }
        WatchUi.requestUpdate();
    }

    function handleCreated(code as Number, data as Dictionary or Null) as Void {
        var status = data != null ? data["status"] : null;
        if (code >= 200 && code < 300 && data != null &&
            status instanceof String && (status.equals("created") || status.equals("already_created"))) {
            _mode = data["mode"] instanceof String ? data["mode"] as String : _mode;
            _savedLabel = data["label"] instanceof String ? data["label"] as String : "8-minute walk";
            _pendingSlot = null;
            _state = :saved;
        } else if (code == 401) {
            _pendingSlot = null;
            _loaded = false;
            _state = :unpaired;
        } else if (code == 409 || code == 410) {
            _pendingSlot = null;
            _state = :error;
            _message = "That slot changed. Let's find another.";
        } else {
            setError(code);
            // An uncertain response must not be presented as a definitive failure.
            if (_pendingSlot != null) {
                _message = "Check your calendar. START safely retries.";
            }
        }
        WatchUi.requestUpdate();
    }

    private function setError(code as Number) as Void {
        _state = :error;
        if (code == 503 || code == 403) {
            _state = :not_connected;
        } else if (code == -1001) {
            _message = "Set an HTTPS calendar server URL.";
        } else if (code < 0) {
            _message = "Calendar is offline. Is the service running?";
        } else {
            _message = "Calendar unavailable. Try again shortly.";
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(130, 24, Graphics.FONT_SMALL, "Momo Calendar", Graphics.TEXT_JUSTIFY_CENTER);
        var accent = _mode.equals("demo") ? 0xFFFF55 : 0x55FFAA;
        dc.setColor(accent, Graphics.COLOR_BLACK);
        var badge = _mode.equals("demo") ? "DEMO CALENDAR" : (_mode.equals("google") ? "GOOGLE CALENDAR" : "YOUR LITTLE ESCAPE");
        dc.drawText(130, 54, Graphics.FONT_XTINY, badge, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        var hint = "START: refresh";
        if (_state == :unconfigured) {
            drawLines(dc, ["Add your Google Calendar", "script URL in Momo's", "app settings."], 94);
            hint = "START: check settings";
        } else if (_state == :unpaired) {
            if (_mode.equals("demo")) {
                drawLines(dc, ["Simulator demo is ready.", "Pair with code 000000.", "No Google login needed."], 94);
            } else {
                drawLines(dc, ["Run setupMomo in your", "Google script, then enter", "its six-digit code here."], 94);
            }
            hint = "START: pair watch";
        } else if (_state == :loading) {
            drawWrapped(dc, _message, 108);
            hint = "One moment...";
        } else if (_state == :not_connected) {
            drawLines(dc, ["Check your Google script", "authorization, then", "come back and refresh."], 94);
        } else if (_state == :ready) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
            dc.drawText(130, 88, Graphics.FONT_XTINY, _busyNow ? "Busy now. Break later." : "Room for a little walk.", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            var slot = getSelectedSlot();
            if (slot != null) {
                drawWrapped(dc, slot["label"] as String, 116);
            }
            dc.drawText(130, 152, Graphics.FONT_XTINY, "8-minute walk", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
            dc.drawText(130, 182, Graphics.FONT_XTINY, (_selected + 1) + " / " + _slots.size() + "   UP / DOWN", Graphics.TEXT_JUSTIFY_CENTER);
            hint = "START: schedule";
        } else if (_state == :empty) {
            drawLines(dc, ["No roomy gaps just yet.", "Keep your plans.", "We'll check again later."], 94);
        } else if (_state == :saved) {
            dc.drawText(130, 92, Graphics.FONT_SMALL, _mode.equals("demo") ? "Demo walk saved" : "Walk scheduled!", Graphics.TEXT_JUSTIFY_CENTER);
            drawWrapped(dc, _savedLabel, 126);
            dc.setColor(accent, Graphics.COLOR_BLACK);
            dc.drawText(130, 169, Graphics.FONT_XTINY, "Chair escape: booked.", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            drawWrapped(dc, _message, 102);
            hint = _pendingSlot != null ? "START: retry safely" : "START: try again";
        }
        dc.setColor(0xAAAAAA, Graphics.COLOR_BLACK);
        dc.drawText(130, 215, Graphics.FONT_XTINY, hint, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawLines(dc as Graphics.Dc, lines as Array<String>, top as Number) as Void {
        for (var i = 0; i < lines.size(); i += 1) {
            dc.drawText(130, top + i * 23, Graphics.FONT_XTINY, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawWrapped(dc as Graphics.Dc, text as String, top as Number) as Void {
        var lines = [] as Array<String>;
        var line = "";
        var word = "";
        for (var i = 0; i <= text.length(); i += 1) {
            var character = i < text.length() ? text.substring(i, i + 1) : " ";
            if (character.equals(" ")) {
                var candidate = line.length() > 0 ? line + " " + word : word;
                if (dc.getTextWidthInPixels(candidate, Graphics.FONT_XTINY) > 202 && line.length() > 0) {
                    lines.add(line);
                    line = word;
                } else {
                    line = candidate;
                }
                word = "";
            } else {
                word += character;
            }
        }
        lines.add(line);
        for (var j = 0; j < lines.size() && j < 4; j += 1) {
            dc.drawText(130, top + j * 23, Graphics.FONT_XTINY, lines[j], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

class MomoCalendarDelegate extends WatchUi.BehaviorDelegate {
    private var _view as MomoCalendarView;

    function initialize(view as MomoCalendarView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean { _view.select(); return true; }
    function onNextPage() as Boolean { _view.moveSelection(1); return true; }
    function onPreviousPage() as Boolean { _view.moveSelection(-1); return true; }
    function onTap(event as WatchUi.ClickEvent) as Boolean { return onSelect(); }
    function onBack() as Boolean {
        _view.dispose();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
    function onMenu() as Boolean {
        if (_view.getState() != :loading) { _view.refresh(); }
        return true;
    }
}

class MomoCalendarConfirmationDelegate extends WatchUi.ConfirmationDelegate {
    private var _view as MomoCalendarView;
    function initialize(view as MomoCalendarView) {
        ConfirmationDelegate.initialize();
        _view = view;
    }
    function onResponse(value as WatchUi.Confirm) as Boolean {
        if (value == WatchUi.CONFIRM_YES) {
            _view.createConfirmedActivity();
        }
        return true;
    }
}
