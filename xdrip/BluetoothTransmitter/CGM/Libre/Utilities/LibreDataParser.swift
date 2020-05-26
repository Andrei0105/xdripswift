import Foundation
import os

/// for trace
fileprivate let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryLibreDataParser)

class LibreDataParser {
    
    /// parses libre block, returns glucoseData as array of GlucoseData, which are uncalibrated values
    /// - parameters:
    ///     - libreData: the 344 bytes block from Libre
    ///     - timeStampLastBgReading: this is of the timestamp of the latest reading we already received during previous session
    /// - returns:
    ///     - array of GlucoseData, first is the most recent. Only returns recent readings, ie not the ones that are older than timeStampLastBgReading. 30 seconds are added here, meaning, new reading should be at least 30 seconds more recent than timeStampLastBgReading
    ///     - sensorState: status of the sensor
    ///     - sensorTimeInMinutes: age of sensor in minutes
    public static func parseLibre1DataWithoutCalibration(libreData: Data, timeStampLastBgReading:Date) -> (glucoseData:[GlucoseData], sensorState:LibreSensorState, sensorTimeInMinutes:Int) {
        
        var i:Int
        var glucoseData:GlucoseData
        var byte:Data
        var timeInMinutes:Double
        let ourTime:Date = Date()
        let indexTrend:Int = getByteAt(buffer: libreData, position: 26) & 0xFF
        let indexHistory:Int = getByteAt(buffer: libreData, position: 27) & 0xFF
        let sensorTimeInMinutes:Int = 256 * (getByteAt(buffer:libreData, position: 317) & 0xFF) + (getByteAt(buffer:libreData, position: 316) & 0xFF)
        let sensorStartTimeInMilliseconds:Double = ourTime.toMillisecondsAsDouble() - (Double)(sensorTimeInMinutes * 60 * 1000)
        var returnValue:Array<GlucoseData> = []
        let sensorState = LibreSensorState(stateByte: libreData[4])
        
       // we will add the most recent readings, but then we'll only add the readings that are at least 5 minutes apart (giving 10 seconds spare)
        // for that variable timeStampLastAddedGlucoseData is used. It's initially set to now + 5 minutes
        var timeStampLastAddedGlucoseData = Date().toMillisecondsAsDouble() + 5 * 60 * 1000
        
        trendloop: for index in 0..<16 {
            i = indexTrend - index - 1
            if i < 0 {i += 16}
            timeInMinutes = max(0, (Double)(sensorTimeInMinutes - index))
            let timeStampOfNewGlucoseData = sensorStartTimeInMilliseconds + timeInMinutes * 60 * 1000
            
            //new reading should be at least 30 seconds younger than timeStampLastBgReading
            if timeStampOfNewGlucoseData > (timeStampLastBgReading.toMillisecondsAsDouble() + 30000.0)
            {
                if timeStampOfNewGlucoseData < timeStampLastAddedGlucoseData - (5 * 60 * 1000 - 10000) {
                    byte = Data()
                    byte.append(libreData[(i * 6 + 29)])
                    byte.append(libreData[(i * 6 + 28)])
                    let glucoseLevelRaw = Double(getGlucoseRaw(bytes: byte))
                    if (glucoseLevelRaw > 0) {
                        glucoseData = GlucoseData(timeStamp: Date(timeIntervalSince1970: sensorStartTimeInMilliseconds/1000 + timeInMinutes * 60), glucoseLevelRaw: glucoseLevelRaw * ConstantsBloodGlucose.libreMultiplier)
                        returnValue.append(glucoseData)
                        timeStampLastAddedGlucoseData = timeStampOfNewGlucoseData
                    }
                }
            } else {
                break trendloop
            }
        }

        // loads history values
        historyloop: for index in 0..<32 {
            i = indexHistory - index - 1
            if i < 0 {i += 32}
            timeInMinutes = max(0,(Double)(abs(sensorTimeInMinutes - 3)/15)*15 - (Double)(index*15))
            let timeStampOfNewGlucoseData = sensorStartTimeInMilliseconds + timeInMinutes * 60 * 1000
            
            //new reading should be at least 30 seconds younger than timeStampLastBgReading
            if timeStampOfNewGlucoseData > (timeStampLastBgReading.toMillisecondsAsDouble() + 30000.0)
            {
                if timeStampOfNewGlucoseData < timeStampLastAddedGlucoseData - (5 * 60 * 1000 - 10000) {
                    byte = Data()
                    byte.append(libreData[(i * 6 + 125)])
                    byte.append(libreData[(i * 6 + 124)])
                    let glucoseLevelRaw = Double(getGlucoseRaw(bytes: byte))
                    if (glucoseLevelRaw > 0) {
                        glucoseData = GlucoseData(timeStamp: Date(timeIntervalSince1970: sensorStartTimeInMilliseconds/1000 + timeInMinutes * 60), glucoseLevelRaw: glucoseLevelRaw * ConstantsBloodGlucose.libreMultiplier)
                        returnValue.append(glucoseData)
                        timeStampLastAddedGlucoseData = timeStampOfNewGlucoseData
                    }
                }
            } else {
                break historyloop
            }
        }

        return (returnValue, sensorState, sensorTimeInMinutes)
        
    }
    
