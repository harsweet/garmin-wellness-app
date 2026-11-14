import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;

// A small live-sensor boundary. The simulator's button-injected samples are
// deliberately separate from live readings and never invent GPS or sunshine.
class HeistSensors {
    var demo as Boolean = true;
    var steps as Number = 0;
    var motion as Float = 0.0;
    var wristAngle as Float = 0.0;
    var heading as Float = 0.0;
    var hasHeading as Boolean = false;
    var heartRate as Number = 0;
    var hasHeartRate as Boolean = false;
    var distance as Float = 0.0;
    var hasGps as Boolean = false;
    var altitudeGain as Float = 0.0;
    var hasAltitude as Boolean = false;
    var solar as Number = 0;
    var hasSolar as Boolean = false;
    var sensorStatus as String = "DEMO / indoor route";
    var hasMotion as Boolean = true;
    var hasGyro as Boolean = true;

    private var _running as Boolean = false;
    private var _highFrequency as Boolean = false;
    private var _gpsRequested as Boolean = false;
    private var _tick as Number = 0;
    private var _lastStep as Number = -1000;
    private var _stepArmed as Boolean = true;
    private var _lastAccel as Number = -10000;
    private var _lastGyro as Number = -10000;
    private var _lastGps as Number = -10000;
    private var _baseAltitude as Float? = null;
    private var _lastPosition as Position.Location? = null;

    function initialize() {
    }

    function resetMission() as Void {
        steps = 0;
        motion = 0.0;
        wristAngle = 0.0;
        heading = 0.0;
        heartRate = 0;
        distance = 0.0;
        altitudeGain = 0.0;
        solar = 0;
        hasGps = false;
        hasSolar = false;
        hasAltitude = false;
        hasHeading = demo;
        hasHeartRate = demo;
        hasMotion = demo;
        hasGyro = demo;
        _baseAltitude = null;
        _lastPosition = null;
        _lastStep = -1000;
        _stepArmed = true;
        _lastAccel = -10000;
        _lastGyro = -10000;
        _lastGps = -10000;
        _tick = 0;
        if (demo) {
            heartRate = 78;
            sensorStatus = "DEMO / indoor route";
        } else {
            sensorStatus = "Waiting for sensors";
        }
    }

    function resetWrist() as Void {
        wristAngle = 0.0;
    }

