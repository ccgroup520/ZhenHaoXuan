import Foundation
import Combine

enum ExportFormat: String, CaseIterable {
    case png = "PNG"
    case jpeg = "JPEG"
    
    var displayName: String {
        rawValue
    }
    
    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }
}

enum ExportQuality: String, CaseIterable {
    case lossless = "无损"
    case high = "高"
    case medium = "中"
    case low = "低"
    
    var displayName: String {
        rawValue
    }
    
    var compressionQuality: CGFloat {
        switch self {
        case .lossless: return 1.0
        case .high: return 0.9
        case .medium: return 0.7
        case .low: return 0.5
        }
    }
}

class ExportSettings: ObservableObject {
    static let shared = ExportSettings()
    
    private let formatKey = "exportFormat"
    private let qualityKey = "exportQuality"
    private let hdrEnabledKey = "exportHdrEnabled"
    
    @Published var format: ExportFormat {
        didSet {
            UserDefaults.standard.set(format.rawValue, forKey: formatKey)
        }
    }
    
    @Published var quality: ExportQuality {
        didSet {
            UserDefaults.standard.set(quality.rawValue, forKey: qualityKey)
        }
    }
    
    @Published var hdrEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hdrEnabled, forKey: hdrEnabledKey)
        }
    }
    
    private init() {
        if let savedFormat = UserDefaults.standard.string(forKey: formatKey),
           let format = ExportFormat(rawValue: savedFormat) {
            self.format = format
        } else {
            self.format = .png
        }
        
        if let savedQuality = UserDefaults.standard.string(forKey: qualityKey),
           let quality = ExportQuality(rawValue: savedQuality) {
            self.quality = quality
        } else {
            self.quality = .lossless
        }
        
        if let savedHDREnabled = UserDefaults.standard.object(forKey: hdrEnabledKey) as? Bool {
            self.hdrEnabled = savedHDREnabled
        } else {
            self.hdrEnabled = VIPManager.shared.canUseHDR
        }
    }
}