    public static func parseLibre1DataWithOOPWebCalibration(libreData: Data, libre1DerivedAlgorithmParameters: Libre1DerivedAlgorithmParameters, timeStampLastBgReading: Date) -> (libreRawGlucoseData:[LibreRawGlucoseData], sensorState:LibreSensorState, sensorTimeInMinutes:Int) {
        
        // TODO: and also parseLibre1DataWithOOPWebCalibration should not return default values
        
        // initialise returnvalue, array of LibreRawGlucoseData
        var finalResult:[LibreRawGlucoseData] = []
        
        // calculate sensorState
        let sensorState = LibreSensorState(stateByte: libreData[4])
        
        let sensorTimeInMinutes:Int = 256 * (Int)(libreData.uint8(position: 317) & 0xFF) + (Int)(libreData.uint8(position: 316) & 0xFF)
        
        // iterates through glucoseData, compares timestamp, if still higher than timeStampLastBgReading (+ 30 seconds) then adds it to finalResult
        let processGlucoseData = { (glucoseData: [LibreRawGlucoseData], timeStampLastAddedGlucoseData: Date) in
            
            var timeStampLastAddedGlucoseDataAsDouble = timeStampLastAddedGlucoseData.toMillisecondsAsDouble()
            
            for glucose in glucoseData {
                
                let timeStampOfNewGlucoseData = glucose.timeStamp
                if timeStampOfNewGlucoseData.toMillisecondsAsDouble() > (timeStampLastBgReading.toMillisecondsAsDouble() + 30000.0) {
                    
                    // return only readings that are at least 5 minutes away from each other, except the first, same approach as in LibreDataParser.parse
                    if timeStampOfNewGlucoseData.toMillisecondsAsDouble() < timeStampLastAddedGlucoseDataAsDouble - (5 * 60 * 1000 - 10000) {
                        timeStampLastAddedGlucoseDataAsDouble = timeStampOfNewGlucoseData.toMillisecondsAsDouble()
                        finalResult.append(glucose)
                    }
                    
                } else {
                    break
                }
            }
            
        }
        
        // get last16 from trend data
        // latest reading will get date of now
        let last16 = trendMeasurements(bytes: libreData, mostRecentReadingDate: Date(), timeStampLastBgReading: timeStampLastBgReading, libre1DerivedAlgorithmParameters: libre1DerivedAlgorithmParameters)
        
        // process last16, new readings should be smaller than now + 5 minutes
        processGlucoseData(trendToLibreGlucose(last16), Date(timeIntervalSinceNow: 5 * 60))
        
        // get last32 from history data
        let last32 = historyMeasurements(bytes: libreData, timeStampLastBgReading: timeStampLastBgReading, libre1DerivedAlgorithmParameters: libre1DerivedAlgorithmParameters)
        
        // process last 32 with date earlier than the earliest in last16
        var timeStampLastAddedGlucoseData = Date()
        if last16.count > 0, let last = last16.last {
            timeStampLastAddedGlucoseData = last.date
        }
        
        processGlucoseData(historyToLibreGlucose(last32), timeStampLastAddedGlucoseData)

        return (finalResult, sensorState, sensorTimeInMinutes)
        
    }

