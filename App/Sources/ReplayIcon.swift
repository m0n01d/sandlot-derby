import DerbyCore

/// Where the camera in the corner sits, and how big a target it has (#42, DESIGN.md §19).
/// Every number in design pixels, y down.
struct ReplayIconLayout {
    /// The picture itself. Small on purpose: it is a mark, not a button.
    var width = 11.0
    var height = 8.0
    /// In from the canvas's own right edge, past the safe area, and down from the top. The one
    /// corner neither HUD writes in: the at-bat view has the headline and the streak top left and
    /// the speed bottom left; the flight view has the exit velocity top left and the park name
    /// bottom right. On a phone the safe inset is the Dynamic Island's, so this clears it in
    /// either landscape orientation; on an iPad the inset is zero and 8 px is the margin every
    /// other corner word uses.
    var inset = 8.0
    var top = 8.0
    /// How far past the picture a tap still counts, so the target is a thumb rather than eleven
    /// pixels — the same growing the outfield scoreboard's tap gets (`AtBatScene.isScoreboardTap`).
    var pad = 14.0
    /// A touch that wanders further than this was a slice, not a tap on the camera.
    var tapSlack = 6.0

    static let standard = ReplayIconLayout()
}

/// The camera in the corner: eleven pixels by eight, chalk body, a hole for the lens, and the
/// hit test that goes with it. Drawn by both play scenes, so it lives in neither (#42).
///
/// It replaces the long press of #4, which Dwight called awkward: "instead of tap and hold which
/// is awkward. just show a camera icon in the corner or something for a instant replay".
enum ReplayIcon {

    /// The picture's top-left corner on a canvas this wide. Right-aligned, so it stays in the
    /// corner however much sky a wide phone adds.
    static func origin(canvasWidth: Double, safeRight: Double,
                       layout: ReplayIconLayout = .standard) -> Point {
        Point(x: (canvasWidth - safeRight - layout.inset - layout.width).rounded(), y: layout.top)
    }

    /// Body, viewfinder hump, lens and shutter. Whole pixels, two palette colours: the chalk a
    /// corner word is written in, and the ink a label plate is drawn on (docs/palette.md).
    static func draw(into canvas: PixelCanvas, safeRight: Double,
                     layout: ReplayIconLayout = .standard) {
        let o = origin(canvasWidth: Double(canvas.width), safeRight: safeRight, layout: layout)
        let x = o.x, y = o.y

        // The hump, left of centre, so the shape is a camera and not a brick.
        canvas.rect(x + 2, y, 3, 1, Palette.chalk)
        canvas.rect(x, y + 1, layout.width, layout.height - 1, Palette.chalk)

        // The lens: a five-across hole through the body, centred.
        canvas.rect(x + 4, y + 2, 3, 1, Palette.ink)
        canvas.rect(x + 3, y + 3, 5, 3, Palette.ink)
        canvas.rect(x + 4, y + 6, 3, 1, Palette.ink)
        // …and the glint that makes a hole read as glass.
        canvas.px(x + 4, y + 3, Palette.chalk)

        // The shutter, top right of the body.
        canvas.px(x + 9, y + 2, Palette.ink)
    }

    /// The target: the picture grown by `pad` on every side. `p` is in canvas space, not the
    /// centred 320 column — the camera is pinned to the canvas's own edge.
    static func contains(_ p: Point, canvasWidth: Double, safeRight: Double,
                         layout: ReplayIconLayout = .standard) -> Bool {
        let o = origin(canvasWidth: canvasWidth, safeRight: safeRight, layout: layout)
        return p.x >= o.x - layout.pad && p.x <= o.x + layout.width + layout.pad
            && p.y >= o.y - layout.pad && p.y <= o.y + layout.height + layout.pad
    }
}
