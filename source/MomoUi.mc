import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

module MomoUi {
    const BG = 0x000000;
    const INK = 0xFFFFFF;
    const MINT = 0x55FFAA;
    const MUTED = 0xAAAAAA;
    const EDGE = 0x555555;
    const SURFACE = 0x005555;

    function clear(dc as Graphics.Dc) as Void {
        dc.setColor(INK, BG); dc.clear();
    }

    function safeWidth(top as Number, height as Number) as Number {
        var first = top < 130 ? 130 - top : top - 130;
        var bottom = top + height;
        var last = bottom < 130 ? 130 - bottom : bottom - 130;
        var distance = first > last ? first : last;
        if (distance >= 126) { return 40; }
        return (2 * Math.sqrt(126 * 126 - distance * distance) - 16).toNumber();
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
        if (width > 208) { width = 208; }
        dc.drawText(130, top, Graphics.FONT_XTINY, fit(dc, value, Graphics.FONT_XTINY, width), Graphics.TEXT_JUSTIFY_CENTER);
    }

    function heading(dc as Graphics.Dc, value as String) as Void {
        dc.setColor(INK, BG);
        dc.drawText(130, 28, Graphics.FONT_SMALL, fit(dc, value, Graphics.FONT_SMALL, 156), Graphics.TEXT_JUSTIFY_CENTER);
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
        var wrapped = lines(dc, value, 200);
        for (var i = 0; i < wrapped.size() && i < maxLines; i += 1) {
            var line = wrapped[i];
            if (i == maxLines - 1 && wrapped.size() > maxLines) { line += "..."; }
            text(dc, line, top + i * 21, color);
        }
    }

    function pill(dc as Graphics.Dc, label as String, top as Number) as Void {
        dc.setColor(SURFACE, BG);
        dc.fillRoundedRectangle(62, top, 136, 27, 10);
        dc.setColor(MINT, SURFACE);
        dc.drawRoundedRectangle(62, top, 136, 27, 10);
        dc.drawText(130, top + 3, Graphics.FONT_XTINY, fit(dc, label, Graphics.FONT_XTINY, 124), Graphics.TEXT_JUSTIFY_CENTER);
    }
}
