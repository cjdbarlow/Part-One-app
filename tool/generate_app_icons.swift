// Run from the repository root: swift tool/generate_app_icons.swift
// Uses the macOS SDK only; no package installation is required.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconPolygon {
    let points: [CGPoint]
    let colour: CGColor
}

// The master deliberately uses only filled polygons, keeping the export editable
// without a font dependency or a general-purpose SVG rendering library.
final class IconSource: NSObject, XMLParserDelegate {
    var canvasSize: CGFloat = 0
    var polygons: [IconPolygon] = []
    var invalid = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes: [String: String]) {
        switch elementName {
        case "svg":
            let values = (attributes["viewBox"] ?? "").split(separator: " ").compactMap { Double($0) }
            guard values.count == 4, values[0] == 0, values[1] == 0,
                  values[2] > 0, values[2] == values[3] else {
                invalid = true
                return
            }
            canvasSize = values[2]
        case "polygon":
            let pairs = (attributes["points"] ?? "").split(whereSeparator: { $0.isWhitespace })
            var points: [CGPoint] = []
            for pair in pairs {
                let coordinates = pair.split(separator: ",").compactMap { Double($0) }
                guard coordinates.count == 2 else {
                    invalid = true
                    return
                }
                points.append(CGPoint(x: coordinates[0], y: coordinates[1]))
            }
            let fill = attributes["fill"] ?? ""
            guard points.count >= 3, fill.count == 7, fill.first == "#",
                  let rgb = UInt32(fill.dropFirst(), radix: 16) else {
                invalid = true
                return
            }
            let components: [CGFloat] = [
                CGFloat((rgb >> 16) & 255) / 255,
                CGFloat((rgb >> 8) & 255) / 255,
                CGFloat(rgb & 255) / 255,
                1,
            ]
            polygons.append(IconPolygon(points: points,
                colour: CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                components: components)!))
        case "title", "desc":
            break
        default:
            invalid = true
        }
    }
}

struct IconError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let sourceURL = root.appendingPathComponent("assets/icon/part-one.svg")
let icon = IconSource()
guard let parser = XMLParser(contentsOf: sourceURL) else {
    throw IconError("Run from the repository root; assets/icon/part-one.svg is required.")
}
parser.delegate = icon
guard parser.parse(), !icon.invalid, icon.canvasSize > 0, !icon.polygons.isEmpty else {
    throw IconError("The icon master must contain a square viewBox and filled polygons.")
}

var exported = 0
func exportPNG(_ relativePath: String, pixels: Int, transparent: Bool = false,
               artworkScale: CGFloat = 1, keepAlpha: Bool = false) throws {
    let alpha = transparent || keepAlpha
        ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
    guard let context = CGContext(data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: pixels * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue) else {
        throw IconError("Cannot create \(pixels)px icon context.")
    }
    let side = CGFloat(pixels)
    if !transparent {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }

    // SVG coordinates start at the top-left; Core Graphics starts at the bottom-left.
    context.translateBy(x: 0, y: side)
    context.scaleBy(x: 1, y: -1)
    let inset = side * (1 - artworkScale) / 2
    context.translateBy(x: inset, y: inset)
    let scale = side * artworkScale / icon.canvasSize
    context.scaleBy(x: scale, y: scale)
    for polygon in icon.polygons {
        context.beginPath()
        context.addLines(between: polygon.points)
        context.closePath()
        context.setFillColor(polygon.colour)
        context.fillPath()
    }

    let output = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(output as CFURL,
              UTType.png.identifier as CFString, 1, nil) else {
        throw IconError("Cannot write \(relativePath).")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconError("PNG export failed: \(relativePath).")
    }
    exported += 1
}

struct IconCatalog: Decodable {
    struct Image: Decodable {
        let filename: String
        let size: String
        let scale: String
    }
    let images: [Image]
}

let catalogDirectory = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
let catalogData = try Data(contentsOf: root.appendingPathComponent("\(catalogDirectory)/Contents.json"))
let catalog = try JSONDecoder().decode(IconCatalog.self, from: catalogData)
var iosSizes: [String: Int] = [:]
for image in catalog.images {
    let dimensions = image.size.split(separator: "x").compactMap { Double($0) }
    guard dimensions.count == 2, dimensions[0] == dimensions[1],
          let scale = Double(image.scale.dropLast()) else {
        throw IconError("Invalid iOS icon size for \(image.filename).")
    }
    let pixels = Int(dimensions[0] * scale)
    if let existing = iosSizes[image.filename], existing != pixels {
        throw IconError("Conflicting iOS icon sizes for \(image.filename).")
    }
    iosSizes[image.filename] = pixels
}
for (filename, pixels) in iosSizes.sorted(by: { $0.key < $1.key }) {
    try exportPNG("\(catalogDirectory)/\(filename)", pixels: pixels)
}

let densities: [(String, Int, Int)] = [
    ("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432),
]
for (density, legacySize, foregroundSize) in densities {
    try exportPNG("android/app/src/main/res/mipmap-\(density)/ic_launcher.png", pixels: legacySize)
    // At 70% scale every vertex fits the central 66dp circular safe zone in a
    // 108dp adaptive layer, including the numeral's bottom-right foot.
    try exportPNG("android/app/src/main/res/drawable-\(density)/ic_launcher_foreground.png",
                  pixels: foregroundSize, transparent: true, artworkScale: 0.70)
}

try exportPNG("assets/icon/part-one-1024.png", pixels: 1024)
try exportPNG("assets/icon/part-one-foreground-2048.png", pixels: 2048, transparent: true)
// Google Play requests a 32-bit PNG; keep the alpha channel fully opaque.
try exportPNG("assets/icon/part-one-play-store-512.png", pixels: 512, keepAlpha: true)
print("Exported \(exported) PNGs: \(iosSizes.count) iOS, 10 Android and 3 master/store assets.")
