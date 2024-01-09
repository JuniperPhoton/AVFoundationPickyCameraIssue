//
//  File.swift
//  AVFoundationPickyCameraIssue
//
//  Created by Photon Juniper on 2024/1/9.
//

import Foundation
import AVFoundation
import CoreImage
import Photos

private class PendingCapturedPhotoToProcess {
    var raw: AVCapturePhoto? = nil
    var processed: AVCapturePhoto? = nil
    var context: CapturedPhotoContext
    
    init(raw: AVCapturePhoto? = nil, processed: AVCapturePhoto? = nil, context: CapturedPhotoContext) {
        self.raw = raw
        self.processed = processed
        self.context = context
    }
    
    var availableCount: Int {
        return [raw, processed].filter { $0 != nil }.count
    }
}

private struct CapturedPhotoContext {
    var resolvedSettings: AVCaptureResolvedPhotoSettings
    
    var id: Int64 {
        resolvedSettings.uniqueID
    }
}

class CameraProcessor: ObservableObject {
    private var pendingToArchive = [Int64: PendingCapturedPhotoToProcess]()
    
    @Published var savedFile: URL? = nil
    @Published var processing = false
    
    func onBeginCaptured(
        resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        let context = CapturedPhotoContext(
            resolvedSettings: resolvedSettings
        )
        let pendingPhoto = PendingCapturedPhotoToProcess(context: context)
        pendingToArchive[context.id] = pendingPhoto
        
        AppLogger.photoLibrary.log("onBeginCaptured, expected count: \(resolvedSettings.expectedPhotoCount), for id: \(context.id)")
    }
    
    func onCaptured(photo: AVCapturePhoto) -> Bool {
        guard let pending = pendingToArchive[photo.resolvedSettings.uniqueID] else {
            AppLogger.photoLibrary.log("onCaptured photo but pendingToArchive is nil for id: \(photo.resolvedSettings.uniqueID)")
            return false
        }
        
        let context = pending.context
        
        AppLogger.photoLibrary.log("onCaptured photo for id: \(context.resolvedSettings.uniqueID), isRaw: \(photo.isRawPhoto)")
        
        if photo.isRawPhoto {
            pending.raw = photo
        } else {
            pending.processed = photo
        }
        
        if pending.availableCount == context.resolvedSettings.expectedPhotoCount {
            startProcess(context: context, pending: pending)
            pendingToArchive.removeValue(forKey: context.id)
            return true
        } else {
            AppLogger.photoLibrary.log("onCaptured photo but pending captured photo is incomplete, current count: \(pending.availableCount), expected: \(context.resolvedSettings.expectedPhotoCount)")
        }
        
        return false
    }
    
    private func startProcess(context: CapturedPhotoContext, pending: PendingCapturedPhotoToProcess) {
        let raw = pending.raw
        let processed = pending.processed
        
        Task { @MainActor in
            self.processing = true
            self.savedFile = await processSave(rawPhoto: raw, processed: processed)
            self.processing = false
        }
    }
    
    private func processSave(
        rawPhoto: AVCapturePhoto?,
        processed: AVCapturePhoto? = nil
    ) async -> URL? {
        let rawFile = await saveRawToFile(photo: rawPhoto)
        let heifFile = await saveProcessedToFile(photo: processed)
        if let heifFile = heifFile {
            let _ = await saveMediaFileToAlbum(processedURL: heifFile, rawURL: rawFile, deleteOnComplete: true)
        }
        return nil
    }
    
    private func saveRawToFile(photo: AVCapturePhoto?) async -> URL? {
        guard let photo = photo, let rawData = photo.fileDataRepresentation() else {
            return nil
        }
        
        guard let rawFile = createTempFileToSave(
            originalFilename: UUID().uuidString,
            subDirName: "demo",
            extensions: "dng"
        ) else {
            return nil
        }
        
        do {
            try rawData.write(to: rawFile)
            return rawFile
        } catch {
            return nil
        }
    }
    
    private func saveProcessedToFile(photo: AVCapturePhoto?) async -> URL? {
        guard let photo = photo else {
            return nil
        }
        
        guard let processedData = photo.fileDataRepresentation() else {
            return nil
        }
        
        guard let processedFile = createTempFileToSave(
            originalFilename: UUID().uuidString,
            subDirName: "demo",
            extensions: "heic"
        ) else {
            return nil
        }
        
        do {
            try processedData.write(to: processedFile)
            return processedFile
        } catch {
            return nil
        }
    }
}

private func createTempFileToSave(
    originalFilename: String,
    subDirName: String? = nil,
    extensions: String
) -> URL? {
    guard var cacheDir = try? FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    ) else {
        print("error on create cache url for file")
        return nil
    }
    
    if let subDirName = subDirName,
       let dir = URL(string: "\(cacheDir.absoluteString)\(subDirName)/") {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            cacheDir = dir
        } catch {
            return nil
        }
    }
    
    guard let name = NSString(string: originalFilename).deletingPathExtension
        .addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) else {
        print("createTempFileToSave failed for name \(originalFilename)")
        return nil
    }
    
    let fileName = name  + "." + extensions
    
    let url = URL(string: "\(cacheDir.absoluteString)\(fileName)")
    
    if let url = url, FileManager.default.fileExists(atPath: url.path) {
        try? FileManager.default.removeItem(at: url)
    }
    
    return url
}

private func saveMediaFileToAlbum(
    processedURL: URL,
    rawURL: URL? = nil,
    deleteOnComplete: Bool
) async -> Bool {
    guard await requestForPermission() else {
        return false
    }
    
    return await withCheckedContinuation { continuation in
        PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = deleteOnComplete
            creationRequest.addResource(
                with: .photo,
                fileURL: processedURL,
                options: options
            )
            
            if let rawURL = rawURL {
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = deleteOnComplete
                creationRequest.addResource(
                    with: .alternatePhoto,
                    fileURL: rawURL,
                    options: options
                )
            }
        } completionHandler: { success, error in
            if deleteOnComplete {
                do {
                    if let rawURL = rawURL {
                        try FileManager.default.removeItem(at: rawURL.absoluteURL)
                    }
                    try FileManager.default.removeItem(at: processedURL.absoluteURL)
                } catch {
                    // ignored
                }
            }
            
            continuation.resume(returning: success)
        }
    }
}

private func requestForPermission() async -> Bool {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    if status == .authorized || status == .limited {
        return true
    }
    return false
}
