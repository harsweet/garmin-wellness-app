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
            openSuggestions();
        }
        return true;
    }

    function onTap(event as WatchUi.ClickEvent) as Boolean {
        if (_view.isShowingHelp()) {
            _view.toggleHelp();
            return true;
        }
        var point = event.getCoordinates();
        if (point[1] >= 240 && point[0] >= 94 && point[0] < 164) {
            var phase = point[0] < 123 ? 0 : (point[0] < 139 ? 1 : 2);
            _model.selectPhase(phase);
            _view.refresh();
            return true;
        }
        if (point[1] >= 210) { return onSelect(); }
        nextRemark();
        return true;
    }

    function onSwipe(event as WatchUi.SwipeEvent) as Boolean {
        var direction = event.getDirection();
        return changePhase(direction == WatchUi.SWIPE_LEFT || direction == WatchUi.SWIPE_UP ? 1 : -1);
    }

    function onMenu() as Boolean {
        var choices = new MomoChoiceView("Hey, you.", homeChoices(), method(:onHomeChoice));
        WatchUi.pushView(choices, new MomoChoiceDelegate(choices), WatchUi.SLIDE_LEFT);
        return true;
    }

    function homeChoices() as Array<Dictionary> {
        return [{"id" => :suggestions, "label" => "Next idea", "detail" => "A little time for you"},
            {"id" => :setup, "label" => "Setup", "detail" => "Your goals & preferences"},
            {"id" => :help, "label" => "Controls", "detail" => "Meet your little sidekick"}];
    }

    function primaryAction() as Symbol { return :suggestions; }

    function onHomeChoice(id as Symbol) as Void {
        if (id == :suggestions) { openSuggestions(); }
        else if (id == :setup) {
            var setup = new MomoOnboardingView(); setup.setReturnToPrevious(true);
            WatchUi.pushView(setup, new MomoOnboardingDelegate(setup), WatchUi.SLIDE_LEFT);
        } else { _view.toggleHelp(); }
    }

    function nextRemark() as Void { _model.nextRemark(); _view.refresh(); }

    function openSuggestions() as Void {
        var calendarView = new MomoCalendarView();
        WatchUi.pushView(calendarView, new MomoCalendarDelegate(calendarView), WatchUi.SLIDE_LEFT);
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
