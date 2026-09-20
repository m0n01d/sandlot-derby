import SpriteKit
import DerbyCore

/// The scoreboard, up close: every career number `DerbyMachine` counts. Reached by tapping the
/// outfield scoreboard in the at-bat view, left by tapping anywhere. Not a menu: nothing here
/// can be chosen or changed, and the game stands still behind it.
final class StatsScene: CanvasScene {
    override var ticksMachine: Bool { false }

    private struct Section {
        let title: String
        let rows: [(label: String, value: String)]
        /// The one row that is not a number: the contract, for a player who has not signed it
        /// (DESIGN.md §16). Slicing it opens the card.
        var isContract = false
    }

    /// How far either side of the contract row's baseline a slice still counts, in design
    /// pixels. The row is 5 px of text; a finger is not.
    private static let contractRowBand = 6.0
    /// The shortest drag that can open the card. Below it the touch is a tap, which closes the
    /// board as every other tap does.
    private static let contractMinimumSliceLength = 12.0

    /// Where the contract row was last drawn, in design space, or nil when there is no such row.
    /// Set during `render` because the board's columns are laid out as they are drawn.
    private var contractRow: (x: Double, y: Double, width: Double)?

    override func render(into canvas: PixelCanvas) {
        guard let controller else { return }
        let width = Double(canvas.width)
        canvas.fill(Palette.wall)

        let left = safeLeft + 8, right = width - safeRight - 8
        canvas.t3(left, 8, "CAREER", Palette.score, scale: 2)
        let park = controller.machine.park.displayName
        canvas.t3(right - Double(park.count) * 8, 8, park, Palette.chalk, scale: 2)

        let columns = max(2, Int((right - left) / 130))
        let gutter = 12.0
        let columnWidth = ((right - left) - gutter * Double(columns - 1)) / Double(columns)
        let top = 26.0
        let pitch = columns >= 3 ? 8.0 : 7.0
        let rowsPerColumn = Int((224 - top - 4) / pitch)

        var column = 0, row = 0
        contractRow = nil
        for section in sections(controller.machine) {
            let needed = section.rows.count + 1
            if row > 0, row + needed > rowsPerColumn, needed <= rowsPerColumn { column += 1; row = 0 }
            guard column < columns else { break }
            let x = left + Double(column) * (columnWidth + gutter)

            canvas.rect(x - 2, top + Double(row) * pitch - 1, columnWidth + 4, 7, Palette.ink)
            canvas.t3(x, top + Double(row) * pitch, section.title, Palette.score)
            row += 1
            for r in section.rows {
                let y = top + Double(row) * pitch
                canvas.t3(x, y, r.label, Palette.chalk)
                canvas.t3(x + columnWidth - Double(r.value.count) * 4, y, r.value, Palette.score)
                if section.isContract { contractRow = (x: x, y: y, width: columnWidth) }
                row += 1
            }
            row += 1
        }
    }

    // MARK: - Input: a tap leaves, a slice across the contract row opens the card

    private var dragStart: CGPoint?
    private var dragLast: CGPoint?
    private var openedContract = false

