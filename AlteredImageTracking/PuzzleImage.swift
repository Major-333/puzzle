//
//  PuzzleImage.swift
//  AlteredImageTracking
//
//  Created by Major333 on 2021/8/12.
//  Copyright © 2021 Apple. All rights reserved.
//

import Foundation
import ARKit

class PuzzleMesh{

    private let puzzleImage : CVPixelBuffer

    let referenceImage: ARReferenceImage

    /// A handle to the anchor ARKit assigned the tracked image.
    private(set) var anchor: ARImageAnchor?

    /// A SceneKit node that animates images of varying style.
    private let visualizationNode: VisualizationNode

    /// Stores a reference to the Core ML output image.
    private var modelOutputImage: CVPixelBuffer?

    private var fadeBetweenStyles = true

    /// A timer that effects a grace period before checking
    ///  for a new rectangular shape in the user's environment.
    private var failedTrackingTimeout: Timer?

    /// The timeout in seconds after which the `imageTrackingLost` delegate is called.
    private var timeout: TimeInterval = 10.0

    /// Increments the style index that's input into the Core ML model.
    /// - Tag: SelectNextStyle
    func selectNextStyle() {
//        print("call SelectNextStyle")
    }

    /// A delegate to tell when image tracking fails.
    weak var delegate: PuzzleMeshDelegate?

    /// Stores a reference to the Puzzle image.
    init?(_ image: CIImage, referenceImage: ARReferenceImage) {

        let tmpImage = UIImage(named: "001.jpeg")
        self.puzzleImage = PuzzleMesh.myImageConverter(from: tmpImage!)!

        self.referenceImage = referenceImage
        visualizationNode = VisualizationNode(referenceImage.physicalSize)

        visualizationNode.delegate = self

        // Start the failed tracking timer right away. This ensures that the app starts
        //  looking for a different image to track if this one isn't trackable.
        resetImageTrackingTimeout()

        // Start altering an image with the next style.
        createAlteredImage()

    }

    deinit {
        visualizationNode.removeAllAnimations()
        visualizationNode.removeFromParentNode()
    }

    /// Displays the altered image using the anchor and node provided by ARKit.
    /// - Tag: AddVisualizationNode
    func add(_ anchor: ARAnchor, node: SCNNode) -> Bool{
        if let imageAnchor = anchor as? ARImageAnchor, imageAnchor.referenceImage == referenceImage {
            self.anchor = imageAnchor

            // Start the image tracking timeout.
            resetImageTrackingTimeout()

            // Add the node that displays the altered image to the node graph.
            node.addChildNode(visualizationNode)

            // If altering the first image completed before the
            //  anchor was added, display that image now.
            if let createdImage = modelOutputImage {
                visualizationNode.display(createdImage)
            }
            return true
        }
        return false
    }

    /**
     If an image the app was tracking is no longer tracked for a given amount of time, invalidate
     the current image tracking session. This, in turn, enables Vision to start looking for a new
     rectangular shape in the camera feed.
     - Tag: AnchorWasUpdated
     */
    func update(_ anchor: ARAnchor) -> Bool{
        if let imageAnchor = anchor as? ARImageAnchor, self.anchor == anchor {
            self.anchor = imageAnchor
            // Reset the timeout if the app is still tracking an image.
            if imageAnchor.isTracked {
                resetImageTrackingTimeout()
            }
            return true
        }
        return false
    }

    /// Toggles whether the app animates successive styles of the altered image.
    func pauseOrResumeFade() {
        guard visualizationNode.parent != nil else { return }

        fadeBetweenStyles.toggle()
//        fadeBetweenStyles = true
        if fadeBetweenStyles {
            ViewController.instance?.showMessage("Resume fading between styles.")
        } else {
            ViewController.instance?.showMessage("Pause fading between styles.")
        }
        visualizationNodeDidFinishFade(visualizationNode)
    }

    /// Prevents the image tracking timeout from expiring.
    private func resetImageTrackingTimeout() {
        failedTrackingTimeout?.invalidate()
        failedTrackingTimeout = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            if let strongSelf = self {
                self?.delegate?.alteredImageLostTracking(strongSelf)
            }
        }
    }

    /// Alters the image's appearance by applying the "StyleTransfer" Core ML model to it.
    /// - Tag: CreateAlteredImage
    func createAlteredImage() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            self.imageAlteringComplete(self.puzzleImage)
        }
    }

    /// - Tag: DisplayAlteredImage
    func imageAlteringComplete(_ createdImage: CVPixelBuffer) {
        guard fadeBetweenStyles else { return }
        modelOutputImage = createdImage
        visualizationNode.display(createdImage)
    }

    /// If altering the image failed, notify delegate the
    ///  to stop tracking this image.
    func imageAlteringFailed(_ errorDescription: String) {
        print("Error: Altering image failed - \(errorDescription).")
        self.delegate?.alteredImageLostTracking(self)
    }

    static func myImageConverter(from image: UIImage) -> CVPixelBuffer? {
      let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
      var pixelBuffer : CVPixelBuffer?
      let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.size.width), Int(image.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
      guard (status == kCVReturnSuccess) else {
        return nil
      }

      CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
      let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

      let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
      let context = CGContext(data: pixelData, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

      context?.translateBy(x: 0, y: image.size.height)
      context?.scaleBy(x: 1.0, y: -1.0)

      UIGraphicsPushContext(context!)
      image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
      UIGraphicsPopContext()
      CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

      return pixelBuffer
    }
}

/// Start altering an image using the next style if
///  an anchor for this altered image was already added.
extension PuzzleMesh: VisualizationNodeDelegate {
    /// - Tag: FadeAnimationComplete
    func visualizationNodeDidFinishFade(_ visualizationNode: VisualizationNode) {
        guard fadeBetweenStyles, anchor != nil else { return }
        selectNextStyle()
        createAlteredImage()
    }
}

/**
 Tells a delegate when image tracking failed.
  In this case, the delegate is the view controller.
 */
protocol PuzzleMeshDelegate: class {
    func alteredImageLostTracking(_ alteredImage: PuzzleMesh)
}
