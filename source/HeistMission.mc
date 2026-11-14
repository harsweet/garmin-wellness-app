import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

// Three ordered physical puzzles. Demo rewards have their own persistent ledger.
class HeistMission {
    var sensors as HeistSensors;
    var screen as Number = 0;
    var part as Number = 0;
    var charge as Number = 0;
    var safePin as Number = 0;
    var safeTarget as Float = 45.0;
    var progress as Float = 0.0;
    var title as String = "CHAIR CARTEL";
    var prompt as String = "Steal back your break.";
    var detail as String = "3 puzzles. One escape.";
    var hint as String = "START deploy";
    var feedback as String = "Your chair is the boss.";
    var targetHeading as Number = 90;
    var headingError as Float = 90.0;
    var loot as Number = 0;
    var completedBreaks as Number = 0;
    var helpfulYes as Number = 0;
    var helpfulNo as Number = 0;
    var demoLoot as Number = 0;
    var demoBreaks as Number = 0;
    var demoHelpfulYes as Number = 0;
    var demoHelpfulNo as Number = 0;
    var missionLoot as Number = 0;
    var elapsed as Number = 0;
    var outdoorBonus as Boolean = false;
    var stairsBonus as Boolean = false;
    var usedFallback as Boolean = false;
    var ratingSaved as Boolean = false;
    var storageOk as Boolean = true;
    var stairsRoute as Boolean = false;

    private var _ticks as Number = 0;
    private var _hold as Number = 0;
    private var _quietTicks as Number = 0;
    private var _restTicks as Number = 0;
    private var _lastWrist as Float = 0.0;
    private var _pinMoved as Boolean = false;
    private var _awardGranted as Boolean = false;
    private var _restUsed as Boolean = false;
    private var _targets as Array<Float> = [45.0, -30.0, 60.0];
    private var _missionDemo as Boolean = true;

    function initialize(sensorSource as HeistSensors) {
        sensors = sensorSource;
        load();
        refreshText();
    }

    function tick() as Void {
        if (screen >= 1 && screen <= 3) {
            sensors.poll();
            _ticks += 1;
            elapsed = (_ticks / 10).toNumber();
            if (sensors.hasGps) {
                usedFallback = false;
            }
            if (sensors.hasSolar && sensors.solar >= 20) {
                outdoorBonus = true;
            }
            if (sensors.hasAltitude && sensors.altitudeGain >= 2.5) {
                stairsBonus = true;
            }
            if (screen == 1) {
                tickCharge();
            } else if (screen == 2) {
                tickSafe();
            } else {
                tickExtraction();
            }
        }
        refreshText();
    }

    function select() as Void {
        if (screen == 0) {
            beginMission();
        } else if (screen == 4) {
            if (!ratingSaved) {
                rate(true);
            } else {
                beginMission();
            }
        } else if (screen == 5) {
            screen = 0;
        } else if (sensors.demo) {
            if (screen == 1) {
                sensors.injectDemo(:walk);
            } else if (screen == 2) {
                var delta = safeTarget - sensors.wristAngle;
                if (delta > 8.0) {
                    sensors.injectDemo(:clockwise);
                } else if (delta < -8.0) {
                    sensors.injectDemo(:counterclockwise);
                }
            } else if (part == 0) {
                sensors.injectDemo(:orient);
            } else {
                sensors.injectDemo(:quiet);
            }
        }
        refreshText();
    }

    function up() as Void {
        if (screen == 0) {
            sensors.stop();
            sensors.demo = !sensors.demo;
            sensors.resetMission();
        } else if (screen == 1 && (sensors.hasAltitude || stairsRoute)) {
            stairsRoute = !stairsRoute;
        }
        refreshText();
    }

    function down() as Void {
        if (screen == 0) {
            screen = 5;
        } else if (screen == 4) {
            if (!ratingSaved) {
                rate(false);
            } else {
                screen = 5;
            }
        }
        refreshText();
    }

    function back() as Boolean {
        if (screen == 0) {
            sensors.stop();
            return false;
        }
        sensors.stop();
        screen = 0;
        refreshText();
        return true;
    }

    private function beginMission() as Void {
        sensors.stop();
        sensors.resetMission();
        sensors.resetWrist();
        _missionDemo = sensors.demo;
        sensors.start();
        screen = 1;
        part = 0;
        charge = 0;
        safePin = 0;
        safeTarget = _targets[0];
        progress = 0.0;
        _ticks = 0;
        elapsed = 0;
        _hold = 0;
        _quietTicks = 0;
        _restTicks = 0;
        _lastWrist = 0.0;
        _pinMoved = false;
        _awardGranted = false;
        _restUsed = false;
        outdoorBonus = false;
        stairsBonus = false;
        usedFallback = !sensors.hasGps;
        ratingSaved = false;
        missionLoot = 0;
        stairsRoute = false;
        System.println("Chair Cartel: mission deployed, demo=" + sensors.demo);
    }

