//
//  Discovery.swift
//  Virion
//
//  Created by Sergey Dikarev on 4/12/20.
//

import Foundation
import CoreBluetooth

public class BLEDiscovery: NSObject
{
    private var queue: DispatchQueue = DispatchQueue(label: "app.BLEDiscovery.ble", attributes: [])
    private var uuid: String = ""
    private var user: String = ""
    private var foundUser: String = ""
    
    private var bluetoothPowerOn = false
    private var bluetoothAdvPowerOn = false
    private var currentPeripheral: CBPeripheral? = nil

    private var resultBlock: ((_ user: String) -> Void)?
    
    private var inBackgroundMode: Bool = false
    private var currentRSSI: Double = 0
    private var shouldAdvertise: Bool = false
    {
        didSet
        {
            if self.shouldAdvertise {
                if self.peripheralManager == nil
                {
                    self.peripheralManager = CBPeripheralManager(delegate: self, queue: self.queue)
                }
            } else {
                self.disconnect(shouldStopAdv: true)

            }
        }
    }
    
    private var shouldDiscover: Bool = true
    {
        didSet
        {
            if shouldDiscover
            {
                if self.centralManager == nil
                {
                    self.centralManager = CBCentralManager(delegate: self, queue: self.queue, options: [CBCentralManagerOptionRestoreIdentifierKey: "MainCentralManager"])
                }
            }
            else
            {
                self.disconnect(shouldStopAdv: true)
            }
        }
    }
    
    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    
    
