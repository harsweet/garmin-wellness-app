import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class WellnessView extends WatchUi.View {
    private const BG = 0x080F18;
    private const PANEL = 0x112B33;
    private const MINT = 0x55FFAA;
    private const AMBER = 0xFFAA55;
    private const PAPER = 0xFFFFDD;
    private const MUTED = 0xAAAAAA;
    private const SHADOW = 0x005555;

    public var mission as HeistMission;
    private var _timer as Timer.Timer;
    private var _frame as Number = 0;
    private var _firstDraw as Boolean = true;

    function initialize(game as HeistMission) {
        View.initialize();
        mission = game;
        _timer = new Timer.Timer();
    }

    function onShow() as Void {
        if (mission.screen >= 1 && mission.screen <= 3) {
            mission.sensors.start();
        }
        _timer.start(method(:onTick), 100, true);
    }

    function onHide() as Void {
        _timer.stop();
        mission.sensors.stop();
    }

    function onTick() as Void {
        _frame = (_frame + 1) % 1200;
        mission.tick();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(PAPER, BG);
        dc.clear();
        dc.setPenWidth(1);
        drawBadge(dc);
        if (mission.screen == 0) {
            drawBriefing(dc);
        } else if (mission.screen == 4) {
            drawDebrief(dc);
        } else if (mission.screen == 5) {
            drawStats(dc);
        } else {
            drawMission(dc);
        }
        if (_firstDraw) {
            System.println("Chair Cartel: UI rendered at " + dc.getWidth() + "x" + dc.getHeight() + ".");
            _firstDraw = false;
        }
    }

    private function drawBadge(dc as Graphics.Dc) as Void {
        var demo = mission.sensors.demo;
        dc.setColor(demo ? AMBER : MINT, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(95, 13, 70, 21, 9);
        text(dc, 130, 13, Graphics.FONT_XTINY, demo ? "DEMO" : "LIVE", BG, 65);
    }

    private function drawBriefing(dc as Graphics.Dc) as Void {
        text(dc, 130, 40, Graphics.FONT_SMALL, "CHAIR CARTEL", PAPER, 205);
        text(dc, 130, 69, Graphics.FONT_XTINY, "Steal back your next break.", MINT, 205);
        var bob = ((_frame / 5).toNumber() % 4) < 2 ? 0 : -2;
        drawChair(dc, 130, 124 + bob, false);
        if ((_frame % 100) < 50) {
            text(dc, 130, 164, Graphics.FONT_XTINY, "You call it working from home.", PAPER, 215);
            text(dc, 130, 182, Graphics.FONT_XTINY, "I call it house arrest.", AMBER, 205);
        } else {
            text(dc, 130, 164, Graphics.FONT_XTINY, "Walk. Crack. Align. Escape.", PAPER, 215);
            text(dc, 130, 182, Graphics.FONT_XTINY, "3 stages. One stolen break.", AMBER, 205);
        }
        button(dc, 130, 204, "START: launch heist", MINT);
        text(dc, 130, 232, Graphics.FONT_XTINY, "UP mode / DOWN stats", MUTED, 122);
    }

    private function drawMission(dc as Graphics.Dc) as Void {
        var stage = mission.screen;
        var name = stage == 1 ? "CHARGE GADGET" : (stage == 2 ? "CRACK THE SAFE" : "EXTRACTION");
        text(dc, 130, 40, Graphics.FONT_SMALL, name, PAPER, 205);
        for (var i = 0; i < 3; i += 1) {
            dc.setColor(i < stage - 1 ? MINT : (i == stage - 1 ? AMBER : PANEL), Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(91 + i * 28, 75, 22, 4, 2);
        }
        if (stage == 1) {
            drawCharge(dc);
        } else if (stage == 2) {
            drawSafe(dc);
        } else {
            drawExtraction(dc);
        }
        text(dc, 130, 184, Graphics.FONT_XTINY, mission.prompt, PAPER, 216);
        var detail = mission.detail;
        if (stage == 1) {
            var infoPage = (_frame / 25).toNumber() % 3;
            if (infoPage == 1) {
                detail = mission.sensors.hasSolar ? "SOLAR " + mission.sensors.solar.toString() + "% / bonus power" : "SOLAR offline / indoor gear";
            } else if (infoPage == 2) {
                detail = mission.sensors.hasAltitude ? "+" + mission.sensors.altitudeGain.format("%.1f") + "m / UP stairs route" : "STAIRS offline / walk route";
            }
        }
        text(dc, 130, 204, Graphics.FONT_XTINY, detail, MUTED, 180);
        text(dc, 130, 228, Graphics.FONT_XTINY, mission.hint, AMBER, 128);
    }

    private function drawCharge(dc as Graphics.Dc) as Void {
        ring(dc, 130, 130, 43, mission.charge / 100.0);
        dc.setColor(PANEL, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(112, 105, 36, 49, 6);
        dc.setColor(MINT, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(123, 101, 14, 5, 2);
        dc.setColor(SHADOW, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(116, 109, 28, 40, 3);
        var level = (34 * mission.charge / 100).toNumber();
        if (level > 0) {
            dc.setColor(MINT, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(119, 146 - level, 22, level, 2);
        }
        dc.setColor(PAPER, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(133, 115, 125, 128);
        dc.drawLine(125, 128, 135, 128);
        dc.drawLine(135, 128, 128, 141);
        dc.setPenWidth(1);
        text(dc, 65, 120, Graphics.FONT_XTINY, mission.sensors.steps.toString(), MINT, 35);
        text(dc, 195, 120, Graphics.FONT_XTINY, mission.charge.toString() + "%", MINT, 42);
        text(dc, 130, 162, Graphics.FONT_XTINY,
            mission.sensors.hasGps ? mission.sensors.distance.format("%.0f") + "m excursion" : "GPS offline / indoor route",
            mission.sensors.hasGps ? MINT : AMBER, 203);
        var offset = (_frame % 8) < 4 ? -2 : 2;
        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        dc.fillEllipse(82, 143 + offset, 4, 7);
        dc.fillEllipse(177, 143 - offset, 4, 7);
    }

    private function drawSafe(dc as Graphics.Dc) as Void {
        dc.setColor(PANEL, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(78, 88, 104, 85, 10);
        ring(dc, 130, 128, 34, mission.progress);
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 12; i += 1) {
            radial(dc, 130, 128, 27, 31, i * 30.0);
        }
        var angle = mission.sensors.wristAngle;
        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        radial(dc, 130, 128, 5, 25, angle);
        dc.setColor(MINT, Graphics.COLOR_TRANSPARENT);
        radial(dc, 130, 128, 33, 38, mission.safeTarget);
        dc.fillCircle(130, 128, 5);
        for (var j = 0; j < 3; j += 1) {
            dc.setColor(j < mission.safePin ? MINT : SHADOW, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(115 + j * 15, 162, 3);
        }
        var turn = mission.safePin == 1 ? "CCW" : "CW";
        text(dc, 130, 91, Graphics.FONT_XTINY, turn, PAPER, 60);
        text(dc, 130, 143, Graphics.FONT_XTINY, angle.format("%.0f") + " / " + mission.safeTarget.format("%.0f"), PAPER, 90);
    }

    private function drawExtraction(dc as Graphics.Dc) as Void {
        if (mission.part == 0) {
            ring(dc, 130, 130, 41, mission.progress);
            dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < 8; i += 1) {
                radial(dc, 130, 130, 35, 38, i * 45.0);
            }
            text(dc, 130, 86, Graphics.FONT_XTINY, "N", MUTED, 20);
            text(dc, 181, 118, Graphics.FONT_XTINY, "E", MINT, 20);
            var angle = mission.sensors.heading;
            dc.setColor(MINT, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(4);
            radial(dc, 130, 130, 0, 29, angle);
            dc.setPenWidth(1);
            dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(130, 130, 5);
            text(dc, 130, 154, Graphics.FONT_XTINY, angle.format("%.0f") + " deg", PAPER, 82);
        } else {
            var breath = ((_frame / 3).toNumber() % 12);
            if (breath > 6) { breath = 12 - breath; }
            dc.setColor(PANEL, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(130, 130, 31 + breath);
            ring(dc, 130, 130, 42, mission.progress);
            dc.setColor(mission.part == 2 ? AMBER : MINT, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(130, 130, 14 + breath);
            dc.setColor(BG, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawLine(124, 128, 124, 134);
            dc.drawLine(136, 128, 136, 134);
            dc.setPenWidth(1);
            var effort = mission.sensors.hasHeartRate ? "HR " + mission.sensors.heartRate.toString() : "HR --";
            text(dc, 130, 91, Graphics.FONT_XTINY, effort, PAPER, 76);
            text(dc, 130, 158, Graphics.FONT_XTINY,
                "MOTION " + mission.sensors.motion.format("%.2f"), PAPER, 132);
        }
    }

    private function drawDebrief(dc as Graphics.Dc) as Void {
        text(dc, 130, 40, Graphics.FONT_SMALL, "BREAK: STOLEN", MINT, 205);
        drawChair(dc, 130, 102, true);
        var amount = "+" + mission.missionLoot.toString();
        text(dc, 130, 134, Graphics.FONT_NUMBER_MILD, amount, AMBER, 145);
        text(dc, 130, 177, Graphics.FONT_XTINY, mission.feedback, MINT, 180);
        text(dc, 130, 197, Graphics.FONT_XTINY,
            mission.ratingSaved ? "Feedback saved. Nice escape." : "Was this break helpful?",
            PAPER, 192);
        text(dc, 130, 222, Graphics.FONT_XTINY,
            mission.ratingSaved ? "START: next heist" : "START yes / DOWN no",
            AMBER, 138);
    }

    private function drawStats(dc as Graphics.Dc) as Void {
        var demo = mission.sensors.demo;
        text(dc, 130, 41, Graphics.FONT_SMALL, "THE STASH", PAPER, 190);
        text(dc, 130, 75, Graphics.FONT_XTINY, demo ? "PRACTICE RUNS ONLY" : "YOUR STOLEN BREAKS", MINT, 195);
        var loot = demo ? mission.demoLoot : mission.loot;
        var breaks = demo ? mission.demoBreaks : mission.completedBreaks;
        var yes = demo ? mission.demoHelpfulYes : mission.helpfulYes;
        var no = demo ? mission.demoHelpfulNo : mission.helpfulNo;
        statRow(dc, 99, "LOOT", loot.toString(), AMBER);
        statRow(dc, 130, "BREAKS", breaks.toString(), MINT);
        statRow(dc, 161, "HELPFUL", yes.toString(), PAPER);
        statRow(dc, 192, "NOT YET", no.toString(), MUTED);
        text(dc, 130, 228, Graphics.FONT_XTINY, "BACK: briefing", AMBER, 128);
    }

    private function statRow(dc as Graphics.Dc, y as Number, label as String,
        value as String, color as Number) as Void {
        dc.setColor(PANEL, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(42, y - 2, 176, 27, 6);
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(54, y, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(204, y, Graphics.FONT_XTINY, value, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    private function drawChair(dc as Graphics.Dc, x as Number, y as Number,
        defeated as Boolean) as Void {
        dc.setColor(SHADOW, Graphics.COLOR_TRANSPARENT);
        dc.fillEllipse(x, y + 29, 41, 4);
        dc.setColor(defeated ? MUTED : AMBER, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - 25, y - 34, 50, 47, 9);
        dc.setColor(defeated ? PANEL : 0xAA5500, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - 20, y - 28, 40, 36, 6);
        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - 32, y + 1, 64, 13, 5);
        dc.setPenWidth(4);
        dc.drawLine(x - 33, y - 8, x - 33, y + 9);
        dc.drawLine(x + 33, y - 8, x + 33, y + 9);
        dc.drawLine(x, y + 13, x, y + 25);
        dc.drawLine(x - 25, y + 26, x + 25, y + 26);
        dc.setColor(PAPER, Graphics.COLOR_TRANSPARENT);
        if (defeated) {
            dc.drawLine(x - 14, y - 17, x - 7, y - 10);
            dc.drawLine(x - 14, y - 10, x - 7, y - 17);
            dc.drawLine(x + 7, y - 17, x + 14, y - 10);
            dc.drawLine(x + 7, y - 10, x + 14, y - 17);
        } else {
            dc.drawLine(x - 15, y - 19, x - 6, y - 15);
            dc.drawLine(x + 6, y - 15, x + 15, y - 19);
            dc.setColor(BG, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x - 17, y - 14, 15, 7, 2);
            dc.fillRoundedRectangle(x + 2, y - 14, 15, 7, 2);
            dc.drawLine(x - 2, y - 12, x + 2, y - 12);
            dc.setColor(PAPER, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x - 7, y - 2, x + 7, y - 2);
        }
        dc.setPenWidth(1);
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - 25, y + 27, 4);
        dc.fillCircle(x + 25, y + 27, 4);
    }

    private function ring(dc as Graphics.Dc, x as Number, y as Number,
        radius as Number, progress as Float) as Void {
        dc.setPenWidth(4);
        dc.setColor(SHADOW, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, radius);
        var p = progress < 0 ? 0.0 : (progress > 1 ? 1.0 : progress);
        if (p > 0.001) {
            dc.setColor(MINT, Graphics.COLOR_TRANSPARENT);
            if (p > 0.995) {
                dc.drawCircle(x, y, radius);
            } else {
                dc.drawArc(x, y, radius, Graphics.ARC_CLOCKWISE, 90, 90 - p * 360);
            }
        }
        dc.setPenWidth(1);
    }

    private function radial(dc as Graphics.Dc, x as Number, y as Number,
        inner as Number, outer as Number, angle as Float) as Void {
        var radians = (angle - 90) * Math.PI / 180;
        var c = Math.cos(radians);
        var s = Math.sin(radians);
        dc.drawLine(x + inner * c, y + inner * s, x + outer * c, y + outer * s);
    }

    private function button(dc as Graphics.Dc, x as Number, y as Number,
        label as String, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - 82, y, 164, 25, 8);
        text(dc, x, y + 1, Graphics.FONT_XTINY, label, BG, 156);
    }

    private function text(dc as Graphics.Dc, x as Number, y as Number,
        font as Graphics.FontType, label as String, color as Number,
        maxWidth as Number) as Void {
        var fitted = label;
        if (dc.getTextWidthInPixels(fitted, font) > maxWidth) {
            var count = label.length();
            while (count > 0 && dc.getTextWidthInPixels(fitted + "..", font) > maxWidth) {
                count -= 1;
                fitted = label.substring(0, count) as String;
            }
            fitted += "..";
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, fitted, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