    function start() as Void {
        if (_running) { return; }
        _running = true;
        if (demo) {
            hasMotion = true;
            hasGyro = true;
            hasHeading = true;
            hasHeartRate = true;
            if (heartRate == 0) { heartRate = 78; }
            sensorStatus = "DEMO / indoor route";
            return;
        }
        hasMotion = false;
        hasGyro = false;
        hasHeading = false;
        hasHeartRate = false;
        sensorStatus = "Waiting for sensors";
        try {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        } catch (error) {
            System.println("Chair Heist: heart-rate sensor unavailable.");
        }
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :accelerometer => { :enabled => true, :sampleRate => 25 },
                :gyroscope => { :enabled => true, :sampleRate => 25 },
                :magnetometer => { :enabled => true, :sampleRate => 10 }
            });
            _highFrequency = true;
        } catch (error) {
            // Keep walking available if a device rejects gyro/magnetometer.
            try {
                Sensor.registerSensorDataListener(method(:onSensorData), {
                    :period => 1,
                    :accelerometer => { :enabled => true, :sampleRate => 25 }
                });
                _highFrequency = true;
            } catch (fallbackError) {
                sensorStatus = "Motion sensor unavailable";
            }
        }
        try {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            _gpsRequested = true;
        } catch (error) {
            hasGps = false;
        }
        readInfo();
    }

    function stop() as Void {
        _running = false;
        if (_highFrequency) {
            try { Sensor.unregisterSensorDataListener(); } catch (error) { }
            _highFrequency = false;
        }
        if (_gpsRequested) {
            try { Position.enableLocationEvents(Position.LOCATION_DISABLE, null); } catch (error) { }
            _gpsRequested = false;
        }
        if (!demo) {
            try { Sensor.setEnabledSensors([]); } catch (error) { }
        }
        // No coordinate, route, activity file, or sensor sample is persisted.
        _lastPosition = null;
    }

    // Called by the view at 10Hz. Slow sensors are read once per second.
    function poll() as Void {
        if (!_running) { return; }
        _tick += 1;
        if (demo) {
            motion *= 0.82;
            hasGps = false;
            hasSolar = false;
            return;
        }
        var now = System.getTimer();
        hasMotion = (now - _lastAccel) < 2500;
        hasGyro = (now - _lastGyro) < 2500;
        if ((now - _lastGps) > 10000) { hasGps = false; }
        if ((_tick % 10) == 0) { readInfo(); }
    }

    function injectDemo(action as Symbol) as Void {
        if (!demo) { return; }
        hasMotion = true;
        hasGyro = true;
        hasHeading = true;
        hasHeartRate = true;
        if (action == :walk) {
            steps += 4;
            motion = 0.35;
            heartRate = 92;
        } else if (action == :clockwise) {
            wristAngle += 15.0;
        } else if (action == :counterclockwise) {
            wristAngle -= 15.0;
        } else if (action == :orient) {
            var delta = 90.0 - heading;
            while (delta > 180.0) { delta -= 360.0; }
            while (delta < -180.0) { delta += 360.0; }
            if (delta > 15.0) { delta = 15.0; }
            if (delta < -15.0) { delta = -15.0; }
            heading += delta;
            if (heading < 0.0) { heading += 360.0; }
            if (heading >= 360.0) { heading -= 360.0; }
        } else if (action == :quiet) {
            motion = 0.01;
            heartRate = 72;
        }
        hasGps = false;
        hasSolar = false;
        sensorStatus = "DEMO / indoor route";
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        if (!_running || demo) { return; }
        var now = System.getTimer();
        var accel = data.accelerometerData;
        if (accel != null && accel.x.size() > 0) {
            var total = 0.0;
            var count = accel.x.size();
            for (var i = 0; i < count; i += 1) {
                var ax = accel.x[i].toFloat();
                var ay = accel.y[i].toFloat();
                var az = accel.z[i].toFloat();
                var dynamic = (Math.sqrt(ax * ax + ay * ay + az * az) / 1000.0 - 1.0).abs();
                total += dynamic;
                // Treat samples as 40ms apart; gate step-like peaks to 300ms.
                var sampleTime = now - (count - 1 - i) * 40;
                if (dynamic < 0.08) { _stepArmed = true; }
                if (_stepArmed && dynamic > 0.18 && sampleTime - _lastStep >= 300) {
                    steps += 1;
                    _lastStep = sampleTime;
                    _stepArmed = false;
                }
            }
            motion = (total / count).toFloat();
            _lastAccel = now;
            hasMotion = true;
        }
        var gyro = data.gyroscopeData;
        if (gyro != null && gyro.z.size() > 0) {
            for (var j = 0; j < gyro.z.size(); j += 1) {
                var speed = gyro.z[j];
                if (speed.abs() > 3.0) {
                    // The z axis turns the watch face like a safe dial.
                    wristAngle -= speed / 25.0;
                }
            }
            _lastGyro = now;
            hasGyro = true;
        }
        sensorStatus = hasGyro ? "Live motion + gyro" : "Live motion / no gyro";
    }

    private function readInfo() as Void {
        try {
            var info = Sensor.getInfo();
            var bearing = info.heading;
            hasHeading = bearing != null;
            if (bearing != null) {
                heading = (bearing * 180.0 / Math.PI).toFloat();
                if (heading < 0.0) { heading += 360.0; }
            }
            var pulse = info.heartRate;
            hasHeartRate = pulse != null && pulse > 0;
            if (pulse != null && pulse > 0) { heartRate = pulse; }
            var altitude = info.altitude;
            hasAltitude = altitude != null;
            if (altitude != null) {
                var baseline = _baseAltitude;
                if (baseline == null) {
                    _baseAltitude = altitude;
                } else {
                    var gain = altitude - baseline;
                    if (gain > altitudeGain) { altitudeGain = gain; }
                }
            }
        } catch (error) {
            hasHeading = false;
            hasHeartRate = false;
            hasAltitude = false;
        }
        try {
            var stats = System.getSystemStats();
            if (stats has :solarIntensity) {
                var intensity = stats.solarIntensity;
                hasSolar = intensity != null && intensity >= 0;
                if (intensity != null && intensity >= 0) {
                    solar = intensity > 100 ? 100 : intensity;
                }
            }
        } catch (error) {
            hasSolar = false;
        }
    }

    function onPosition(info as Position.Info) as Void {
        if (!_running || demo) { return; }
        var location = info.position;
        hasGps = location != null && info.accuracy >= Position.QUALITY_USABLE;
        if (!hasGps || location == null) {
            _lastPosition = null;
            return;
        }
        var previous = _lastPosition;
        if (previous != null) {
            // Local tangent-plane distance is sufficient for a short excursion.
            var before = previous.toRadians();
            var after = location.toRadians();
            var north = (after[0] - before[0]) * 6371000.0;
            var east = (after[1] - before[1])
                * Math.cos((after[0] + before[0]) / 2.0) * 6371000.0;
            var segment = Math.sqrt(north * north + east * east);
            // Ignore tiny GPS jitter and implausible jumps during a short walk.
            if (segment >= 2.0 && segment < 30.0) {
                distance += segment.toFloat();
            }
            if (segment >= 2.0) {
                _lastPosition = location;
            }
        } else {
            _lastPosition = location;
        }
        _lastGps = System.getTimer();
    }
}
