//
//  LibreRawGlucoseOOPA2Data.swift
//  xdrip
//
//  Created by Johan Degraeve on 08/06/2020.
//  Copyright © 2020 Johan Degraeve. All rights reserved.
//

// source https://github.com/JohanDegraeve/xdripswift/blob/bd5b3060f3a7d4c68dce767b5c86306239d06d14/xdrip/BluetoothTransmitter/CGM/Libre/Utilities/LibreRawGlucoseData.swift#L208

import Foundation

public class LibreRawGlucoseOOPA2Data: NSObject, Decodable, LibreRawGlucoseWeb {
    
    var errcode: Int?
    
    var list: [LibreRawGlucoseOOPA2List]?
    
    /// - time when instance of LibreRawGlucoseOOPData was created
    /// - this can be created to calculate the timestamp of realtimeLibreRawGlucoseData
    let creationTimeStamp = Date()

    /// server parse value
    var content: LibreRawGlucoseOOPA2Cotent? {
        return list?.first?.content
    }
    
    /// if the server value is error return true
    var isError: Bool {
        if content?.currentBg ?? 0 <= 10 {
            return true
        }
        return list?.first?.content?.historicBg?.isEmpty ?? true
    }
    
    /// if `false`, it means current 344 bytes can not get the parameters from server
    var canGetParameters: Bool {
        if let id = content?.currentTime {
            if id >= 60 {
                return true
            }
        }
        return false
    }
    
    /// sensor state
    var sensorState: LibreSensorState {
        if let id = content?.currentTime {
            if id < 60 { // if sensor time < 60, the sensor is starting
                return LibreSensorState.starting
            } else if id >= 20880 { // if sensor time >= 20880, the sensor expired
                return LibreSensorState.expired
            }
        }
        
        let state = LibreSensorState.ready
        return state
    }
    
    func glucoseData() -> (libreRawGlucoseData:[LibreRawGlucoseData], sensorState:LibreSensorState, sensorTimeInMinutes:Int?) {
        
        // initialize returnvalue, empty glucoseData array, sensorState, and nil as sensorTimeInMinutes
        var returnValue: ([LibreRawGlucoseData], LibreSensorState, Int?) = ([LibreRawGlucoseData](), sensorState, nil)

        // if isError function returns true, then return empty array
        guard !isError else { return returnValue }
        
        // if sensorState is not .ready, then return empty array
        if sensorState != .ready { return returnValue }

        // content should be non nil, content.currentBg not nil and currentBg != 0, content.currentTime (sensorTimeInMinutes) not nil
        guard let content = content, let currentBg = content.currentBg, currentBg != 0, let sensorTimeInMinutes = content.currentTime else { return returnValue }
        
        // set senorTimeInMinutes in returnValue
        returnValue.2 = sensorTimeInMinutes
        
        // create realtimeLibreRawGlucoseData, which is the current glucose data
        let realtimeLibreRawGlucoseData = LibreRawGlucoseData(timeStamp: creationTimeStamp, glucoseLevelRaw: currentBg)

        // add first element
        returnValue.0.append(realtimeLibreRawGlucoseData)

        // history should be non nil, otherwise return only the first value
        guard var history = content.historicBg else { return returnValue }
        
        // check the order, first should be the smallest time, time is sensor time in minutes, means first should be the oldest
        // if not, reverse it
        if (history.first?.time ?? 0) < (history.last?.time ?? 0) {
            history = history.reversed()
        }
        
        for historicGlucoseA2 in history {
            
            // if quality != 0, the value is error, don't add it
            if historicGlucoseA2.quality != 0 {continue}
            
            // if time is nil, (which is sensorTimeInMinutes at the moment this reading was created), then we can't calculate the timestamp, don't add it
            if historicGlucoseA2.time == nil {continue}
            
            // bg value should be non nil and > 0.0
            if historicGlucoseA2.bg == nil {continue}
            if historicGlucoseA2.bg! == 0.0 {continue}
            
            let libreRawGlucoseData = LibreRawGlucoseData(timeStamp: creationTimeStamp.addingTimeInterval(-60 * Double(sensorTimeInMinutes - historicGlucoseA2.time!)), glucoseLevelRaw: historicGlucoseA2.bg!)
            
            returnValue.0.insert(libreRawGlucoseData, at: 0)
            
        }
        
        return (returnValue)
        
    }
    
    /// when sensor return error 344 bytes, server will return wrong glucose data
    var valueError: Bool {
        // sensor time < 60, the sensor is starting
        if let id = content?.currentTime, id < 60 {
            return false
        }
        
        // current glucose is error
        if content?.currentBg ?? 0 <= 10 {
            return true
        }
        return false
    }
    
    override public var description: String {
            
        var returnValue = "LibreRawGlucoseOOPA2Data =\n"
        
        // a description created by LibreRawGlucoseWeb
        returnValue = returnValue + (self as LibreRawGlucoseWeb).description
        
        if let errcode = errcode {
            returnValue = returnValue + "   errcode = " + errcode.description + "\n"
        }
        
        return returnValue
        
    }
    
}
