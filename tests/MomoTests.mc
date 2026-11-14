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
    model.applyMood(0);
    Test.assertEqual(model.getPhase(), 0);
    model.applyMood(0);
    Test.assertEqual(model.getRemark(), model.getRemark());
    var first = model.getRemark();
    delegate.onNextPage();
    Test.assert(model.getRemark().equals(first) == false);
    for (var i = 0; i < 3; i += 1) { delegate.onPreviousPage(); }
    Test.assertEqual(model.getRemark(), first);
    Test.assertEqual(model.getPhase(), 0);
    model.applyMood(2);
    Test.assertEqual(model.getPhase(), 2);
    view.toggleHelp();
    Test.assert(view.isShowingHelp());
    delegate.onBack();
    Test.assert(!view.isShowingHelp());
    logger.debug("Physical-button behaviors, backend mood, quips, and help passed.");
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