    private function tickCharge() as Void {
        charge = stairsRoute ? ((sensors.altitudeGain * 100) / 3.0).toNumber()
            : ((sensors.steps * 100) / 24).toNumber();
        if (charge > 100) { charge = 100; }
        progress = charge / 100.0;
        if (charge >= 100) {
            screen = 2;
            progress = 0.0;
            sensors.resetWrist();
            _lastWrist = 0.0;
            _pinMoved = false;
            _hold = 0;
            System.println("Chair Cartel: gadget charged; safe unlocked.");
        }
    }

    private function tickSafe() as Void {
        if (!sensors.hasGyro) {
            _hold = 0;
            progress = safePin / 3.0;
            return;
        }
        var movement = sensors.wristAngle - _lastWrist;
        var clockwise = safePin != 1;
        if (movement.abs() > 0.5) {
            if ((clockwise && movement > 0.0) || (!clockwise && movement < 0.0)) {
                _pinMoved = true;
            } else {
                _pinMoved = false;
                _hold = 0;
            }
        }
        _lastWrist = sensors.wristAngle;
        if (_pinMoved && (sensors.wristAngle - safeTarget).abs() <= 10.0) {
            _hold += 1;
        } else {
            _hold = 0;
        }
        progress = (safePin + (_hold / 5.0)) / 3.0;
        if (_hold >= 5) {
            safePin += 1;
            _hold = 0;
            _pinMoved = false;
            System.println("Chair Cartel: safe tumbler " + safePin + " cracked.");
            if (safePin == 3) {
                screen = 3;
                part = 0;
                progress = 0.0;
                _lastWrist = sensors.wristAngle;
            } else {
                safeTarget = _targets[safePin];
            }
        }
    }

    private function tickExtraction() as Void {
        // Effort feedback is a pacing cue, never a requirement to raise heart rate.
        if (!_restUsed && sensors.hasHeartRate && sensors.heartRate >= 120) {
            part = 2;
            _restUsed = true;
            _restTicks = 0;
            _hold = 0;
            _quietTicks = 0;
        }
        if (part == 2) {
            if (sensors.hasMotion && sensors.motion < 0.15) {
                _restTicks += 1;
            } else {
                _restTicks = 0;
            }
            progress = _restTicks / 50.0;
            if (_restTicks >= 50) {
                part = 0;
                progress = 0.0;
            }
            return;
        }
        if (part == 0) {
            if (!sensors.hasHeading) {
                _hold = 0;
                progress = 0.0;
                return;
            }
            var difference = (sensors.heading - targetHeading).abs().toFloat();
            headingError = difference > 180.0 ? 360.0 - difference : difference;
            if (headingError <= 15.0) {
                _hold += 1;
            } else {
                _hold = 0;
            }
            progress = _hold / 10.0;
            if (_hold >= 10) {
                part = 1;
                _quietTicks = 0;
                progress = 0.0;
                System.println("Chair Cartel: antenna aligned; quiet extraction.");
            }
        } else {
            if (sensors.hasMotion && sensors.motion < 0.15) {
                _quietTicks += 1;
            } else {
                _quietTicks = 0;
            }
            progress = _quietTicks / 40.0;
            if (_quietTicks >= 40) {
                completeMission();
            }
        }
    }

    private function completeMission() as Void {
        if (_awardGranted) { return; }
        _awardGranted = true;
        missionLoot = 100 + (stairsBonus ? 25 : 0) + (outdoorBonus ? 25 : 0);
        if (_missionDemo) {
            demoLoot += missionLoot;
            demoBreaks += 1;
        } else {
            loot += missionLoot;
            completedBreaks += 1;
        }
        screen = 4;
        progress = 1.0;
        sensors.stop();
        save();
        System.println("Chair Cartel: extracted " + missionLoot + " loot; demo=" + _missionDemo);
    }

    private function rate(helpful as Boolean) as Void {
        if (ratingSaved || !_awardGranted) { return; }
        ratingSaved = true;
        if (_missionDemo) {
            if (helpful) { demoHelpfulYes += 1; } else { demoHelpfulNo += 1; }
        } else {
            if (helpful) { helpfulYes += 1; } else { helpfulNo += 1; }
        }
        save();
    }

