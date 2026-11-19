import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
class MomoActivityTestData {
    static function activity() as Dictionary {
        return {"id" => "native-test-session", "activityId" => "walk", "title" => "2-minute walk", "durationMinutes" => 2, "label" => "Today 2:30 PM", "tracking" => "steps", "stepTarget" => 60};
    }
    static function idea(source as String) as Dictionary {
        return {"mode" => "demo", "connected" => true, "aiSource" => source, "profileConfigured" => false,
            "suggestion" => {"id" => "idea-test", "slotId" => "slot-test", "activityId" => "walk", "title" => "2-minute walk", "durationMinutes" => 2, "label" => "Today 2:30 PM", "quip" => "Your chair and I agree. A tiny adventure?", "reason" => "A short walk fits your available time and preferences."}};
    }
}

(:test)
class MomoFakeActivityClient extends MomoCalendarClient {
    var writes as Number = 0;
    var completes as Number = 0;
    var source as String = "";
    var moodQueries as Number = 0;
    var lastMood as String = "";
    var insightsCalls as Number = 0;
    var lastVitals as Dictionary or Null = null;
    function initialize() { MomoCalendarClient.initialize(); }
    function hasServer() as Boolean { return true; }
    function hasToken() as Boolean { return true; }
    function suggestions(callback as Method) as Void {
        callback.invoke(200, MomoActivityTestData.idea("fallback"));
    }
    function suggestionsWithMood(mood as String, callback as Method) as Void {
        moodQueries += 1;
        lastMood = mood;
        var idea = MomoActivityTestData.idea("grok");
        var s = idea["suggestion"] as Dictionary;
        s["coachLine"] = "Easy pace for a " + mood + " afternoon.";
        callback.invoke(200, idea);
    }
    function insights(callback as Method) as Void {
        insightsCalls += 1;
        callback.invoke(200, {
            "mode" => "demo",
            "totalCompleted" => 5,
            "streakDays" => 3,
            "topActivity" => {"activityId" => "walk", "title" => "8-minute walk", "helpfulRate" => 80},
            "activities" => [
                {"activityId" => "walk", "title" => "Walk", "completed" => 4, "helped" => 3, "rated" => 4, "helpfulRate" => 75},
                {"activityId" => "breathe", "title" => "Breathe", "completed" => 1, "helped" => 1, "rated" => 1, "helpfulRate" => 100}
            ]
        });
    }
    function decide(id as String, decision as String, callback as Method) as Void {
        if (decision.equals("accept")) {
            writes += 1;
            callback.invoke(200, {"mode" => "demo", "status" => "created", "activity" => MomoActivityTestData.activity()});
        } else if (decision.equals("snooze")) { callback.invoke(200, {"mode" => "demo", "status" => "snoozed"}); }
        else { callback.invoke(200, MomoActivityTestData.idea("fallback")); }
    }
    function startActivity(id as String, callback as Method) as Void { callback.invoke(200, {"activity" => MomoActivityTestData.activity()}); }
    function completeActivity(id as String, proof as String, steps as Number, elapsed as Number, callback as Method) as Void {
        completes += 1; source = proof;
        callback.invoke(200, {"mode" => "demo", "status" => "completed", "activity" => MomoActivityTestData.activity()});
    }
    function completeActivityWithVitals(id as String, proof as String, steps as Number, elapsed as Number, vitals as Dictionary or Null, callback as Method) as Void {
        lastVitals = vitals;
        completeActivity(id, proof, steps, elapsed, callback);
    }
    function feedback(id as String, helpful as String, callback as Method) as Void { callback.invoke(200, {"status" => "recorded", "message" => "Noted. More of what works for you."}); }
}