    /// Function which groups common functionality used for transmitters that support the 344 Libre block. It checks if webOOP is enabled, if yes tries to use the webOOP, response is processed and delegate is called. If webOOP is not enabled, then local parsing is done.
    /// - parameters:
    ///     - libreSensorSerialNumber : if nil, then webOOP will not be used and local parsing will be done
    ///     - patchInfo : will be used by server to out the glucose data, corresponds to type of sensor. Nil if not known which is used for Bubble or MM older firmware versions and also Watlaa
    ///     - libreData : the 344 bytes from Libre sensor
    ///     - timeStampLastBgReading : timestamp of last reading, older readings will be ignored
    ///     - webOOPEnabled : is webOOP enabled or not, if not enabled, local parsing is used
    ///     - oopWebSite : the site url to use if oop web would be enabled
    ///     - oopWebToken : the token to use if oop web would be enabled
    ///     - cgmTransmitterDelegate : the cgmTransmitterDelegate
    ///     - completionHandler : will be called when glucose data is read with as parameter the timestamp of the last reading. Goal is that caller can set timeStampLastBgReading to the new value
    public static func libreDataProcessor(libreSensorSerialNumber: LibreSensorSerialNumber?, patchInfo: String?, webOOPEnabled: Bool, oopWebSite: String?, oopWebToken: String?, libreData: Data, cgmTransmitterDelegate : CGMTransmitterDelegate?, timeStampLastBgReading: Date, completionHandler:@escaping ((_ timeStampLastBgReading: Date) -> ())) {

        // get libreSensorType
        guard let libreSensorType = LibreSensorType.type(patchInfo: patchInfo) else {

            if let patchInfo = patchInfo {
                
                // as we failed to create libreSensorType, patchInfo should not be nil
                trace("in libreDataProcessor, failed to create libreSensorType, patchInfo = %{public}@", log: log, category: ConstantsLog.categoryLibreDataParser, type: .info, patchInfo)
                
            }

            return

        }

        // TODO: there should be a check here on patchInfo ? because if webOOP not enabled by user, and it's not a libre1, then this will probably fail
        // how to ensure that weboop is enabled ? probably best is if patchInfo shows that it's a libre 2 sensor, then enable web oop
        
        if let libreSensorSerialNumber = libreSensorSerialNumber, let oopWebSite = oopWebSite, let oopWebToken = oopWebToken, webOOPEnabled {
            
            // TODO : throw this patchInfo in an enum, with a function that tells is if Libre1 parsing or Libre2 parsing or other is required ?
            
            // if patchInfo starts with "70" or "E5" or if patchInfo is nil, then it's a Libre 1 sensor
            if libreSensorType == .libreProH || libreSensorType == .libreUS || libreSensorType == .libre1 {
                
                // use the local Libre 1 parsing
                
                // get LibreDerivedAlgorithmParameters and parse using the libre1DerivedAlgorithmParameters
                LibreOOPClient.getLibre1DerivedAlgorithmParameters(bytes: libreData, libreSensorSerialNumber: libreSensorSerialNumber, oopWebSite: oopWebSite, oopWebToken: oopWebToken) { (libre1DerivedAlgorithmParameters) in
                    
                    // parse the data using oop web algorithm
                    let parsedResult = LibreDataParser.parseLibre1DataWithOOPWebCalibration(libreData: libreData, libre1DerivedAlgorithmParameters: libre1DerivedAlgorithmParameters, timeStampLastBgReading: timeStampLastBgReading)
                    
                    handleGlucoseData(result: (parsedResult.libreRawGlucoseData.map { $0 as GlucoseData }, parsedResult.sensorTimeInMinutes, nil), cgmTransmitterDelegate: cgmTransmitterDelegate, libreSensorSerialNumber: libreSensorSerialNumber, completionHandler: completionHandler)
                    
                }
                
                return
                
            }
            
            // patchInfo must be non nill as we've already tested that
            guard let patchInfo = patchInfo else {return}
            
            // if patchInfo.hasPrefix("A2"), server uses another arithmetic to handle the 344 bytes
            if libreSensorType == .libre1A2 {
                LibreOOPClient.getLibreRawGlucoseOOPOA2Data(libreData: libreData, oopWebSite: oopWebSite) { (libreRawGlucoseOOPA2Data) in
                    
                    
                    let test = libreRawGlucoseOOPA2Data
                        
                }
            } else {
                
                    LibreOOPClient.getLibreRawGlucoseOOPData(libreData: libreData, libreSensorSerialNumber: libreSensorSerialNumber, patchInfo: patchInfo, oopWebSite: oopWebSite, oopWebToken: oopWebToken) { (libreRawGlucoseOOPData) in
                        
                        // TODO : check if debug tracing is enabled, to avoid to parse for description when it's not needed
                        trace("in libreDataProcessor, received libreRawGlucoseOOPData = %{public}@", log: log, category: ConstantsLog.categoryLibreDataParser, type: .debug, libreRawGlucoseOOPData.description)
                        
                        // convert libreRawGlucoseOOPData to (libreRawGlucoseData:[LibreRawGlucoseData], sensorState:LibreSensorState, sensorTimeInMinutes:Int?)
                        let parsedResult = libreRawGlucoseOOPData.glucoseData()
                        
                        handleGlucoseData(result: (parsedResult.libreRawGlucoseData.map { $0 as GlucoseData }, parsedResult.sensorTimeInMinutes, nil), cgmTransmitterDelegate: cgmTransmitterDelegate, libreSensorSerialNumber: libreSensorSerialNumber, completionHandler: completionHandler)
                        
                }
                
            }

        } else if !webOOPEnabled {
            
            //get readings from buffer using local Libre 1 parser
            let parsedLibre1Data = LibreDataParser.parseLibre1DataWithoutCalibration(libreData: libreData, timeStampLastBgReading: timeStampLastBgReading)
            
            // handle the result
            handleGlucoseData(result: (parsedLibre1Data.glucoseData, parsedLibre1Data.sensorTimeInMinutes, nil), cgmTransmitterDelegate: cgmTransmitterDelegate, libreSensorSerialNumber: libreSensorSerialNumber, completionHandler: completionHandler)
            
            
        }

    }

}