    private function refreshText() as Void {
        if (screen == 0) {
            title = "CHAIR CARTEL";
            prompt = "Steal back your break.";
            detail = "3 puzzles. One escape.";
            feedback = "I call it house arrest.";
            hint = "START deploy / UP mode";
        } else if (screen == 1) {
            title = "01 / CHARGE GADGET";
            prompt = stairsRoute ? "Optional: climb 3m" : "Walk 24 steps";
            detail = stairsRoute ? sensors.altitudeGain.format("%.1f") + " / 3.0m climbed"
                : sensors.steps + " / 24 steps";
            feedback = !sensors.hasMotion && !stairsRoute ? "Waiting for motion data"
                : (sensors.hasGps ? sensors.distance.format("%.0f") + "m excursion" : "No GPS? Indoor route.");
            hint = stairsRoute ? "UP back to walking" : (sensors.demo ? "START = 4 demo steps"
                : (sensors.hasAltitude ? "UP optional stairs" : "Walk at your own pace"));
        } else if (screen == 2) {
            title = "02 / CRACK THE SAFE";
            prompt = safePin == 1 ? "Turn LEFT, then hold" : "Turn RIGHT, then hold";
            detail = "Dial " + sensors.wristAngle.format("%.0f") + " / " + safeTarget.format("%.0f");
            feedback = sensors.hasGyro ? "Pin " + (safePin + 1) + " / 3  R > L > R" : "Waiting for wrist data";
            hint = sensors.demo ? "START turn / then wait" : "Rotate wrist gently";
        } else if (screen == 3) {
            title = "03 / QUIET EXTRACTION";
            if (part == 0) {
                prompt = "Point antenna EAST";
                detail = sensors.hasHeading ? "Heading " + sensors.heading.format("%.0f") + " / 90" : "Waiting for compass";
                feedback = "Align, then hold 1 sec";
                hint = sensors.demo ? "START turn antenna" : "Turn slowly to EAST";
            } else if (part == 2) {
                prompt = "Rest in the shadows";
                detail = "Take a quiet 5 seconds";
                feedback = sensors.hasMotion ? "No rush. Breathe easy." : "Waiting for motion data";
                hint = sensors.demo ? "START demo rest" : "Stay comfortable";
            } else {
                prompt = "Stay still. Slip away.";
                detail = "Quiet " + (_quietTicks / 10).toNumber() + " / 4 seconds";
                feedback = sensors.hasMotion ? "Motion " + sensors.motion.format("%.2f") : "Waiting for motion data";
                hint = sensors.demo ? "START demo stillness" : "A calm wrist seals it";
            }
        } else if (screen == 4) {
            title = "HEIST COMPLETE";
            prompt = "+" + missionLoot + " LOOT";
            detail = ratingSaved ? "Feedback saved. Thanks." : "Did this break help?";
            feedback = storageOk ? (_missionDemo ? "Demo loot saved" : "Break and loot saved") : "Save failed; try again";
            hint = ratingSaved ? "START another heist" : "START yes / DOWN no";
        } else {
            title = sensors.demo ? "DEMO DOSSIER" : "YOUR DOSSIER";
            prompt = (sensors.demo ? demoLoot : loot) + " LOOT";
            detail = (sensors.demo ? demoBreaks : completedBreaks) + " breaks completed";
            feedback = "Helpful " + (sensors.demo ? demoHelpfulYes : helpfulYes) + " / "
                + ((sensors.demo ? demoHelpfulYes : helpfulYes) + (sensors.demo ? demoHelpfulNo : helpfulNo));
            hint = "BACK to briefing";
        }
        if (screen >= 1 && screen <= 3 && sensors.hasHeartRate && sensors.heartRate >= 110 && part != 2) {
            feedback = "HR " + sensors.heartRate + " / take it easy";
        }
    }

    private function readCount(record as Dictionary, key as String) as Number {
        var value = record.get(key);
        if (value instanceof Number && value >= 0 && value <= 100000000) {
            return value as Number;
        }
        return 0;
    }

    private function load() as Void {
        try {
            var value = Application.Storage.getValue("chair-cartel-v1");
            if (!(value instanceof Dictionary)) { return; }
            var record = value as Dictionary;
            if (record.get("version") != 1) { return; }
            loot = readCount(record, "loot");
            completedBreaks = readCount(record, "breaks");
            helpfulYes = readCount(record, "yes");
            helpfulNo = readCount(record, "no");
            demoLoot = readCount(record, "demoLoot");
            demoBreaks = readCount(record, "demoBreaks");
            demoHelpfulYes = readCount(record, "demoYes");
            demoHelpfulNo = readCount(record, "demoNo");
        } catch (error) {
            storageOk = false;
            System.println("Chair Cartel: stats could not be loaded.");
        }
    }

    private function save() as Void {
        try {
            Application.Storage.setValue("chair-cartel-v1", {
                "version" => 1, "loot" => loot, "breaks" => completedBreaks,
                "yes" => helpfulYes, "no" => helpfulNo,
                "demoLoot" => demoLoot, "demoBreaks" => demoBreaks,
                "demoYes" => demoHelpfulYes, "demoNo" => demoHelpfulNo
            });
            storageOk = true;
        } catch (error) {
            storageOk = false;
            System.println("Chair Cartel: progress could not be saved.");
        }
    }
}
