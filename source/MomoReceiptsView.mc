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

    private function formatTopCard(value as String) as String {
        if (value.length() > 12 && value.substring(0, 12).equals("Best break: ")) {
            return value.substring(12, value.length());
        }
        if (value.length() > 10 && value.substring(0, 10).equals("Top pick: ")) {
            return value.substring(10, value.length());
        }
        return value;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        MomoUi.clear(dc);

        if (_state == :ready) {
            var totalPages = 1 + _activities.size();
            MomoUi.drawPageRail(dc, totalPages, _page, MomoUi.MINT);
            if (_page == 0) {
                var eyebrow = _mode.equals("demo") ? "DEMO RECEIPTS" : "RECEIPTS";
                dc.setColor(MomoUi.MINT, MomoUi.BG);
                dc.drawText(130, 16, Graphics.FONT_XTINY, MomoUi.fit(dc, eyebrow, Graphics.FONT_XTINY, 114), Graphics.TEXT_JUSTIFY_CENTER);
                MomoUi.titleText(dc, "What works", 34, MomoUi.INK);

                // Two side-by-side stat tiles
                dc.setColor(MomoUi.INK, MomoUi.BG);
                dc.drawText(82, 66, Graphics.FONT_MEDIUM, _totalBreaks.toString(), Graphics.TEXT_JUSTIFY_CENTER);
                dc.setColor(MomoUi.MUTED, MomoUi.BG);
                dc.drawText(82, 100, Graphics.FONT_XTINY, "BREAKS", Graphics.TEXT_JUSTIFY_CENTER);

                dc.setColor(MomoUi.EDGE, MomoUi.BG);
                dc.drawLine(130, 72, 130, 118);

                dc.setColor(MomoUi.GOLD, MomoUi.BG);
                dc.drawText(178, 66, Graphics.FONT_MEDIUM, _streakDays.toString() + "d", Graphics.TEXT_JUSTIFY_CENTER);
                dc.setColor(MomoUi.MUTED, MomoUi.BG);
                dc.drawText(178, 100, Graphics.FONT_XTINY, "STREAK", Graphics.TEXT_JUSTIFY_CENTER);

                // Highlighted Top Break card
                dc.setColor(MomoUi.DEEP, MomoUi.BG);
                dc.fillRoundedRectangle(36, 130, 188, 66, 12);
                dc.setColor(MomoUi.SURFACE, MomoUi.BG);
                dc.drawRoundedRectangle(36, 130, 188, 66, 12);

                dc.setColor(MomoUi.GOLD, Graphics.COLOR_TRANSPARENT);
                dc.drawText(130, 136, Graphics.FONT_XTINY, "TOP BREAK", Graphics.TEXT_JUSTIFY_CENTER);

                var cardLines = MomoUi.lines(dc, formatTopCard(_topSummary), 172);
                dc.setColor(MomoUi.INK, Graphics.COLOR_TRANSPARENT);
                var lineCount = cardLines.size() < 2 ? cardLines.size() : 2;
                for (var i = 0; i < lineCount; i += 1) {
                    var line = cardLines[i];
                    if (i == 1 && cardLines.size() > 2) {
                        while (line.length() > 0 && dc.getTextWidthInPixels(line + "...", Graphics.FONT_XTINY) > 172) {
                            line = line.substring(0, line.length() - 1);
                        }
                        line = line + "...";
                    } else {
                        line = MomoUi.fit(dc, line, Graphics.FONT_XTINY, 172);
                    }
                    dc.drawText(130, 156 + i * 18, Graphics.FONT_XTINY, line, Graphics.TEXT_JUSTIFY_CENTER);
                }

                MomoUi.pill(dc, _activities.size() > 0 ? "UP/DOWN" : "refresh", 214);
            } else {
                var item = _activities[_page - 1];
                var kind = item["activityId"] as String;
                var title = item["title"] as String;
                var completed = item["completed"] as Number;
                var helped = item["helped"] as Number;
                var rated = item["rated"] as Number;
                var rate = item["helpfulRate"] as Number;
                var accent = MomoUi.activityAccent(kind);

                // Activity badge + vector icon (ring on BG keeps crescent/eye cutouts crisp)
                dc.setPenWidth(2);
                dc.setColor(MomoUi.SURFACE, MomoUi.BG);
                dc.drawCircle(130, 32, 15);
                dc.setPenWidth(1);
                MomoUi.drawIcon(dc, kind, 130, 32, accent);

                MomoUi.titleText(dc, title, 54, MomoUi.INK);

                var ratio = rated > 0 ? (helped.toFloat() / rated.toFloat()) : 0.0f;
                var barColor = rate >= 60 ? MomoUi.MINT : (rate >= 30 ? MomoUi.GOLD : MomoUi.LAVENDER);

                dc.setColor(barColor, MomoUi.BG);
                dc.drawText(130, 82, Graphics.FONT_LARGE, rated > 0 ? rate.toString() + "%" : "--", Graphics.TEXT_JUSTIFY_CENTER);

                MomoUi.drawProgressBar(dc, 48, 138, 164, 10, ratio, barColor);

                var statLine = rated > 0
                    ? helped + "/" + rated + " helped · " + completed + " done"
                    : completed + " done · unrated";
                MomoUi.text(dc, statLine, 158, MomoUi.INK);
                MomoUi.text(dc, (_page + 1) + " of " + totalPages, 182, MomoUi.MUTED);
                MomoUi.pill(dc, "UP/DOWN", 214);
            }
            return;
        }

        if (_state == :error) {
            MomoUi.drawStartTick(dc, MomoUi.MINT);
        }
        MomoUi.heading(dc, "What works");
        MomoUi.text(dc, _mode.equals("demo") ? "DEMO RECEIPTS" : "RECEIPTS", 50, MomoUi.MINT);
        MomoUi.drawDivider(dc, 76, 120);
        MomoUi.paragraph(dc, _message, 92, 4, MomoUi.INK);
        var pillLabel = _state == :loading ? "wait..." : (_state == :empty ? "back" : "retry");
        MomoUi.pill(dc, pillLabel, 214);
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
