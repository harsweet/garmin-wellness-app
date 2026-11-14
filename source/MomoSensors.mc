import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.UserProfile;

// Latest on-device samples only. Heart rate, SpO2, and respiration are reported,
// not used by the watch to decide a face. Missing sensors stay null.
module MomoSensors {
    function whole(value as Object or Null, min as Number, max as Number) as Number or Null {
        if (value instanceof Float) { value = (value as Float).toNumber(); }
        if (!(value instanceof Number)) { return null; }
        var number = value as Number;
        return number >= min && number <= max ? number : null;
    }

    function newest(iterator as SensorHistory.SensorHistoryIterator or Null) as Object or Null {
        if (iterator == null) { return null; }
        for (var i = 0; i < 6; i += 1) {
            var sample = iterator.next();
            if (sample == null) { return null; }
            if (sample.data != null) { return sample.data; }
        }
        return null;
    }

    function history(symbol as Symbol) as Object or Null {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has symbol)) { return null; }
        try {
            var method = new Lang.Method(SensorHistory, symbol);
            return newest(method.invoke({:period => 86400, :order => SensorHistory.ORDER_NEWEST_FIRST}) as SensorHistory.SensorHistoryIterator);
        } catch (ex) { return null; }
    }

    function snapshot() as Dictionary {
        var reading = {
            "source" => "unavailable",
            "steps" => null, "stepGoal" => null, "calories" => null, "distanceMeters" => null,
            "floorsClimbed" => null, "floorsDescended" => null,
            "activeMinutes" => null, "moderateMinutes" => null, "vigorousMinutes" => null,
            "heartRate" => null, "restingHeartRate" => null, "bodyBattery" => null, "stress" => null,
            "spo2" => null, "respiration" => null, "elevationMeters" => null, "pressureHpa" => null,
            "temperatureC" => null, "timeToRecoveryHours" => null, "moveBarLevel" => null
        };
        var saw = false;
        try {
            var info = ActivityMonitor.getInfo();
            if (info != null) {
                saw = true;
                try { reading["steps"] = whole(info.steps, 0, 200000); } catch (ex) {}
                try { reading["stepGoal"] = whole(info.stepGoal, 1, 200000); } catch (ex) {}
                try { reading["calories"] = whole(info.calories, 0, 20000); } catch (ex) {}
                try {
                    var centimeters = whole(info.distance, 0, 20000000);
                    if (centimeters != null) { reading["distanceMeters"] = centimeters / 100.0; }
                } catch (ex) {}
                try { reading["floorsClimbed"] = whole(info.floorsClimbed, 0, 10000); } catch (ex) {}
                try { reading["floorsDescended"] = whole(info.floorsDescended, 0, 10000); } catch (ex) {}
                try { reading["respiration"] = whole(info.respirationRate, 4, 60); } catch (ex) {}
                try { reading["timeToRecoveryHours"] = whole(info.timeToRecovery, 0, 240); } catch (ex) {}
                try { reading["moveBarLevel"] = whole(info.moveBarLevel, 0, 5); } catch (ex) {}
                try { reading["stress"] = whole(info.stressScore, 0, 100); } catch (ex) {}
                try {
                    var active = info.activeMinutesDay;
                    if (active != null) {
                        reading["activeMinutes"] = whole(active.total, 0, 1440);
                        reading["moderateMinutes"] = whole(active.moderate, 0, 1440);
                        reading["vigorousMinutes"] = whole(active.vigorous, 0, 1440);
                    }
                } catch (ex) {}
            }
        } catch (ex) {}
        var heart = whole(history(:getHeartRateHistory), 30, 220);
        var battery = whole(history(:getBodyBatteryHistory), 0, 100);
        var stress = whole(history(:getStressHistory), 0, 100);
        var oxygen = whole(history(:getOxygenSaturationHistory), 50, 100);
        var elevation = history(:getElevationHistory);
        var pressure = history(:getPressureHistory);
        var temperature = history(:getTemperatureHistory);
        if (heart != null) { reading["heartRate"] = heart; saw = true; }
        if (battery != null) { reading["bodyBattery"] = battery; saw = true; }
        if (stress != null) { reading["stress"] = stress; saw = true; }
        if (oxygen != null) { reading["spo2"] = oxygen; saw = true; }
        if (elevation instanceof Float) { elevation = (elevation as Float).toNumber(); }
        var elevationMeters = whole(elevation, -500, 9000);
        if (elevationMeters != null) { reading["elevationMeters"] = elevationMeters; saw = true; }
        if (pressure instanceof Float) { pressure = (pressure as Float).toNumber(); }
        if (pressure instanceof Number) {
            var hpa = whole((pressure as Number) / 100, 300, 1100);
            if (hpa != null) { reading["pressureHpa"] = hpa; saw = true; }
        }
        if (temperature instanceof Float) { temperature = (temperature as Float).toNumber(); }
        var celsius = whole(temperature, -40, 60);
        if (celsius != null) { reading["temperatureC"] = celsius; saw = true; }
        try {
            var live = Activity.getActivityInfo();
            if (live != null) {
                if (reading["heartRate"] == null) {
                    var liveHeart = whole(live.currentHeartRate, 30, 220);
                    if (liveHeart != null) { reading["heartRate"] = liveHeart; saw = true; }
                }
                if (reading["spo2"] == null) {
                    var liveOxygen = whole(live.currentOxygenSaturation, 50, 100);
                    if (liveOxygen != null) { reading["spo2"] = liveOxygen; saw = true; }
                }
                if (reading["elevationMeters"] == null) {
                    var liveElevation = live.altitude;
                    if (liveElevation instanceof Float) { liveElevation = (liveElevation as Float).toNumber(); }
                    var liveMeters = whole(liveElevation, -500, 9000);
                    if (liveMeters != null) { reading["elevationMeters"] = liveMeters; saw = true; }
                }
                if (reading["pressureHpa"] == null) {
                    var livePressure = live.ambientPressure;
                    if (livePressure instanceof Float) { livePressure = (livePressure as Float).toNumber(); }
                    if (livePressure instanceof Number) {
                        var liveHpa = whole((livePressure as Number) / 100, 300, 1100);
                        if (liveHpa != null) { reading["pressureHpa"] = liveHpa; saw = true; }
                    }
                }
            }
        } catch (ex) {}
        if (Toybox has :UserProfile) {
            try {
                var resting = whole(UserProfile.getProfile().restingHeartRate, 30, 120);
                if (resting != null) { reading["restingHeartRate"] = resting; saw = true; }
            } catch (ex) {}
        }
        if (saw) { reading["source"] = "watch"; }
        return reading;
    }
}
