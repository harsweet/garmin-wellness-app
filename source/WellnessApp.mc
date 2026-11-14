import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class WellnessApp extends Application.AppBase {
    private var _sensors as HeistSensors;
    private var _mission as HeistMission;

    function initialize() {
        AppBase.initialize();
        _sensors = new HeistSensors();
        _mission = new HeistMission(_sensors);
    }

    function onStart(state as Dictionary?) as Void {
        System.println("Chair Heist: briefing ready. START deploys; UP switches DEMO/LIVE.");
    }

    function onStop(state as Dictionary?) as Void {
        _sensors.stop();
        System.println("Chair Heist: sensors stopped.");
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new WellnessView(_mission), new WellnessDelegate(_mission)];
    }
}
