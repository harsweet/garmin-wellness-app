import Toybox.ActivityMonitor;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;

module MomoSensors {

    function readActivityInfo() as Dictionary {
        var steps = null as Number or Null;
        var moveBarLevel = null as Number or Null;
        var activeMinutes = null as Number or Null;
        if (ActivityMonitor has :getInfo) {
            try {
                var info = ActivityMonitor.getInfo();
                if (info != null) {
                    if (info has :steps && info.steps instanceof Number && (info.steps as Number) >= 0) {
                        steps = info.steps as Number;
                    }
                    if (info has :moveBarLevel && info.moveBarLevel instanceof Number && (info.moveBarLevel as Number) >= 0) {
                        moveBarLevel = info.moveBarLevel as Number;
                    }
                    if (info has :activeMinutesDay && info.activeMinutesDay != null && info.activeMinutesDay has :total) {
                        var total = info.activeMinutesDay.total;
                        if (total instanceof Number && (total as Number) >= 0) {
                            activeMinutes = total as Number;
                        }
                    }
                }
            } catch (error) {}
        }
        return {
            "steps" => steps,
            "moveBarLevel" => moveBarLevel,
            "activeMinutes" => activeMinutes
        };
    }

    function extractLatest(iter as SensorHistory.SensorHistoryIterator or Null, minValid as Number or Null) as Number or Null {
        if (iter == null) { return null; }
        for (var i = 0; i < 5; i += 1) {
            var sample = iter.next();
            if (sample == null) { break; }
            var raw = sample.data;
            var value = null as Number or Null;
            if (raw instanceof Number) {
                value = raw as Number;
            } else if (raw instanceof Float) {
                value = Math.round(raw as Float).toNumber();
            }
            if (value != null && (minValid == null || value >= minValid)) {
                return value;
            }
        }
        return null;
    }

    function readHeartRate() as Number or Null {
        if (SensorHistory has :getHeartRateHistory) {
            try {
                return extractLatest(SensorHistory.getHeartRateHistory({:period => 5, :order => SensorHistory.ORDER_NEWEST_FIRST}), 20);
            } catch (error) {}
        }
        return null;
    }

    function readStress() as Number or Null {
        if (SensorHistory has :getStressHistory) {
            try {
                return extractLatest(SensorHistory.getStressHistory({:period => 5, :order => SensorHistory.ORDER_NEWEST_FIRST}), 0);
            } catch (error) {}
        }
        return null;
    }

    function readBodyBattery() as Number or Null {
        if (SensorHistory has :getBodyBatteryHistory) {
            try {
                return extractLatest(SensorHistory.getBodyBatteryHistory({:period => 5, :order => SensorHistory.ORDER_NEWEST_FIRST}), 0);
            } catch (error) {}
        }
        return null;
    }

    function readElevation() as Number or Null {
        if (SensorHistory has :getElevationHistory) {
            try {
                return extractLatest(SensorHistory.getElevationHistory({:period => 5, :order => SensorHistory.ORDER_NEWEST_FIRST}), null);
            } catch (error) {}
        }
        return null;
    }

    function readTemperature() as Number or Null {
        if (SensorHistory has :getTemperatureHistory) {
            try {
                return extractLatest(SensorHistory.getTemperatureHistory({:period => 5, :order => SensorHistory.ORDER_NEWEST_FIRST}), null);
            } catch (error) {}
        }
        return null;
    }

    function readSolarIntensity() as Number or Null {
        try {
            var stats = System.getSystemStats();
            if (stats != null && stats has :solarIntensity) {
                var solar = stats.solarIntensity;
                if (solar instanceof Number && (solar as Number) >= 0) {
                    return solar as Number;
                }
            }
        } catch (error) {}
        return null;
    }

    function deriveMovement(steps as Number or Null, activeMinutes as Number or Null, moveBarLevel as Number or Null) as String {
        if ((steps != null && steps >= 7000) || (activeMinutes != null && activeMinutes >= 45)) {
            return "active";
        }
        if (steps != null && steps >= 2000) {
            return "some";
        }
        if (steps != null && steps >= 0 && moveBarLevel != null && moveBarLevel >= 3) {
            return "low";
        }
        return "unknown";
    }

    function deriveEnergy(checkInMood as String) as String {
        if (checkInMood.equals("fried")) { return "low"; }
        if (checkInMood.equals("okay")) { return "okay"; }
        if (checkInMood.equals("wired")) { return "high"; }
        return "unknown";
    }

    function snapshot(demo as Boolean, checkInMood as String) as Dictionary {
        var activity = readActivityInfo();
        var steps = activity["steps"] as Number or Null;
        var moveBarLevel = activity["moveBarLevel"] as Number or Null;
        var activeMinutes = activity["activeMinutes"] as Number or Null;
        var mood = checkInMood.length() > 0 ? checkInMood : "unknown";
        return {
            "steps" => steps,
            "movement" => deriveMovement(steps, activeMinutes, moveBarLevel),
            "energy" => deriveEnergy(mood),
            "checkInMood" => mood,
            "source" => demo ? "simulated" : "watch",
            "heartRate" => readHeartRate(),
            "stress" => readStress(),
            "bodyBattery" => readBodyBattery(),
            "moveBarLevel" => moveBarLevel,
            "activeMinutes" => activeMinutes,
            "elevationMeters" => readElevation(),
            "temperatureC" => readTemperature(),
            "solarIntensity" => readSolarIntensity()
        };
    }

    function vitalsSnapshot() as Dictionary {
        return {
            "hr" => readHeartRate(),
            "stress" => readStress(),
            "elevation" => readElevation()
        };
    }

    function vibrate(pattern as Symbol) as Void {
        if (Attention has :vibrate && Attention has :VibeProfile) {
            try {
                var vibeData = null as Array<Attention.VibeProfile> or Null;
                if (pattern == :inhale) {
                    vibeData = [new Attention.VibeProfile(35, 120)];
                } else if (pattern == :exhale) {
                    vibeData = [new Attention.VibeProfile(20, 180)];
                } else if (pattern == :step) {
                    vibeData = [new Attention.VibeProfile(45, 90)];
                } else if (pattern == :celebrate) {
                    vibeData = [
                        new Attention.VibeProfile(50, 100),
                        new Attention.VibeProfile(0, 80),
                        new Attention.VibeProfile(75, 180)
                    ];
                }
                if (vibeData != null) {
                    Attention.vibrate(vibeData);
                }
            } catch (error) {}
        }
    }
}
