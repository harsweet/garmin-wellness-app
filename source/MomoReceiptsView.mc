import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class MomoReceiptsView extends WatchUi.View {
    private var _client as MomoCalendarClient;
    private var _state as Symbol = :loading;
    private var _loaded as Boolean = false;
    private var _mode as String = "demo";
    private var _page as Number = 0;
    private var _totalBreaks as Number = 0;
    private var _streakDays as Number = 0;
    private var _topSummary as String = "";
    private var _activities as Array<Dictionary> = [];
    private var _message as String = "Reading your break receipts...";

    function initialize() {
        View.initialize();
        _client = new MomoCalendarClient();
    }

    function getState() as Symbol { return _state; }
    function getPage() as Number { return _page; }
    function getActivitiesCount() as Number { return _activities.size(); }
    function setService(client as MomoCalendarClient) as Void { _client = client; }

    function onShow() as Void {
        _mode = _client.getMode();
        if (!_loaded) { refresh(); }
    }

    function dispose() as Void {
        _client.cancel();
    }

    function refresh() as Void {
        _loaded = true;
        _page = 0;
        if (!_client.hasServer()) {
            _state = :error;
            _message = "Momo is offline. Connect the service and try again.";
        } else if (!_client.hasToken()) {
            _state = :error;
            _message = "Pair your watch first to view your receipts.";
        } else {
            _state = :loading;
            _message = "Reading your break receipts...";
            _client.insights(method(:handleInsights));
        }
        WatchUi.requestUpdate();
    }

    function movePage(direction as Number) as Void {
        if (_state != :ready) { return; }
        var totalPages = 1 + _activities.size();
        if (totalPages <= 1) { return; }
        _page = ((_page + direction) % totalPages + totalPages) % totalPages;
        WatchUi.requestUpdate();
    }

    function handleInsights(code as Number, data as Dictionary or Null) as Void {
        _page = 0;
        if (code >= 200 && code < 300 && data != null) {
            _mode = data["mode"] instanceof String ? data["mode"] as String : _mode;
            var payload = data["insights"] instanceof Dictionary ? data["insights"] as Dictionary : data;
            _totalBreaks = readNumber(payload, ["totalCompleted", "totalBreaks", "completedCount"], 0);
            _streakDays = readNumber(payload, ["streakDays", "streak"], 0);
            var rawActivities = payload["byActivity"] != null ? payload["byActivity"] : payload["activities"];
            _activities = parseActivities(rawActivities);
            _topSummary = parseTopSummary(payload);
            if (_totalBreaks == 0 && _activities.size() == 0) {
                _state = :empty;
                _message = "No receipts yet. Finish a break and tell Momo how it felt.";
            } else {
                _state = :ready;
            }
        } else {
            _state = :error;
            _message = data != null && data["message"] instanceof String
                ? data["message"] as String
                : "Could not load receipts. START retries.";
        }
        WatchUi.requestUpdate();
    }

    private function readNumber(dict as Dictionary, keys as Array<String>, fallback as Number) as Number {
        for (var i = 0; i < keys.size(); i += 1) {
            var val = dict[keys[i]];
            if (val instanceof Number) { return val as Number; }
        }
        return fallback;
    }

    private function parseActivities(raw as Object or Null) as Array<Dictionary> {
        var result = [] as Array<Dictionary>;
        if (!(raw instanceof Array)) { return result; }
        var items = raw as Array;
        for (var i = 0; i < items.size() && result.size() < 6; i += 1) {
            var item = items[i];
            if (!(item instanceof Dictionary)) { continue; }
            var entry = item as Dictionary;
            var id = entry["activityId"] instanceof String ? entry["activityId"] as String : "break";
            var title = entry["title"] instanceof String ? entry["title"] as String : activityLabel(id);
            var completed = readNumber(entry, ["completed", "count"], 0);
            var helped = readNumber(entry, ["helpful", "helped", "helpfulCount", "yes"], 0);
            var somewhat = readNumber(entry, ["somewhat"], 0);
            var notHelpful = readNumber(entry, ["notHelpful"], 0);
            var rated = readNumber(entry, ["rated", "feedbackCount", "totalRated"], helped + somewhat + notHelpful);
            if (rated < helped) { rated = helped; }
            var rate = readNumber(entry, ["helpRate", "helpfulRate", "rate"], rated > 0 ? ((helped * 100) / rated).toNumber() : 0);
            result.add({
                "activityId" => id,
                "title" => title,
                "completed" => completed,
                "helped" => helped,
                "rated" => rated,
                "helpfulRate" => rate
            });
        }
        return result;
    }

    private function parseTopSummary(data as Dictionary) as String {
        var topObj = data["topActivity"];
        if (!(topObj instanceof Dictionary)) { topObj = data["bestActivity"]; }
        if (topObj instanceof Dictionary) {
            var top = topObj as Dictionary;
            var title = top["title"] instanceof String ? top["title"] as String : activityLabel(top["activityId"] instanceof String ? top["activityId"] as String : "");
            var rate = readNumber(top, ["helpRate", "helpfulRate", "rate"], -1);
            if (title.length() > 0) {
                return rate >= 0 ? "Best break: " + title + " · " + rate + "% helpful" : "Best break: " + title;
            }
        }
        if (_activities.size() > 0) {
            var best = _activities[0];
            for (var i = 1; i < _activities.size(); i += 1) {
                var candidate = _activities[i];
                if ((candidate["helpfulRate"] as Number) > (best["helpfulRate"] as Number)) {
                    best = candidate;
                }
            }
            var rate = best["helpfulRate"] as Number;
            var title = best["title"] as String;
            if ((best["rated"] as Number) > 0) {
                return "Best break: " + title + " · " + rate + "% helpful";
            }
            return "Top pick: " + title;
        }
        return "Finish a few breaks to spot your favorites.";
    }

    private function activityLabel(id as String) as String {
        if (id.equals("walk")) { return "Walk"; }
        if (id.equals("stretch")) { return "Stretch"; }
        if (id.equals("breathe")) { return "Breathe"; }
        if (id.equals("rest")) { return "Quiet rest"; }
        if (id.equals("eyes")) { return "Eye rest"; }
        if (id.equals("stairs")) { return "Stairs"; }
        if (id.equals("sunlight")) { return "Sunlight"; }
        return id.length() > 0 ? id : "Break";
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        MomoUi.clear(dc);
        MomoUi.heading(dc, "What works");
        MomoUi.text(dc, _mode.equals("demo") ? "DEMO RECEIPTS" : "YOUR BREAK RECEIPTS", 56, MomoUi.MINT);

        var hint = "START: refresh";
        if (_state == :loading) {
            MomoUi.paragraph(dc, _message, 108, 3, MomoUi.INK);
            hint = "One moment...";
        } else if (_state == :ready) {
            var totalPages = 1 + _activities.size();
            if (_page == 0) {
                var streakLabel = _streakDays == 1 ? "1 day" : _streakDays + " days";
                MomoUi.text(dc, _totalBreaks + (_totalBreaks == 1 ? " break done" : " breaks done"), 88, MomoUi.INK);
                MomoUi.text(dc, "Streak: " + streakLabel, 112, MomoUi.GOLD);
                MomoUi.paragraph(dc, _topSummary, 140, 3, MomoUi.LAVENDER);
                hint = _activities.size() > 0 ? "UP/DOWN: receipts" : "START: refresh";
            } else {
                var item = _activities[_page - 1];
                var title = item["title"] as String;
                var completed = item["completed"] as Number;
                var helped = item["helped"] as Number;
                var rated = item["rated"] as Number;
                var rate = item["helpfulRate"] as Number;

                MomoUi.text(dc, title, 86, MomoUi.INK);
                var receiptLine = rated > 0
                    ? helped + "/" + rated + " helped (" + rate + "%)"
                    : "No ratings yet";
                MomoUi.text(dc, receiptLine, 112, MomoUi.MINT);

                var ratio = rated > 0 ? (helped.toFloat() / rated.toFloat()) : 0.0f;
                var barColor = rate >= 60 ? MomoUi.MINT : (rate >= 30 ? MomoUi.GOLD : MomoUi.LAVENDER);
                MomoUi.drawProgressBar(dc, 52, 142, 156, 8, ratio, barColor);

                MomoUi.text(dc, completed + (completed == 1 ? " completed" : " completed"), 162, MomoUi.MUTED);
                MomoUi.text(dc, (_page + 1) + " / " + totalPages, 186, MomoUi.MUTED);
                hint = "UP/DOWN: browse";
            }
            for (var i = 0; i < totalPages && i < 7; i += 1) {
                dc.setColor(i == _page ? MomoUi.MINT : MomoUi.EDGE, MomoUi.BG);
                dc.fillCircle(237, 112 + i * 7, i == _page ? 2 : 1);
            }
        } else {
            MomoUi.paragraph(dc, _message, 105, 4, MomoUi.INK);
            hint = _state == :empty ? "BACK: return" : "START: retry";
        }
        MomoUi.pill(dc, hint, 215);
    }
}

class MomoReceiptsDelegate extends WatchUi.BehaviorDelegate {
    private var _view as MomoReceiptsView;

    function initialize(view as MomoReceiptsView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean { _view.movePage(1); return true; }
    function onPreviousPage() as Boolean { _view.movePage(-1); return true; }
    function onSelect() as Boolean { _view.refresh(); return true; }
    function onTap(event as WatchUi.ClickEvent) as Boolean { return onSelect(); }
    function onBack() as Boolean {
        _view.dispose();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
