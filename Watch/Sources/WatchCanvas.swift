import Foundation

/// The watch's canvas (docs/watch.md §3). The scale is an integer number of *physical* pixels
/// per design unit, never points: three physical pixels is 1.5 pt on an Ultra, and `.aspectFit`
/// would land on 3.01 and smear rows.
struct WatchCanvas: Equatable {
    /// The smallest canvas the watch framings are laid out for, in design units. The largest
    /// integer scale that still gives at least this much wins; the leftover pixels are a black
    /// border of at most a couple of pixels.
    static let minWidth = 136
    static let minHeight = 165

    /// Physical pixels per design unit.
    let scale: Int
    /// The canvas, in design units.
    let width: Int
    let height: Int
    /// Where the canvas's top-left pixel sits on the glass, in physical pixels, so the border is
    /// split evenly and the sprite lands on the pixel grid.
    let originX: Int
    let originY: Int

    /// The fit for a screen `pixelWidth × pixelHeight` physical pixels. Nil for a screen smaller
    /// than the minimum at scale 1, which no watch is.
    static func fit(pixelWidth: Int, pixelHeight: Int) -> WatchCanvas? {
        var scale = min(pixelWidth / minWidth, pixelHeight / minHeight)
        while scale > 0, pixelWidth / scale < minWidth || pixelHeight / scale < minHeight { scale -= 1 }
        guard scale > 0 else { return nil }
        let w = pixelWidth / scale, h = pixelHeight / scale
        return WatchCanvas(scale: scale, width: w, height: h,
                           originX: (pixelWidth - w * scale) / 2, originY: (pixelHeight - h * scale) / 2)
    }
}
