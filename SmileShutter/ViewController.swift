//
//  ViewController.swift
//  SmileShutter
//
//  Copyright © KeisukeKonishi. All rights reserved.
//

import UIKit
import AVFoundation
import CoreImage

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    
    //顔認識
    var detector: CIDetector!
    
    //カメラ設定
    var mySession: AVCaptureSession!
    var myCamera:AVCaptureDevice!
    var myVideoInput: AVCaptureDeviceInput!
    var myVideoOutput: AVCaptureVideoDataOutput!
    var myPhotoOutput: AVCapturePhotoOutput!
    
    //表示
    var faceView = UIView()
    //シャッターフラグ
    var shutterFlag:Bool = true
    //フレームカウント
    var frameCnt = 0;
    //
    var focusPoint:CGPoint!
    //
    let speech = AVSpeechSynthesizer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        detector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy:CIDetectorAccuracyHigh])
        
        prepareVideo()
    }
    
    func prepareVideo(){
    
        //接続
        mySession = AVCaptureSession()
        mySession.sessionPreset = AVCaptureSessionPresetHigh
    
        //接続先
        myCamera = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        let input = try!AVCaptureDeviceInput(device: myCamera)
        mySession.addInput(input)
    
        //ビデオ設定
        myVideoOutput = AVCaptureVideoDataOutput()
        myVideoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable:Int(kCVPixelFormatType_32BGRA)]
        
        //myVideoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
        myVideoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "myqueue"))
        myVideoOutput.alwaysDiscardsLateVideoFrames = true
        mySession.addOutput(myVideoOutput)
        
        //カメラ設定
        myPhotoOutput = AVCapturePhotoOutput()
        myPhotoOutput.isHighResolutionCaptureEnabled = true
        mySession.addOutput(myPhotoOutput)
    
        //画像を表示するレイヤーを生成
        let myVideoLayer:AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer.init(session: mySession)
        myVideoLayer.frame = self.view.bounds
        myVideoLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
        
        //Viewに追加
        self.view.layer.addSublayer(myVideoLayer)
        
        //カメラ向き
        for connection in self.myVideoOutput.connections {
            if let conn = connection as? AVCaptureConnection {
                if conn.isVideoOrientationSupported {
                    conn.videoOrientation = AVCaptureVideoOrientation.portrait
                }
            }
        }
        
        //認識結果表示Viewの設定
        faceView = UIView(frame: self.view.bounds)
        self.view.addSubview(faceView)
        
        mySession.startRunning()
    }
    
    //1フレーム毎の処理
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        
        frameCnt += 1
        
        if frameCnt > 15 {
            //同期処理で顔認識　（非同期ではキューが溜まりすぎるため）
            DispatchQueue.main.async {
                let image = self.UIImageFromCMSampleBuffer(buffer: sampleBuffer)
                self.findFace(image: image)
            }
            frameCnt = 0
        }
    }
    
    //CMSampleBufferをUIImageに変換する
    func UIImageFromCMSampleBuffer(buffer:CMSampleBuffer) -> UIImage{
        // サンプルバッファからピクセルバッファを取り出す
        let pixelBuffer:CVImageBuffer = CMSampleBufferGetImageBuffer(buffer)!
        
        // ピクセルバッファをベースにCoreImageのCIImageオブジェクトを作成
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        //CIImageからCGImageを作成
        let pixelBufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let pixelBufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let imageRect:CGRect = CGRect(x:0,y:0,width:pixelBufferWidth, height:pixelBufferHeight)
        let ciContext = CIContext.init()
        let cgimage = ciContext.createCGImage(ciImage, from: imageRect )
        
        // CGImageからUIImageを作成
        let image = UIImage(cgImage: cgimage!)
        return image
    }
    
    //顔認識処理
    func findFace(image:UIImage){
        guard let faceImage = CIImage(image: image) else{ return }
        
        var smileCount = 0
        var blinkCount = 0
        var faceSize:CGFloat = 0
        
        let faces = detector.features(in: faceImage, options: [CIDetectorSmile:true, CIDetectorEyeBlink:true])
        
        //描画した画像を削除
        for subView:UIView in self.faceView.subviews{
            subView.removeFromSuperview()
        }
        
        //検出した顔毎の処理
        for face in faces as! [CIFaceFeature]{
            
            var faceColor : CGColor = UIColor.blue.cgColor
            
            if face.rightEyeClosed && face.leftEyeClosed{
                faceColor = UIColor.green.cgColor
                blinkCount += 1
                print("EyeClosed: 😑")
            }
            if face.hasSmile{
                print("😁")
                faceColor = UIColor.red.cgColor
                smileCount += 1
            }
            
            //////////////
            //描画処理
            //////////////
            // 座標変換
            var faceRect : CGRect = face.bounds
            let widthPer = (self.view.bounds.width/image.size.width)
            let heightPer = (self.view.bounds.height/image.size.height)
            
            //
            let size = widthPer * heightPer
            if faceSize < size {
                faceSize = size
                focusPoint = CGPoint(x: widthPer, y: heightPer)
            }
            // UIKitは左上に原点があるが、CoreImageは左下に原点があるので揃える
            faceRect.origin.y = image.size.height - faceRect.origin.y - faceRect.size.height
            
            //倍率変換
            faceRect.origin.x = faceRect.origin.x * widthPer
            faceRect.origin.y = faceRect.origin.y * heightPer
            faceRect.size.width = faceRect.size.width * widthPer
            faceRect.size.height = faceRect.size.height * heightPer
            
            // 画像の顔の周りを線で囲うUIViewを生成.
            let faceOutline = UIView(frame: faceRect)
            faceOutline.layer.borderWidth = 1
            faceOutline.layer.borderColor = faceColor
            self.faceView.addSubview(faceOutline)
        }
        
        //検出した顔の数
        if faces.count != 0 {
            print("Number of Faces: \(faces.count)")
            print("Number of Smile: \(smileCount)")
            print("Number of Blink: \(blinkCount)")
            
            if smileCount == faces.count && blinkCount == 0 && self.shutterFlag == true{
                speech(str: "撮ります")
                print("focusPoint : \(focusPoint.x),\(focusPoint.y)")
                takePhoto()
                self.shutterFlag = false
            }
            else{
                speech(str: "笑って")
            }
            
            if blinkCount == faces.count && self.shutterFlag == false{
                self.shutterFlag = true
            }
        }
        //myCamera.unlockForConfiguration()
        
    }
    
    //カメラ撮影
    func takePhoto(){
        let settingPhoto = AVCapturePhotoSettings()
        settingPhoto.flashMode = .auto
        settingPhoto.isAutoStillImageStabilizationEnabled = true
        settingPhoto.isHighResolutionPhotoEnabled = true
        /*
         do{
         try myCamera.lockForConfiguration()
         myCamera.focusMode = .autoFocus
         myCamera.focusPointOfInterest = focusPoint
         myCamera.exposureMode = .autoExpose
         myCamera.exposurePointOfInterest = focusPoint
         //myCamera.unlockForConfiguration()
         //myPhotoOutput.capturePhoto(with: settingPhoto, delegate: self)
         }
         catch{
         
         }
         */
        myPhotoOutput.capturePhoto(with: settingPhoto, delegate: self)
    }
    
    //アルバムに保存
    func capture(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhotoSampleBuffer photoSampleBuffer: CMSampleBuffer?, previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        if let photoSampleBuffer = photoSampleBuffer{
            let photoData = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: photoSampleBuffer, previewPhotoSampleBuffer: previewPhotoSampleBuffer)
            let image = UIImage(data:photoData!)
            UIImageWriteToSavedPhotosAlbum(image!, nil, nil, nil)
        }
    }
    
    //喋る
    func speech(str:String){
        let utterance = AVSpeechUtterance(string: str)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.4
        utterance.pitchMultiplier = 1.2
        speech.speak(utterance)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    


}

