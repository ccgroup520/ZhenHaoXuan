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

 @MainActor
class ExportSettings: ObservableObject {
    static let shared = ExportSettings()
    
    private let formatKey = "exportFormat"
    private let qualityKey = "exportQuality"
    private let hdrKey = "exportHDR"
    
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
    
    /// HDR 导出开关（仅付费会员可用）
    @Published var hdrEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hdrEnabled, forKey: hdrKey)
        }
    }
    
    private init() {
        if let savedFormat = UserDefaults.standard.string(forKey: formatKey),
           let format = ExportFormat(rawValue: savedFormat) {
            self.format = format
        } else {
            self.format = .jpeg
        }
        
        if let savedQuality = UserDefaults.standard.string(forKey: qualityKey),
           let quality = ExportQuality(rawValue: savedQuality) {
            self.quality = quality
        } else {
            self.quality = .high
        }
        
        if let savedHDR = UserDefaults.standard.object(forKey: hdrKey) as? Bool {
            self.hdrEnabled = savedHDR
        } else {
            self.hdrEnabled = false
        }
    }
}
