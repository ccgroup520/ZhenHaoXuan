//
//  ZhenHaoXuanApp.swift
//  ZhenHaoXuan
//
//  Created by 两颗银盐 on 2026/4/7.
//

import SwiftUI

@main
struct ZhenHaoXuanApp: App {
    // 确保VIPManager在应用启动时初始化
    @StateObject private var vipManager = VIPManager.shared
    @StateObject private var userProfile = UserProfileManager.shared

    init() {
        // 启动时清理上次运行残留的临时视频文件。
        DispatchQueue.global(qos: .utility).async {
            MediaTempStore.removeAll()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vipManager)
                .environmentObject(userProfile)
        }
    }
}
