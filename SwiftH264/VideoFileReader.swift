//
//  VideoFileRender.swift
//  SwiftPlayer
//
//  Created by zhongzhendong on 4/18/16.
//  Copyright © 2016 zhongzhendong. All rights reserved.
//

import Foundation

typealias VideoPacket = Array<UInt8>

class VideoFileReader: NSObject {
    
    let bufferCap: Int = 512 * 1024
    var streamBuffer = Array<UInt8>()
    
    var fileStream: InputStream?
    
    let startCode: [UInt8] = [0,0,0,1]
    
    func openVideoFile(_ fileURL: URL) {

        streamBuffer = [UInt8]()
        
        fileStream = InputStream(url: fileURL)
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
                    
                    let packet = Array(streamBuffer[0..<startIndex])
                    streamBuffer.removeSubrange(0..<startIndex)
                    
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
    
    fileprivate func readStremData() -> Int{
        
        if let stream = fileStream, stream.hasBytesAvailable{
            
            var tempArray = Array<UInt8>(repeating: 0, count: bufferCap)
            let bytes = stream.read(&tempArray, maxLength: bufferCap)
            
            if bytes > 0 {
                streamBuffer.append(contentsOf: Array(tempArray[0..<bytes]))
            }
            
            return bytes
        }
        
        return 0
    }
}
