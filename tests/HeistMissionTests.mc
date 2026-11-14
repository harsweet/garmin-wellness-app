import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

// Tests never enable real sensors and restore the user's persistent ledger.
(:test)
function heistSafeRequiresOrderedTurns(logger as Test.Logger) as Boolean {
    var source = new HeistSensors();
    var mission = new HeistMission(source);
    mission.select();
    for (var i = 0; i < 6; i += 1) {
        mission.select();
        mission.tick();
    }
    var passed = true;
    try {
        Test.assertEqual(mission.screen, 2);
        for (var j = 0; j < 3; j += 1) {
            source.injectDemo(:counterclockwise);
            mission.tick();
        }
        for (var k = 0; k < 8; k += 1) { mission.tick(); }
        Test.assertEqualMessage(mission.safePin, 0, "Wrong first direction cannot crack a pin");
        for (var turn = 0; turn < 6; turn += 1) {
            source.injectDemo(:clockwise);
            mission.tick();
        }
        for (var hold = 0; hold < 5; hold += 1) { mission.tick(); }
        Test.assertEqual(mission.safePin, 1);
        source.injectDemo(:clockwise);
        for (var wait = 0; wait < 8; wait += 1) { mission.tick(); }
        Test.assertEqualMessage(mission.safePin, 1, "Second pin requires reversing direction");
    } catch (error) {
        logger.error(error.toString());
        passed = false;
    }
    source.stop();
    return passed;
}

(:test)
function heistIndoorFallbackSavesOnceAndReloads(logger as Test.Logger) as Boolean {
    var snapshot = Application.Storage.getValue("chair-cartel-v1");
    var source = new HeistSensors();
    var mission = new HeistMission(source);
    var oldLoot = mission.demoLoot;
    var oldBreaks = mission.demoBreaks;
    var oldRealBreaks = mission.completedBreaks;
    var oldYes = mission.demoHelpfulYes;
    var passed = true;
    try {
        mission.select();
        for (var tick = 0; tick < 300 && mission.screen != 4; tick += 1) {
            mission.select();
            mission.tick();
        }
        Test.assertEqualMessage(mission.screen, 4, "All three stages finish without GPS or solar");
        Test.assert(mission.usedFallback);
        Test.assert(!source.hasGps && !source.hasSolar);
        Test.assert(!mission.outdoorBonus);
        Test.assertEqual(mission.missionLoot, 100);
        Test.assertEqual(mission.demoLoot, oldLoot + 100);
        Test.assertEqual(mission.demoBreaks, oldBreaks + 1);
        Test.assertEqual(mission.completedBreaks, oldRealBreaks);
        for (var extra = 0; extra < 50; extra += 1) { mission.tick(); }
        Test.assertEqualMessage(mission.demoBreaks, oldBreaks + 1, "Completion is counted once");
        mission.select();
        Test.assert(mission.ratingSaved);
        Test.assertEqual(mission.demoHelpfulYes, oldYes + 1);
        mission.down(); // A second rating attempt only opens the dossier.
        Test.assertEqual(mission.demoHelpfulYes, oldYes + 1);
        var reloaded = new HeistMission(new HeistSensors());
        Test.assertEqual(reloaded.demoLoot, oldLoot + 100);
        Test.assertEqual(reloaded.demoBreaks, oldBreaks + 1);
        Test.assertEqual(reloaded.demoHelpfulYes, oldYes + 1);
        Test.assertEqual(reloaded.completedBreaks, oldRealBreaks);
    } catch (error) {
        logger.error(error.toString());
        passed = false;
    }
    source.stop();
    if (snapshot == null) {
        Application.Storage.deleteValue("chair-cartel-v1");
    } else {
        Application.Storage.setValue("chair-cartel-v1", snapshot);
    }
    return passed;
}

