import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;
import Toybox.Application;
import Toybox.WatchUi;

(:test)
function momoCalendarBuildUrlOverridesSavedSettings(logger as Test.Logger) as Boolean {
    var builtIn = WatchUi.loadResource(Rez.Strings.CalendarBuildServerUrl) as String;
    if (builtIn.length() == 0) {
        logger.debug("No build-specific calendar URL configured.");
        return true;
    }
    var original = Application.Properties.getValue("CalendarServerUrl");
    var passed = true;
    try {
        Application.Properties.setValue("CalendarServerUrl", "http://127.0.0.1:8787");
        var client = new MomoCalendarClient();
        Test.assertEqual(client.getServerUrl(), builtIn);
        Application.Properties.setValue("CalendarServerUrl", "https://old-demo.trycloudflare.com");
        Test.assertEqual(client.getServerUrl(), builtIn);
        Test.assert(client.hasServer());
        logger.debug("Current build URL wins over saved HTTP and expired demo URL settings.");
    } catch (error) {
        logger.error(error.toString());
        passed = false;
    }
    Application.Properties.setValue("CalendarServerUrl", original instanceof String ? original : "");
    return passed;
}

(:test)
function momoCalendarSlotsAndStates(logger as Test.Logger) as Boolean {
    var view = new MomoCalendarView();
    Test.assertEqual(view.getState(), :unpaired);
    view.handleAvailability(200, {"connected" => true, "mode" => "demo", "busyNow" => true, "slots" => [
        {"id" => "first", "label" => "Today 12:30 PM"},
        {"id" => "second", "label" => "Today 1:30 PM"}
    ]});
    Test.assertEqual(view.getState(), :ready);
    Test.assertEqual(view.getSelectedSlot()["id"], "first");
    view.moveSelection(-1);
    Test.assertEqual(view.getSelectedSlot()["id"], "second");
    view.moveSelection(1);
    Test.assertEqual(view.getSelectedIndex(), 0);
    view.handleAvailability(200, {"connected" => true, "mode" => "google", "slots" => []});
    Test.assertEqual(view.getState(), :empty);
    view.handleAvailability(401, null);
    Test.assertEqual(view.getState(), :unpaired);
    view.handleAvailability(503, null);
    Test.assertEqual(view.getState(), :not_connected);
    view.handleAvailability(-2, null);
    Test.assertEqual(view.getState(), :error);
    view.handleCreated(409, null);
    Test.assertEqual(view.getState(), :error);
    view.handleCreated(200, {"status" => "already_created", "mode" => "google", "label" => "Today 12:30 PM"});
    Test.assertEqual(view.getState(), :saved);
    logger.debug("Calendar parsing, selection, expired auth, conflict, offline and saved states passed.");
    return true;
}

(:test)
function momoCalendarAndPairingRender(logger as Test.Logger) as Boolean {
    var reference = Graphics.createBufferedBitmap({:width => 260, :height => 260});
    var bitmap = reference.get() as Graphics.BufferedBitmap;
    var dc = bitmap.getDc();
    var view = new MomoCalendarView();
    view.onUpdate(dc);
    view.handleAvailability(200, {"connected" => true, "mode" => "demo", "busyNow" => false, "slots" => [{"id" => "first", "label" => "Tomorrow 12:30 PM"}]});
    view.onUpdate(dc);
    view.handleAvailability(200, {"connected" => true, "mode" => "google", "slots" => []});
    view.onUpdate(dc);
    view.handleAvailability(503, null);
    view.onUpdate(dc);
    view.handleAvailability(-2, null);
    view.onUpdate(dc);
    view.handleCreated(200, {"status" => "created", "mode" => "google", "label" => "Tomorrow 12:30 PM"});
    view.onUpdate(dc);
    var pairing = new MomoPairingView();
    Test.assertEqual(pairing.getCode(), "000000");
    pairing.adjust(-1);
    Test.assertEqual(pairing.getCode(), "900000");
    pairing.next();
    pairing.adjust(1);
    Test.assertEqual(pairing.getCode(), "910000");
    Test.assert(pairing.previous());
    Test.assertEqual(pairing.getPosition(), 0);
    pairing.onUpdate(dc);
    logger.debug("Calendar screens and six-digit pairing rendered with the fēnix fonts.");
    return true;
}
