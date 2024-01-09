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
    let processor: CameraProcessor = CameraProcessor()
    
    @Published var showCaptureAnimation = false
    
    private var cancellables = [AnyCancellable]()
    
    init() {
        renderer.initializeCIContext(colorSpace: nil, name: "preview")
        camSession = AppCameraSession(settings: cameraSettings, processor: processor)
        
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
        
        cameraSettings.$zoomedIn.receive(on: DispatchQueue.main)
            .sink { [weak self] output in
                guard let self = self else {
                    return
                }
                if output {
                    camSession.zoom(factor: 1.5, animated: true)
                } else {
                    camSession.zoom(factor: 1, animated: true)
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
        
        camSession.onPreview = { [weak self] image in
            guard let self = self else {
                return
            }
            DispatchQueue.main.async {
                self.renderer.requestChanged(displayedImage: image)
            }
        }
        
        camSession.onBeginCapture = { [weak self] in
            guard let self = self else {
                return
            }
            
            DispatchQueue.main.async {
                self.toggleCaptureAnimation()
            }
        }
        
        let session = await camSession.setupSession(selectedDeviceInfo: main, shouldReconstructCamera: true)
        
        guard session != nil else {
            return
        }
        
        if cameraSettings.fixRawShift {
            applyZoomFactorFix()
        }
        
        if cameraSettings.zoomedIn {
            camSession.zoom(factor: 1.5, animated: false)
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
    
    private func toggleCaptureAnimation() {
        showCaptureAnimation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showCaptureAnimation = false
        }
    }
}
