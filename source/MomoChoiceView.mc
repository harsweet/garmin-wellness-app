import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Watch-sized choices use the same small font and margins as Momo's screens.
class MomoChoiceView extends WatchUi.View {
    private var _title as String;
    private var _items as Array<Dictionary>;
    private var _callback as Method;
    private var _selected as Number = 0;

    function initialize(title as String, items as Array<Dictionary>, callback as Method) {
        View.initialize(); _title = title; _items = items; _callback = callback;
    }

    function getSelectedIndex() as Number { return _selected; }
    function getSelectedId() as Symbol { return _items[_selected]["id"] as Symbol; }
    function getItems() as Array<Dictionary> { return _items; }
    function move(direction as Number) as Void {
        _selected = ((_selected + direction) % _items.size() + _items.size()) % _items.size();
        WatchUi.requestUpdate();
    }
    function rowBounds(row as Number) as Dictionary { return {"x" => 31, "y" => 70 + row * 46, "width" => 198, "height" => 42}; }
    function choose() as Void {
        var id = getSelectedId();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        _callback.invoke(id);
    }
    function onUpdate(dc as Graphics.Dc) as Void {
        MomoUi.clear(dc);
        MomoUi.drawStartTick(dc, MomoUi.MINT);
        MomoUi.heading(dc, _title);
        MomoUi.drawDivider(dc, 54, 110);
        var first = _selected > 1 ? _selected - 1 : 0;
        var lastFirst = _items.size() > 3 ? _items.size() - 3 : 0;
        if (first > lastFirst) { first = lastFirst; }
        var fontH = dc.getFontHeight(Graphics.FONT_XTINY);
        for (var row = 0; row < 3 && first + row < _items.size(); row += 1) {
            var index = first + row;
            var item = _items[index];
            var box = rowBounds(row);
            var top = box["y"] as Number;
            var isSelected = (index == _selected);
            if (isSelected) {
                dc.setColor(MomoUi.SURFACE, MomoUi.BG);
                dc.fillRoundedRectangle(31, top, 198, 42, 10);
                dc.setColor(MomoUi.MINT, MomoUi.SURFACE);
                dc.fillRoundedRectangle(33, top + 6, 4, 30, 2);
            }
            var label = item["label"] as String;
            var detail = item["detail"] instanceof String ? item["detail"] as String : "";
            var background = isSelected ? MomoUi.SURFACE : MomoUi.BG;
            dc.setColor(isSelected ? MomoUi.INK : MomoUi.MUTED, background);
            var textTop = detail.length() > 0 ? top + 3 : top + ((42 - fontH) / 2).toNumber();
            dc.drawText(45, textTop, Graphics.FONT_XTINY, MomoUi.fit(dc, label, Graphics.FONT_XTINY, 174), Graphics.TEXT_JUSTIFY_LEFT);
            if (detail.length() > 0) {
                dc.setColor(isSelected ? MomoUi.MUTED : MomoUi.EDGE, background);
                dc.drawText(45, top + 22, Graphics.FONT_XTINY, MomoUi.fit(dc, detail, Graphics.FONT_XTINY, 174), Graphics.TEXT_JUSTIFY_LEFT);
            }
            if (!isSelected && row < 2 && index + 1 < _items.size() && index + 1 != _selected) {
                dc.setColor(MomoUi.EDGE, MomoUi.BG);
                dc.drawLine(45, top + 44, 215, top + 44);
            }
        }
        MomoUi.drawPageRail(dc, _items.size(), _selected, MomoUi.MINT);
        MomoUi.text(dc, "START · select", 218, MomoUi.MUTED);
    }
}

class MomoChoiceDelegate extends WatchUi.BehaviorDelegate {
    private var _view as MomoChoiceView;
    function initialize(view as MomoChoiceView) { BehaviorDelegate.initialize(); _view = view; }
    function onNextPage() as Boolean { _view.move(1); return true; }
    function onPreviousPage() as Boolean { _view.move(-1); return true; }
    function onSelect() as Boolean { _view.choose(); return true; }
    function onBack() as Boolean { WatchUi.popView(WatchUi.SLIDE_RIGHT); return true; }
    function onTap(event as WatchUi.ClickEvent) as Boolean { return onSelect(); }
}
