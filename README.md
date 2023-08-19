## BLE Discovery swift package 
Detect BLE devices with the same BLE ID (UUID string), exchange information between BLE devices

### Usage

##### Start discovering contacts
To start discover BLE contacts use: 

```Swift
let discovery = BLEDiscovery(uuid: "UUID string")
self.discovery.startDiscovering { user in
                    
}
```

To advertise your own string info: 

```Swift
let discovery = BLEDiscovery()
discovery.startAdvertising(with: user_string_info)
```
