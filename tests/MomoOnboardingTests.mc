import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;

(:test)
function momoOnboardingQrBoundsAndCompletion(logger as Test.Logger) as Boolean {
    var qr = [] as Array<String>;
    for (var row = 0; row < 21; row += 1) { qr.add("111111100000001111111"); }
    var view = new MomoOnboardingView();
    view.handleOnboarding(200, {"profileConfigured" => false, "mode" => "demo", "qr" => qr});
    Test.assertEqual(view.getState(), :qr);
    var bounds = view.qrGeometry();
    Test.assert(bounds["moduleSize"] >= 2);
    Test.assert(bounds["size"] <= 176);
    Test.assert(bounds["x"] >= 40);
    Test.assert(bounds["y"] >= 49);
    Test.assert(bounds["y"] + bounds["size"] <= 225);
    var reference = Graphics.createBufferedBitmap({:width => 260, :height => 260});
    var bitmap = reference.get() as Graphics.BufferedBitmap;
    var dc = bitmap.getDc();
    view.onUpdate(dc);
    Test.assert(!view.setQr(["1", "01"]));
    view.handleStatus(200, {"profileConfigured" => true});
    Test.assertEqual(view.getState(), :ready);
    view.onUpdate(dc);
    view.handleOnboarding(-2, null);
    Test.assertEqual(view.getState(), :error);
    view.onUpdate(dc);
    logger.debug("QR integer pixels, quiet-zone bounds, profile completion, invalid data, and offline screens passed.");
    return true;
}
