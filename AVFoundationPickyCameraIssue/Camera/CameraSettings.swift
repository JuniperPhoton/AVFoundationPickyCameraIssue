//
//  File.swift
//  AVFoundationPickyCameraIssue
//
//  Created by Photon Juniper on 2024/1/9.
//

import Foundation

class CameraSettings: ObservableObject {
    @Published var useRaw = true
    @Published var fixRawShift = false
}
