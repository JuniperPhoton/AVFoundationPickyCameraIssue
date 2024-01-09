//
//  AppLogger.swift
//  AVFoundationPickyCameraIssue
//
//  Created by Photon Juniper on 2024/1/9.
//

import Foundation
import OSLog

class AppLogger {
    static let camera = Logger(subsystem: "com.juniperphoton.demo", category: "camera")
    static let photoLibrary = Logger(subsystem: "com.juniperphoton.demo", category: "photoLibrary")
}
