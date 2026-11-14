import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MomoApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new MomoOnboardingView();
        return [view, new MomoOnboardingDelegate(view)];
    }
}
