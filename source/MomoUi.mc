import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

module MomoUi {
    const BG = 0x000000;
    const INK = 0xFFFFFF;
    const MINT = 0x55FFAA;
    const TEAL = 0x00AA55;
    const MUTED = 0xAAAAAA;
    const EDGE = 0x555555;
    const SURFACE = 0x005555;
    const DEEP = 0x000055;
    const LAVENDER = 0xAAAAFF;
    const GOLD = 0xFFFF55;
    const PEACH = 0xFFAA55;
    const CORAL = 0xFF5555;

    function clear(dc as Graphics.Dc) as Void {
        dc.setColor(INK, BG); dc.clear();
    }

    function safeWidth(top as Number, height as Number) as Number {
        var first = top < 130 ? 130 - top : top - 130;
        var bottom = top + height;
        var last = bottom < 130 ? 130 - bottom : bottom - 130;
        var distance = first > last ? first : last;
        if (distance >= 124) { return 40; }
        return (2 * Math.sqrt(124 * 124 - distance * distance) - 18).toNumber();
    }

    function fit(dc as Graphics.Dc, text as String, font as Graphics.FontType, width as Number) as String {
        if (dc.getTextWidthInPixels(text, font) <= width) { return text; }
        var result = text;
        while (result.length() > 0 && dc.getTextWidthInPixels(result + "...", font) > width) {
            result = result.substring(0, result.length() - 1);
        }
        return result + "...";
    }

    function text(dc as Graphics.Dc, value as String, top as Number, color as Number) as Void {
        dc.setColor(color, BG);
        var width = safeWidth(top, dc.getFontHeight(Graphics.FONT_XTINY));
        if (width > 206) { width = 206; }
        dc.drawText(130, top, Graphics.FONT_XTINY, fit(dc, value, Graphics.FONT_XTINY, width), Graphics.TEXT_JUSTIFY_CENTER);
    }

    function titleText(dc as Graphics.Dc, value as String, top as Number, color as Number) as Void {
        dc.setColor(color, BG);
        var width = safeWidth(top, dc.getFontHeight(Graphics.FONT_SMALL));
        if (width > 204) { width = 204; }
        dc.drawText(130, top, Graphics.FONT_SMALL, fit(dc, value, Graphics.FONT_SMALL, width), Graphics.TEXT_JUSTIFY_CENTER);
    }

