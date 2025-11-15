//
//  BluetoothManager.swift
//  tachy-app
//
//  Created for BLE communication with Arduino Nano PPG
//

import Foundation
import CoreBluetooth
import Combine

class BluetoothManager: NSObject, ObservableObject {
    // Service and Characteristic UUIDs matching Arduino code
    private let serviceUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef0")
    private let characteristicUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef1")
    private let deviceName = "NanoPPG"
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var ppgCharacteristic: CBCharacteristic?
    
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var ppgVoltage: Float = 0.0
    @Published var connectionStatus = "Disconnected"
    @Published var voltageHistory: [(time: Date, voltage: Float)] = []
    @Published var peakCount: Int = 0
    @Published var bpm: Float = 0.0
    
    private let maxHistoryCount = 500 // Keep last 500 data points
    private let timeWindow: TimeInterval = 5.0 // Show last 5 seconds
    private let peakThreshold: Float = 2.8 // Voltage threshold for peak detection
    private let minPeakInterval: TimeInterval = 0.3 // Minimum time between peaks (to avoid noise)
    
    private var previousVoltage: Float = 0.0
    private var lastPeakTime: Date?
    private var peakTimestamps: [Date] = [] // Store recent peak timestamps for BPM calculation
    private let maxPeakTimestamps = 10 // Keep last 10 peaks for BPM calculation
    
    // Filtered history showing only the last 5 seconds
    var recentVoltageHistory: [(time: Date, voltage: Float)] {
        guard !voltageHistory.isEmpty else { return [] }
        let cutoffTime = Date().addingTimeInterval(-timeWindow)
        return voltageHistory.filter { $0.time >= cutoffTime }
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = "Bluetooth is off"
            return
        }
        
        isScanning = true
        connectionStatus = "Scanning for \(deviceName)..."
        // Scan for peripherals - try with service UUID first, but also accept any device
        // This makes it more reliable if service UUID isn't advertised
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        // Stop scanning after 15 seconds if no device found
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            if let self = self, self.isScanning, !self.isConnected {
                self.stopScanning()
                self.connectionStatus = "Device not found. Make sure NanoPPG is powered on."
            }
        }
    }
    
    func stopScanning() {
        isScanning = false
        centralManager.stopScan()
    }
    
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    private func calculateBPM() {
        guard peakTimestamps.count >= 2 else {
            bpm = 0.0
            return
        }
        
        // Calculate average interval between peaks
        var intervals: [TimeInterval] = []
        for i in 1..<peakTimestamps.count {
            let interval = peakTimestamps[i].timeIntervalSince(peakTimestamps[i - 1])
            intervals.append(interval)
        }
        
        // Calculate average interval
        let averageInterval = intervals.reduce(0.0, +) / Double(intervals.count)
        
        // Convert to BPM (beats per minute)
        if averageInterval > 0 {
            bpm = Float(60.0 / averageInterval)
        } else {
            bpm = 0.0
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionStatus = "Bluetooth ready"
        case .poweredOff:
            connectionStatus = "Bluetooth is off"
        case .unauthorized:
            connectionStatus = "Bluetooth unauthorized"
        case .unsupported:
            connectionStatus = "Bluetooth unsupported"
        default:
            connectionStatus = "Bluetooth unavailable"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check if this is our device by name or advertised service
        let peripheralName = peripheral.name ?? ""
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let isOurDevice = peripheralName.contains("NanoPPG") || 
                         peripheralName == deviceName ||
                         advertisedServices.contains(serviceUUID)
        
        if isOurDevice {
            stopScanning()
            connectedPeripheral = peripheral
            connectionStatus = "Connecting to \(peripheralName.isEmpty ? deviceName : peripheralName)..."
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStatus = "Connected"
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionStatus = "Disconnected"
        connectedPeripheral = nil
        ppgCharacteristic = nil
        ppgVoltage = 0.0
        voltageHistory.removeAll()
        peakCount = 0
        bpm = 0.0
        previousVoltage = 0.0
        lastPeakTime = nil
        peakTimestamps.removeAll()
        
        if let error = error {
            connectionStatus = "Disconnected: \(error.localizedDescription)"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionStatus = "Connection failed"
        if let error = error {
            connectionStatus = "Connection failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([characteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                ppgCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                connectionStatus = "Receiving data..."
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == characteristicUUID,
              let data = characteristic.value else { return }
        
        if error != nil {
            connectionStatus = "Error reading data"
            return
        }
        
        // Arduino sends float (4 bytes) - read as little-endian
        if data.count >= 4 {
            var voltage: Float = 0.0
            data.withUnsafeBytes { buffer in
                if let baseAddress = buffer.baseAddress {
                    voltage = baseAddress.load(as: Float.self)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let currentTime = Date()
                self.ppgVoltage = voltage
                
                // Peak detection: detect when voltage crosses above threshold
                if self.previousVoltage < self.peakThreshold && voltage >= self.peakThreshold {
                    // Check if enough time has passed since last peak (debouncing)
                    if let lastPeak = self.lastPeakTime {
                        let timeSinceLastPeak = currentTime.timeIntervalSince(lastPeak)
                        if timeSinceLastPeak >= self.minPeakInterval {
                            self.peakCount += 1
                            self.lastPeakTime = currentTime
                            self.peakTimestamps.append(currentTime)
                            
                            // Keep only recent peaks for BPM calculation
                            if self.peakTimestamps.count > self.maxPeakTimestamps {
                                self.peakTimestamps.removeFirst()
                            }
                            
                            // Calculate BPM from peak intervals
                            self.calculateBPM()
                        }
                    } else {
                        // First peak
                        self.peakCount += 1
                        self.lastPeakTime = currentTime
                        self.peakTimestamps.append(currentTime)
                    }
                }
                
                self.previousVoltage = voltage
                
                // Add to history
                let dataPoint = (time: currentTime, voltage: voltage)
                self.voltageHistory.append(dataPoint)
                
                // Keep only the last maxHistoryCount points
                if self.voltageHistory.count > self.maxHistoryCount {
                    self.voltageHistory.removeFirst(self.voltageHistory.count - self.maxHistoryCount)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            connectionStatus = "Notification error: \(error.localizedDescription)"
        }
    }
}

