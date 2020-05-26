import Foundation

protocol LibreRawGlucoseWeb {
    
    /// if the server value is error  return true
    var isError: Bool { get }
    
    /// if `false`, it means current 344 bytes can not get the parameters from server
    var canGetParameters: Bool { get }
    
    /// sensor state
    var sensorState: LibreSensorState { get }
    
    /// when sensor return error 344 bytes, server will return wrong glucose data
    var valueError: Bool { get }
    
    /// gets LibreRawGlucoseData,
    ///  - parameters: sensorTimeInMinutes, if known. If it is not known give nil value
    ///  - Returns: array of LibreRawGlucoseData, sensorState, sensorTimeInMinutes
    func glucoseData() -> (libreRawGlucoseData:[LibreRawGlucoseData], sensorState:LibreSensorState, sensorTimeInMinutes:Int?)
    
}

// to implement a var description
extension LibreRawGlucoseWeb {

    var description: String {
        
        var returnValue =  "   isError = " + isError.description + "\n"
        
        returnValue = returnValue + "   sensorState = " + sensorState.description + "\n"
        
        returnValue = returnValue + "   canGetParameters = " + canGetParameters.description + "\n"
        
        returnValue = returnValue + "   valueError = " + valueError.description + "\n"
        
        let libreGlucoseData = glucoseData()
        
        returnValue = returnValue + "\nSize of [LibreRawGlucoseData] = " + libreGlucoseData.libreRawGlucoseData.count.description + "\n"
        
        if libreGlucoseData.libreRawGlucoseData.count > 0 {
            returnValue = returnValue + "list = \n"
            
            for glucoseData in libreGlucoseData.libreRawGlucoseData {
                returnValue = returnValue + glucoseData.description + "\n"
            }
        }
        
        if let sensorTimeInMinutes = libreGlucoseData.sensorTimeInMinutes {

            returnValue = returnValue + "sensor time in minutes = " + sensorTimeInMinutes.description + "\n"

        } else {

            returnValue = returnValue + "sensor time in minutes is unknown\n"

        }
        
        return returnValue
        
    }
    
}
