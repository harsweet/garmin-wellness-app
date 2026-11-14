import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;

// Baked mock calendar. The weekly schedule is compiled into the app as the
// MockCalendarData string resource, so the calendar screen always has data
// shaped exactly like the server contract, even with no demo server running.
// day_of_week uses Connect IQ's convention: 0 = Sunday ... 6 = Saturday.
class MomoMockCalendar {
    private var _schedule as Dictionary or Null = null;
    private const WALK_MINUTES = 8;
    private const BUFFER_SECONDS = 120;
    private const DAY_START_HOUR = 8;
    private const DAY_END_HOUR = 20;

    function initialize() {}

    function availability() as Dictionary {
        var events = getEvents();
        var nowMoment = Time.now();
        // FORMAT_SHORT yields numeric fields: day_of_week 1 = Sunday ... 7 =
        // Saturday and month 1-12. Shift day_of_week to the schedule's
        // 0 = Sunday ... 6 = Saturday convention.
        var now = Time.Gregorian.info(nowMoment, Time.FORMAT_SHORT);
        var nowSecs = now.hour * 3600 + now.min * 60 + now.sec;
        var busy = buildBusy(events, now, nowSecs);
        var busyNow = false;
        for (var i = 0; i < busy.size(); i += 1) {
            var range = busy[i];
            if (range[0] <= 0 && range[1] > 0) {
                busyNow = true;
            }
        }
        var slots = findSlots(nowMoment, nowSecs, busy);
        var message = slots.size() > 0
            ? "I found room for a little walk."
            : "No free daytime slot in the next 24 hours.";
        return {
            "connected" => true,
            "mode" => "mock",
            "busyNow" => busyNow,
            "slots" => slots,
            "message" => message
        };
    }

    // Mirrors the bridge's retry semantics: the same slot id can only be
    // created once; a repeat returns already_created instead of duplicating.
    function createActivity(slotId as String, label as String, callback as Method) as Void {
        var status = "created";
        var stored = Application.Storage.getValue("mockCreatedSlots");
        var created = stored instanceof Array ? (stored as Array) : ([] as Array);
        for (var i = 0; i < created.size(); i += 1) {
            if (created[i] instanceof String && (created[i] as String).equals(slotId)) {
                status = "already_created";
            }
        }
        if (status.equals("created")) {
            created.add(slotId);
            Application.Storage.setValue("mockCreatedSlots", created);
            var storedWalks = Application.Storage.getValue("mockSavedWalks");
            var walks = storedWalks instanceof Array ? (storedWalks as Array) : ([] as Array);
            walks.add(label);
            Application.Storage.setValue("mockSavedWalks", walks);
        }
        callback.invoke(200, {
            "status" => status,
            "label" => label,
            "eventUrl" => "",
            "mode" => "mock"
        });
    }

    // Labels of mock walks saved on this device, in save order. Persisted in
    // Application.Storage so they survive app restarts.
    function getSavedWalks() as Array {
        var stored = Application.Storage.getValue("mockSavedWalks");
        return stored instanceof Array ? (stored as Array) : ([] as Array);
    }

    private function getEvents() as Array {
        var schedule = loadSchedule();
        if (schedule != null && schedule["events"] instanceof Array) {
            return schedule["events"] as Array;
        }
        return [] as Array;
    }

    private function loadSchedule() as Dictionary or Null {
        if (_schedule == null) {
            // The Connect IQ runtime has no JSON parser, so the schedule from
            // mock-calendar.json at the project root is baked in as a literal.
            // Keep the two in sync when editing the schedule.
            _schedule = {
                "scheduleName" => "Regular week",
                "events" => [
                    { "label" => "Gym", "days" => [1, 2, 3, 4, 5], "start" => "07:00", "end" => "08:00" },
                    { "label" => "Work 9-5", "days" => [1, 2, 3, 4, 5], "start" => "09:00", "end" => "17:00" },
                    { "label" => "Doctor appointment", "days" => [6], "start" => "10:00", "end" => "15:00" },
                    { "label" => "Travel", "days" => [0], "start" => "13:00", "end" => "16:00" }
                ]
            };
        }
        return _schedule;
    }