(:test)
function heistMissingMotionCannotPassExtraction(logger as Test.Logger) as Boolean {
    var source = new HeistSensors();
    var mission = new HeistMission(source);
    mission.select();
    mission.screen = 3;
    mission.part = 1;
    source.hasMotion = false;
    source.motion = 0.0;
    var passed = true;
    try {
        for (var i = 0; i < 70; i += 1) { mission.tick(); }
        Test.assertEqual(mission.screen, 3);
        Test.assertEqualMessage(mission.progress, 0.0, "Missing sensor data is never treated as stillness");
        mission.screen = 2;
        source.hasGyro = false;
        source.wristAngle = 45.0;
        for (var j = 0; j < 10; j += 1) { mission.tick(); }
        Test.assertEqualMessage(mission.safePin, 0, "Missing gyro cannot crack a safe");
    } catch (error) {
        logger.error(error.toString());
        passed = false;
    }
    source.stop();
    return passed;
}

(:test)
function heistHighEffortOffersQuietRest(logger as Test.Logger) as Boolean {
    var source = new HeistSensors();
    var mission = new HeistMission(source);
    mission.select();
    mission.screen = 3;
    source.heartRate = 125;
    source.hasHeartRate = true;
    var passed = true;
    try {
        mission.tick();
        Test.assertEqualMessage(mission.part, 2, "Elevated effort branches to rest");
        Test.assertEqual(mission.title, "03 / QUIET EXTRACTION");
        source.injectDemo(:quiet);
        for (var i = 0; i < 50; i += 1) { mission.tick(); }
        Test.assertEqualMessage(mission.part, 0, "Rest returns to the antenna puzzle");
        Test.assertEqual(mission.screen, 3);
    } catch (error) {
        logger.error(error.toString());
        passed = false;
    }
    source.stop();
    return passed;
}

(:test)
function heistOptionalStairsAlwaysHasWalkingExit(logger as Test.Logger) as Boolean {
    var source = new HeistSensors();
    var mission = new HeistMission(source);
    var passed = true;
    try {
        mission.select();
        mission.up();
        Test.assert(!mission.stairsRoute);
        source.hasAltitude = true;
        source.altitudeGain = 1.5;
        mission.up();
        mission.tick();
        Test.assert(mission.stairsRoute);
        Test.assertEqual(mission.charge, 50);
        source.hasAltitude = false;
        mission.up();
        mission.tick();
        Test.assert(!mission.stairsRoute);
        Test.assertEqual(mission.screen, 1);
        Test.assertEqual(mission.charge, 0);
        source.hasAltitude = true;
        source.altitudeGain = 3.0;
        mission.up();
        mission.tick();
        Test.assertEqual(mission.screen, 2);
        Test.assert(mission.stairsBonus);
    } catch (error) {
        logger.error(error.toString());
        passed = false;
    }
    source.stop();
    return passed;
}

// Exercise every native drawing path on the device renderer, without UI access.
(:test)
function heistAllScreensRenderOnDevice(logger as Test.Logger) as Boolean {
    var source = new HeistSensors();
    var mission = new HeistMission(source);
    var view = new WellnessView(mission);
    var passed = true;
    try {
        var reference = Graphics.createBufferedBitmap({ :width => 260, :height => 260 });
        var bitmap = reference.get() as Graphics.BufferedBitmap;
        var dc = bitmap.getDc();
        for (var screen = 0; screen <= 5; screen += 1) {
            mission.screen = screen;
            mission.progress = 0.6;
            mission.charge = 60;
            view.onUpdate(dc);
        }
        mission.screen = 3;
        mission.part = 1;
        view.onUpdate(dc);
        mission.part = 2;
        view.onUpdate(dc);
        source.demo = false;
        mission.screen = 5;
        view.onUpdate(dc);
        logger.debug("Rendered briefing, all mini-games, debrief, demo and live stats.");
    } catch (error) {
        logger.error(error.toString());
        passed = false;
    }
    source.stop();
    return passed;
}