(:test)
function momoSuggestionsRequireConfirmation(logger as Test.Logger) as Boolean {
    var saved = Application.Storage.getValue("momoActivitySession");
    var passed = true;
    try {
        var service = new MomoFakeActivityClient();
        var view = new MomoCalendarView(); view.setService(service);
        view.handleSuggestions(200, MomoActivityTestData.idea("grok"));
        Test.assertEqual(view.getState(), :ready);
        Test.assertEqual(view.getAiSource(), "grok");
        Test.assertEqual(service.writes, 0);
        var confirmation = new MomoSuggestionConfirmationDelegate(view);
        confirmation.onResponse(WatchUi.CONFIRM_NO);
        Test.assertEqual(service.writes, 0);
        confirmation.onResponse(WatchUi.CONFIRM_YES);
        Test.assertEqual(service.writes, 1);
        Test.assertEqual(view.getState(), :saved);
        view.handleSuggestions(200, MomoActivityTestData.idea("fallback"));
        Test.assertEqual(view.getAiSource(), "fallback");
        view.decide("alternative");
        Test.assertEqual(service.writes, 1);
        view.decide("snooze");
        Test.assertEqual(view.getState(), :snoozed);
        Test.assertEqual(service.writes, 1);
    } catch (error) { logger.error(error.toString()); passed = false; }
    if (saved == null) { Application.Storage.deleteValue("momoActivitySession"); }
    else { Application.Storage.setValue("momoActivitySession", saved); }
    return passed;
}

(:test)
function momoForegroundTrackingDoesNotCreditMissingData(logger as Test.Logger) as Boolean {
    var tracker = new MomoActivityTracker(MomoActivityTestData.activity(), null);
    tracker.resume(0, 100);
    tracker.update(1000, null);
    tracker.update(2000, 500);
    Test.assertEqual(tracker.steps(), 0);
    tracker.update(3000, 510);
    tracker.update(4000, 5); // Daily counter reset.
    tracker.update(5000, 9);
    Test.assertEqual(tracker.steps(), 14);
    tracker.pause();
    tracker.resume(200000, 900);
    tracker.update(201000, 910);
    Test.assertEqual(tracker.steps(), 24);
    Test.assertEqual(tracker.elapsedSeconds(), 6);
    tracker.update(400000, 5000); // Suspended event loop cannot prove participation.
    Test.assertEqual(tracker.steps(), 24);
    Test.assertEqual(tracker.elapsedSeconds(), 6);
    Test.assert(!tracker.goalMet());
    var resumed = new MomoActivityTracker(MomoActivityTestData.activity(), tracker.snapshot());
    Test.assertEqual(resumed.steps(), 24);
    Test.assertEqual(resumed.elapsedSeconds(), 6);
    logger.debug("Missing readings, counter resets, suspended time, resume, and persisted progress are handled.");
    return true;
}

(:test)
function momoCompletionSeparatesReportingAndDemoProof(logger as Test.Logger) as Boolean {
    var saved = Application.Storage.getValue("momoActivitySession");
    var savedBreaks = Application.Storage.getValue("momoBreaksToday");
    var savedDate = Application.Storage.getValue("momoBreaksDate");
    Application.Storage.deleteValue("momoActivitySession");
    var passed = true;
    try {
        var service = new MomoFakeActivityClient();
        var view = new MomoActivityView(MomoActivityTestData.activity(), "demo"); view.setService(service);
        Test.assertEqual(view.getState(), :scheduled);
        Test.assertEqual(service.completes, 0);
        view.select();
        Test.assertEqual(view.getState(), :running);
        Test.assert(!view.getTracker().goalMet());
        view.finishActivity(false);
        Test.assertEqual(service.source, "self_report");
        Test.assertEqual(view.getState(), :feedback);
        view.sendFeedback("yes");
        Test.assertEqual(view.getState(), :done);
        Test.assert(Application.Storage.getValue("momoActivitySession") == null);
        var demo = new MomoActivityView(MomoActivityTestData.activity(), "demo"); demo.setService(service);
        demo.select(); demo.finishActivity(true);
        Test.assertEqual(service.source, "simulated_steps");
        Test.assert(demo.getTracker().goalMet());
        Test.assertEqual(demo.getState(), :feedback);
    } catch (error) { logger.error(error.toString()); passed = false; }
    if (saved == null) { Application.Storage.deleteValue("momoActivitySession"); }
    else { Application.Storage.setValue("momoActivitySession", saved); }
    if (savedBreaks == null) { Application.Storage.deleteValue("momoBreaksToday"); }
    else { Application.Storage.setValue("momoBreaksToday", savedBreaks); }
    if (savedDate == null) { Application.Storage.deleteValue("momoBreaksDate"); }
    else { Application.Storage.setValue("momoBreaksDate", savedDate); }
    return passed;
}