    required init(uuid: String) {
        super.init()
        self.uuid = uuid
        NotificationCenter.default.addObserver(self, selector: #selector(self.appDidEnterBackground(notification:)), name: Notification.Name("UIApplication.didEnterBackgroundNotification"), object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.appWillEnterForeground(notification:)), name: Notification.Name("UIApplication.willEnterForegroundNotification"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: Notification.Name("UIApplication.didEnterBackgroundNotification"), object: nil)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("UIApplication.willEnterForegroundNotification"), object: nil)
    }

    private func startAdvertising()
    {
        if bluetoothAdvPowerOn
        {
            let cbuuid = CBUUID(string: self.uuid)
                        
            let advertisingData = [CBAdvertisementDataServiceUUIDsKey: [cbuuid]] as [String : Any]
            
            let characteristic = CBMutableCharacteristic(type: cbuuid, properties: CBCharacteristicProperties.read, value: self.user.data(using: .utf8), permissions: CBAttributePermissions.readable)
            let desc = CBMutableDescriptor(type: cbuuid, value: self.user.data(using: .utf8))
            characteristic.descriptors = [desc]
            let service = CBMutableService(type: cbuuid, primary: true)
            
            service.characteristics = [characteristic]
            self.peripheralManager?.add(service)
            self.peripheralManager?.startAdvertising(advertisingData)
        }
        
    }
    
    public func startAdvertising(with username: String)
    {
        self.user = username
        self.shouldAdvertise = true
    }
    
    public func stopAdvertising()
    {
        self.shouldAdvertise = false
    }
    
    public func startDiscovering(completion: @escaping (_ user: String) -> Void)
    {
        self.resultBlock = completion
        self.shouldDiscover = true
    }
    
    public func stopDiscovering()
    {
        self.shouldDiscover = false
    }
    
    private func disconnect(shouldStopAdv: Bool) {
        
        guard let peripheral = self.currentPeripheral else {
            print("No peripheral available to cleanup.")
            return
        }
        
        if peripheral.state != .connected {
            print("Peripheral is not connected.")
            self.currentPeripheral = nil
            return
        }
        
        guard let services = peripheral.services else {
            // disconnect directly
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        for service in services {
            // iterate through characteristics
            if let characteristics = service.characteristics {
                for characteristic in characteristics {
                    // find the Transfer Characteristic we defined in our Device struct
                    if characteristic.uuid == CBUUID.init(string: self.uuid) {
                        // 5
                        peripheral.setNotifyValue(false, for: characteristic)
                        return
                    }
                }
            }
        }
        
        centralManager.cancelPeripheralConnection(peripheral)
        if shouldStopAdv
        {
            if (self.peripheralManager) != nil {
                self.peripheralManager?.stopAdvertising()
                self.peripheralManager?.delegate = nil
                self.peripheralManager = nil
            }
        }
        
    }
    
    public func startDetecting()
    {
        if bluetoothPowerOn
        {
            let scanOptions = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            let services = [CBUUID(string: self.uuid)]
            
            self.centralManager.scanForPeripherals(withServices: services, options: scanOptions)
            
        }
        
    }
    
    @objc private func appDidEnterBackground(notification: Notification)
    {
        self.inBackgroundMode = true
        
    }
    
    @objc private func appWillEnterForeground(notification: Notification)
    {
        self.inBackgroundMode = false
        
    }
    
    
    private func calculateAccuracy(txPower: Int, rssi: Double) -> Double {
        if (rssi == 0) {
            return -1.0; // if we cannot determine accuracy, return -1.
        }
        
        let ratio: Double = rssi*1.0/Double(txPower)
        if (ratio < 1.0) {
            return pow(ratio,10)
        }
        else {
            let accuracy: Double =  (0.89976) * pow(ratio,7.7095) + 0.111
            return accuracy
        }
    }
    
}

extension BLEDiscovery: CBPeripheralDelegate
{
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services
        {
            for service in services
            {
                let cbuuid = CBUUID(string: self.uuid)
                peripheral.discoverCharacteristics([cbuuid], for: service)
            }
        }
        
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        self.currentRSSI = RSSI.doubleValue
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        if error == nil, let characteristics = service.characteristics
        {
            for characteristic in characteristics
            {
                if characteristic.uuid == CBUUID(string: self.uuid)
                {
                    //Log(characteristic.descriptors)
                    peripheral.readValue(for: characteristic)

                    
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let value = characteristic.value, let val = String(data: value, encoding: .utf8)
        {
            //print("Discover username in background: \(val)")
            foundUser = val
            self.resultBlock?(val)

        }
        self.disconnect(shouldStopAdv: false)

        
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {

    }
}

extension BLEDiscovery: CBPeripheralManagerDelegate
{
    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        print("Discovery peripheralManagerDidStartAdvertising")
    }
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == CBManagerState.poweredOn
        {
            bluetoothAdvPowerOn = true
            self.startAdvertising()
        }
        else
        {
            bluetoothAdvPowerOn = false
            //Log("Peripheral manager state \(peripheral.state.rawValue)")
            
        }
    }
}

extension BLEDiscovery: CBCentralManagerDelegate
{
    
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        if let peripheralsObject = dict[CBCentralManagerRestoredStatePeripheralsKey] {
            let peripherals = peripheralsObject as! Array<CBPeripheral>
            if peripherals.count > 0 {
                
                //currentPeripheral = peripherals[0]
                //currentPeripheral?.delegate = self
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        //print("Discover peripheral: \(peripheral.identifier.uuidString)")
        self.currentPeripheral = peripheral
        self.currentPeripheral?.delegate = self
        self.centralManager.connect(peripheral, options: nil)

        
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {

        peripheral.discoverServices([CBUUID(string: self.uuid)])
        peripheral.readRSSI()
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        //Log("Discover peripheral connection fail: \(peripheral) with error \(error!.localizedDescription)")
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        //Log("central manager state \(central.state.rawValue)")

        if central.state == CBManagerState.poweredOn
        {
            NotificationCenter.default.post(name: Notification.Name(rawValue: "BLE_allowed"), object: nil)

            bluetoothPowerOn = true
            self.startDetecting()
        }
        else
        {
            self.currentPeripheral = nil
            bluetoothPowerOn = false
        
            NotificationCenter.default.post(name: Notification.Name(rawValue: "BLE_restricted"), object: nil)
        }
    }
    
    
}
