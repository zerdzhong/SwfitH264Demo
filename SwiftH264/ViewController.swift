//
//  ViewController.swift
//  SwiftH264
//
//  Created by zhongzhendong on 4/20/16.
//  Copyright © 2016 zhongzhendong. All rights reserved.
//

import UIKit
import VideoToolbox
import AVFoundation

class ViewController: UIViewController {
    
    var formatDesc: CMVideoFormatDescriptionRef?
    var decompressionSession: VTDecompressionSessionRef?
    var videoLayer: AVSampleBufferDisplayLayer?
    
    var spsSize: Int = 0
    var ppsSize: Int = 0
    
    var sps: Array<UInt8>?
    var pps: Array<UInt8>?


    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        videoLayer = AVSampleBufferDisplayLayer()
        
        if let layer = videoLayer {
            layer.frame = CGRectMake(0, 400, 300, 300)
            layer.videoGravity = AVLayerVideoGravityResizeAspect
            
            
            let _CMTimebasePointer = UnsafeMutablePointer<CMTimebase?>.alloc(1)
            let status = CMTimebaseCreateWithMasterClock( kCFAllocatorDefault, CMClockGetHostTimeClock(),  _CMTimebasePointer )
            layer.controlTimebase = _CMTimebasePointer.memory
            
            if let controlTimeBase = layer.controlTimebase where status == noErr {
                CMTimebaseSetTime(controlTimeBase, kCMTimeZero);
                CMTimebaseSetRate(controlTimeBase, 1.0);
            }
            
            self.view.layer.addSublayer(layer)
    
        }

    }

    @IBAction func startClicked(sender: UIButton) {
        
        dispatch_async(dispatch_get_global_queue(0, 0)) { 
            let filePath = NSBundle.mainBundle().pathForResource("mtv", ofType: "h264")
            let url = NSURL(fileURLWithPath: filePath!)
            self.decodeFile(url)
        }
    }
    
    func decodeFile(fileURL: NSURL) {
        
        let videoReader = VideoFileReader()
        videoReader.openVideoFile(fileURL)
        
        while var packet = videoReader.netPacket() {
            self.receivedRawVideoFrame(&packet)
        }
        
    }
    
    func receivedRawVideoFrame(inout videoPacket: VideoPacket) {
        
        //replace start code with nal size
        var biglen = CFSwapInt32HostToBig(UInt32(videoPacket.count - 4))
        memcpy(&videoPacket, &biglen, 4)
        
        let nalType = videoPacket[4] & 0x1F
        
        switch nalType {
        case 0x05:
            print("Nal type is IDR frame")
            if createDecompSession() {
                decodeVideoPacket(videoPacket)
            }
        case 0x07:
            print("Nal type is SPS")
            spsSize = videoPacket.count - 4
            sps = Array(videoPacket[4..<videoPacket.count])
        case 0x08:
            print("Nal type is PPS")
            ppsSize = videoPacket.count - 4
            pps = Array(videoPacket[4..<videoPacket.count])
        default:
            print("Nal type is B/P frame")
            decodeVideoPacket(videoPacket)
            break;
        }
        
        print("Read Nalu size \(videoPacket.count)");
    }

    func decodeVideoPacket(videoPacket: VideoPacket) {
        
        let bufferPointer = UnsafeMutablePointer<UInt8>(videoPacket)
        
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,bufferPointer, videoPacket.count,
                                                        kCFAllocatorNull,
                                                        nil, 0, videoPacket.count,
                                                        0, &blockBuffer)
        
        if status != kCMBlockBufferNoErr {
            return
        }
        
        var sampleBuffer: CMSampleBuffer?
        let sampleSizeArray = [videoPacket.count]
        
        status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                           blockBuffer,
                                           formatDesc,
                                           1, 0, nil,
                                           1, sampleSizeArray,
                                           &sampleBuffer)
        
        
        
        if let buffer = sampleBuffer, let session = decompressionSession where status == kCMBlockBufferNoErr {
            
            let attachments:CFArrayRef? = CMSampleBufferGetSampleAttachmentsArray(buffer, true)
            if let attachmentArray = attachments {
                let dic = unsafeBitCast(CFArrayGetValueAtIndex(attachmentArray, 0), CFMutableDictionary.self)
                
                CFDictionarySetValue(dic,
                                     unsafeAddressOf(kCMSampleAttachmentKey_DisplayImmediately),
                                     unsafeAddressOf(kCFBooleanTrue))
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                self.videoLayer?.enqueueSampleBuffer(buffer)
                self.videoLayer?.setNeedsDisplay()
            })
            
            var flagOut = VTDecodeInfoFlags(rawValue: 0)
            var outputBuffer = UnsafeMutablePointer<CVPixelBuffer>.alloc(1)
            
            status = VTDecompressionSessionDecodeFrame(session, buffer,
                                                       [._EnableAsynchronousDecompression],
                                                       &outputBuffer, &flagOut)
            
            if status == noErr {
                print("OK")
            }else if(status == kVTInvalidSessionErr) {
                print("IOS8VT: Invalid session, reset decoder session");
            } else if(status == kVTVideoDecoderBadDataErr) {
                print("IOS8VT: decode failed status=\(status)(Bad data)");
            } else if(status != noErr) {
                print("IOS8VT: decode failed status=\(status)");
            }
        }
    }
    
    func createDecompSession() -> Bool{
        formatDesc = nil
        
        if let spsData = sps, let ppsData = pps {
            let pointerSPS = UnsafePointer<UInt8>(spsData)
            let pointerPPS = UnsafePointer<UInt8>(ppsData)
            
            // make pointers array
            let dataParamArray = [pointerSPS, pointerPPS]
            let parameterSetPointers = UnsafePointer<UnsafePointer<UInt8>>(dataParamArray)
            
            // make parameter sizes array
            let sizeParamArray = [spsData.count, ppsData.count]
            let parameterSetSizes = UnsafePointer<Int>(sizeParamArray)
            
            
            let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, parameterSetPointers, parameterSetSizes, 4, &formatDesc)
            
            if let desc = formatDesc where status == noErr {
                
                if let session = decompressionSession {
                    VTDecompressionSessionInvalidate(session)
                    decompressionSession = nil
                }
                
                var videoSessionM : VTDecompressionSession?
                
                let decoderParameters = NSMutableDictionary()
                let destinationPixelBufferAttributes = NSMutableDictionary()
                destinationPixelBufferAttributes.setValue(NSNumber(unsignedInt: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange), forKey: kCVPixelBufferPixelFormatTypeKey as String)
                
                var outputCallback = VTDecompressionOutputCallbackRecord()
                outputCallback.decompressionOutputCallback = decompressionSessionDecodeFrameCallback
                outputCallback.decompressionOutputRefCon = UnsafeMutablePointer<Void>(unsafeAddressOf(self))
                
                let status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                          desc, decoderParameters,
                                                          destinationPixelBufferAttributes,&outputCallback,
                                                          &videoSessionM)
                
                if(status != noErr) {
                    print("\t\t VTD ERROR type: \(status)")
                }
                
                self.decompressionSession = videoSessionM
            }else {
                print("IOS8VT: reset decoder session failed status=\(status)")
            }
        }
        
        return true
    }
    
    func displayDecodedFrame(imageBuffer: CVImageBuffer?) {
        
    }

}

private func decompressionSessionDecodeFrameCallback(decompressionOutputRefCon: UnsafeMutablePointer<Void>, _ sourceFrameRefCon: UnsafeMutablePointer<Void>, _ status: OSStatus, _ infoFlags: VTDecodeInfoFlags, _ imageBuffer: CVImageBuffer?, _ presentationTimeStamp: CMTime, _ presentationDuration: CMTime) -> Void {
    
        let streamManager: ViewController = unsafeBitCast(decompressionOutputRefCon, ViewController.self)
    
        if status == noErr {
            // do something with your resulting CVImageBufferRef that is your decompressed frame
            streamManager.displayDecodedFrame(imageBuffer);
        }
}

