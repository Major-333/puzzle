/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view controller that recognizes and tracks images found in the user's environment.
*/

import ARKit
import Foundation
import SceneKit
import UIKit

class ViewController: UIViewController {

    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var messagePanel: UIView!
    @IBOutlet weak var messageLabel: UILabel!

    static var instance: ViewController?
    
    /// An object that detects rectangular shapes in the user's environment.
    let rectangleDetector = RectangleDetector()
    
    /// An object that represents an augmented image that exists in the user's environment.
//    var alteredImage: AlteredImage?
    var alteredImage: PuzzleMesh?
    
    var trackingImages: Set<ARReferenceImage> = []
    
    var alteredImageNum: Int = 2
    var alteredImageList: [PuzzleMesh?] = Array(repeating: nil, count: 2)
    var lastFoundIndex: Int = -1
    
    override func viewDidLoad() {
        super.viewDidLoad()

        rectangleDetector.delegate = self
        sceneView.delegate = self
    }

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
        ViewController.instance = self
		
		// Prevent the screen from being dimmed after a while.
		UIApplication.shared.isIdleTimerDisabled = true
        
        for (index, _) in self.alteredImageList.enumerated(){
            searchForNewImageToTrack(for: index)
        }
	}
    
    func searchForNewImageToTrack(for imageIndex: Int) {
        self.alteredImageList[imageIndex]?.delegate = nil
        self.alteredImageList[imageIndex] = nil
        
        // Restart the session and remove any image anchors that may have been detected previously.
        runImageTrackingSession(with: [], runOptions: [.removeExistingAnchors, .resetTracking])
        
        showMessage("Look for a rectangular image.", autoHide: false)
    }
    
    /// - Tag: ImageTrackingSession
    private func runImageTrackingSession(with trackingImages: Set<ARReferenceImage>,
                                         runOptions: ARSession.RunOptions = [.removeExistingAnchors]) {
        let configuration = ARImageTrackingConfiguration()
        configuration.maximumNumberOfTrackedImages = 2
        configuration.trackingImages = trackingImages
        sceneView.session.run(configuration, options: runOptions)
    }
    
    // The timer for message presentation.
    private var messageHideTimer: Timer?
    
    func showMessage(_ message: String, autoHide: Bool = true) {
        DispatchQueue.main.async {
            self.messageLabel.text = message
            self.setMessageHidden(false)
            
            self.messageHideTimer?.invalidate()
            if autoHide {
                self.messageHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                    self?.setMessageHidden(true)
                }
            }
        }
    }
    
    private func setMessageHidden(_ hide: Bool) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState], animations: {
                self.messagePanel.alpha = hide ? 0 : 1
            })
        }
    }
    
    /// Handles tap gesture input.
    @IBAction func didTap(_ sender: Any) {
        alteredImage?.pauseOrResumeFade()
        for item in alteredImageList{
            item?.pauseOrResumeFade()
        }
    }
    
}

extension ViewController: ARSCNViewDelegate {
    
    /// - Tag: ImageWasRecognized
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        for (index,item) in self.alteredImageList.enumerated(){
            if(item?.add(anchor, node:node) == true){
                break
            }
        }
        setMessageHidden(true)
    }

    /// - Tag: DidUpdateAnchor
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        for (index,item) in self.alteredImageList.enumerated(){
            if(item?.update(anchor) == true){
                break
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard let arError = error as? ARError else { return }
        
        if arError.code == .invalidReferenceImage {
            // Restart the experience, as otherwise the AR session remains stopped.
            // There's no benefit in surfacing this error to the user.
            print("Error: The detected rectangle cannot be tracked.")
            for (index, _) in self.alteredImageList.enumerated(){
                searchForNewImageToTrack(for: index)
            }
            return
        }
        
        let errorWithInfo = arError as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Use `compactMap(_:)` to remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            
            // Present an alert informing about the error that just occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                for (index, _) in self.alteredImageList.enumerated(){
                    self.searchForNewImageToTrack(for: index)
                }
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
}

extension ViewController: MultipleRectangleDetectorDelegate {
    func multilpleRectangleFound(rectangleContentList: [CIImage]) {
        DispatchQueue.main.async {
            guard self.alteredImageList.count == self.alteredImageNum else{
                print("[Error]: Number of alteredImageList is invalid")
                return
            }

            let rectangleContentNum = rectangleContentList.count
//            var trackingImages: Set<ARReferenceImage> = []
            self.trackingImages.removeAll()
            for index in 0 ..< rectangleContentNum{
                let rectangleContent = rectangleContentList[index]
                guard let referenceImagePixelBuffer = rectangleContent.toPixelBuffer(pixelFormat: kCVPixelFormatType_32BGRA) else {
                    print("Error: Could not convert rectangle content into an ARReferenceImage.")
                    return
                }
                let possibleReferenceImage = ARReferenceImage(referenceImagePixelBuffer, orientation: .up, physicalWidth: CGFloat(0.1))
                possibleReferenceImage.validate { [weak self] (error) in
                    if let error = error {
                        print("Reference image validation failed: \(error.localizedDescription)")
                        return
                    }
                }
                guard let newAlteredImage = PuzzleMesh(rectangleContent, referenceImage: possibleReferenceImage) else { return }
                newAlteredImage.delegate = self
                self.alteredImageList[index] = newAlteredImage
                self.trackingImages.insert(newAlteredImage.referenceImage)
            }
            guard self.trackingImages.count > 0 else {
                return
            }
            print("[FOUND]:", rectangleContentNum, self.trackingImages.count, self.trackingImages)
            self.runImageTrackingSession(with: self.trackingImages)
        }
    }
}

/// Enables the app to create a new image from any rectangular shapes that may exist in the user's environment.
//extension ViewController: AlteredImageDelegate {
//    func alteredImageLostTracking(_ alteredImage: AlteredImage) {
//        searchForNewImageToTrack()
//    }
//}

extension ViewController: PuzzleMeshDelegate {
    func alteredImageLostTracking(_ alteredImage: PuzzleMesh) {
        for (index, item) in self.alteredImageList.enumerated(){
            if item === alteredImage {
                print("[WARNNING]", index)
                searchForNewImageToTrack(for: index)
                return
            }
        }
        print("[ERROR] in alteredImageLostTracking")
    }
}
