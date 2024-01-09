//
//  CamAuthorization.swift
//  AVFoundationPickyCameraIssue
//
//  Created by Photon Juniper on 2024/1/9.
//

import Foundation
import AVFoundation

class CamAuthorization {
    static let shared = CamAuthorization()
    
    var isAuthorized: Bool {
        get {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            // Determine if the user previously authorized camera access.
            return status == .authorized
        }
    }
    
    var isDenied: Bool {
        get {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            // Determine if the user previously authorized camera access.
            return status == .denied || status == .restricted
        }
    }
    
    private init() {
        // empty
    }
    
    func requestForPermission() async -> Bool {
        return await AVCaptureDevice.requestAccess(for: .video)
    }
}
