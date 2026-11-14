import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class MomoDelegate extends WatchUi.BehaviorDelegate {
    private var _view as MomoView;
    private var _model as MomoModel;

    function initialize(view as MomoView, model as MomoModel) {
        BehaviorDelegate.initialize();
        _view = view;
        _model = model;
    }

    function onNextPage() as Boolean {
        return changePhase(1);
    }

    function onPreviousPage() as Boolean {
        return changePhase(-1);
    }

    function onSelect() as Boolean {
        if (_view.isShowingHelp()) {
            _view.toggleHelp();
        } else {
            _model.nextRemark();
            _view.refresh();
        }
        return true;
    }

    function onTap(event as WatchUi.ClickEvent) as Boolean {
        if (_view.isShowingHelp()) {
            _view.toggleHelp();
            return true;
        }
        var point = event.getCoordinates();
        if (point[1] >= 224 && point[0] >= 94 && point[0] < 164) {
            var phase = point[0] < 123 ? 0 : (point[0] < 139 ? 1 : 2);
            _model.selectPhase(phase);
            _view.refresh();
            return true;
        }
        return onSelect();
    }

    function onSwipe(event as WatchUi.SwipeEvent) as Boolean {
        var direction = event.getDirection();
        return changePhase(direction == WatchUi.SWIPE_LEFT || direction == WatchUi.SWIPE_UP ? 1 : -1);
    }

    function onMenu() as Boolean {
        var calendarView = new MomoCalendarView();
        WatchUi.pushView(calendarView, new MomoCalendarDelegate(calendarView), WatchUi.SLIDE_LEFT);
        return true;
    }

    function onHold(event as WatchUi.ClickEvent) as Boolean {
        _view.toggleHelp();
        return true;
    }

    function onBack() as Boolean {
        if (_view.isShowingHelp()) {
            _view.toggleHelp();
        } else {
            System.exit();
        }
        return true;
    }

    private function changePhase(direction as Number) as Boolean {
        if (_view.isShowingHelp()) {
            _view.toggleHelp();
        }
        _model.movePhase(direction);
        _view.refresh();
        return true;
    }
}
