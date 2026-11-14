import Toybox.Lang;

// All day descriptions are demo fixtures. Nothing here reads live health data.
// Later integrations can replace this model's input without changing the view.
class MomoModel {
    const SLEEPY = 0;
    const CHILL = 1;
    const THRIVING = 2;
    const PHASE_COUNT = 3;

    private var _phase as Number = CHILL;
    private var _remark as Number = 0;

    private var _remarks as Array<Array<String>> = [
        [
            "Your chair called. It wants some space.",
            "Quiet day, huh? Even a tiny walk counts.",
            "I'm on banana-saving mode. Tiny reset?",
            "No big plans. Just a little fresh start."
        ],
        [
            "A little movement. A little chill. Very us.",
            "A perfectly decent day to be a monkey.",
            "Small wins today. I'll take the credit.",
            "Nothing wild. Still worth a tiny high-five."
        ],
        [
            "You moved. You conquered. I accessorized.",
            "What a day. These shades were necessary.",
            "Main character energy. Banana budget.",
            "Today's plot twist? You absolutely showed up."
        ]
    ];

    function initialize() {}

    function getPhase() as Number {
        return _phase;
    }

    function selectPhase(phase as Number) as Void {
        // Normalize in both directions so UP/DOWN wrap around naturally.
        _phase = ((phase % PHASE_COUNT) + PHASE_COUNT) % PHASE_COUNT;
        _remark = 0;
    }

    function movePhase(direction as Number) as Void {
        selectPhase(_phase + direction);
    }

    function nextRemark() as Void {
        _remark = (_remark + 1) % _remarks[_phase].size();
    }

    function getRemark() as String {
        return _remarks[_phase][_remark];
    }

    function getTitle() as String {
        return ["SLOW DAY", "JUST CHILLIN'", "MAIN CHARACTER"][_phase];
    }

    function getAccent() as Number {
        // Chosen on the fēnix MIP display's native 64-color grid.
        return [0xAAAAFF, 0x55FFAA, 0xFFFF55][_phase];
    }

    function getBitmapId() as ResourceId {
        return [Rez.Drawables.MomoSleepy, Rez.Drawables.MomoChill, Rez.Drawables.MomoThriving][_phase];
    }

    function getImageX() as Number {
        return [64, 77, 77][_phase];
    }

    function getImageY() as Number {
        return [-4, 32, 32][_phase];
    }
}
