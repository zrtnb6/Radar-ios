import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 生成 iOS App 图标（1024×1024，满幅方形，不预置圆角 —— 系统会自己裁）。
// 用法：swiftc -O GenerateIcon.swift -o /tmp/genicon && /tmp/genicon Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Unable to create icon context")
}

let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
context.saveGState()
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

context.setFillColor(CGColor(red: 0.075, green: 0.345, blue: 0.665, alpha: 1))
context.fill(canvas)

// 顶部一层极淡高光，保证在大图标尺寸下仍有体积感
let sheen = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0)
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 420), options: [])

let center = CGPoint(x: 512, y: 512)
context.setLineCap(.round)

// 两道扫描弧，缺口在左上；iOS 图标会被裁圆角，弧线留出安全边距
for (index, radius) in [286.0, 164.0].enumerated() {
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: index == 0 ? 0.96 : 0.72))
    context.setLineWidth(70)
    context.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
    context.strokePath()
}

// 中心命中点：一颗 IPA 方块 + 下载箭头，暗示“这里是 iOS 安装包”
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
context.fillEllipse(in: CGRect(x: center.x - 92, y: center.y - 92, width: 184, height: 184))
context.setFillColor(CGColor(red: 0.36, green: 0.79, blue: 0.65, alpha: 1))
context.fillEllipse(in: CGRect(x: center.x - 66, y: center.y - 66, width: 132, height: 132))

context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.setLineWidth(20)
context.move(to: CGPoint(x: center.x, y: center.y + 34))
context.addLine(to: CGPoint(x: center.x, y: center.y - 16))
context.strokePath()
context.move(to: CGPoint(x: center.x - 30, y: center.y - 2))
context.addLine(to: CGPoint(x: center.x, y: center.y - 34))
context.addLine(to: CGPoint(x: center.x + 30, y: center.y - 2))
context.strokePath()

context.restoreGState()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    fatalError("Unable to create icon image")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Unable to write icon file")
}
print("icon written to \(CommandLine.arguments[1])")
