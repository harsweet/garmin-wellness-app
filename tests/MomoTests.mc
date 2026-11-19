import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

// Exercise the actual controller/model together, including wraparound and help.
(:test)
function momoNavigationAndQuips(logger as Test.Logger) as Boolean {
    var model = new MomoModel();
    var view = new MomoView(model);
    var delegate = new MomoDelegate(view, model);
    Test.assertEqual(model.getPhase(), 1);
    delegate.onPreviousPage();
    Test.assertEqual(model.getPhase(), 0);
    var first = model.getRemark();
    for (var i = 0; i < 4; i += 1) {
        delegate.nextRemark();
    }
    Test.assertEqual(model.getRemark(), first);
    delegate.onPreviousPage();
    Test.assertEqual(model.getPhase(), 2);
    delegate.onNextPage();
    Test.assertEqual(model.getPhase(), 0);
    view.toggleHelp();
    Test.assert(view.isShowingHelp());
    delegate.onBack();
    Test.assert(!view.isShowingHelp());
    logger.debug("Physical-button behaviors, mood wraparound, quips, and help passed.");
    return true;
}

// Use fēnix 7 Pro's real font metrics and resource loader, not approximated widths.
(:test)
function momoAllPhasesRenderAndFit(logger as Test.Logger) as Boolean {
    var reference = Graphics.createBufferedBitmap({:width => 260, :height => 260});
    var bitmap = reference.get() as Graphics.BufferedBitmap;
    var dc = bitmap.getDc();
    var model = new MomoModel();
    var view = new MomoView(model);
    var font = Graphics.FONT_XTINY;
    logger.debug("Remark font height: " + dc.getFontHeight(font));

    for (var phase = 0; phase < 3; phase += 1) {
        model.selectPhase(phase);
        Test.assert(dc.getTextWidthInPixels(model.getTitle(), font) <= 208);
        for (var quip = 0; quip < 4; quip += 1) {
            var lines = view.wrapRemark(dc, model.getRemark());
            logger.debug(model.getTitle() + ": " + lines.size() + " lines / " + model.getRemark());
            Test.assertEqualMessage(lines.size() <= 2, true, "Remark must fit its two-line area.");
            for (var line = 0; line < lines.size(); line += 1) {
                Test.assert(dc.getTextWidthInPixels(lines[line], font) <= 208);
            }
            // This catches missing resources, rendering API failures, and memory errors.
            view.onUpdate(dc);
            model.nextRemark();
        }
        view.onHide();
    }
    view.toggleHelp();
    view.onUpdate(dc);
    logger.debug("All three supplied images, twelve remarks, and help rendered.");
    return true;
}