fileprivate func getByteAt(buffer:Data, position:Int) -> Int {
    // TODO: move to extension data
    return Int(buffer[position])
}

fileprivate func getGlucoseRaw(bytes:Data) -> Int {
    return ((256 * (getByteAt(buffer: bytes, position: 0) & 0xFF) + (getByteAt(buffer: bytes, position: 1) & 0xFF)) & 0x1FFF)
}

fileprivate func trendMeasurements(bytes: Data, mostRecentReadingDate: Date, timeStampLastBgReading: Date, _ offset: Double = 0.0, slope: Double = 0.1, libre1DerivedAlgorithmParameters: Libre1DerivedAlgorithmParameters?) -> [LibreMeasurement] {
    
    //    let headerRange =   0..<24   //  24 bytes, i.e.  3 blocks a 8 bytes
    let bodyRange   =  24..<320  // 296 bytes, i.e. 37 blocks a 8 bytes
    //    let footerRange = 320..<344  //  24 bytes, i.e.  3 blocks a 8 bytes
    
    let body   = Array(bytes[bodyRange])
    let nextTrendBlock = Int(body[2])
    
    var measurements = [LibreMeasurement]()
    // Trend data is stored in body from byte 4 to byte 4+96=100 in units of 6 bytes. Index on data such that most recent block is first.
    for blockIndex in 0...15 {
        var index = 4 + (nextTrendBlock - 1 - blockIndex) * 6 // runs backwards
        if index < 4 {
            index = index + 96 // if end of ring buffer is reached shift to beginning of ring buffer
        }
        let range = index..<index+6
        let measurementBytes = Array(body[range])
        let measurementDate = mostRecentReadingDate.addingTimeInterval(Double(-60 * blockIndex))
        
        if measurementDate > timeStampLastBgReading {
            let measurement = LibreMeasurement(bytes: measurementBytes, slope: slope, offset: offset, date: measurementDate, libre1DerivedAlgorithmParameters: libre1DerivedAlgorithmParameters)
            measurements.append(measurement)
        }
        
    }
    return measurements
}

