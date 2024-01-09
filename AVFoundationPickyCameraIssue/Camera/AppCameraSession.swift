//
//  CamSession.swift
//  AVFoundationPickyCameraIssue
//
//  Created by Photon Juniper on 2024/1/9.
//

import Foundation
import AVFoundation
import CoreImage

struct AVCaptureDeviceInfo {
    let device: AVCaptureDevice
    let isMain: Bool
    let isBack: Bool
}

class AppCameraSession: NSObject {
    var onPreview: ((CIImage?) -> Void)? = nil
    var onFirstFrame: (() -> Void)? = nil
    var onBeginCapture: (() -> Void)? = nil
    var isSwitchingLens = false
    
    var previewSize: CGSize = .zero
    
    var bypassFilters = false
    var zoomedFactor = 1.0
    
    let cameraSettings: CameraSettings
    let processor: CameraProcessor
    
    private var triggerFirstFrameCallback = false
    
    private(set) var captureSession: AVCaptureSession? = nil
    private(set) var photoOutput: AVCapturePhotoOutput? = nil
    
    private var videoOutput: AVCaptureVideoDataOutput? = nil
    private var device: AVCaptureDevice? = nil
    private var deviceInput: AVCaptureDeviceInput? = nil
    
    private(set) var supportedDevices = [AVCaptureDeviceInfo]()
    
    private var captureContinuation: CheckedContinuation<Bool, Never>? = nil
    private let previewQueue = DispatchQueue(label: "preview_queue")
    private let main = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    
    init(settings: CameraSettings, processor: CameraProcessor) {
        self.cameraSettings = settings
        self.processor = processor
    }
    
    func stop() async -> Bool {
        if self.captureSession == nil {
            return false
        }
        
        self.captureSession?.stopRunning()
        self.triggerFirstFrameCallback = false
        self.onPreview?(nil)
        return true
    }
    
