import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MomoApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var model = new MomoModel();
        var view = new MomoView(model);
        return [view, new MomoDelegate(view, model)];
    }
}
