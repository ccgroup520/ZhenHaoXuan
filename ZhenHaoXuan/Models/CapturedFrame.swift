import Foundation
import UIKit

struct CapturedFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let timestamp: TimeInterval
    let videoName: String
    let captureDate = Date()
}
