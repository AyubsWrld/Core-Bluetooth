//
//  BluetoothManager.swift
//  Core Bluetooth
//
//  Created by Ayub Mohamed on 2024-12-26.
//


import SwiftUI
import CoreBluetooth

class BluetoothManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    
    @Published var isScanning = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectionStatus = "Disconnected"
    @Published var receivedData: String = ""
    
    // ESP32 Service UUIDs from your C code
    let SERVICE_UUID_A = CBUUID(string: "00FF")
    let SERVICE_UUID_B = CBUUID(string: "00EE")
    let CHARACTERISTIC_UUID_A = CBUUID(string: "FF01")
    let CHARACTERISTIC_UUID_B = CBUUID(string: "EE01")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard let centralManager = centralManager,
              centralManager.state == .poweredOn else { return }
        
        isScanning = true
        discoveredDevices.removeAll()
        // Scan for devices advertising our services
        centralManager.scanForPeripherals(withServices: [SERVICE_UUID_A, SERVICE_UUID_B],
                                        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
    }
    
    func connect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        centralManager?.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }
    
    func writeValue(_ value: Data, for characteristic: CBCharacteristic) {
        peripheral?.writeValue(value, for: characteristic, type: .withResponse)
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
        case .poweredOff:
            print("Bluetooth is powered off")
            connectionStatus = "Bluetooth is powered off"
        case .unsupported:
            print("Bluetooth is unsupported")
            connectionStatus = "Bluetooth is unsupported"
        default:
            print("Unknown state")
            connectionStatus = "Unknown state"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                       advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(peripheral) {
            discoveredDevices.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionStatus = "Connected to \(peripheral.name ?? "Unknown Device")"
        peripheral.delegate = self
        peripheral.discoverServices([SERVICE_UUID_A, SERVICE_UUID_B])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionStatus = "Disconnected"
        self.peripheral = nil
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        // Handle the received data
        let receivedString = String(data: data, encoding: .utf8) ?? "Invalid data"
        DispatchQueue.main.async {
            self.receivedData = receivedString
        }
    }
}

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Status: \(bluetoothManager.connectionStatus)")
                    .padding()
                
                if !bluetoothManager.discoveredDevices.isEmpty {
                    List(bluetoothManager.discoveredDevices, id: \.identifier) { device in
                        Button(action: {
                            bluetoothManager.connect(to: device)
                        }) {
                            Text(device.name ?? "Unknown Device")
                        }
                    }
                } else {
                    Text("No devices found")
                        .foregroundColor(.gray)
                        .padding()
                }
                
                if !bluetoothManager.receivedData.isEmpty {
                    Text("Received: \(bluetoothManager.receivedData)")
                        .padding()
                }
                
                HStack {
                    Button(action: {
                        if bluetoothManager.isScanning {
                            bluetoothManager.stopScanning()
                        } else {
                            bluetoothManager.startScanning()
                        }
                    }) {
                        Text(bluetoothManager.isScanning ? "Stop Scanning" : "Start Scanning")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        bluetoothManager.disconnect()
                    }) {
                        Text("Disconnect")
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("ESP32 BLE Demo")
        }
    }
}