    // Busy intervals as [startOffset, endOffset] in seconds relative to now,
    // covering today and tomorrow so the 24-hour suggestion window is covered.
    private function buildBusy(events as Array, now as Time.Gregorian.Info, nowSecs as Number) as Array {
        var busy = [] as Array;
        for (var d = 0; d < 2; d += 1) {
            // Gregorian.Info.day_of_week is a DayOfWeek enum (1 = Sunday ... 7 =
            // Saturday); shift to the schedule's 0 = Sunday ... 6 = Saturday.
            var dow = (now.day_of_week - 1 + d) % 7;
            for (var i = 0; i < events.size(); i += 1) {
                var event = events[i];
                if (!(event instanceof Dictionary)) {
                    continue;
                }
                var days = event["days"];
                if (!(days instanceof Array)) {
                    continue;
                }
                var matched = false;
                for (var j = 0; j < days.size(); j += 1) {
                    if (days[j] instanceof Number && (days[j] as Number) == dow) {
                        matched = true;
                    }
                }
                if (!matched) {
                    continue;
                }
                var startClock = parseClock(event["start"]);
                var endClock = parseClock(event["end"]);
                if (startClock == null || endClock == null) {
                    continue;
                }
                var startOff = d * 86400 + ((startClock as Number) - nowSecs);
                var endOff = d * 86400 + ((endClock as Number) - nowSecs);
                if (endOff > 0) {
                    busy.add([startOff, endOff]);
                }
            }
        }
        return busy;
    }

    // Same suggestion rules as the Google bridge: 8-minute walks between
    // 08:00 and 20:00 local, half-hour grid, 2-minute buffers around busy
    // periods, next 24 hours, three suggestions in chronological order.
    private function findSlots(nowMoment as Time.Moment, nowSecs as Number, busy as Array) as Array {
        var slots = [] as Array;
        var dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        for (var d = 0; d < 2 && slots.size() < 3; d += 1) {
            var dayInfo = Time.Gregorian.info(nowMoment.add(new Time.Duration(d * 86400)), Time.FORMAT_SHORT);
            var dateTag = dayInfo.year + "-" + pad2(dayInfo.month) + "-" + pad2(dayInfo.day);
            var dayName = dayNames[dayInfo.day_of_week - 1];
            for (var hour = DAY_START_HOUR; hour <= DAY_END_HOUR && slots.size() < 3; hour += 1) {
                var starts = [0, 30];
                for (var s = 0; s < starts.size() && slots.size() < 3; s += 1) {
                    var timeOfDay = hour * 3600 + starts[s] * 60;
                    if (timeOfDay + WALK_MINUTES * 60 > DAY_END_HOUR * 3600) {
                        continue;
                    }
                    var offset = d * 86400 + timeOfDay - nowSecs;
                    if (offset < 0 || offset > 86400) {
                        continue;
                    }
                    if (!isFree(offset, busy)) {
                        continue;
                    }
                    slots.add(makeSlot(dayInfo, dayName, dateTag, hour, starts[s]));
                }
            }
        }
        return slots;
    }

    private function isFree(offset as Number, busy as Array) as Boolean {
        var walkStart = offset - BUFFER_SECONDS;
        var walkEnd = offset + WALK_MINUTES * 60 + BUFFER_SECONDS;
        for (var i = 0; i < busy.size(); i += 1) {
            var range = busy[i];
            if (walkStart < range[1] && walkEnd > range[0]) {
                return false;
            }
        }
        return true;
    }

    private function makeSlot(dayInfo as Time.Gregorian.Info, dayName as String, dateTag as String, hour as Number, minute as Number) as Dictionary {
        var labelHour = hour;
        var ampm = "AM";
        if (labelHour == 0) {
            labelHour = 12;
        } else if (labelHour >= 12) {
            ampm = "PM";
            if (labelHour > 12) {
                labelHour -= 12;
            }
        }
        var endMinutes = hour * 60 + minute + WALK_MINUTES;
        var endHour = endMinutes / 60;
        var endMinute = endMinutes % 60;
        return {
            "id" => "mock-" + dateTag + "-" + pad2(hour) + pad2(minute),
            "label" => dayName + " " + labelHour + ":" + pad2(minute) + " " + ampm,
            "start" => dateTag + "T" + pad2(hour) + ":" + pad2(minute) + ":00",
            "end" => dateTag + "T" + pad2(endHour) + ":" + pad2(endMinute) + ":00",
            "durationMinutes" => WALK_MINUTES
        };
    }

    private function parseClock(value as Object or Null) as Number or Null {
        if (!(value instanceof String)) {
            return null;
        }
        var text = value as String;
        if (text.length() < 5) {
            return null;
        }
        var hour = text.substring(0, 2).toNumber();
        var minute = text.substring(3, 5).toNumber();
        if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
            return null;
        }
        return hour * 3600 + minute * 60;
    }

    private function pad2(value as Number) as String {
        return value < 10 ? "0" + value : "" + value;
    }
}
