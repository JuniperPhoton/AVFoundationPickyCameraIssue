//
//  MainViewModel.swift
//  AVFoundationPickyCameraIssue
//
//  Created by Photon Juniper on 2024/1/9.
//

import SwiftUI
import Combine

class MainViewModel: ObservableObject {
    let renderer: MetalRenderer = MetalRenderer()
    let cameraSettings: CameraSettings = CameraSettings()
    let camSession: AppCameraSession
    
    private var cancellables = [AnyCancellable]()

    init() {
        renderer.initializeCIContext(colorSpace: nil, name: "preview")
        camSession = AppCameraSession(settings: cameraSettings)
        
        cameraSettings.$fixRawShift.receive(on: DispatchQueue.main)
            .sink { [weak self] output in
                guard let self = self else {
                    return
                }
                if output {
                    self.applyZoomFactorFix()
                } else {
                    self.resetZoomFactorFix()
                }
            }
            .store(in: &cancellables)
    }
    
    func setupCamera() async {
        guard await CamAuthorization.shared.requestForPermission() else {
            return
        }
        
        let devices = await camSession.discoverDevices()
        
        guard !devices.isEmpty else {
            return
        }
        
        guard let main = devices.first(where: { $0.isMain }) else {
            return
        }
        
        camSession.onPreview = { image in
            DispatchQueue.main.async {
                self.renderer.requestChanged(displayedImage: image)
            }
        }
        
        let session = await camSession.setupSession(selectedDeviceInfo: main, shouldReconstructCamera: true)
        
        guard session != nil else {
            return
        }
        
        if cameraSettings.fixRawShift {
            applyZoomFactorFix()
        }
    }
    
    func stopCamera() async {
        let _ = await camSession.stop()
    }
    
    func capture() async {
        let _ = await camSession.capturePhoto()
    }
    
    private func applyZoomFactorFix() {
        camSession.zoom(factor: 1.0001, animated: false)
    }
    
    private func resetZoomFactorFix() {
        camSession.zoom(factor: 1.0, animated: false)
    }
}
