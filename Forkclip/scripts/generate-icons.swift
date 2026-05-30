import AppKit
import Foundation
import ImageIO

struct RGBAImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]
}

struct IconRenderer {
    private let sourceFileName = "forkclip-icon.png"
    let outputDirectory: URL
    let fileManager = FileManager.default

    func run() throws {
        let sourceURL = outputDirectory.appendingPathComponent(sourceFileName)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw NSError(
                domain: "IconRenderer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing icon source: \(sourceURL.path)"]
            )
        }

        var sourceImage = try loadImage(from: sourceURL)
        removeConnectedDarkBackground(from: &sourceImage)

        let iconsetDirectory = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        let appIconURL = outputDirectory.appendingPathComponent("AppIcon.icns")
        let menuIconURL = outputDirectory.appendingPathComponent("AppMenuIconTemplate.png")

        try recreateDirectory(iconsetDirectory)

        let iconSizes: [(Int, String)] = [
            (16, "icon_16x16.png"),
            (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),
            (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),
            (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),
            (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),
            (1024, "icon_512x512@2x.png")
        ]

        for (size, name) in iconSizes {
            let resized = try resizedImage(sourceImage, size: size)
            try writePNG(image: resized, to: iconsetDirectory.appendingPathComponent(name))
        }

        try runProcess(
            executable: "/usr/bin/iconutil",
            arguments: ["-c", "icns", iconsetDirectory.path, "-o", appIconURL.path]
        )

        let menuImage = makeMenuBarImage(try resizedImage(sourceImage, size: 36))
        try writePNG(image: menuImage, to: menuIconURL)
        // ClipboardFeedbackClick.wav is an externally sourced app asset; keep it outside
        // icon generation so running this script does not overwrite the curated sound.
    }

    private func recreateDirectory(_ directory: URL) throws {
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func loadImage(from url: URL) throws -> RGBAImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(
                domain: "IconRenderer",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read image: \(url.path)"]
            )
        }
        return try draw(cgImage: cgImage, width: cgImage.width, height: cgImage.height)
    }

    private func resizedImage(_ image: RGBAImage, size: Int) throws -> RGBAImage {
        try draw(cgImage: cgImage(from: image), width: size, height: size)
    }

    private func draw(cgImage: CGImage, width: Int, height: Int) throws -> RGBAImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        try pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                  ) else {
                throw NSError(domain: "IconRenderer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap context"])
            }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    private func removeConnectedDarkBackground(from image: inout RGBAImage) {
        var visited = Array(repeating: false, count: image.width * image.height)
        var queue: [(Int, Int)] = []

        func enqueue(_ x: Int, _ y: Int) {
            guard x >= 0, x < image.width, y >= 0, y < image.height else { return }
            let index = y * image.width + x
            guard !visited[index], isBackgroundDark(image: image, x: x, y: y) else { return }
            visited[index] = true
            queue.append((x, y))
        }

        let seedSpan = min(12, max(image.width, image.height))
        for offset in 0..<seedSpan {
            enqueue(offset, 0)
            enqueue(0, offset)
            enqueue(image.width - 1 - offset, 0)
            enqueue(image.width - 1, offset)
            enqueue(image.width - 1 - offset, image.height - 1)
            enqueue(image.width - 1, image.height - 1 - offset)
            enqueue(offset, image.height - 1)
            enqueue(0, image.height - 1 - offset)
        }

        var cursor = 0
        while cursor < queue.count {
            let (x, y) = queue[cursor]
            cursor += 1
            setTransparent(image: &image, x: x, y: y)
            enqueue(x + 1, y)
            enqueue(x - 1, y)
            enqueue(x, y + 1)
            enqueue(x, y - 1)
        }
    }

    private func isBackgroundDark(image: RGBAImage, x: Int, y: Int) -> Bool {
        let offset = (y * image.width + x) * 4
        let red = Int(image.pixels[offset])
        let green = Int(image.pixels[offset + 1])
        let blue = Int(image.pixels[offset + 2])
        let alpha = Int(image.pixels[offset + 3])
        let luminance = (red * 299 + green * 587 + blue * 114) / 1_000
        let colorRange = max(red, green, blue) - min(red, green, blue)
        return alpha > 0 && luminance <= 18 && colorRange <= 14
    }

    private func setTransparent(image: inout RGBAImage, x: Int, y: Int) {
        let offset = (y * image.width + x) * 4
        image.pixels[offset] = 0
        image.pixels[offset + 1] = 0
        image.pixels[offset + 2] = 0
        image.pixels[offset + 3] = 0
    }

    private func makeMenuBarImage(_ image: RGBAImage) -> RGBAImage {
        var detailMask = [UInt8](repeating: 0, count: image.width * image.height)
        for pixelIndex in 0..<detailMask.count {
            let index = pixelIndex * 4
            let sourceAlpha = Int(image.pixels[index + 3])
            let red = Int(image.pixels[index])
            let green = Int(image.pixels[index + 1])
            let blue = Int(image.pixels[index + 2])
            let luminance = (red * 299 + green * 587 + blue * 114) / 1_000
            let iconAlpha = sourceAlpha > 8 && luminance < 130
                ? min(255, (130 - luminance) * 3)
                : 0
            detailMask[pixelIndex] = UInt8(iconAlpha)
        }

        let widenedDetails = dilatedAlphaMask(detailMask, width: image.width, height: image.height, radius: 1)
        var menuBarImage = image
        for pixelIndex in 0..<widenedDetails.count {
            let index = pixelIndex * 4
            let sourceAlpha = image.pixels[index + 3]
            guard sourceAlpha > 8 else {
                menuBarImage.pixels[index] = 0
                menuBarImage.pixels[index + 1] = 0
                menuBarImage.pixels[index + 2] = 0
                menuBarImage.pixels[index + 3] = 0
                continue
            }

            let detailAlpha = widenedDetails[pixelIndex]
            let detailStrength = Double(detailAlpha) / 255.0
            let whiteComponent = UInt8((1.0 - detailStrength) * 255.0)
            menuBarImage.pixels[index] = whiteComponent
            menuBarImage.pixels[index + 1] = whiteComponent
            menuBarImage.pixels[index + 2] = whiteComponent
            menuBarImage.pixels[index + 3] = sourceAlpha
        }
        return menuBarImage
    }

    private func dilatedAlphaMask(_ alphaMask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var result = alphaMask
        for y in 0..<height {
            for x in 0..<width {
                var maxAlpha: UInt8 = 0
                for offsetY in -radius...radius {
                    for offsetX in -radius...radius {
                        guard offsetX * offsetX + offsetY * offsetY <= radius * radius else { continue }
                        let neighborX = x + offsetX
                        let neighborY = y + offsetY
                        guard neighborX >= 0, neighborX < width, neighborY >= 0, neighborY < height else { continue }
                        maxAlpha = max(maxAlpha, alphaMask[neighborY * width + neighborX])
                    }
                }
                result[y * width + x] = maxAlpha
            }
        }
        return result
    }

    private func cgImage(from image: RGBAImage) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let data = Data(image.pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw NSError(domain: "IconRenderer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        return cgImage
    }

    private func writePNG(image: RGBAImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(cgImage: try cgImage(from: image))
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "IconRenderer", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }
        try data.write(to: url)
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "IconRenderer",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Process failed: \(executable) \(arguments.joined(separator: " "))"]
            )
        }
    }
}

let outputPath = CommandLine.arguments.dropFirst().first ?? "."
let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
try IconRenderer(outputDirectory: outputDirectory).run()