(:test)
function momoSensorsAndMovementDerivation(logger as Test.Logger) as Boolean {
    Test.assertEqual(MomoSensors.deriveMovement(7000, 5, 0), "active");
    Test.assertEqual(MomoSensors.deriveMovement(100, 45, 0), "active");
    Test.assertEqual(MomoSensors.deriveMovement(2000, 10, 4), "some");
    Test.assertEqual(MomoSensors.deriveMovement(0, 0, 3), "low");
    Test.assertEqual(MomoSensors.deriveMovement(500, 5, 2), "unknown");
    Test.assertEqual(MomoSensors.deriveMovement(null, null, null), "unknown");

    Test.assertEqual(MomoSensors.deriveEnergy("fried"), "low");
    Test.assertEqual(MomoSensors.deriveEnergy("okay"), "okay");
    Test.assertEqual(MomoSensors.deriveEnergy("wired"), "high");
    Test.assertEqual(MomoSensors.deriveEnergy("unknown"), "unknown");

    var simSnap = MomoSensors.snapshot(true, "wired");
    Test.assertEqual(simSnap["source"], "simulated");
    Test.assertEqual(simSnap["energy"], "high");
    Test.assertEqual(simSnap["checkInMood"], "wired");
    Test.assert(simSnap.hasKey("heartRate"));
    Test.assert(simSnap.hasKey("stress"));
    Test.assert(simSnap.hasKey("bodyBattery"));
    Test.assert(simSnap.hasKey("moveBarLevel"));
    Test.assert(simSnap.hasKey("activeMinutes"));
    Test.assert(simSnap.hasKey("elevationMeters"));
    Test.assert(simSnap.hasKey("temperatureC"));
    Test.assert(simSnap.hasKey("solarIntensity"));

    var watchCtx = MomoActivityTracker.contextWithMood(false, "fried");
    Test.assertEqual(watchCtx["source"], "watch");
    Test.assertEqual(watchCtx["energy"], "low");

    var defaultCtx = MomoActivityTracker.context(true);
    Test.assertEqual(defaultCtx["checkInMood"], "unknown");
    Test.assertEqual(defaultCtx["energy"], "unknown");

    var vitals = MomoSensors.vitalsSnapshot();
    Test.assert(vitals.hasKey("hr"));
    Test.assert(vitals.hasKey("stress"));
    Test.assert(vitals.hasKey("elevation"));

    MomoSensors.vibrate(:inhale);
    MomoSensors.vibrate(:exhale);
    MomoSensors.vibrate(:step);
    MomoSensors.vibrate(:celebrate);
    logger.debug("MomoSensors movement, energy, snapshot, vitals, and safe haptics passed.");
    return true;
}

(:test)
function momoAnimatedHomeAndBreaksCounter(logger as Test.Logger) as Boolean {
    var savedCount = Application.Storage.getValue("momoBreaksToday");
    var savedDate = Application.Storage.getValue("momoBreaksDate");
    Application.Storage.deleteValue("momoBreaksToday");
    Application.Storage.deleteValue("momoBreaksDate");
    var passed = true;
    try {
        var model = new MomoModel();
        var view = new MomoView(model);
        var delegate = new MomoDelegate(view, model);

        var choices = delegate.homeChoices();
        var hasCheckin = false;
        var hasReceipts = false;
        for (var i = 0; i < choices.size(); i += 1) {
            if (choices[i]["id"] == :checkin) { hasCheckin = true; }
            if (choices[i]["id"] == :receipts) { hasReceipts = true; }
        }
        Test.assert(hasCheckin);
        Test.assert(hasReceipts);

        view.setContextForTest(null, null, null, 0);
        Test.assertEqual(view.statusBanner(), "DEMO / JUST CHILLIN'");
        view.setContextForTest(72, 3200, 68, 2);
        Test.assertEqual(view.statusBanner(), "HR 72 · 3.2k steps");
        view.setContextForTest(null, null, 68, 2);
        Test.assertEqual(view.statusBanner(), "BB 68 · 2 breaks");

        Test.assertEqual(MomoModel.getBreaksToday(), 0);
        Test.assertEqual(MomoModel.incrementBreaksToday(), 1);
        Test.assertEqual(MomoModel.getBreaksToday(), 1);

        var reference = Graphics.createBufferedBitmap({:width => 260, :height => 260});
        var bitmap = reference.get() as Graphics.BufferedBitmap;
        var dc = bitmap.getDc();

        view.onShow();
        for (var tick = 0; tick < 8; tick += 1) {
            view.onAnimTick();
            view.onUpdate(dc);
        }
        Test.assertEqual(view.getAnimStep(), 0);
        view.onHide();
        logger.debug("Animated home view, live status banner, breaks counter, and home menu choices passed.");
    } catch (error) {
        logger.error(error.toString());
        passed = false;
    }
    if (savedCount == null) { Application.Storage.deleteValue("momoBreaksToday"); }
    else { Application.Storage.setValue("momoBreaksToday", savedCount); }
    if (savedDate == null) { Application.Storage.deleteValue("momoBreaksDate"); }
    else { Application.Storage.setValue("momoBreaksDate", savedDate); }
    return passed;
}
