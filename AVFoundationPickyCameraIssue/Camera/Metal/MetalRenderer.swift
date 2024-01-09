//
//  Renderer.swift
//  PhotonCam
//
//  Created by Photon Juniper on 2023/10/27.
//

import Foundation
import Metal
import MetalKit
import CoreImage

private let maxBuffersInFlight = 3

public final class MetalRenderer: NSObject, MTKViewDelegate, ObservableObject {
    @Published var requestedDisplayedTime = CFAbsoluteTimeGetCurrent()
    
    public let device: MTLDevice
    
    let commandQueue: MTLCommandQueue
    var ciContext: CIContext? = nil
    var opaqueBackground: CIImage
    let startTime: CFAbsoluteTime
    
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    
    var scaleToFill: Bool = false
    
    private var displayedImage: CIImage? = nil
    
    public override init() {
        let start = CFAbsoluteTimeGetCurrent()
        self.device = MTLCreateSystemDefaultDevice()!
        self.commandQueue = self.device.makeCommandQueue()!
        self.opaqueBackground = CIImage.black
        
        self.startTime = CFAbsoluteTimeGetCurrent()
        
        debugPrint("MetalRenderer init \(CFAbsoluteTimeGetCurrent() - start)s")
        super.init()
    }
    
    /// The the background color to be composited with.
    /// If the color is not opaque, please remember to set ``isOpaque`` in ``MetalView``.
    public func setBackgroundColor(ciColor: CIColor) {
        self.opaqueBackground = CIImage(color: ciColor)
    }
    
    public func setScaleToFill(scaleToFill: Bool) {
        self.scaleToFill = scaleToFill
    }
    
    /// Initialize the CIContext with a specified working ``CGColorSpace``.
    public func initializeCIContext(colorSpace: CGColorSpace?, name: String) {
        let start = CFAbsoluteTimeGetCurrent()
        
        // Set up the Core Image context's options:
        // - Name the context to make CI_PRINT_TREE debugging easier.
        // - Disable caching because the image differs every frame.
        // - Allow the context to use the low-power GPU, if available.
        var options = [CIContextOption: Any]()
        options = [
            .name: name,
            .cacheIntermediates: false,
            .allowLowPower: true,
        ]
        if let colorSpace = colorSpace {
            options[.workingColorSpace] = colorSpace
        }
        self.ciContext = CIContext(
            mtlCommandQueue: self.commandQueue,
            options: options
        )
        
        debugPrint("MetalRenderer initializeCIContext \(CFAbsoluteTimeGetCurrent() - start)s, name: \(name) to color space: \(String(describing: colorSpace))")
    }
    
    /// Request update the image.
    public func requestChanged(displayedImage: CIImage?) {
        self.displayedImage = displayedImage
        self.requestedDisplayedTime = CFAbsoluteTimeGetCurrent()
    }
    
    /// - Tag: draw
    public func draw(in view: MTKView) {
        guard let ciContext = ciContext else {
            debugPrint("CIContext is nil!")
            return
        }
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            // Add a completion handler that signals `inFlightSemaphore` when Metal and the GPU have fully
            // finished processing the commands that the app encoded for this frame.
            // This completion indicates that Metal and the GPU no longer need the dynamic buffers that
            // Core Image writes to in this frame.
            // Therefore, the CPU can overwrite the buffer contents without corrupting any rendering operations.
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
                semaphore.signal()
            }
            
            if let drawable = view.currentDrawable {
                let dSize = view.drawableSize
                
                // Create a destination the Core Image context uses to render to the drawable's Metal texture.
                let destination = CIRenderDestination(
                    width: Int(dSize.width),
                    height: Int(dSize.height),
                    pixelFormat: view.colorPixelFormat,
                    commandBuffer: nil
                ) {
                    return drawable.texture
                }
                
                // Create a displayable image for the current time.
                guard var image = self.displayedImage else {
                    return
                }
                
                let scaleW = CGFloat(dSize.width) / image.extent.width
                let scaleH = CGFloat(dSize.height) / image.extent.height
                
                // To perfrom scaledToFit, use min. Use max for scaledToFill effect.
                let scale: CGFloat
                if scaleToFill {
                    scale = max(scaleW, scaleH)
                } else {
                    scale = min(scaleW, scaleH)
                }
                
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                
                // Center the image in the view's visible area.
                let iRect = image.extent
                var backBounds = CGRect(x: 0, y: 0, width: dSize.width, height: dSize.height)
                
                let shiftX: CGFloat
                let shiftY: CGFloat
                
                shiftX = round((backBounds.size.width + iRect.origin.x - iRect.size.width) * 0.5)
                shiftY = round((backBounds.size.height + iRect.origin.y - iRect.size.height) * 0.5)
                
                // Read the center port of the image.
                backBounds = backBounds.offsetBy(dx: -shiftX, dy: -shiftY)
                
                // Blend the image over an opaque background image.
                // This is needed if the image is smaller than the view, or if it has transparent pixels.
                image = image.composited(over: self.opaqueBackground)
                
                // Start a task that renders to the texture destination.
                _ = try? ciContext.startTask(
                    toRender: image,
                    from: backBounds,
                    to: destination,
                    at: .zero
                )
                
                // Insert a command to present the drawable when the buffer has been scheduled for execution.
                commandBuffer.present(drawable)
                
                // Commit the command buffer so that the GPU executes the work that the Core Image Render Task issues.
                commandBuffer.commit()
            }
        }
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Respond to drawable size or orientation changes.
    }
}
