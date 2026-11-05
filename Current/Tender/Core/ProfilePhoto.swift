import Foundation

public struct ProfilePhoto: Codable, Equatable, Sendable {
    public var originalImage: String
    public var croppedImage: String
    public var crop: ProfilePhotoCrop
    public init(originalImage: String, croppedImage: String, crop: ProfilePhotoCrop) {
        self.originalImage = originalImage; self.croppedImage = croppedImage; self.crop = crop
    }
}

/// Coordinates are relative to the upright source image, independent of preview size.
public struct ProfilePhotoCrop: Codable, Equatable, Sendable {
    public var zoom: Double = 1
    public var centerX: Double = 0.5
    public var centerY: Double = 0.5
    public init(zoom: Double = 1, centerX: Double = 0.5, centerY: Double = 0.5) {
        self.zoom = zoom; self.centerX = centerX; self.centerY = centerY
    }
    public var isValid: Bool {
        zoom.isFinite && centerX.isFinite && centerY.isFinite && (1...5).contains(zoom) &&
            (0...1).contains(centerX) && (0...1).contains(centerY)
    }
    public func constrained(width: Double, height: Double) -> Self {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              zoom.isFinite, centerX.isFinite, centerY.isFinite else { return Self() }
        let zoom = min(5, max(1, zoom))
        let halfSide = min(width, height) / (2 * zoom)
        return Self(zoom: zoom, centerX: min(1 - halfSide / width, max(halfSide / width, centerX)),
                    centerY: min(1 - halfSide / height, max(halfSide / height, centerY)))
    }
    public struct SourceRectangle: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var side: Double
    }
    public func sourceRectangle(width: Double, height: Double) -> SourceRectangle? {
        guard isValid, width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let crop = constrained(width: width, height: height)
        let side = min(width, height) / crop.zoom
        return SourceRectangle(x: crop.centerX * width - side / 2, y: crop.centerY * height - side / 2, side: side)
    }
}
