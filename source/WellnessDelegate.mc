import Toybox.Lang;
import Toybox.WatchUi;

class WellnessDelegate extends WatchUi.BehaviorDelegate {
    private var _mission as HeistMission;

    function initialize(mission as HeistMission) {
        BehaviorDelegate.initialize();
        _mission = mission;
    }

    // START/STOP is the upper-right button on the Fenix 7 Pro.
    function onSelect() as Boolean {
        _mission.select();
        WatchUi.requestUpdate();
        return true;
    }

    // DOWN is the lower-left button. BACK keeps its default exit behavior.
    function onNextPage() as Boolean {
        _mission.down();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _mission.up();
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() as Boolean {
        var handled = _mission.back();
        WatchUi.requestUpdate();
        return handled;
    }
}
