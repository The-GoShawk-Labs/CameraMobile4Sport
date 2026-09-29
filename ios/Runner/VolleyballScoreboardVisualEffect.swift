import Foundation
import AVFoundation
import CoreImage
import HaishinKit
import UIKit

/**
 * HaishinKit VisualEffect implementation.
 * Renders the authentic Flutter [ScoreboardOverlay] widget bitmap
 * over the camera stream frames using Metal/CoreImage hardware acceleration
 * before VideoToolbox encodes to H.264.
 */
public final class VolleyballScoreboardVisualEffect: VisualEffect {
    private let lock = NSLock()
    private var state: VolleyballScoreboardState = .empty
    private var isDirty: Bool = true
    private var cachedCIImage: CIImage?
    private var cachedExtent: CGSize = .zero
    private var customOverlayCIImage: CIImage?

    public func updateState(_ newState: VolleyballScoreboardState) {
        lock.lock()
        defer { lock.unlock() }
        if state != newState {
            state = newState
            isDirty = true
            customOverlayCIImage = nil
        }
    }

    public func updateOverlayBitmap(data: Data, width: Int, height: Int) {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return }
        let ciImage = CIImage(cgImage: cgImage)

        lock.lock()
        self.customOverlayCIImage = ciImage
        self.isDirty = true
        lock.unlock()
    }

    public override func execute(_ image: CIImage, info: CMSampleBuffer?) -> CIImage {
        let extent = image.extent.size
        if extent.width <= 0 || extent.height <= 0 {
            return image
        }

        lock.lock()
        let customCI = customOverlayCIImage
        let shouldRedraw = isDirty || cachedCIImage == nil || cachedExtent != extent
        let currentState = state
        lock.unlock()

        // 1. If authentic Flutter ScoreboardOverlay widget bitmap is provided, composite it
        if let customCI = customCI {
            let targetWidth = extent.width * 0.58
            let scale = targetWidth / customCI.extent.width
            let scaled = customCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let originX = (extent.width - scaled.extent.width) / 2.0
            let originY = extent.height - scaled.extent.height - 40.0 // 40px margin from top
            let positioned = scaled.transformed(by: CGAffineTransform(translationX: originX, y: originY))
            return positioned.composited(over: image)
        }

        // 2. Fallback: CoreGraphics renderer
        if shouldRedraw {
            if let newOverlay = renderScoreboardOverlay(size: extent, state: currentState) {
                lock.lock()
                cachedCIImage = newOverlay
                cachedExtent = extent
                isDirty = false
                lock.unlock()
            }
        }

        lock.lock()
        let overlay = cachedCIImage
        lock.unlock()

        guard let overlay = overlay else {
            return image
        }

        return overlay.composited(over: image)
    }

    private func renderScoreboardOverlay(size: CGSize, state: VolleyballScoreboardState) -> CIImage? {
        let bannerWidth = size.width * 0.60
        let bannerHeight: CGFloat = 110.0
        let originX = (size.width - bannerWidth) / 2.0
        let originY = size.height - bannerHeight - 40.0

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1.0

        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)
        let uiImage = renderer.image { ctx in
            let bannerRect = CGRect(x: originX, y: originY, width: bannerWidth, height: bannerHeight)
            let path = UIBezierPath(roundedRect: bannerRect, cornerRadius: 18.0)
            UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 0.85).setFill()
            path.fill()

            UIColor(white: 1.0, alpha: 0.35).setStroke()
            path.lineWidth = 2.0
            path.stroke()

            let pillWidth: CGFloat = 180.0
            let pillHeight: CGFloat = 40.0
            let pillX = originX + (bannerWidth - pillWidth) / 2.0
            let pillY = originY + (bannerHeight - pillHeight) / 2.0
            let pillRect = CGRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)
            let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: 12.0)
            UIColor(red: 2/255, green: 132/255, blue: 199/255, alpha: 0.95).setFill()
            pillPath.fill()

            let setAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let setText = "SET \(state.currentSet) (\(state.setsA):\(state.setsB))"
            let setTextSize = setText.size(withAttributes: setAttributes)
            let setTextRect = CGRect(
                x: pillX + (pillWidth - setTextSize.width) / 2.0,
                y: pillY + (pillHeight - setTextSize.height) / 2.0,
                width: setTextSize.width,
                height: setTextSize.height
            )
            setText.draw(in: setTextRect, withAttributes: setAttributes)

            let teamAAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let teamARect = CGRect(x: originX + 32, y: originY + 36, width: 260, height: 40)
            state.teamA.draw(in: teamARect, withAttributes: teamAAttributes)

            if state.servingTeam == "A" {
                let dotRect = CGRect(x: originX + 14, y: originY + 48, width: 12, height: 12)
                UIColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1.0).setFill()
                UIBezierPath(ovalIn: dotRect).fill()
            }

            let scoreAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 42, weight: .black),
                .foregroundColor: UIColor.yellow
            ]
            let scoreAText = "\(state.scoreA)"
            let scoreARect = CGRect(x: pillX - 70, y: originY + 30, width: 60, height: 50)
            scoreAText.draw(in: scoreARect, withAttributes: scoreAttributes)

            let scoreBText = "\(state.scoreB)"
            let scoreBRect = CGRect(x: pillX + pillWidth + 20, y: originY + 30, width: 60, height: 50)
            scoreBText.draw(in: scoreBRect, withAttributes: scoreAttributes)

            let teamBAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let teamBRect = CGRect(x: originX + bannerWidth - 292, y: originY + 36, width: 260, height: 40)
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .right
            var teamBAttrCopy = teamBAttributes
            teamBAttrCopy[.paragraphStyle] = pStyle
            state.teamB.draw(in: teamBRect, withAttributes: teamBAttrCopy)

            if state.servingTeam == "B" {
                let dotRect = CGRect(x: originX + bannerWidth - 24, y: originY + 48, width: 12, height: 12)
                UIColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1.0).setFill()
                UIBezierPath(ovalIn: dotRect).fill()
            }

            // Red Event / Toast Banner directly below the scoreboard card
            let rawToastText = !state.toastMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? state.toastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                : state.eventTag.trimmingCharacters(in: .whitespacesAndNewlines)
            let toastText = VolleyballScoreboardVisualEffect.isDisplayableBanner(rawToastText) ? rawToastText : ""

            if !toastText.isEmpty {
                let redBannerWidth: CGFloat = 280.0
                let redBannerHeight: CGFloat = 34.0
                let redBannerX = originX + (bannerWidth - redBannerWidth) / 2.0
                let redBannerY = originY - redBannerHeight - 8.0
                let redBannerRect = CGRect(x: redBannerX, y: redBannerY, width: redBannerWidth, height: redBannerHeight)
                let redBannerPath = UIBezierPath(roundedRect: redBannerRect, cornerRadius: 12.0)
                UIColor(red: 229/255, green: 57/255, blue: 53/255, alpha: 0.92).setFill()
                redBannerPath.fill()

                let pStyleCenter = NSMutableParagraphStyle()
                pStyleCenter.alignment = .center
                let toastAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .black),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: pStyleCenter
                ]
                let bannerText = toastText.uppercased()
                let textSize = bannerText.size(withAttributes: toastAttributes)
                let textRect = CGRect(
                    x: redBannerX,
                    y: redBannerY + (redBannerHeight - textSize.height) / 2.0,
                    width: redBannerWidth,
                    height: textSize.height
                )
                bannerText.draw(in: textRect, withAttributes: toastAttributes)
            }
        }

        guard let cgImage = uiImage.cgImage else { return nil }
        return CIImage(cgImage: cgImage)
    }

    public static func isDisplayableBanner(_ tag: String) -> Bool {
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.isEmpty { return false }
        if clean.hasPrefix("POINT") ||
           clean.contains("POCZĄTEK") ||
           clean.contains("POCZATEK") ||
           clean.contains("START MECZU") ||
           clean.contains("COFNIĘTO") ||
           clean.contains("COFNIETO") ||
           clean == "SCOREUPDATE" ||
           clean == "INIT" ||
           clean == "START" ||
           clean == "NONE" {
            return false
        }
        return true
    }
}