(:test)
function momoSuggestionAndSessionScreensRender(logger as Test.Logger) as Boolean {
    var saved = Application.Storage.getValue("momoActivitySession");
    var savedBreaks = Application.Storage.getValue("momoBreaksToday");
    var savedDate = Application.Storage.getValue("momoBreaksDate");
    Application.Storage.deleteValue("momoActivitySession");
    var passed = true;
    try {
        var reference = Graphics.createBufferedBitmap({:width => 260, :height => 260});
        var bitmap = reference.get() as Graphics.BufferedBitmap;
        var dc = bitmap.getDc();
        var view = new MomoCalendarView();
        view.handleSuggestions(200, MomoActivityTestData.idea("grok"));
        view.onUpdate(dc); view.moveSelection(1); view.onUpdate(dc); view.moveSelection(1); view.onUpdate(dc);
        view.handleSuggestions(200, MomoActivityTestData.idea("fallback")); view.onUpdate(dc);
        view.handleSnoozed(200, {"status" => "snoozed"}); view.onUpdate(dc);
        view.handleSuggestions(-2, null); view.onUpdate(dc);
        var activity = new MomoActivityView(MomoActivityTestData.activity(), "demo");
        var service = new MomoFakeActivityClient(); activity.setService(service);
        activity.onUpdate(dc); activity.select(); activity.onUpdate(dc);
        activity.finishActivity(true); activity.onUpdate(dc);
        activity.sendFeedback("somewhat"); activity.onUpdate(dc);
        logger.debug("Grok/scripted suggestions, reasons, setup, snooze, offline, scheduled, tracking, and feedback screens rendered.");
    } catch (error) { logger.error(error.toString()); passed = false; }
    if (saved == null) { Application.Storage.deleteValue("momoActivitySession"); }
    else { Application.Storage.setValue("momoActivitySession", saved); }
    if (savedBreaks == null) { Application.Storage.deleteValue("momoBreaksToday"); }
    else { Application.Storage.setValue("momoBreaksToday", savedBreaks); }
    if (savedDate == null) { Application.Storage.deleteValue("momoBreaksDate"); }
    else { Application.Storage.setValue("momoBreaksDate", savedDate); }
    return passed;
}

(:test)
function momoMoodCheckInAndCoachLineSuggestions(logger as Test.Logger) as Boolean {
    var saved = Application.Storage.getValue("momoActivitySession");
    Application.Storage.deleteValue("momoActivitySession");
    var passed = true;
    try {
        var service = new MomoFakeActivityClient();
        var view = new MomoCalendarView();
        view.setService(service);

        var choices = view.actionChoices();
        var hasMoodChoice = false;
        for (var i = 0; i < choices.size(); i += 1) {
            if (choices[i]["id"] == :mood) { hasMoodChoice = true; }
        }
        Test.assert(hasMoodChoice);

        view.setCheckInMood("fried");
        view.refresh();
        Test.assertEqual(service.moodQueries, 1);
        Test.assertEqual(service.lastMood, "fried");
        Test.assertEqual(view.getState(), :ready);

        var reference = Graphics.createBufferedBitmap({:width => 260, :height => 260});
        var bitmap = reference.get() as Graphics.BufferedBitmap;
        var dc = bitmap.getDc();
        view.setSensorClueForTest("LIVE · HR 72 · BB 68");
        view.onUpdate(dc);
        view.moveSelection(1);
        view.onUpdate(dc);
        logger.debug("Mood check-in query, sensor clue badge, and coachLine page rendering passed.");
    } catch (error) { logger.error(error.toString()); passed = false; }
    if (saved == null) { Application.Storage.deleteValue("momoActivitySession"); }
    else { Application.Storage.setValue("momoActivitySession", saved); }
    return passed;
}