fileprivate func historyMeasurements(bytes: Data, timeStampLastBgReading: Date, _ offset: Double = 0.0, slope: Double = 0.1, libre1DerivedAlgorithmParameters: Libre1DerivedAlgorithmParameters?) -> [LibreMeasurement] {
    //    let headerRange =   0..<24   //  24 bytes, i.e.  3 blocks a 8 bytes
    let bodyRange   =  24..<320  // 296 bytes, i.e. 37 blocks a 8 bytes
    //    let footerRange = 320..<344  //  24 bytes, i.e.  3 blocks a 8 bytes
    
    let body   = Array(bytes[bodyRange])
    let nextHistoryBlock = Int(body[3])
    let minutesSinceStart = Int(body[293]) << 8 + Int(body[292])
    let sensorStartTimeInMilliseconds:Double = Date().toMillisecondsAsDouble() - (Double)(minutesSinceStart * 60 * 1000)
    
    var measurements = [LibreMeasurement]()
    
    // History data is stored in body from byte 100 to byte 100+192-1=291 in units of 6 bytes. Index on data such that most recent block is first.
    for blockIndex in 0..<32 {
        
        let timeInMinutes = max(0,(Double)(abs(minutesSinceStart - 3)/15)*15 - (Double)(blockIndex*15))
        
        var index = 100 + (nextHistoryBlock - 1 - blockIndex) * 6 // runs backwards
        if index < 100 {
            index = index + 192 // if end of ring buffer is reached shift to beginning of ring buffer
        }
        
        let range = index..<index+6
        let measurementBytes = Array(body[range])
        
        let measurementDate = Date(timeIntervalSince1970: sensorStartTimeInMilliseconds/1000 + timeInMinutes * 60)
        
        if measurementDate > timeStampLastBgReading {
            
            let measurement = LibreMeasurement(bytes: measurementBytes, slope: slope, offset: offset, minuteCounter: Int(timeInMinutes.rawValue), date: measurementDate, libre1DerivedAlgorithmParameters: libre1DerivedAlgorithmParameters)
            measurements.append(measurement)
            
        } else {
            break
        }
        
    }
    
    return measurements
}

/// calls delegate with parameters from result
/// - parameters:
///     - result
///           - glucoseData : array of GlucoseData
///           - sensorState : LibreSensorState
///           - sensorTimeInMinutes: int
///           - errorDescription: optional
///     - cgmTransmitterDelegate: instance  of CGMTransmitterDelegate, which will be called with result
///     - libreSensorSerialNumber
///     - callback which takes a data as parameter, being timeStampLastBgReading
///
/// if result.errorDescription not nil, then delegate function error will be called
fileprivate func handleGlucoseData(result: (glucoseData:[GlucoseData], sensorTimeInMinutes:Int?, errorDescription: String?), cgmTransmitterDelegate : CGMTransmitterDelegate?, libreSensorSerialNumber:LibreSensorSerialNumber?, completionHandler:((_ timeStampLastBgReading: Date) -> ())) {
    
    // if result.errorDescription not nil, then send it to the delegate
    guard result.errorDescription == nil else {
        
        // in case weboop is not used then result.errorDescription is always nil, that's how it's code here. So we can
        cgmTransmitterDelegate?.error(message: "Web OOP : " + result.errorDescription!)
        
        return
    }
    
    // if sensor time < 60, return an empty glucose data array
    if let sensorTimeInMinutes = result.sensorTimeInMinutes {

        guard sensorTimeInMinutes >= 60 else {
            
            var emptyArray = [GlucoseData]()
            
            cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &emptyArray, transmitterBatteryInfo: nil, sensorTimeInMinutes: result.sensorTimeInMinutes)
            
            return
            
        }

    }
    
    // call delegate with result
    var result = result
    cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &result.glucoseData, transmitterBatteryInfo: nil, sensorTimeInMinutes: result.sensorTimeInMinutes)
    
    //set timeStampLastBgReading to timestamp of latest reading in the response so that next time we parse only the more recent readings
    if result.glucoseData.count > 0 {
        completionHandler(result.glucoseData[0].timeStamp)
    }
    
}


/// to glucose data
/// - Parameter measurements: array of LibreMeasurement
/// - Returns: array of LibreRawGlucoseData
fileprivate func trendToLibreGlucose(_ measurements: [LibreMeasurement]) -> [LibreRawGlucoseData] {
    
    var origarr = [LibreRawGlucoseData]()
    for trend in measurements {
        let glucose = LibreRawGlucoseData.init(timeStamp: trend.date, glucoseLevelRaw: trend.temperatureAlgorithmGlucose)
        origarr.append(glucose)
    }
    return origarr
}

fileprivate func historyToLibreGlucose(_ measurements: [LibreMeasurement]) -> [LibreRawGlucoseData] {
    
    var origarr = [LibreRawGlucoseData]()
    
    for history in measurements {
        let glucose = LibreRawGlucoseData(timeStamp: history.date, unsmoothedGlucose: history.temperatureAlgorithmGlucose)
        origarr.append(glucose)
    }
    
    return origarr
    
}