    func discoverDevices() async -> [AVCaptureDeviceInfo] {
        guard let main = main else {
            AppLogger.camera.error("no main camera")
            return []
        }
        
        let backDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera,
            ],
            mediaType: .video,
            position: .back
        )
        
        let frontDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .front
        )
        
        var supportedDevices = backDiscoverySession.devices
        
        for frontDevice in frontDiscoverySession.devices {
            supportedDevices.insert(frontDevice, at: 0)
        }
        
        AppLogger.camera.log("supportedDevices \(supportedDevices.count)")
        
        self.supportedDevices = supportedDevices.map { device in
            return AVCaptureDeviceInfo(
                device: device,
                isMain: device.modelID == main.modelID,
                isBack: device.position == .back
            )
        }
        
        return self.supportedDevices
    }
    
    @discardableResult
    func setupSession(
        selectedDeviceInfo: AVCaptureDeviceInfo,
        shouldReconstructCamera: Bool
    ) async -> AVCaptureSession? {
        let isAuthorized = CamAuthorization.shared.isAuthorized
        if !isAuthorized, !(await CamAuthorization.shared.requestForPermission()) {
            AppLogger.camera.error("failed to get authorization from camera")
            return nil
        }
        
        if self.captureSession != nil && !shouldReconstructCamera {
            AppLogger.camera.info("setupSession, but found captureSession, start running...")
            configureOutput(photoOutput: photoOutput, videoOutput: videoOutput, device: device)
            self.captureSession?.startRunning()
            return captureSession
        }
        
        self.captureSession?.stopRunning()
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let captureSession = AVCaptureSession()
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo
        
        let selectedDevice = selectedDeviceInfo.device
        
        AppLogger.camera.info("setup session with device \(String(describing: selectedDeviceInfo))")
        
        guard
            let videoDeviceInput = try? AVCaptureDeviceInput(device: selectedDevice),
            captureSession.canAddInput(videoDeviceInput)
        else {
            AppLogger.camera.error("failed to add video device input")
            return nil
        }
        
        captureSession.addInput(videoDeviceInput)
        
        if !addOutputs(session: captureSession) {
            return nil
        }
        
        self.deviceInput = videoDeviceInput
        self.device = selectedDevice
        self.captureSession = captureSession
        
        self.configureOutput(photoOutput: photoOutput, videoOutput: videoOutput, device: device)
        
        captureSession.commitConfiguration()
        captureSession.startRunning()
        
        AppLogger.camera.info("setup captureSession completed, duration: \(CFAbsoluteTimeGetCurrent() - startTime)s")
        
        return captureSession
    }
    
    private func addOutputs(session: AVCaptureSession) -> Bool {
        if let existPhotoOutput = self.photoOutput {
            session.removeOutput(existPhotoOutput)
        }
        
        let photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.sessionPreset = .photo
            session.addOutput(photoOutput)
            self.photoOutput = photoOutput
        } else {
            AppLogger.camera.error("failed to add photoOutput")
            return false
        }
        
        if let existVideoOutput = self.videoOutput {
            session.removeOutput(existVideoOutput)
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            self.videoOutput = videoOutput
        } else {
            AppLogger.camera.error("Could not add video device output to the session")
            return false
        }
        
        return true
    }
    
    private func configureOutput(
        photoOutput: AVCapturePhotoOutput?,
        videoOutput: AVCaptureVideoDataOutput?,
        device: AVCaptureDevice?
    ) {
        guard let photoOutput = photoOutput,
              let videoDevice = device,
              let videoOutput = videoOutput else {
            return
        }
        
        photoOutput.isAppleProRAWEnabled = photoOutput.isAppleProRAWSupported
        photoOutput.isContentAwareDistortionCorrectionEnabled = photoOutput.isContentAwareDistortionCorrectionSupported
        photoOutput.maxPhotoQualityPrioritization = .quality
        
        AppLogger.camera.log("set photoOutput.isAppleProRAWEnabled to \(photoOutput.isAppleProRAWEnabled)")
        
        if let dimensions = videoDevice.activeFormat.supportedMaxPhotoDimensions.last {
            photoOutput.maxPhotoDimensions = dimensions
            AppLogger.camera.log("set photoOutput.maxPhotoDimensions to \(String(describing: dimensions))")
        }
        
        videoOutput.automaticallyConfiguresOutputBufferDimensions = false
        videoOutput.deliversPreviewSizedOutputBuffers = true
        
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
        
        videoOutput.setSampleBufferDelegate(self, queue: previewQueue)
    }
    
    func zoom(factor: CGFloat, animated: Bool) {
        guard let device = self.device else {
            return
        }
        
        self.zoomedFactor = factor
        
        do {
            defer {
                device.unlockForConfiguration()
            }
            
            try device.lockForConfiguration()
            
            if animated {
                device.ramp(toVideoZoomFactor: factor, withRate: 30)
            } else {
                device.videoZoomFactor = factor
            }
        } catch {
            // ignored
        }
    }
    
    func switchLens(modelId: String) async {
        guard let session = captureSession, let deviceInput = deviceInput else {
            return
        }
        
        await MainActor.run {
            isSwitchingLens = true
        }
        
        session.stopRunning()
        session.beginConfiguration()
        session.removeInput(deviceInput)
        
        let device = supportedDevices.first { info in
            info.device.modelID == modelId
        }
        
        if let device = device, let newDeviceInput = try? AVCaptureDeviceInput(device: device.device) {
            if session.canAddInput(newDeviceInput) {
                session.addInput(newDeviceInput)
                
                self.deviceInput = newDeviceInput
                self.device = device.device
            }
        }
        
        if !addOutputs(session: session) {
            return
        }
        
        configureOutput(photoOutput: photoOutput, videoOutput: videoOutput, device: device?.device)
        
        session.commitConfiguration()
        session.startRunning()
        
        await MainActor.run {
            self.isSwitchingLens = false
        }
    }
    
    func capturePhoto() async -> Bool {
        guard let photoOutput = photoOutput else {
            AppLogger.camera.error("capturePhoto but photo output is nil")
            return false
        }
        
        let photoSettings: AVCapturePhotoSettings
        
        let availableFormats = photoOutput.availableRawPhotoPixelFormatTypes
        AppLogger.camera.log("capture photo availableRawPhotoPixelFormatTypes: \(availableFormats.count)")
        
        let proRawFormat = availableFormats.first { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
        let bayerRawFormat = availableFormats.first { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }
        
        var rawFormat: OSType? = proRawFormat ?? bayerRawFormat
        let processedFormat = [AVVideoCodecKey: AVVideoCodecType.hevc]
        
        if zoomedFactor != 1.0 {
            rawFormat = nil
        }
        
        // Retrieve the RAW format, favoring the Apple ProRAW format when it's in an enabled state.
        if cameraSettings.useRaw, let rawFormat = rawFormat {
            AppLogger.camera.log("capture using raw")
            
            photoSettings = AVCapturePhotoSettings(
                rawPixelFormatType: rawFormat,
                processedFormat: processedFormat
            )
            
            // Select the first available codec type, which is JPEG.
            // This type is used as raw thumbnail.
            guard let thumbnailPhotoCodecType =
                    photoSettings.availableRawEmbeddedThumbnailPhotoCodecTypes.first else {
                // Handle the failure to find an available thumbnail photo codec type.
                AppLogger.camera.error("error to find availableRawEmbeddedThumbnailPhotoCodecTypes")
                return false
            }
            
            // Select the maximum photo dimensions as thumbnail dimensions if a full-size thumbnail is desired.
            // The system clamps these dimensions to the photo dimensions if the capture produces a photo with smaller than maximum dimensions.
            let dimensions = photoSettings.maxPhotoDimensions
            photoSettings.rawEmbeddedThumbnailPhotoFormat = [
                AVVideoCodecKey: thumbnailPhotoCodecType,
                AVVideoWidthKey: dimensions.width > 0 ? dimensions.width : 10000,
                AVVideoHeightKey: dimensions.height > 0 ? dimensions.height : 10000,
            ]
        } else {
            AppLogger.camera.error("error to find raw format isAppleProRAWEnabled: \(photoOutput.isAppleProRAWEnabled)")
            photoSettings = AVCapturePhotoSettings(format: processedFormat)
        }
        
        if let supportedDimensions = device?.activeFormat.supportedMaxPhotoDimensions,
           let max = supportedDimensions.last,
           let min = supportedDimensions.first {
            let dimensions: CMVideoDimensions
            
            // If we uses 1.2 or 1.5x zoom scale factor and the maximum 48MP dimensions,
            // the output photo's exposure and the preview's won't match.
            // Change the maxPhotoDimensions can fix this issue.
            if zoomedFactor > 1.0 && cameraSettings.fixZoomedExposure {
                dimensions = min
            } else {
                dimensions = max
            }
            
            photoSettings.maxPhotoDimensions = dimensions
        }
        
        if let photoOutputConnection = photoOutput.connection(with: .video) {
            if photoOutputConnection.isVideoOrientationSupported {
                photoOutputConnection.videoOrientation = .portrait
            }
        }
        
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.captureContinuation = continuation
        }
    }
}

extension AppCameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if isSwitchingLens {
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let _ = onPreview else {
            return
        }
        
        if !triggerFirstFrameCallback {
            if let onFirstFrame = onFirstFrame {
                triggerFirstFrameCallback = true
                onFirstFrame()
            }
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        self.onPreview?(ciImage)
    }
}

extension AppCameraSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        AppLogger.camera.log("photoOutput willCapturePhotoFor")
        onBeginCapture?()
        processor.onBeginCaptured(resolvedSettings: resolvedSettings)
    }
    
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        AppLogger.camera.log("photoOutput didCapturePhotoFor")
    }
    
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        AppLogger.camera.log("photoOutput didFinishProcessingPhoto, isRawPhoto \(photo.isRawPhoto) error \(error)")
        if error == nil {
            if processor.onCaptured(photo: photo) {
                captureContinuation?.resume(returning: true)
                captureContinuation = nil
            }
        } else {
            captureContinuation?.resume(returning: false)
            captureContinuation = nil
        }
    }
    
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        AppLogger.camera.log("photoOutput didFinishCaptureFor \(error)")
        captureContinuation?.resume(returning: error == nil)
        captureContinuation = nil
    }
}
