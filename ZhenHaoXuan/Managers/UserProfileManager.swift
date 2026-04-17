//
//  UserProfileManager.swift
//  ZhenHaoXuan
//
//  用户资料管理器 - 处理Apple账户头像和用户信息
//

import Foundation
import SwiftUI
import Combine
import AuthenticationServices

class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()
    
    // MARK: - Published Properties
    @Published var userName: String = "用户"
    @Published var userImage: UIImage?
    @Published var isSignedIn: Bool = false
    
    // MARK: - UserDefaults Keys
    private let userNameKey = "userName"
    private let userImageDataKey = "userImageData"
    private let isSignedInKey = "isSignedIn"
    
    // MARK: - Initialization
    private init() {
        loadUserProfile()
    }
    
    // MARK: - User Profile Management
    
    private func loadUserProfile() {
        userName = UserDefaults.standard.string(forKey: userNameKey) ?? "用户"
        isSignedIn = UserDefaults.standard.bool(forKey: isSignedInKey)
        
        if let imageData = UserDefaults.standard.data(forKey: userImageDataKey) {
            userImage = UIImage(data: imageData)
        }
    }
    
    func saveUserProfile(name: String, image: UIImage?) {
        userName = name
        UserDefaults.standard.set(name, forKey: userNameKey)
        
        if let image = image, let imageData = image.jpegData(compressionQuality: 0.8) {
            userImage = image
            UserDefaults.standard.set(imageData, forKey: userImageDataKey)
        } else {
            userImage = nil
            UserDefaults.standard.removeObject(forKey: userImageDataKey)
        }
        
        isSignedIn = true
        UserDefaults.standard.set(true, forKey: isSignedInKey)
    }
    
    func clearUserProfile() {
        userName = "用户"
        userImage = nil
        isSignedIn = false
        
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: userImageDataKey)
        UserDefaults.standard.set(false, forKey: isSignedInKey)
    }
    
    // MARK: - Apple Sign In
    
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let components = [
                    appleIDCredential.fullName?.familyName,
                    appleIDCredential.fullName?.givenName
                ]
                let suppliedName = components
                    .compactMap { $0 }
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let name = suppliedName.isEmpty ? (isSignedIn ? userName : "Apple用户") : suppliedName
                
                // 尝试获取头像（Apple Sign In 不直接提供头像，使用占位图或默认头像）
                let defaultImage = createDefaultAvatar(name: name)
                
                saveUserProfile(name: name, image: defaultImage)
            }
            
        case .failure(let error):
            print("Apple Sign In failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Default Avatar
    
    func createDefaultAvatar(name: String) -> UIImage {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let initial = String(name.prefix(1)).uppercased()
        
        let image = renderer.image { context in
            // 背景渐变
            let gradientColors = [
                UIColor.systemBlue.cgColor,
                UIColor.systemPurple.cgColor
            ]
            
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: gradientColors as CFArray,
                locations: [0, 1]
            )!
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            
            // 文字
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 80, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            
            let textSize = initial.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            initial.draw(in: textRect, withAttributes: attributes)
        }
        
        return image
    }
}