    function heading(dc as Graphics.Dc, value as String) as Void {
        dc.setColor(INK, BG);
        dc.drawText(130, 22, Graphics.FONT_SMALL, fit(dc, value, Graphics.FONT_SMALL, 152), Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawDivider(dc as Graphics.Dc, y as Number, width as Number) as Void {
        var half = (width / 2).toNumber();
        dc.setColor(EDGE, BG);
        dc.drawLine(130 - half, y, 130 + half, y);
    }

    // Splits URLs and other unbroken strings as well as ordinary sentences.
    function lines(dc as Graphics.Dc, value as String, width as Number) as Array<String> {
        var result = [] as Array<String>;
        var line = "";
        var lastSpace = -1;
        for (var i = 0; i < value.length(); i += 1) {
            var character = value.substring(i, i + 1);
            var next = line + character;
            if (dc.getTextWidthInPixels(next, Graphics.FONT_XTINY) > width && line.length() > 0) {
                if (lastSpace > 0) {
                    result.add(line.substring(0, lastSpace));
                    line = line.substring(lastSpace + 1, line.length()) + character;
                } else { result.add(line); line = character; }
                lastSpace = -1;
                for (var j = 0; j < line.length(); j += 1) {
                    if (line.substring(j, j + 1).equals(" ")) { lastSpace = j; }
                }
            } else { line = next; }
            if (character.equals(" ")) { lastSpace = line.length() - 1; }
        }
        if (line.length() > 0) { result.add(line); }
        return result;
    }

    function paragraph(dc as Graphics.Dc, value as String, top as Number, maxLines as Number, color as Number) as Void {
        var wrapped = lines(dc, value, 194);
        for (var i = 0; i < wrapped.size() && i < maxLines; i += 1) {
            var line = wrapped[i];
            if (i == maxLines - 1 && wrapped.size() > maxLines) { line += "..."; }
            text(dc, line, top + i * 20, color);
        }
    }

    // Compact dark-teal capsule sized to sit strictly inside the round watch bezel.
    function pill(dc as Graphics.Dc, label as String, top as Number) as Void {
        var pillW = 116;
        var pillH = 22;
        var left = 130 - (pillW / 2).toNumber();
        dc.setColor(SURFACE, BG);
        dc.fillRoundedRectangle(left, top, pillW, pillH, 11);
        dc.setColor(INK, SURFACE);
        var fontH = dc.getFontHeight(Graphics.FONT_XTINY);
        var textY = top + ((pillH - fontH) / 2).toNumber();
        dc.drawText(130, textY, Graphics.FONT_XTINY, fit(dc, label, Graphics.FONT_XTINY, pillW - 14), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Subtle 2 o'clock rim indicator aligned with the fēnix 7 Pro physical START button.
    function drawStartTick(dc as Graphics.Dc, color as Number) as Void {
        dc.setPenWidth(4);
        dc.setColor(color, BG);
        dc.drawArc(130, 130, 125, Graphics.ARC_COUNTER_CLOCKWISE, 20, 40);
        dc.setPenWidth(1);
    }

    // Curved right-edge page indicator dots following the watch glass contour.
    function drawPageRail(dc as Graphics.Dc, count as Number, active as Number, color as Number) as Void {
        if (count <= 1) { return; }
        var shown = count > 7 ? 7 : count;
        var step = 7.0f;
        var startDeg = ((shown - 1) * step) / 2.0f;
        for (var i = 0; i < shown; i += 1) {
            var deg = startDeg - i * step;
            var rad = deg * Math.PI / 180.0;
            var cx = 130 + Math.round(119.0 * Math.cos(rad)).toNumber();
            var cy = 130 - Math.round(119.0 * Math.sin(rad)).toNumber();
            var isCurrent = (i == active);
            dc.setColor(isCurrent ? color : EDGE, BG);
            dc.fillCircle(cx, cy, isCurrent ? 3 : 2);
        }
    }

    function drawProgressBar(dc as Graphics.Dc, x as Number, y as Number, width as Number, height as Number, progress as Float, color as Number) as Void {
        var clamped = progress < 0.0f ? 0.0f : (progress > 1.0f ? 1.0f : progress);
        var radius = (height / 2).toNumber();
        dc.setColor(EDGE, BG);
        dc.fillRoundedRectangle(x, y, width, height, radius);
        var fill = (width * clamped).toNumber();
        if (fill > 0) {
            if (fill < height) { fill = height; }
            dc.setColor(color, BG);
            dc.fillRoundedRectangle(x, y, fill, height, radius);
        }
    }

    // Native Garmin 270-degree horseshoe bezel gauge (open at 6 o'clock for clean bottom prompts).
    function drawBezelProgress(dc as Graphics.Dc, progress as Float, color as Number) as Void {
        var clamped = progress < 0.0f ? 0.0f : (progress > 1.0f ? 1.0f : progress);
        var r = 123;
        dc.setPenWidth(4);
        dc.setColor(EDGE, BG);
        dc.drawArc(130, 130, r, Graphics.ARC_CLOCKWISE, 225, 315);

        // Rounded track end-caps at 225 deg and 315 deg
        dc.fillCircle(43, 217, 2);
        dc.fillCircle(217, 217, 2);

        var span = (270.0f * clamped).toNumber();
        if (span > 0) {
            var endAngle = (225 - span + 360) % 360;
            dc.setPenWidth(6);
            dc.setColor(color, BG);
            dc.drawArc(130, 130, r, Graphics.ARC_CLOCKWISE, 225, endAngle);
            dc.setPenWidth(1);
            // Smooth circular end-caps on active arc
            dc.fillCircle(43, 217, 3);
            var endRad = endAngle * Math.PI / 180.0;
            var ex = 130 + Math.round(r * Math.cos(endRad)).toNumber();
            var ey = 130 - Math.round(r * Math.sin(endRad)).toNumber();
            dc.fillCircle(ex, ey, 3);
        }
        dc.setPenWidth(1);
    }

    function activityAccent(kind as String) as Number {
        if (kind.equals("stretch") || kind.equals("stairs")) { return PEACH; }
        if (kind.equals("eyes") || kind.equals("rest")) { return LAVENDER; }
        if (kind.equals("sunlight")) { return GOLD; }
        return MINT;
    }

    // Crisp vector icon for each break activity and status indicator.
    function drawIcon(dc as Graphics.Dc, kind as String, cx as Number, cy as Number, color as Number) as Void {
        dc.setColor(color, BG);
        if (kind.equals("breathe")) {
            dc.setPenWidth(2);
            dc.drawCircle(cx, cy, 9);
            dc.drawCircle(cx, cy, 4);
            dc.setPenWidth(1);
        } else if (kind.equals("walk")) {
            // Stylized double stride footprints
            dc.fillRoundedRectangle(cx - 7, cy - 6, 5, 9, 2);
            dc.fillCircle(cx - 5, cy + 6, 2);
            dc.fillRoundedRectangle(cx + 2, cy - 2, 5, 9, 2);
            dc.fillCircle(cx + 4, cy - 6, 2);
        } else if (kind.equals("stretch")) {
            // Reaching person silhouette
            dc.fillCircle(cx, cy - 7, 3);
            dc.setPenWidth(2);
            dc.drawLine(cx, cy - 3, cx, cy + 5);
            dc.drawLine(cx, cy - 2, cx - 7, cy - 9);
            dc.drawLine(cx, cy - 2, cx + 7, cy - 9);
            dc.drawLine(cx, cy + 5, cx - 5, cy + 10);
            dc.drawLine(cx, cy + 5, cx + 5, cy + 10);
            dc.setPenWidth(1);
        } else if (kind.equals("eyes")) {
            // Almond eye silhouette with iris + highlight
            dc.setPenWidth(2);
            dc.drawArc(cx, cy + 6, 12, Graphics.ARC_COUNTER_CLOCKWISE, 40, 140);
            dc.drawArc(cx, cy - 6, 12, Graphics.ARC_COUNTER_CLOCKWISE, 220, 320);
            dc.setPenWidth(1);
            dc.fillCircle(cx, cy, 4);
            dc.setColor(BG, BG);
            dc.fillCircle(cx + 1, cy - 1, 1);
        } else if (kind.equals("stairs")) {
            // Rising 3-step staircase
            dc.setPenWidth(2);
            dc.drawLine(cx - 9, cy + 7, cx - 3, cy + 7);
            dc.drawLine(cx - 3, cy + 7, cx - 3, cy + 1);
            dc.drawLine(cx - 3, cy + 1, cx + 3, cy + 1);
            dc.drawLine(cx + 3, cy + 1, cx + 3, cy - 5);
            dc.drawLine(cx + 3, cy - 5, cx + 9, cy - 5);
            dc.setPenWidth(1);
        } else if (kind.equals("sunlight")) {
            // Sun core + 8 rays
            dc.fillCircle(cx, cy, 4);
            dc.setPenWidth(2);
            dc.drawLine(cx, cy - 10, cx, cy - 7);
            dc.drawLine(cx, cy + 7, cx, cy + 10);
            dc.drawLine(cx - 10, cy, cx - 7, cy);
            dc.drawLine(cx + 7, cy, cx + 10, cy);
            dc.drawLine(cx - 7, cy - 7, cx - 5, cy - 5);
            dc.drawLine(cx + 5, cy + 5, cx + 7, cy + 7);
            dc.drawLine(cx + 7, cy - 7, cx + 5, cy - 5);
            dc.drawLine(cx - 5, cy + 5, cx - 7, cy + 7);
            dc.setPenWidth(1);
        } else if (kind.equals("rest")) {
            // Crescent moon + tiny star
            dc.fillCircle(cx - 1, cy, 8);
            dc.setColor(BG, BG);
            dc.fillCircle(cx + 3, cy - 2, 7);
            dc.setColor(color, BG);
            dc.fillCircle(cx + 7, cy - 6, 1);
        } else if (kind.equals("heart")) {
            // Tiny crisp heart for live HR
            dc.fillCircle(cx - 3, cy - 2, 3);
            dc.fillCircle(cx + 3, cy - 2, 3);
            dc.fillPolygon([[cx - 6, cy - 1], [cx + 6, cy - 1], [cx, cy + 6]]);
        } else if (kind.equals("check")) {
            // Celebration checkmark inside circle
            dc.setPenWidth(3);
            dc.drawCircle(cx, cy, 16);
            dc.drawLine(cx - 7, cy + 1, cx - 2, cy + 6);
            dc.drawLine(cx - 2, cy + 6, cx + 8, cy - 6);
            dc.setPenWidth(1);
        } else {
            dc.fillCircle(cx, cy, 4);
        }
    }

    function drawSparkles(dc as Graphics.Dc, frame as Number) as Void {
        var points = [
            [44, 78], [216, 78],
            [28, 130], [232, 130],
            [50, 186], [210, 186],
            [78, 42], [182, 42]
        ] as Array<Array<Number>>;
        var colors = [GOLD, MINT, PEACH, LAVENDER] as Array<Number>;
        dc.setPenWidth(2);
        dc.setColor(SURFACE, BG);
        dc.drawArc(130, 130, 122, Graphics.ARC_CLOCKWISE, 225, 315);
        dc.setPenWidth(1);
        for (var i = 0; i < points.size(); i += 1) {
            var pt = points[i];
            var r = ((frame + i) % 3 == 0) ? 3 : 2;
            dc.setColor(colors[(i + frame) % colors.size()], BG);
            dc.fillCircle(pt[0], pt[1], r);
        }
    }
}