    private func designPoint(for touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return CGPoint(x: p.x, y: size.height - p.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        dragStart = designPoint(for: touch)
        dragLast = dragStart
        openedContract = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let start = dragStart, let last = dragLast else { return }
        let p = designPoint(for: touch)
        dragLast = p
        guard !openedContract, let row = contractRow else { return }
        guard hypot(p.x - start.x, p.y - start.y) >= Self.contractMinimumSliceLength else { return }
        let band = Self.contractRowBand
        let top = row.y - band, bottom = row.y + 5 + band
        // A straddle of the row's band, anywhere across its width.
        let crossed = (last.y < top && p.y >= top) || (last.y > bottom && p.y <= bottom)
            || (min(last.y, p.y) >= top && max(last.y, p.y) <= bottom)
        guard crossed, max(last.x, p.x) >= row.x, min(last.x, p.x) <= row.x + row.width else { return }
        openedContract = true
        controller?.showContract()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { dragStart = nil; dragLast = nil }
        guard !openedContract else { return }
        controller?.hideStats()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragStart = nil
        dragLast = nil
    }

    // MARK: - What is on the board

    private func sections(_ machine: DerbyMachine) -> [Section] {
        let t = machine.tally
        func n(_ s: Stat) -> String { grouped(t.count(s)) }
        func percent(_ part: Stat, of whole: Stat) -> String {
            t[whole] > 0 ? "\(Int((t[part] / t[whole] * 100).rounded()))%" : "-"
        }
        func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }
        let fewest = t.value(ifRecorded: .fewestPitchesToClearPark).map { grouped(Int($0)) } ?? "-"

        // The contract, once and quietly (DESIGN.md §16): one row, the price the store charges
        // today, and no badge, banner or timer. It goes first because the board runs out of
        // columns on a narrow screen and drops whatever is last, and a row nobody can reach is
        // not an offer. Gone for good once it is signed. The price is "-" until the store
        // answers, rather than a number the game made up.
        var board: [Section] = []
        if let controller, !controller.isEntitled {
            board.append(Section(title: "THE SHOW",
                                 rows: [(controller.store.priceText ?? "-", "SLICE TO SIGN")],
                                 isContract: true))
        }

        board += [
            Section(title: "THE LONG GAME", rows: [
                ("PITCHES", n(.pitches)),
                ("PARKS CLEARED", n(.parksCleared)),
                ("PITCHES THIS PARK", n(.pitchesThisPark)),
                ("FEWEST TO CLEAR", fewest),
                ("PITCHES TO THE SHOW", t.value(ifRecorded: .pitchesToTheShow).map { grouped(Int($0)) } ?? "-"),
                ("TIME AT THE PLATE", clock(t[.secondsPlayed])),
            ]),
            Section(title: "STREAKS", rows: [
                ("HR STREAK", n(.homeRunStreak)),
                ("BEST HR STREAK", n(.bestHomeRunStreak)),
                ("HIT STREAK", n(.hitStreak)),
                ("BEST HIT STREAK", n(.bestHitStreak)),
            ]),
            Section(title: "AT THE PLATE", rows: [
                ("SWINGS", n(.swings)),
                ("CONTACT", percent(.hits, of: .swings)),
                ("WHIFFS", n(.whiffs)),
                ("CALLED STRIKES", n(.calledStrikes)),
                ("BALLS TAKEN", n(.ballsTaken)),
                ("CHASES", n(.chases)),
            ]),
            Section(title: "CONTACT", rows: [
                ("HITS", n(.hits)),
                ("BARRELS", n(.barrels)),
                ("AVG EXIT VELO", oneDecimal(t.averageExitVelocityMPH)),
                ("BEST EXIT VELO", oneDecimal(t[.bestExitVelocityMPH])),
                ("AVG LAUNCH ANGLE", oneDecimal(t.averageLaunchAngleDegrees)),
                ("GROUNDERS", n(.groundBalls)),
                ("LINERS", n(.lineDrives)),
                ("FLY BALLS", n(.flyBalls)),
                ("POP UPS", n(.popUps)),
                ("OFF THE WALL", n(.wallHits)),
            ]),
            Section(title: "DISTANCE", rows: [
                ("TOTAL FEET", n(.totalFeet)),
                ("MILES", String(format: "%.2f", t[.totalFeet] / 5280)),
                ("LONGEST", n(.longestFeet)),
                ("HIGHEST APEX", n(.highestApexFeet)),
                ("LONGEST HANG", oneDecimal(t[.longestHangTime])),
            ]),
            Section(title: "HOME RUNS", rows: [
                ("HOME RUNS", n(.homeRuns)),
                ("PER PITCH", percent(.homeRuns, of: .pitches)),
                ("NO DOUBTERS", n(.noDoubters)),
                ("WALL SCRAPERS", n(.wallScrapers)),
                ("MOONSHOTS", n(.moonshots)),
                ("LASERS", n(.lasers)),
            ]),
            Section(title: "BY PITCH  SEEN/HIT/HR", rows: PitchType.all.map {
                ($0.name, "\(t.count(.seen($0)))/\(t.count(.hits($0)))/\(t.count(.homeRuns($0)))")
            }),
        ]
        return board
    }

    /// 1234567 → "1,234,567".
    private func grouped(_ value: Int) -> String {
        var out = ""
        for (i, ch) in String(value).reversed().enumerated() {
            if i > 0, i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return String(out.reversed())
    }

    /// Seconds → "H:MM:SS".
    private func clock(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}
