// 앱 아이콘 생성 스크립트: swift gen_icon.swift
// macOS 아이콘 그리드(1024 캔버스, 100px 인셋, 라운드 사각형)에 ☕를 그려 AppIcon.png 출력
import AppKit

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.45, green: 0.29, blue: 0.18, alpha: 1),
    ending: NSColor(calibratedRed: 0.24, green: 0.15, blue: 0.09, alpha: 1)
)!
gradient.draw(in: path, angle: -90)

let emoji = "☕" as NSString
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 560)]
let textSize = emoji.size(withAttributes: attrs)
emoji.draw(
    at: NSPoint(x: (canvas - textSize.width) / 2, y: (canvas - textSize.height) / 2),
    withAttributes: attrs
)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("PNG 변환 실패")
}
try! png.write(to: URL(fileURLWithPath: "AppIcon.png"))
print("AppIcon.png 생성 완료")