(:test)
function momoInteractiveBreakModesAndVitalsRender(logger as Test.Logger) as Boolean {
    var saved = Application.Storage.getValue("momoActivitySession");
    var savedBreaks = Application.Storage.getValue("momoBreaksToday");
    var savedDate = Application.Storage.getValue("momoBreaksDate");
    Application.Storage.deleteValue("momoActivitySession");
    Application.Storage.deleteValue("momoBreaksToday");
    Application.Storage.deleteValue("momoBreaksDate");
    var passed = true;
    try {
        var reference = Graphics.createBufferedBitmap({:width => 260, :height => 260});
        var bitmap = reference.get() as Graphics.BufferedBitmap;
        var dc = bitmap.getDc();

        var kinds = ["breathe", "stretch", "eyes", "stairs", "walk", "sunlight", "rest"] as Array<String>;
        for (var i = 0; i < kinds.size(); i += 1) {
            var kind = kinds[i];
            var session = {
                "id" => "test-" + kind,
                "activityId" => kind,
                "title" => kind + " break",
                "durationMinutes" => 3,
                "label" => "Now",
                "tracking" => kind.equals("walk") ? "steps" : "timer",
                "stepTarget" => kind.equals("walk") ? 80 : 0,
                "coachLine" => "Stay gentle with yourself."
            };
            var service = new MomoFakeActivityClient();
            var view = new MomoActivityView(session, "demo");
            view.setService(service);
            view.select();
            Test.assertEqual(view.getState(), :running);
            view.setStartVitalsForTest(74, 42, 100);
            // Advance tracker through multiple seconds (covers breathe INHALE/HOLD/EXHALE & stretch/eyes steps).
            view.getTracker().resume(0, 1000);
            view.getTracker().update(1000, 1005);
            view.onUpdate(dc);
            view.getTracker().update(5000, 1010);
            view.onUpdate(dc);
            view.getTracker().update(9000, 1020);
            view.onUpdate(dc);
            view.finishActivity(true);
            Test.assertEqual(view.getState(), :feedback);
            Test.assert(service.lastVitals != null);
            Test.assertEqual((service.lastVitals as Dictionary)["startHr"], 74);
            view.onUpdate(dc);
            view.sendFeedback("yes");
            Test.assertEqual(view.getState(), :done);
            view.onUpdate(dc);
            Application.Storage.deleteValue("momoActivitySession");
        }
        Test.assertEqual(MomoModel.getBreaksToday(), kinds.size());
        logger.debug("All 7 interactive break modes, vitals capture, celebration sparkles, and break counter passed.");
    } catch (error) { logger.error(error.toString()); passed = false; }
    if (saved == null) { Application.Storage.deleteValue("momoActivitySession"); }
    else { Application.Storage.setValue("momoActivitySession", saved); }
    if (savedBreaks == null) { Application.Storage.deleteValue("momoBreaksToday"); }
    else { Application.Storage.setValue("momoBreaksToday", savedBreaks); }
    if (savedDate == null) { Application.Storage.deleteValue("momoBreaksDate"); }
    else { Application.Storage.setValue("momoBreaksDate", savedDate); }
    return passed;
}

(:test)
function momoReceiptsViewRendersSummaryAndPages(logger as Test.Logger) as Boolean {
    var reference = Graphics.createBufferedBitmap({:width => 260, :height => 260});
    var bitmap = reference.get() as Graphics.BufferedBitmap;
    var dc = bitmap.getDc();

    var service = new MomoFakeActivityClient();
    var view = new MomoReceiptsView();
    view.setService(service);
    view.onUpdate(dc); // Loading state
    view.onShow();
    Test.assertEqual(service.insightsCalls, 1);
    Test.assertEqual(view.getState(), :ready);
    Test.assertEqual(view.getActivitiesCount(), 2);
    Test.assertEqual(view.getPage(), 0);
    view.onUpdate(dc); // Summary card
    view.movePage(1);
    Test.assertEqual(view.getPage(), 1);
    view.onUpdate(dc); // Activity 1
    view.movePage(1);
    Test.assertEqual(view.getPage(), 2);
    view.onUpdate(dc); // Activity 2
    view.movePage(1);
    Test.assertEqual(view.getPage(), 0);

    view.handleInsights(200, {"totalCompleted" => 0, "streakDays" => 0, "activities" => []});
    Test.assertEqual(view.getState(), :empty);
    view.onUpdate(dc);

    view.handleInsights(-2, null);
    Test.assertEqual(view.getState(), :error);
    view.onUpdate(dc);
    logger.debug("MomoReceiptsView summary, activity receipt bars, wraparound, empty, and error states passed.");
    return true;
}
