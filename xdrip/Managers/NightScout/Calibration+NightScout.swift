//
//  Calibration+NightScout.swift
//  xdrip
//
//  Created by Tudor-Andrei Vrabie on 27/06/2020.
//  Copyright © 2020 Johan Degraeve. All rights reserved.
//

import Foundation

extension Calibration {
    
    /// dictionary representation for upload to NightScout
    public var dictionaryRepresentationForNightScoutUpload: [String: Any] {
        
        return  [
            "_id": id,
            "device": deviceName ?? "",
            "date": timeStamp.toMillisecondsAsInt64(),
            "dateString": timeStamp.ISOStringFromDate(),
            "type": "cal",
            "mbg": bg,
            "filtered": round(adjustedRawValue * 1000),
            "unfiltered": round(rawValue * 1000),
            "noise": 1,
            "sysTime": timeStamp.ISOStringFromDate(),
            "slope": slope,
            "intercept": intercept
        ]
        
    }
    
}

