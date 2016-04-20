//
//  VideoFileRender.swift
//  SwiftPlayer
//
//  Created by zhongzhendong on 4/18/16.
//  Copyright © 2016 zhongzhendong. All rights reserved.
//

import Foundation

struct VideoPacket {
    var buffer: Array<UInt8>
    var bufferSize: Int
    
    init(size: Int) {
        bufferSize = size
        buffer = Array<UInt8>(count:size, repeatedValue: 0)
    }
}

class VideoFileReader: NSObject {
    
//    var bufferSize: Int = 0
    let bufferCap: Int = 512 * 1024
    var streamBuffer = Array<UInt8>()
    
    var fileStream: NSInputStream?
    
    let startCode: [UInt8] = [0,0,0,1]
    
    func openVideoFile(fileURL: NSURL) {

        streamBuffer = [UInt8]()
        
        fileStream = NSInputStream(URL: fileURL)
        fileStream?.open()
    }
    
    func netPacket() -> VideoPacket? {
        
        if streamBuffer.count == 0 && readStremData() == 0{
            return nil
        }
        
        //make sure start with start code
        if streamBuffer.count < 5 || Array(streamBuffer[0...3]) != startCode {
            return nil
        }
        
        //find second start code , so startIndex = 4
        var startIndex = 4
        
        while true {
            
            while ((startIndex + 3) < streamBuffer.count) {
                if Array(streamBuffer[startIndex...startIndex+3]) == startCode {
                    
                    var packet = VideoPacket(size: startIndex)
                    
                    packet.buffer = Array(streamBuffer[0..<startIndex])
                    streamBuffer.removeRange(0..<startIndex)
                    
                    return packet
                }
                startIndex += 1
            }
            
            // not found next start code , read more data
            if readStremData() == 0 {
                return nil
            }
        }
    }
    
    private func readStremData() -> Int{
        
        if let stream = fileStream where stream.hasBytesAvailable{
            
            var tempArray = Array<UInt8>(count: bufferCap, repeatedValue: 0)
            let bytes = stream.read(&tempArray, maxLength: bufferCap)
            
            if bytes > 0 {
                streamBuffer.appendContentsOf(Array(tempArray[0..<bytes]))
            }
            
            return bytes
        }
        
        return 0
    }
}
