import 'dart:async';
import 'dart:developer';
import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hydrify/cubit/hydration/hydration_sync.dart';
import 'package:hydrify/helpers/database_helper.dart';
import 'package:hydrify/models/hydration_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'ble_state.dart';

class BleCubit extends Cubit<BleState> implements HydrationSync {
  BleCubit() : super(const BleState());
  final _hydrationController =
      StreamController<List<HydrationEntry>>.broadcast();

  final Guid serviceUUID = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
  final Guid dataUUID = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
  final Guid hydrationDataUUID = Guid("6E400004-B5A3-F393-E0A9-E50E24DCCA9E");
  final Guid ackUUID = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
  final Guid hydrationCharUUID = Guid("6E400005-B5A3-F393-E0A9-E50E24DCCA9E");

  BluetoothCharacteristic? _dataChar;
  BluetoothCharacteristic? _ackChar;
  BluetoothCharacteristic? _hydrationDataChar;
  BluetoothCharacteristic? _hydrationChar; // 🔹 NEW for 7-slot hydration data

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  String? savedDeviceName;
  String? savedDeviceId;

  final bool _isReconnecting = false;
  final dbHelper = DatabaseHelper();
  final List<HydrationEntry> _pendingSlots = [];

  // ---------------------------------------------------------------------------
  // BLE initialization and scanning
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    emit(state.copyWith(
      status: BleStatus.initializing,
      message: "Initializing...",
    ));

    await _waitForBluetoothOn(() async {
      final prefs = await SharedPreferences.getInstance();
      savedDeviceName = prefs.getString('last_device_name');
      savedDeviceId = prefs.getString('last_device_id');

      final bool isFirst = (savedDeviceName == null || savedDeviceId == null);
      emit(state.copyWith(
        status: BleStatus.initializing,
        message: "Initializing Bluetooth",
        isFirstConnection: isFirst,
      ));

      if (!isFirst) {
        _scanForLastDevice();
      } else {
        _scanForAllDevices();
      }
    });
  }

  Future<void> _waitForBluetoothOn(Future<void> Function() onReady) async {
    if (await FlutterBluePlus.isSupported == false) {
      emit(state.copyWith(
        status: BleStatus.error,
        message: "Bluetooth not supported",
      ));
      return;
    }

    final currentState = await FlutterBluePlus.adapterState.first;
    if (currentState == BluetoothAdapterState.on) {
      await onReady();
      return;
    }

    emit(state.copyWith(
      status: BleStatus.error,
      message: "Please turn on Bluetooth",
    ));

    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first;

    await onReady();
  }

  void _scanForLastDevice() {
    if (savedDeviceId == null && savedDeviceName == null) return;

    emit(state.copyWith(
      status: BleStatus.scanning,
      message: "Scanning for Sipnudge device...",
    ));

    _scanSub?.cancel();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (var r in results) {
        // ✅ Filter for only Sipnudge devices
        final deviceName = r.device.name.toLowerCase();
        if (!deviceName.contains('sipnudge')) continue;

        if (r.device.id.id == savedDeviceId ||
            r.device.name == savedDeviceName) {
          _scanSub?.cancel();
          FlutterBluePlus.stopScan();
          _connectToDevice(r.device);
          return;
        }
      }
    }, onError: (e) {
      emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
      _rescan(lastDeviceOnly: true);
    });

    Future.delayed(const Duration(seconds: 20), () {
      if (state.status == BleStatus.scanning) {
        FlutterBluePlus.stopScan().then((_) => _scanForLastDevice());
      }
    });
  }

  // void _scanForLastDevice() {
  //   if (savedDeviceId == null && savedDeviceName == null) return;

  //   emit(state.copyWith(
  //     status: BleStatus.scanning,
  //     message: "Scanning for last device...",
  //   ));

  //   _scanSub?.cancel();
  //   FlutterBluePlus.startScan(
  //     timeout: const Duration(seconds: 20),
  //     withServices: [serviceUUID],
  //   );

  //   _scanSub = FlutterBluePlus.scanResults.listen((results) {
  //     for (var r in results) {
  //       if (r.device.id.id == savedDeviceId ||
  //           r.device.name == savedDeviceName) {
  //         _scanSub?.cancel();
  //         FlutterBluePlus.stopScan();
  //         _connectToDevice(r.device);
  //         return;
  //       }
  //     }
  //   }, onError: (e) {
  //     emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
  //     _rescan(lastDeviceOnly: true);
  //   });

  //   Future.delayed(const Duration(seconds: 20), () {
  //     if (state.status == BleStatus.scanning) {
  //       FlutterBluePlus.stopScan().then((_) => _scanForLastDevice());
  //     }
  //   });
  // }

  void _scanForAllDevices() {
    emit(state.copyWith(
      status: BleStatus.scanning,
      message: "Scanning for Sipnudge devices...",
    ));

    _scanSub?.cancel();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (results.isNotEmpty) {
        // ✅ Only include devices with "Sipnudge" in their name
        var filtered = results.where((it) {
          final name = it.device.name.toLowerCase();
          return name.contains('sipnudge');
        }).toList();

        if (filtered.isNotEmpty) {
          emit(state.copyWith(scannedDevices: filtered));
        }
      }
    }, onError: (e) {
      emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
      _rescan();
    });

    Future.delayed(const Duration(seconds: 20), () async {
      if (state.status == BleStatus.scanning) {
        FlutterBluePlus.stopScan().then((_) => _scanForAllDevices());
      }
    });
  }

  // void _scanForAllDevices() {
  //   emit(state.copyWith(
  //     status: BleStatus.scanning,
  //     message: "Scanning for BLE devices...",
  //   ));

  //   _scanSub?.cancel();
  //   FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

  //   _scanSub = FlutterBluePlus.scanResults.listen((results) {
  //     if (results.isNotEmpty) {
  //       var filtered = results
  //           .where(
  //               (it) => it.advertisementData.serviceUuids.contains(serviceUUID))
  //           .toList();
  //       emit(state.copyWith(scannedDevices: filtered));
  //     }
  //   }, onError: (e) {
  //     emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
  //     _rescan();
  //   });

  //   Future.delayed(const Duration(seconds: 20), () async {
  //     if (state.status == BleStatus.scanning) {
  //       FlutterBluePlus.stopScan().then((_) => _scanForAllDevices());
  //     }
  //   });
  // }

  Future<void> _rescan({
    bool lastDeviceOnly = false,
    Duration delay = const Duration(milliseconds: 200),
  }) async {
    if (FlutterBluePlus.isScanningNow) return;
    await Future.delayed(delay);
    if (lastDeviceOnly) {
      _scanForLastDevice();
    } else {
      _scanForAllDevices();
    }
  }

  // ---------------------------------------------------------------------------
  // BLE connection
  // ---------------------------------------------------------------------------

  Future<void> connectToSelectedDevice(BluetoothDevice device) async {
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _connectToDevice(device);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    emit(state.copyWith(
      status: BleStatus.connecting,
      message: "Connecting to ${device.name}...",
    ));

    try {
      await device.connect(autoConnect: false, timeout: Duration(seconds: 6));
      await device.connectionState
          .where((s) => s == BluetoothConnectionState.connected)
          .first;

      _listenToConnection(device);

      final prefs = await SharedPreferences.getInstance();
      final wasFirst = (savedDeviceId == null || savedDeviceName == null);
      await prefs.setString('last_device_id', device.id.id);
      await prefs.setString('last_device_name', device.name);

      savedDeviceId = device.id.id;
      savedDeviceName = device.name;
      if (wasFirst) emit(state.copyWith(isFirstConnection: false));

      await _discoverServices(device);
      await prefs.setBool('ble_connected_once', true);
    } catch (e) {
      emit(state.copyWith(
          status: BleStatus.error, message: "Connection failed: $e"));
      _rescan(
          lastDeviceOnly: (savedDeviceId != null || savedDeviceName != null));
    }
  }

  // ---------------------------------------------------------------------------
  // Service Discovery + Notification setup
  // ---------------------------------------------------------------------------

  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid == serviceUUID) {
          for (var c in s.characteristics) {
            if (c.uuid == dataUUID) _dataChar = c;
            if (c.uuid == ackUUID) _ackChar = c;
            if (c.uuid == hydrationDataUUID) _hydrationDataChar = c;
            if (c.uuid == hydrationCharUUID) _hydrationChar = c; // ✅ new
          }
        }
      }

      if (_dataChar == null || _ackChar == null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_device_id');
        await prefs.remove('last_device_name');

        savedDeviceId = null;
        savedDeviceName = null;

        emit(state.copyWith(
          status: BleStatus.error,
          message: "Required characteristics not found",
          isFirstConnection: true,
        ));

        await device.disconnect();
        _rescan(lastDeviceOnly: false);
        return;
      }

      // 🩵 Main data (battery, volume, percent)
      _dataChar!.onValueReceived.listen((value) {
        final data = String.fromCharCodes(value);
        log("Received data: $data", name: "BLE_Cubit");
        _parseData(data);
        _sendAck(device);
      });
      await _dataChar!.setNotifyValue(true);

      // // 💧 Hydration history data
      // _hydrationDataChar?.onValueReceived.listen((value) {
      //   final data = String.fromCharCodes(value);
      //   log("HydrationDataReceived: $data", name: "BLE_Cubit");
      //   var slots = _parseHydrationData(data);
      //   if (slots.isNotEmpty) _hydrationController.add(slots);
      //   _sendAck(device, sendAckToHydrationSlotsCharacteristic: true);
      // });
      // await _hydrationDataChar?.setNotifyValue(true);

      // 🔹 NEW: Real-time hydration slot data (slotId/Target/Consumed)
      if (_hydrationChar != null) {
        await _hydrationChar!.setNotifyValue(true);
        _hydrationChar!.onValueReceived.listen((value) async {
          final data = String.fromCharCodes(value);
          final entry = _parseHydrationSlotData(data);

          if (entry != null) {
            final updated = List<HydrationEntry>.from(state.hydrationEntries);
            updated[entry.slot.index] = entry;

            emit(state.copyWith(hydrationEntries: updated));

            // Save to database
            await dbHelper.insertOrUpdateSlot(entry);
            //await DatabaseHelper.instance.insertOrUpdateSlot(entry);
          }
        });

        // _hydrationChar!.onValueReceived.listen((value) async {
        //   final data = String.fromCharCodes(value);
        //   final updatedEntry = _parseHydrationSlotData(data);

        //   if (updatedEntry != null) {
        //     // Take the existing hydration entries from state
        //     final updatedList =
        //         List<HydrationEntry>.from(state.hydrationEntries);

        //     // Find the matching slot
        //     final index =
        //         updatedList.indexWhere((e) => e.slot == updatedEntry.slot);

        //     if (index != -1) {
        //       // Update the existing entry with new amount and waterDrank
        //       updatedList[index] = updatedList[index].copyWith(
        //         //amount: updatedEntry.amount,
        //         targetIntake: updatedEntry.targetIntake,
        //         waterDrank: updatedEntry.waterDrank,
        //       );
        //     }

        //     // Emit the new state so the UI rebuilds
        //     emit(state.copyWith(hydrationEntries: updatedList));
        //   }
        // });
      }

      emit(state.copyWith(
        status: BleStatus.connected,
        message: "Connected to ${device.name}",
      ));

      await _flushPendingSlots();
    } catch (e) {
      try {
        await device.disconnect();
      } catch (_) {}

      emit(state.copyWith(
        status: BleStatus.error,
        message: "Service discovery failed: $e",
      ));
      _rescan(lastDeviceOnly: savedDeviceId != null || savedDeviceName != null);
    }
  }

  // ---------------------------------------------------------------------------
  // Data parsing and ACK
  // ---------------------------------------------------------------------------

  void _parseData(String data) {
    final parts = data.split(';');
    int? battery;
    double? volume;
    int? percent;

    for (var p in parts) {
      if (p.contains('battery=')) battery = int.tryParse(p.split('=')[1]);
      if (p.contains('volume=')) volume = double.tryParse(p.split('=')[1]);
      if (p.contains('percent=')) percent = int.tryParse(p.split('=')[1]);
    }

    emit(state.copyWith(battery: battery, volume: volume, percent: percent));
  }

  // List<HydrationEntry> _parseHydrationData(String payload) {
  //   if (payload.isEmpty || payload.toLowerCase() == "na") return [];
  //   return payload.split("|").map((entry) {
  //     final parts = entry.split("/");
  //     if (parts.length < 5) throw FormatException("Invalid payload: $entry");

  //     final index = int.parse(parts[1]);
  //     final startEpoch = int.parse(parts[2]);
  //     final endEpoch = int.parse(parts[3]);
  //     final amount = int.parse(parts[4]);

  //     final slot = HydrationSlot.values[index];
  //     return HydrationEntry(
  //       slot: slot,
  //       startTime: _epochToTimeOfDay(startEpoch),
  //       endTime: _epochToTimeOfDay(endEpoch),
  //       waterDrank: amount.toDouble(),
  //       targetIntake: 0,
  //       //amount: 0,
  //     );
  //   }).toList();
  // }

  // HydrationEntry? _parseHydrationSlotData(String payload) {
  //   try {
  //     if (payload.isEmpty || payload.toLowerCase() == 'na') return null;

  //     final parts = payload.split('/');
  //     if (parts.length < 3)
  //       throw FormatException("Invalid slot payload: $payload");

  //     // final slotId = int.parse(parts[0]);
  //     // final target = double.parse(parts[1]);
  //     // final consumed = double.parse(parts[2]);
  //     final slotIndex = int.parse(parts[0].split(':')[1]);
  //     final targetIntake = double.parse(parts[1].split(':')[1]);
  //     final waterDrank = double.parse(parts[2].split(':')[1]);

  //     final slot = HydrationSlot.values[slotIndex];

  //     if (slotIndex < 0 || slotIndex >= HydrationSlot.values.length) {
  //       throw RangeError("Invalid slot index: $slotIndex");
  //     }

  //     //final slot = HydrationSlot.values[slotIndex];
  //     final now = DateTime.now();

  //     return HydrationEntry(
  //       slot: slot,
  //       startTime: TimeOfDay(hour: now.hour, minute: now.minute),
  //       endTime: TimeOfDay(hour: now.hour, minute: now.minute + 1),
  //       amount: 0,
  //       targetIntake: targetIntake,
  //       waterDrank: waterDrank,
  //       status: waterDrank >= targetIntake
  //           ? HydrationStatus.completed
  //           : HydrationStatus.pending,
  //     );
  //   } catch (e) {
  //     log("Failed to parse hydration slot data: $e", name: "BLE_Cubit");
  //     return null;
  //   }
  // }
  HydrationEntry? _parseHydrationSlotData(String data) {
    try {
      final parts = data.split('/'); // [slot, target, consumed]
      if (parts.length != 3) return null;

      final slotIndex = int.parse(parts[0]);
      final targetIntake = double.parse(parts[1]);
      final waterDrank = double.parse(parts[2]);

      final slot = HydrationSlot.values[slotIndex];

      return HydrationEntry(
        slot: slot,
        startTime: const TimeOfDay(hour: 6, minute: 0),
        endTime: const TimeOfDay(hour: 7, minute: 0),
        targetIntake: targetIntake,
        waterDrank: waterDrank,
        status: waterDrank >= targetIntake
            ? HydrationStatus.completed
            : HydrationStatus.pending,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendAck(BluetoothDevice device,
      {bool sendAckToHydrationSlotsCharacteristic = false}) async {
    try {
      if (sendAckToHydrationSlotsCharacteristic) {
        await _hydrationDataChar?.write("ACK".codeUnits, withoutResponse: true);
      } else {
        await _ackChar?.write("ACK".codeUnits, withoutResponse: true);
      }
    } catch (e) {
      log("ACK failed: $e", name: "BLE_Cubit");
    }
  }

  // ---------------------------------------------------------------------------
  // Utilities + Hydration sync
  // ---------------------------------------------------------------------------

  void _listenToConnection(BluetoothDevice device) {
    _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen((stateChange) {
      switch (stateChange) {
        case BluetoothConnectionState.connected:
          emit(state.copyWith(
            status: BleStatus.connected,
            message: "Connected to ${device.name}",
          ));
          break;
        case BluetoothConnectionState.disconnected:
          emit(state.copyWith(
            status: BleStatus.disconnected,
            message: "Device disconnected",
          ));
          if (savedDeviceId != null || savedDeviceName != null) {
            _rescan(lastDeviceOnly: true);
          }
          break;
        default:
          break;
      }
    });
  }

  Future<void> _flushPendingSlots() async {
    if (_ackChar == null || _pendingSlots.isEmpty) return;

    try {
      final payload = _pendingSlots.map((slot) {
        final start = _timeOfDayToEpoch(slot.startTime);
        final end = _timeOfDayToEpoch(slot.endTime);
        return "${slot.slot.label}/${slot.slot.index}/$start/$end/${slot.targetIntake}";
      }).join("|");

      log("Flushing hydration slots: $payload");
      await _ackChar!.write(payload.codeUnits, withoutResponse: true);
      _pendingSlots.clear();

      emit(state.copyWith(
        status: BleStatus.connected,
        message: "Hydration slots synced",
      ));
    } catch (e) {
      emit(
          state.copyWith(status: BleStatus.error, message: "Flush failed: $e"));
    }
  }

  int _timeOfDayToEpoch(TimeOfDay tod) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return dt.millisecondsSinceEpoch ~/ 1000;
  }

  TimeOfDay _epochToTimeOfDay(int epoch) {
    final date = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    return TimeOfDay(hour: date.hour, minute: date.minute);
  }

  @override
  Future<void> queueHydrationSlots(List<HydrationEntry> entries) async {
    _pendingSlots.clear();
    _pendingSlots.addAll(entries);
    if (state.status == BleStatus.connected) {
      await _flushPendingSlots();
    } else {
      emit(state.copyWith(message: "Device not connected, will sync later"));
    }
  }

  Future<void> forgetDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_device_id');
    await prefs.remove('last_device_name');

    savedDeviceId = null;
    savedDeviceName = null;

    emit(
      state.copyWith(
        status: BleStatus.scanning,
        isFirstConnection: true,
        message: "Device forgotten. \nReady to scan for new devices.",
      ),
    );

    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    emit(
      state.copyWith(
        status: BleStatus.scanning,
        isFirstConnection: true,
        scannedDevices: [],
        message: "Device forgotten. \nReady to scan for new devices.",
      ),
    );

    _scanForAllDevices();
  }

  @override
  Stream<List<HydrationEntry>> get hydrationUpdates =>
      _hydrationController.stream;
}

//======================================================================

// // // ble_cubit.dart (replace your current file with this)
// // import 'dart:async';
// // import 'dart:developer';
// // import 'package:bloc/bloc.dart';
// // import 'package:flutter/material.dart';
// // import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// // import 'package:hydrify/cubit/hydration/hydration_sync.dart';
// // import 'package:hydrify/helpers/database_helper.dart';
// // import 'package:hydrify/models/hydration_entry.dart';
// // import 'package:shared_preferences/shared_preferences.dart';

// // part 'ble_state.dart';

// // class BleCubit extends Cubit<BleState> implements HydrationSync {
// //   BleCubit() : super(const BleState());
// //   final _hydrationController =
// //       StreamController<List<HydrationEntry>>.broadcast();

// //   // UUIDs
// //   final Guid serviceUUID = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid dataUUID = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid hydrationDataUUID = Guid("6E400004-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid ackUUID = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid hydrationCharUUID =
// //       Guid("6E400005-B5A3-F393-E0A9-E50E24DCCA9E"); // slots
// //   final Guid waterDataBufUUID =
// //       Guid("6E400006-B5A3-F393-E0A9-E50E24DCCA9E"); // large buffer

// //   // Characteristics
// //   BluetoothCharacteristic? _dataChar;
// //   BluetoothCharacteristic? _ackChar;
// //   BluetoothCharacteristic? _hydrationDataChar; // short history
// //   BluetoothCharacteristic? _hydrationChar; // slots realtime
// //   BluetoothCharacteristic? _waterDataChar; // 30-day buffer

// //   StreamSubscription<List<ScanResult>>? _scanSub;
// //   StreamSubscription<BluetoothConnectionState>? _connectionSub;

// //   String? savedDeviceName;
// //   String? savedDeviceId;

// //   final dbHelper = DatabaseHelper();
// //   final List<HydrationEntry> _pendingSlots = [];

// //   // -----------------------
// //   // START / SCAN / CONNECT
// //   // -----------------------
// //   Future<void> start() async {
// //     emit(state.copyWith(
// //       status: BleStatus.initializing,
// //       message: "Initializing...",
// //     ));

// //     await _waitForBluetoothOn(() async {
// //       final prefs = await SharedPreferences.getInstance();
// //       savedDeviceName = prefs.getString('last_device_name');
// //       savedDeviceId = prefs.getString('last_device_id');

// //       final bool isFirst = (savedDeviceName == null || savedDeviceId == null);
// //       emit(state.copyWith(
// //         status: BleStatus.initializing,
// //         message: "Initializing Bluetooth",
// //         isFirstConnection: isFirst,
// //       ));

// //       if (!isFirst) {
// //         _scanForLastDevice();
// //       } else {
// //         _scanForAllDevices();
// //       }
// //     });
// //   }

// //   Future<void> _waitForBluetoothOn(Future<void> Function() onReady) async {
// //     if (await FlutterBluePlus.isSupported == false) {
// //       emit(state.copyWith(
// //         status: BleStatus.error,
// //         message: "Bluetooth not supported",
// //       ));
// //       return;
// //     }

// //     final currentState = await FlutterBluePlus.adapterState.first;
// //     if (currentState == BluetoothAdapterState.on) {
// //       await onReady();
// //       return;
// //     }

// //     emit(state.copyWith(
// //       status: BleStatus.error,
// //       message: "Please turn on Bluetooth",
// //     ));

// //     await FlutterBluePlus.adapterState
// //         .where((s) => s == BluetoothAdapterState.on)
// //         .first;

// //     await onReady();
// //   }

// //   void _scanForLastDevice() {
// //     if (savedDeviceId == null && savedDeviceName == null) return;

// //     emit(state.copyWith(
// //       status: BleStatus.scanning,
// //       message: "Scanning for Sipnudge device...",
// //     ));

// //     _scanSub?.cancel();
// //     FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

// //     _scanSub = FlutterBluePlus.scanResults.listen((results) {
// //       for (var r in results) {
// //         final deviceName = r.device.name.toLowerCase();
// //         if (!deviceName.contains('sipnudge')) continue;

// //         if (r.device.id.id == savedDeviceId ||
// //             r.device.name == savedDeviceName) {
// //           _scanSub?.cancel();
// //           FlutterBluePlus.stopScan();
// //           _connectToDevice(r.device);
// //           return;
// //         }
// //       }
// //     }, onError: (e) {
// //       emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
// //       _rescan(lastDeviceOnly: true);
// //     });

// //     Future.delayed(const Duration(seconds: 20), () {
// //       if (state.status == BleStatus.scanning) {
// //         FlutterBluePlus.stopScan().then((_) => _scanForLastDevice());
// //       }
// //     });
// //   }

// //   void _scanForAllDevices() {
// //     emit(state.copyWith(
// //       status: BleStatus.scanning,
// //       message: "Scanning for Sipnudge devices...",
// //     ));

// //     _scanSub?.cancel();
// //     FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

// //     _scanSub = FlutterBluePlus.scanResults.listen((results) {
// //       if (results.isNotEmpty) {
// //         var filtered = results.where((it) {
// //           final name = it.device.name.toLowerCase();
// //           return name.contains('sipnudge');
// //         }).toList();

// //         if (filtered.isNotEmpty) {
// //           emit(state.copyWith(scannedDevices: filtered));
// //         }
// //       }
// //     }, onError: (e) {
// //       emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
// //       _rescan();
// //     });

// //     Future.delayed(const Duration(seconds: 20), () async {
// //       if (state.status == BleStatus.scanning) {
// //         FlutterBluePlus.stopScan().then((_) => _scanForAllDevices());
// //       }
// //     });
// //   }

// //   Future<void> _rescan({
// //     bool lastDeviceOnly = false,
// //     Duration delay = const Duration(milliseconds: 200),
// //   }) async {
// //     if (FlutterBluePlus.isScanningNow) return;
// //     await Future.delayed(delay);
// //     if (lastDeviceOnly) {
// //       _scanForLastDevice();
// //     } else {
// //       _scanForAllDevices();
// //     }
// //   }

// //   Future<void> connectToSelectedDevice(BluetoothDevice device) async {
// //     FlutterBluePlus.stopScan();
// //     _scanSub?.cancel();
// //     _connectToDevice(device);
// //   }

// //   Future<void> _connectToDevice(BluetoothDevice device) async {
// //     emit(state.copyWith(
// //       status: BleStatus.connecting,
// //       message: "Connecting to ${device.name}...",
// //     ));

// //     try {
// //       await device.connect(autoConnect: false, timeout: Duration(seconds: 8));
// //       await device.connectionState
// //           .where((s) => s == BluetoothConnectionState.connected)
// //           .first;

// //       _listenToConnection(device);

// //       final prefs = await SharedPreferences.getInstance();
// //       final wasFirst = (savedDeviceId == null || savedDeviceName == null);
// //       await prefs.setString('last_device_id', device.id.id);
// //       await prefs.setString('last_device_name', device.name);

// //       savedDeviceId = device.id.id;
// //       savedDeviceName = device.name;
// //       if (wasFirst) emit(state.copyWith(isFirstConnection: false));

// //       await _discoverServices(device);
// //       await prefs.setBool('ble_connected_once', true);
// //     } catch (e) {
// //       emit(state.copyWith(
// //           status: BleStatus.error, message: "Connection failed: $e"));
// //       _rescan(
// //           lastDeviceOnly: (savedDeviceId != null || savedDeviceName != null));
// //     }
// //   }

// //   Future<void> _discoverServices(BluetoothDevice device) async {
// //     try {
// //       final services = await device.discoverServices();
// //       for (var s in services) {
// //         if (s.uuid == serviceUUID) {
// //           for (var c in s.characteristics) {
// //             if (c.uuid == dataUUID) _dataChar = c;
// //             if (c.uuid == ackUUID) _ackChar = c;
// //             if (c.uuid == hydrationDataUUID) _hydrationDataChar = c;
// //             if (c.uuid == hydrationCharUUID) _hydrationChar = c;
// //             if (c.uuid == waterDataBufUUID) _waterDataChar = c;
// //           }
// //         }
// //       }

// //       if (_dataChar == null || _ackChar == null) {
// //         final prefs = await SharedPreferences.getInstance();
// //         await prefs.remove('last_device_id');
// //         await prefs.remove('last_device_name');

// //         savedDeviceId = null;
// //         savedDeviceName = null;

// //         emit(state.copyWith(
// //           status: BleStatus.error,
// //           message: "Required characteristics not found",
// //           isFirstConnection: true,
// //         ));

// //         await device.disconnect();
// //         _rescan(lastDeviceOnly: false);
// //         return;
// //       }

// //       // main data
// //       _dataChar!.onValueReceived.listen((value) {
// //         final data = String.fromCharCodes(value);
// //         log("Received data: $data", name: "BLE_Cubit");
// //         _parseData(data);
// //         _sendAck(device);
// //       });
// //       await _dataChar!.setNotifyValue(true);

// //       // hydration short history
// //       _hydrationDataChar?.onValueReceived.listen((value) {
// //         final data = String.fromCharCodes(value);
// //         log("HydrationDataReceived: $data", name: "BLE_Cubit");
// //         final slots = _parseHydrationData(data);
// //         if (slots.isNotEmpty) _hydrationController.add(slots);
// //         _sendAck(device, sendAckToHydrationSlotsCharacteristic: true);
// //       });
// //       await _hydrationDataChar?.setNotifyValue(true);

// //       // slots realtime
// //       if (_hydrationChar != null) {
// //         await _hydrationChar!.setNotifyValue(true);
// //         _hydrationChar!.onValueReceived.listen((value) async {
// //           final raw = String.fromCharCodes(value);
// //           log("Hydration SLOT raw → $raw", name: "BLE_Cubit");

// //           // support multiple chunks separated by '|'
// //           final chunks = raw.split('|');
// //           final updatedEntries = <HydrationEntry>[];

// //           for (var chunk in chunks) {
// //             final trimmed = chunk.trim();
// //             if (trimmed.isEmpty) continue;
// //             final entry = _parseHydrationSlotData(trimmed);
// //             if (entry != null) {
// //               updatedEntries.add(entry);

// //               // persist and update in-memory state
// //               try {
// //                 await dbHelper.insertOrUpdateSlot(entry);
// //               } catch (e) {
// //                 log("DB error insert/update slot: $e");
// //               }

// //               // in-place update to state.hydrationEntries
// //               final current =
// //                   List<HydrationEntry>.from(state.hydrationEntries ?? []);
// //               if (entry.slot.index < current.length) {
// //                 current[entry.slot.index] = entry;
// //               } else {
// //                 // fill gaps
// //                 while (current.length <= entry.slot.index) {
// //                   final s = HydrationSlot.values[current.length];
// //                   current.add(HydrationEntry(
// //                     slot: s,
// //                     startTime: const TimeOfDay(hour: 0, minute: 0),
// //                     endTime: const TimeOfDay(hour: 0, minute: 0),
// //                     amount: 0,
// //                     targetIntake: 0,
// //                     waterDrank: 0,
// //                   ));
// //                 }
// //                 current[entry.slot.index] = entry;
// //               }
// //               emit(state.copyWith(hydrationEntries: current));
// //             }
// //           }

// //           if (updatedEntries.isNotEmpty) {
// //             _hydrationController.add(updatedEntries);
// //             emit(state.copyWith(
// //                 message: "Updated ${updatedEntries.length} slot(s)"));
// //           }

// //           _sendAck(device);
// //         });
// //       }

// //       // 30-day buffer
// //       if (_waterDataChar != null) {
// //         await _waterDataChar!.setNotifyValue(true);
// //         _waterDataChar!.onValueReceived.listen((value) {
// //           final raw = String.fromCharCodes(value);
// //           log("WATER BUFFER raw → $raw", name: "BLE_Cubit");
// //           final history = _parseWaterHistoryData(raw);
// //           // you can expose history via state or other stream if needed
// //           emit(state.copyWith(waterHistory: history));
// //           _sendAck(device);
// //         });
// //       }

// //       emit(state.copyWith(
// //         status: BleStatus.connected,
// //         message: "Connected to ${device.name}",
// //       ));

// //       await _flushPendingSlots();
// //     } catch (e) {
// //       try {
// //         await device.disconnect();
// //       } catch (_) {}
// //       emit(state.copyWith(
// //         status: BleStatus.error,
// //         message: "Service discovery failed: $e",
// //       ));
// //       _rescan(lastDeviceOnly: savedDeviceId != null || savedDeviceName != null);
// //     }
// //   }

// //   // -----------------------
// //   // Parsing helpers
// //   // -----------------------

// //   void _parseData(String data) {
// //     final parts = data.split(';');
// //     int? battery;
// //     double? volume;
// //     int? percent;

// //     for (var p in parts) {
// //       if (p.contains('battery=')) battery = int.tryParse(p.split('=')[1]);
// //       if (p.contains('volume=')) volume = double.tryParse(p.split('=')[1]);
// //       if (p.contains('percent=')) percent = int.tryParse(p.split('=')[1]);
// //     }

// //     emit(state.copyWith(battery: battery, volume: volume, percent: percent));
// //   }

// //   /// Parse hydration history short format (slotsBuf) - sets targetIntake and consumed where available
// //   List<HydrationEntry> _parseHydrationData(String payload) {
// //     if (payload.isEmpty || payload.toLowerCase() == "na") return [];
// //     final results = <HydrationEntry>[];

// //     final chunks = payload.split('|');
// //     for (var c in chunks) {
// //       final s = c.trim();
// //       if (s.isEmpty) continue;

// //       // sanitize and extract numbers
// //       final nums =
// //           RegExp(r'-?\d+').allMatches(s).map((m) => m.group(0)!).toList();
// //       if (nums.length >= 3) {
// //         final index = int.parse(nums[0]);
// //         final target = double.tryParse(nums[1]) ?? 0;
// //         final consumed = double.tryParse(nums[2]) ?? 0;

// //         final slot = HydrationSlot
// //             .values[index.clamp(0, HydrationSlot.values.length - 1)];
// //         results.add(HydrationEntry(
// //           slot: slot,
// //           startTime: _epochToTimeOfDay(0),
// //           endTime: _epochToTimeOfDay(0),
// //           amount: 0,
// //           targetIntake: target,
// //           waterDrank: consumed,
// //           status: consumed >= target
// //               ? HydrationStatus.completed
// //               : HydrationStatus.pending,
// //         ));
// //       } else {
// //         log("Skipped hydrationData chunk (unexpected format): '$s'");
// //       }
// //     }

// //     return results;
// //   }

// //   /// Parse a single slot payload (robust)
// //   HydrationEntry? _parseHydrationSlotData(String data) {
// //     try {
// //       // remove invisible chars
// //       final clean = data.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();

// //       // Extract numeric tokens (handles many separators)
// //       final matches = RegExp(r'-?\d+(\.\d+)?').allMatches(clean).toList();

// //       // If format is slot/target/consumed -> we will get 3 numbers
// //       if (matches.length >= 3) {
// //         final slotIndex = int.parse(matches[0].group(0)!.split('.').first);
// //         final target = double.parse(matches[1].group(0)!);
// //         final consumed = double.parse(matches[2].group(0)!);

// //         final slot = HydrationSlot
// //             .values[slotIndex.clamp(0, HydrationSlot.values.length - 1)];

// //         return HydrationEntry(
// //           slot: slot,
// //           startTime: const TimeOfDay(hour: 0, minute: 0),
// //           endTime: const TimeOfDay(hour: 0, minute: 0),
// //           amount: 0,
// //           targetIntake: target,
// //           waterDrank: consumed,
// //           status: consumed >= target
// //               ? HydrationStatus.completed
// //               : HydrationStatus.pending,
// //         );
// //       }

// //       // fallback: if data contains "slot:" style keys like "slot:0,target:425,consumed:400"
// //       final Map<String, String> kv = {};
// //       for (final part in clean.split(RegExp(r'[,;|]'))) {
// //         final kvParts = part.split(':');
// //         if (kvParts.length >= 2) {
// //           kv[kvParts[0].trim().toLowerCase()] = kvParts[1].trim();
// //         }
// //       }
// //       if (kv.isNotEmpty &&
// //           (kv.containsKey('slot') || kv.containsKey('index'))) {
// //         final slotIndex = int.tryParse(kv['slot'] ?? kv['index'] ?? '0') ?? 0;
// //         final target = double.tryParse(kv['target'] ?? '0') ?? 0;
// //         final consumed =
// //             double.tryParse(kv['consumed'] ?? kv['drank'] ?? '0') ?? 0;
// //         final slot = HydrationSlot
// //             .values[slotIndex.clamp(0, HydrationSlot.values.length - 1)];
// //         return HydrationEntry(
// //           slot: slot,
// //           startTime: const TimeOfDay(hour: 0, minute: 0),
// //           endTime: const TimeOfDay(hour: 0, minute: 0),
// //           amount: 0,
// //           targetIntake: target,
// //           waterDrank: consumed,
// //           status: consumed >= target
// //               ? HydrationStatus.completed
// //               : HydrationStatus.pending,
// //         );
// //       }

// //       // unknown format
// //       log("Unknown slot format: '$data'");
// //       return null;
// //     } catch (e) {
// //       log("Error parsing slot data: $e");
// //       return null;
// //     }
// //   }

// //   /// Parse the long waterDataBuf and return list of day maps
// //   List<Map<String, dynamic>> _parseWaterHistoryData(String data) {
// //     try {
// //       if (data.isEmpty || data.toLowerCase() == 'na') return [];

// //       final parts = data
// //           .split('|')
// //           .map((p) => p.trim())
// //           .where((p) => p.isNotEmpty)
// //           .toList();
// //       if (parts.isEmpty) return [];

// //       // first token is base epoch (seconds)
// //       final baseEpoch = int.tryParse(parts.first) ?? 0;
// //       final history = <Map<String, dynamic>>[];

// //       for (int i = 1; i < parts.length; i++) {
// //         final token = parts[i];
// //         final nums = RegExp(r'-?\d+(\.\d+)?')
// //             .allMatches(token)
// //             .map((m) => m.group(0)!)
// //             .toList();
// //         if (nums.length >= 3) {
// //           final dayOffset = int.parse(nums[0]);
// //           final target = double.parse(nums[1]);
// //           final consumed = double.parse(nums[2]);
// //           final date = DateTime.fromMillisecondsSinceEpoch(
// //               (baseEpoch + dayOffset * 86400) * 1000);
// //           final percent = target == 0 ? 0.0 : (consumed / target) * 100.0;
// //           history.add({
// //             'date': date,
// //             'dayOffset': dayOffset,
// //             'target': target,
// //             'consumed': consumed,
// //             'percent': percent,
// //           });
// //         } else {
// //           // if token is epoch/amount or different format, try to parse two numbers: epoch and value
// //           final two = RegExp(r'-?\d+(\.\d+)?')
// //               .allMatches(token)
// //               .map((m) => m.group(0)!)
// //               .toList();
// //           if (two.length >= 2) {
// //             final epochMaybe = int.tryParse(two[0]) ?? 0;
// //             final total = double.tryParse(two[1]) ?? 0;
// //             final date = DateTime.fromMillisecondsSinceEpoch(epochMaybe * 1000);
// //             history.add({
// //               'date': date,
// //               'dayOffset': null,
// //               'target': null,
// //               'consumed': total,
// //               'percent': null,
// //             });
// //           } else {
// //             log("Skipped waterDataBuf token (unknown): '$token'");
// //           }
// //         }
// //       }

// //       log("Parsed water history: ${history.length} days");
// //       return history;
// //     } catch (e) {
// //       log("Failed to parse waterDataBuf: $e");
// //       return [];
// //     }
// //   }

// //   Future<void> _sendAck(BluetoothDevice device,
// //       {bool sendAckToHydrationSlotsCharacteristic = false}) async {
// //     try {
// //       if (sendAckToHydrationSlotsCharacteristic) {
// //         await _hydrationDataChar?.write("ACK".codeUnits, withoutResponse: true);
// //       } else {
// //         await _ackChar?.write("ACK".codeUnits, withoutResponse: true);
// //       }
// //     } catch (e) {
// //       log("ACK failed: $e", name: "BLE_Cubit");
// //     }
// //   }

// //   void _listenToConnection(BluetoothDevice device) {
// //     _connectionSub?.cancel();
// //     _connectionSub = device.connectionState.listen((stateChange) {
// //       switch (stateChange) {
// //         case BluetoothConnectionState.connected:
// //           emit(state.copyWith(
// //             status: BleStatus.connected,
// //             message: "Connected to ${device.name}",
// //           ));
// //           break;
// //         case BluetoothConnectionState.disconnected:
// //           emit(state.copyWith(
// //             status: BleStatus.disconnected,
// //             message: "Device disconnected",
// //           ));
// //           if (savedDeviceId != null || savedDeviceName != null) {
// //             _rescan(lastDeviceOnly: true);
// //           }
// //           break;
// //         default:
// //           break;
// //       }
// //     });
// //   }

// //   Future<void> _flushPendingSlots() async {
// //     if (_ackChar == null || _pendingSlots.isEmpty) return;

// //     try {
// //       final payload = _pendingSlots.map((slot) {
// //         final start = _timeOfDayToEpoch(slot.startTime);
// //         final end = _timeOfDayToEpoch(slot.endTime);
// //         return "${slot.slot.label}/${slot.slot.index}/$start/$end/${slot.amount}";
// //       }).join("|");

// //       log("Flushing hydration slots: $payload");
// //       await _ackChar!.write(payload.codeUnits, withoutResponse: true);
// //       _pendingSlots.clear();

// //       emit(state.copyWith(
// //         status: BleStatus.connected,
// //         message: "Hydration slots synced",
// //       ));
// //     } catch (e) {
// //       emit(
// //           state.copyWith(status: BleStatus.error, message: "Flush failed: $e"));
// //     }
// //   }

// //   int _timeOfDayToEpoch(TimeOfDay tod) {
// //     final now = DateTime.now();
// //     final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
// //     return dt.millisecondsSinceEpoch ~/ 1000;
// //   }

// //   TimeOfDay _epochToTimeOfDay(int epoch) {
// //     if (epoch <= 0) return const TimeOfDay(hour: 0, minute: 0);
// //     final date = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
// //     return TimeOfDay(hour: date.hour, minute: date.minute);
// //   }

// //   @override
// //   Future<void> queueHydrationSlots(List<HydrationEntry> entries) async {
// //     _pendingSlots.clear();
// //     _pendingSlots.addAll(entries);
// //     if (state.status == BleStatus.connected) {
// //       await _flushPendingSlots();
// //     } else {
// //       emit(state.copyWith(message: "Device not connected, will sync later"));
// //     }
// //   }

// //   Future<void> forgetDevice() async {
// //     final prefs = await SharedPreferences.getInstance();
// //     await prefs.remove('last_device_id');
// //     await prefs.remove('last_device_name');

// //     savedDeviceId = null;
// //     savedDeviceName = null;

// //     emit(
// //       state.copyWith(
// //         status: BleStatus.scanning,
// //         isFirstConnection: true,
// //         message: "Device forgotten. \nReady to scan for new devices.",
// //       ),
// //     );

// //     if (FlutterBluePlus.isScanningNow) {
// //       await FlutterBluePlus.stopScan();
// //     }
// //     emit(
// //       state.copyWith(
// //         status: BleStatus.scanning,
// //         isFirstConnection: true,
// //         scannedDevices: [],
// //         message: "Device forgotten. \nReady to scan for new devices.",
// //       ),
// //     );

// //     _scanForAllDevices();
// //   }

// //   @override
// //   Stream<List<HydrationEntry>> get hydrationUpdates =>
// //       _hydrationController.stream;
// // }

// //===================================================================

// // // // ble_cubit.dart
// // import 'dart:async';
// // import 'dart:developer';
// // import 'package:bloc/bloc.dart';
// // import 'package:flutter/material.dart';
// // import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// // import 'package:fluttertoast/fluttertoast.dart';
// // import 'package:hydrify/cubit/hydration/hydration_sync.dart';
// // import 'package:hydrify/helpers/database_helper.dart';
// // import 'package:hydrify/models/hydration_entry.dart';
// // import 'package:shared_preferences/shared_preferences.dart';

// // part 'ble_state.dart';

// // class BleCubit extends Cubit<BleState> implements HydrationSync {
// //   BleCubit() : super(const BleState());
// //   final _hydrationController =
// //       StreamController<List<HydrationEntry>>.broadcast();

// //   // UUIDs
// //   final Guid serviceUUID = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid dataUUID = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid hydrationDataUUID = Guid("6E400004-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid ackUUID = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid hydrationCharUUID =
// //       Guid("6E400005-B5A3-F393-E0A9-E50E24DCCA9E"); // slots
// //   final Guid waterDataBufUUID =
// //       Guid("6E400006-B5A3-F393-E0A9-E50E24DCCA9E"); // large buffer

// //   // Characteristics (flutter_blue_plus types)
// //   BluetoothCharacteristic? _dataChar;
// //   BluetoothCharacteristic? _ackChar;
// //   BluetoothCharacteristic? _hydrationDataChar; // history small
// //   BluetoothCharacteristic? _hydrationChar; // slots real-time (SLOTS_UUID)
// //   BluetoothCharacteristic? _waterDataChar; // waterDataBuf (WATER_DATA_UUID)

// //   StreamSubscription<List<ScanResult>>? _scanSub;
// //   StreamSubscription<BluetoothConnectionState>? _connectionSub;

// //   String? savedDeviceName;
// //   String? savedDeviceId;

// //   final bool _isReconnecting = false;
// //   final dbHelper = DatabaseHelper();
// //   final List<HydrationEntry> _pendingSlots = [];

// //   // ---------------------------------------------------------------------------
// //   // BLE initialization and scanning
// //   // ---------------------------------------------------------------------------

// //   Future<void> start() async {
// //     emit(state.copyWith(
// //       status: BleStatus.initializing,
// //       message: "Initializing...",
// //     ));

// //     await _waitForBluetoothOn(() async {
// //       final prefs = await SharedPreferences.getInstance();
// //       savedDeviceName = prefs.getString('last_device_name');
// //       savedDeviceId = prefs.getString('last_device_id');

// //       final bool isFirst = (savedDeviceName == null || savedDeviceId == null);
// //       emit(state.copyWith(
// //         status: BleStatus.initializing,
// //         message: "Initializing Bluetooth",
// //         isFirstConnection: isFirst,
// //       ));

// //       if (!isFirst) {
// //         _scanForLastDevice();
// //       } else {
// //         _scanForAllDevices();
// //       }
// //     });
// //   }

// //   Future<void> _waitForBluetoothOn(Future<void> Function() onReady) async {
// //     if (await FlutterBluePlus.isSupported == false) {
// //       emit(state.copyWith(
// //         status: BleStatus.error,
// //         message: "Bluetooth not supported",
// //       ));
// //       return;
// //     }

// //     final currentState = await FlutterBluePlus.adapterState.first;
// //     if (currentState == BluetoothAdapterState.on) {
// //       await onReady();
// //       return;
// //     }

// //     emit(state.copyWith(
// //       status: BleStatus.error,
// //       message: "Please turn on Bluetooth",
// //     ));

// //     await FlutterBluePlus.adapterState
// //         .where((s) => s == BluetoothAdapterState.on)
// //         .first;

// //     await onReady();
// //   }

// //   void _scanForLastDevice() {
// //     if (savedDeviceId == null && savedDeviceName == null) return;

// //     emit(state.copyWith(
// //       status: BleStatus.scanning,
// //       message: "Scanning for Sipnudge device...",
// //     ));

// //     _scanSub?.cancel();
// //     FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

// //     _scanSub = FlutterBluePlus.scanResults.listen((results) {
// //       for (var r in results) {
// //         // ✅ Filter for only Sipnudge devices
// //         final deviceName = r.device.name.toLowerCase();
// //         if (!deviceName.contains('sipnudge')) continue;

// //         if (r.device.id.id == savedDeviceId ||
// //             r.device.name == savedDeviceName) {
// //           _scanSub?.cancel();
// //           FlutterBluePlus.stopScan();
// //           _connectToDevice(r.device);
// //           return;
// //         }
// //       }
// //     }, onError: (e) {
// //       emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
// //       _rescan(lastDeviceOnly: true);
// //     });

// //     Future.delayed(const Duration(seconds: 20), () {
// //       if (state.status == BleStatus.scanning) {
// //         FlutterBluePlus.stopScan().then((_) => _scanForLastDevice());
// //       }
// //     });
// //   }

// //   void _scanForAllDevices() {
// //     emit(state.copyWith(
// //       status: BleStatus.scanning,
// //       message: "Scanning for Sipnudge devices...",
// //     ));

// //     _scanSub?.cancel();
// //     FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

// //     _scanSub = FlutterBluePlus.scanResults.listen((results) {
// //       if (results.isNotEmpty) {
// //         // ✅ Only include devices with "Sipnudge" in their name
// //         var filtered = results.where((it) {
// //           final name = it.device.name.toLowerCase();
// //           return name.contains('sipnudge');
// //         }).toList();

// //         if (filtered.isNotEmpty) {
// //           emit(state.copyWith(scannedDevices: filtered));
// //         }
// //       }
// //     }, onError: (e) {
// //       emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
// //       _rescan();
// //     });

// //     Future.delayed(const Duration(seconds: 20), () async {
// //       if (state.status == BleStatus.scanning) {
// //         FlutterBluePlus.stopScan().then((_) => _scanForAllDevices());
// //       }
// //     });
// //   }

// //   Future<void> _rescan({
// //     bool lastDeviceOnly = false,
// //     Duration delay = const Duration(milliseconds: 200),
// //   }) async {
// //     if (FlutterBluePlus.isScanningNow) return;
// //     await Future.delayed(delay);
// //     if (lastDeviceOnly) {
// //       _scanForLastDevice();
// //     } else {
// //       _scanForAllDevices();
// //     }
// //   }

// //   // ---------------------------------------------------------------------------
// //   // BLE connection
// //   // ---------------------------------------------------------------------------

// //   Future<void> connectToSelectedDevice(BluetoothDevice device) async {
// //     FlutterBluePlus.stopScan();
// //     _scanSub?.cancel();
// //     _connectToDevice(device);
// //   }

// //   Future<void> _connectToDevice(BluetoothDevice device) async {
// //     emit(state.copyWith(
// //       status: BleStatus.connecting,
// //       message: "Connecting to ${device.name}...",
// //     ));

// //     try {
// //       await device.connect(autoConnect: false, timeout: Duration(seconds: 6));
// //       await device.connectionState
// //           .where((s) => s == BluetoothConnectionState.connected)
// //           .first;

// //       _listenToConnection(device);

// //       final prefs = await SharedPreferences.getInstance();
// //       final wasFirst = (savedDeviceId == null || savedDeviceName == null);
// //       await prefs.setString('last_device_id', device.id.id);
// //       await prefs.setString('last_device_name', device.name);

// //       savedDeviceId = device.id.id;
// //       savedDeviceName = device.name;
// //       if (wasFirst) emit(state.copyWith(isFirstConnection: false));

// //       await _discoverServices(device);
// //       await prefs.setBool('ble_connected_once', true);
// //     } catch (e) {
// //       emit(state.copyWith(
// //           status: BleStatus.error, message: "Connection failed: $e"));
// //       _rescan(
// //           lastDeviceOnly: (savedDeviceId != null || savedDeviceName != null));
// //     }
// //   }

// //   // ---------------------------------------------------------------------------
// //   // Service Discovery + Notification setup
// //   // ---------------------------------------------------------------------------

// //   Future<void> _discoverServices(BluetoothDevice device) async {
// //     try {
// //       final services = await device.discoverServices();
// //       for (var s in services) {
// //         if (s.uuid == serviceUUID) {
// //           for (var c in s.characteristics) {
// //             if (c.uuid == dataUUID) _dataChar = c;
// //             if (c.uuid == ackUUID) _ackChar = c;
// //             if (c.uuid == hydrationDataUUID) _hydrationDataChar = c;
// //             if (c.uuid == hydrationCharUUID) _hydrationChar = c;
// //             if (c.uuid == waterDataBufUUID) _waterDataChar = c;
// //           }
// //         }
// //       }

// //       if (_dataChar == null || _ackChar == null) {
// //         final prefs = await SharedPreferences.getInstance();
// //         await prefs.remove('last_device_id');
// //         await prefs.remove('last_device_name');

// //         savedDeviceId = null;
// //         savedDeviceName = null;

// //         emit(state.copyWith(
// //           status: BleStatus.error,
// //           message: "Required characteristics not found",
// //           isFirstConnection: true,
// //         ));

// //         await device.disconnect();
// //         _rescan(lastDeviceOnly: false);
// //         return;
// //       }

// //       // 🩵 Main data (battery, volume, percent)
// //       _dataChar!.onValueReceived.listen((value) {
// //         final data = String.fromCharCodes(value);
// //         log("Received data: $data", name: "BLE_Cubit");
// //         _parseData(data);
// //         _sendAck(device);
// //       });
// //       await _dataChar!.setNotifyValue(true);

// //       // 💧 Hydration history data (short)
// //       _hydrationDataChar?.onValueReceived.listen((value) {
// //         final data = String.fromCharCodes(value);
// //         log("HydrationDataReceived: $data", name: "BLE_Cubit");

// //         final slots = _parseHydrationData(data);
// //         if (slots.isNotEmpty) _hydrationController.add(slots);

// //         _sendAck(device, sendAckToHydrationSlotsCharacteristic: true);
// //       });
// //       await _hydrationDataChar?.setNotifyValue(true);

// //       // 🔹 Real-time hydration slot data (slotId/target/consumed)
// //       if (_hydrationChar != null) {
// //         await _hydrationChar!.setNotifyValue(true);
// //         _hydrationChar!.onValueReceived.listen((value) async {
// //           final data = String.fromCharCodes(value);
// //           log("Hydration Slot Data (raw): $data", name: "BLE_Cubit");

// //           // Support multiple chunks separated by '|'
// //           final chunks = data.split('|');
// //           List<HydrationEntry> updatedEntries = [];

// //           for (var chunk in chunks) {
// //             final chunkTrim = chunk.trim();
// //             if (chunkTrim.isEmpty) continue;
// //             final entry = _parseHydrationSlotData(chunkTrim);
// //             if (entry != null) {
// //               // update in-memory list (state.hydrationEntries)
// //               final updatedList =
// //                   List<HydrationEntry>.from(state.hydrationEntries ?? []);
// //               if (entry.slot.index < updatedList.length) {
// //                 updatedList[entry.slot.index] = entry;
// //               } else {
// //                 // if missing, ensure we fill gaps
// //                 while (updatedList.length <= entry.slot.index) {
// //                   // push a default empty entry for missing slots
// //                   final slot = HydrationSlot.values[updatedList.length];
// //                   updatedList.add(HydrationEntry(
// //                     slot: slot,
// //                     startTime: const TimeOfDay(hour: 0, minute: 0),
// //                     endTime: const TimeOfDay(hour: 0, minute: 0),
// //                     amount: 0,
// //                     targetIntake: 0,
// //                     waterDrank: 0,
// //                   ));
// //                 }
// //                 updatedList[entry.slot.index] = entry;
// //               }
// //               updatedEntries.add(entry);

// //               // persist this slot in DB if you have such method
// //               try {
// //                 await dbHelper.insertOrUpdateSlot(entry);
// //               } catch (e) {
// //                 log("DB insert/update slot failed: $e");
// //               }

// //               emit(state.copyWith(hydrationEntries: updatedList));
// //             }
// //           }

// //           if (updatedEntries.isNotEmpty) {
// //             _hydrationController.add(updatedEntries);
// //             emit(state.copyWith(
// //                 message: "Updated ${updatedEntries.length} hydration slot(s)"));
// //           }

// //           _sendAck(device);
// //         });
// //       }

// //       // 🔹 Big buffer: WATER_DATA (30-day history)
// //       if (_waterDataChar != null) {
// //         await _waterDataChar!.setNotifyValue(true);
// //         _waterDataChar!.onValueReceived.listen((value) {
// //           final raw = String.fromCharCodes(value);
// //           log("📦 WaterDataBuf received: $raw", name: "BLE_Cubit");
// //           _parseWaterHistoryData(raw);
// //           _sendAck(device);
// //         });
// //       }

// //       emit(state.copyWith(
// //         status: BleStatus.connected,
// //         message: "Connected to ${device.name}",
// //       ));

// //       await _flushPendingSlots();
// //     } catch (e) {
// //       try {
// //         await device.disconnect();
// //       } catch (_) {}

// //       emit(state.copyWith(
// //         status: BleStatus.error,
// //         message: "Service discovery failed: $e",
// //       ));
// //       _rescan(lastDeviceOnly: savedDeviceId != null || savedDeviceName != null);
// //     }
// //   }

// //   // ---------------------------------------------------------------------------
// //   // Data parsing and ACK
// //   // ---------------------------------------------------------------------------

// //   void _parseData(String data) {
// //     final parts = data.split(';');
// //     int? battery;
// //     double? volume;
// //     int? percent;

// //     for (var p in parts) {
// //       if (p.contains('battery=')) battery = int.tryParse(p.split('=')[1]);
// //       if (p.contains('volume=')) volume = double.tryParse(p.split('=')[1]);
// //       if (p.contains('percent=')) percent = int.tryParse(p.split('=')[1]);
// //     }

// //     emit(state.copyWith(battery: battery, volume: volume, percent: percent));
// //   }

// //   /// Parse hydration history short format that device sends on hydrationDataUUID
// //   /// Expects entries like: "Label/Index/startEpoch/endEpoch/amount|..."
// //   List<HydrationEntry> _parseHydrationData(String payload) {
// //     if (payload.isEmpty || payload.toLowerCase() == "na") return [];
// //     return payload.split("|").map((entry) {
// //       final parts = entry.split("/");
// //       if (parts.length < 5) throw FormatException("Invalid payload: $entry");

// //       final index = int.parse(parts[1]);
// //       final startEpoch = int.parse(parts[2]);
// //       final endEpoch = int.parse(parts[3]);
// //       final amount = int.parse(parts[4]);

// //       final slot = HydrationSlot.values[index];
// //       return HydrationEntry(
// //         slot: slot,
// //         startTime: _epochToTimeOfDay(startEpoch),
// //         endTime: _epochToTimeOfDay(endEpoch),
// //         // device sends the planned amount here — store that in amount
// //         amount: 0,
// //         targetIntake: 0,
// //         // actual consumed unknown here
// //         waterDrank: 0,
// //       );
// //     }).toList();
// //   }

// //   /// Parse a single slot update payload (slotIndex/target/consumed)
// //   HydrationEntry? _parseHydrationSlotData(String data) {
// //     try {
// //       data = data.trim();

// //       // Example: "0/425/400"
// //       if (data.contains("/")) {
// //         final parts = data.split("/");

// //         if (parts.length < 3) {
// //           debugPrint("❌ Invalid slot data: $data");
// //           return null;
// //         }

// //         final slotIndex = int.parse(parts[0]);
// //         final target = double.parse(parts[1]); // THIS IS WHERE 425 COMES
// //         final consumed = double.parse(parts[2]); // THIS IS WHERE 400 COMES

// //         return HydrationEntry(
// //           slot: HydrationSlot.values[slotIndex],
// //           startTime: const TimeOfDay(hour: 0, minute: 0),
// //           endTime: const TimeOfDay(hour: 0, minute: 0),
// //           targetIntake: target, // NOW WILL DISPLAY 425, 213, ETC
// //           waterDrank: consumed,
// //           amount: 0,
// //           status: consumed >= target
// //               ? HydrationStatus.completed
// //               : HydrationStatus.pending,
// //         );
// //       }

// //       debugPrint("❌ Unknown hydration format: $data");
// //       return null;
// //     } catch (e) {
// //       debugPrint("❌ Slot parse failed: $data ERROR: $e");
// //       return null;
// //     }
// //   }

// //   /// Parse the long waterDataBuf that your device sends.
// //   /// Expected (device example):
// //   /// "1758076200|0/2000/1800|1/2000/1800|2/2000/1800|..."
// //   /// where first token is baseEpoch, subsequent tokens are either:
// //   ///  - index/target/consumed   (index = day offset from baseEpoch)
// //   ///  - or epoch/totalDrank     (per-day epoch + total)
// //   ///
// //   /// Returns a List of maps: { "date": "DD-MM-YYYY", "totalDrank": double, "target": double? }
// //   // List<Map<String, dynamic>> _parseWaterDataBuf(String payload) {
// //   //   try {
// //   //     if (payload.isEmpty || payload.toLowerCase() == "na") return [];

// //   //     final tokens =
// //   //         payload.split("|").where((t) => t.trim().isNotEmpty).toList();
// //   //     if (tokens.isEmpty) return [];

// //   //     // Determine format
// //   //     final first = tokens[0].trim();
// //   //     final results = <Map<String, dynamic>>[];

// //   //     // If first token has no '/' and is a large number -> baseEpoch
// //   //     final firstHasSlash = first.contains('/');
// //   //     int? baseEpoch;
// //   //     int startIndex = 0;
// //   //     if (!firstHasSlash) {
// //   //       final maybeEpoch = int.tryParse(first);
// //   //       if (maybeEpoch != null && maybeEpoch > 1000000000) {
// //   //         baseEpoch = maybeEpoch;
// //   //         startIndex = 1;
// //   //       }
// //   //     }

// //   //     for (int i = startIndex; i < tokens.length; i++) {
// //   //       final t = tokens[i].trim();
// //   //       if (t.isEmpty) continue;

// //   //       // 1) index/target/consumed  (device example)
// //   //       if (t.contains('/')) {
// //   //         final parts = t.split('/');
// //   //         if (parts.length >= 3) {
// //   //           // index relative to baseEpoch
// //   //           final index = int.tryParse(parts[0]) ?? 0;
// //   //           final target = double.tryParse(parts[1]) ?? 0;
// //   //           final consumed = double.tryParse(parts[2]) ?? 0;

// //   //           DateTime day;
// //   //           if (baseEpoch != null) {
// //   //             day = DateTime.fromMillisecondsSinceEpoch(
// //   //                 (baseEpoch + index * 86400) * 1000);
// //   //           } else {
// //   //             // fallback: treat index as epoch (if large)
// //   //             if (index > 1000000000) {
// //   //               day = DateTime.fromMillisecondsSinceEpoch(index * 1000);
// //   //             } else {
// //   //               // fallback to today + index
// //   //               day = DateTime.now().add(Duration(days: index));
// //   //             }
// //   //           }

// //   //           final formatted =
// //   //               "${day.day.toString().padLeft(2, '0')}-${day.month.toString().padLeft(2, '0')}-${day.year}";
// //   //           results.add({
// //   //             'date': formatted,
// //   //             'totalDrank': consumed,
// //   //             'target': target,
// //   //           });
// //   //           continue;
// //   //         }

// //   //         // 2) maybe epoch/totalDrank (two-part)
// //   //         if (parts.length == 2) {
// //   //           final maybeEpoch = int.tryParse(parts[0]);
// //   //           final total = double.tryParse(parts[1]) ?? 0;
// //   //           if (maybeEpoch != null && maybeEpoch > 1000000000) {
// //   //             final day =
// //   //                 DateTime.fromMillisecondsSinceEpoch(maybeEpoch * 1000);
// //   //             final formatted =
// //   //                 "${day.day.toString().padLeft(2, '0')}-${day.month.toString().padLeft(2, '0')}-${day.year}";
// //   //             results.add({
// //   //               'date': formatted,
// //   //               'totalDrank': total,
// //   //               'target': null,
// //   //             });
// //   //             continue;
// //   //           }
// //   //         }
// //   //       }

// //   //       // If token has no slash but is epoch-like, try to read next token as the day's value
// //   //       final onlyEpoch = int.tryParse(t);
// //   //       if (onlyEpoch != null && onlyEpoch > 1000000000) {
// //   //         // try next token as value
// //   //         if (i + 1 < tokens.length) {
// //   //           final next = tokens[i + 1].trim();
// //   //           final total = double.tryParse(next.replaceAll('/', '')) ??
// //   //               double.tryParse(next) ??
// //   //               0;
// //   //           final day = DateTime.fromMillisecondsSinceEpoch(onlyEpoch * 1000);
// //   //           final formatted =
// //   //               "${day.day.toString().padLeft(2, '0')}-${day.month.toString().padLeft(2, '0')}-${day.year}";
// //   //           results.add({
// //   //             'date': formatted,
// //   //             'totalDrank': total,
// //   //             'target': null,
// //   //           });
// //   //           i++; // skip the next token
// //   //           continue;
// //   //         }
// //   //       }

// //   //       // Unknown token pattern -> skip but log
// //   //       log("Unknown waterDataBuf token skipped: '$t'", name: "BLE_Cubit");
// //   //     }

// //   //     return results;
// //   //   } catch (e) {
// //   //     log("Failed to parse waterDataBuf: $e", name: "BLE_Cubit");
// //   //     return [];
// //   //   }
// //   // }

// //   List<Map<String, dynamic>> _parseWaterHistoryData(String data) {
// //     try {
// //       final parts = data.split('|');
// //       if (parts.isEmpty) return [];

// //       final epoch = int.tryParse(parts.first.trim()) ?? 0;
// //       final List<Map<String, dynamic>> history = [];

// //       for (var i = 1; i < parts.length; i++) {
// //         if (parts[i].trim().isEmpty) continue;

// //         final values = parts[i].split('/');
// //         if (values.length < 3) continue;

// //         final day = int.tryParse(values[0]) ?? 0;
// //         final goal = double.tryParse(values[1]) ?? 0;
// //         final consumed = double.tryParse(values[2]) ?? 0;
// //         final date = DateTime.fromMillisecondsSinceEpoch(
// //           (epoch + (day * 86400)) * 1000,
// //         );

// //         final percent = goal == 0 ? 0 : (consumed / goal) * 100;

// //         history.add({
// //           'day': day,
// //           'date': date,
// //           'goal': goal,
// //           'consumed': consumed,
// //           'percent': percent,
// //         });
// //       }

// //       log("Parsed BLE history: $history");
// //       return history;
// //     } catch (e) {
// //       log("Error parsing water history: $e");
// //       return [];
// //     }
// //   }

// //   Future<void> _sendAck(BluetoothDevice device,
// //       {bool sendAckToHydrationSlotsCharacteristic = false}) async {
// //     try {
// //       if (sendAckToHydrationSlotsCharacteristic) {
// //         await _hydrationDataChar?.write("ACK".codeUnits, withoutResponse: true);
// //       } else {
// //         await _ackChar?.write("ACK".codeUnits, withoutResponse: true);
// //       }
// //     } catch (e) {
// //       log("ACK failed: $e", name: "BLE_Cubit");
// //     }
// //   }

// //   // ---------------------------------------------------------------------------
// //   // Utilities + Hydration sync
// //   // ---------------------------------------------------------------------------

// //   void _listenToConnection(BluetoothDevice device) {
// //     _connectionSub?.cancel();
// //     _connectionSub = device.connectionState.listen((stateChange) {
// //       switch (stateChange) {
// //         case BluetoothConnectionState.connected:
// //           emit(state.copyWith(
// //             status: BleStatus.connected,
// //             message: "Connected to ${device.name}",
// //           ));
// //           break;
// //         case BluetoothConnectionState.disconnected:
// //           emit(state.copyWith(
// //             status: BleStatus.disconnected,
// //             message: "Device disconnected",
// //           ));
// //           if (savedDeviceId != null || savedDeviceName != null) {
// //             _rescan(lastDeviceOnly: true);
// //           }
// //           break;
// //         default:
// //           break;
// //       }
// //     });
// //   }

// //   Future<void> _flushPendingSlots() async {
// //     if (_ackChar == null || _pendingSlots.isEmpty) return;

// //     try {
// //       final payload = _pendingSlots.map((slot) {
// //         final start = _timeOfDayToEpoch(slot.startTime);
// //         final end = _timeOfDayToEpoch(slot.endTime);
// //         return "${slot.slot.label}/${slot.slot.index}/$start/$end/${slot.amount}";
// //       }).join("|");

// //       log("Flushing hydration slots: $payload");
// //       await _ackChar!.write(payload.codeUnits, withoutResponse: true);
// //       _pendingSlots.clear();

// //       emit(state.copyWith(
// //         status: BleStatus.connected,
// //         message: "Hydration slots synced",
// //       ));
// //     } catch (e) {
// //       emit(
// //           state.copyWith(status: BleStatus.error, message: "Flush failed: $e"));
// //     }
// //   }

// //   int _timeOfDayToEpoch(TimeOfDay tod) {
// //     final now = DateTime.now();
// //     final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
// //     return dt.millisecondsSinceEpoch ~/ 1000;
// //   }

// //   TimeOfDay _epochToTimeOfDay(int epoch) {
// //     final date = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
// //     return TimeOfDay(hour: date.hour, minute: date.minute);
// //   }

// //   @override
// //   Future<void> queueHydrationSlots(List<HydrationEntry> entries) async {
// //     _pendingSlots.clear();
// //     _pendingSlots.addAll(entries);
// //     if (state.status == BleStatus.connected) {
// //       await _flushPendingSlots();
// //     } else {
// //       emit(state.copyWith(message: "Device not connected, will sync later"));
// //     }
// //   }

// //   Future<void> forgetDevice() async {
// //     final prefs = await SharedPreferences.getInstance();
// //     await prefs.remove('last_device_id');
// //     await prefs.remove('last_device_name');

// //     savedDeviceId = null;
// //     savedDeviceName = null;

// //     emit(
// //       state.copyWith(
// //         status: BleStatus.scanning,
// //         isFirstConnection: true,
// //         message: "Device forgotten. \nReady to scan for new devices.",
// //       ),
// //     );

// //     if (FlutterBluePlus.isScanningNow) {
// //       await FlutterBluePlus.stopScan();
// //     }
// //     emit(
// //       state.copyWith(
// //         status: BleStatus.scanning,
// //         isFirstConnection: true,
// //         scannedDevices: [],
// //         message: "Device forgotten. \nReady to scan for new devices.",
// //       ),
// //     );

// //     _scanForAllDevices();
// //   }

// //   @override
// //   Stream<List<HydrationEntry>> get hydrationUpdates =>
// //       _hydrationController.stream;
// // }

// // //=====================================================================

// // import 'dart:async';
// // import 'dart:developer';
// // import 'package:bloc/bloc.dart';
// // import 'package:flutter/material.dart';
// // import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// // import 'package:fluttertoast/fluttertoast.dart';
// // import 'package:hydrify/cubit/hydration/hydration_sync.dart';
// // import 'package:hydrify/helpers/database_helper.dart';
// // import 'package:hydrify/models/hydration_entry.dart';
// // import 'package:shared_preferences/shared_preferences.dart';

// // part 'ble_state.dart';

// // class BleCubit extends Cubit<BleState> implements HydrationSync {
// //   BleCubit() : super(const BleState());
// //   final _hydrationController =
// //       StreamController<List<HydrationEntry>>.broadcast();

// //   final Guid serviceUUID = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid dataUUID = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid hydrationDataUUID = Guid("6E400004-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid ackUUID = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid hydrationCharUUID = Guid("6E400005-B5A3-F393-E0A9-E50E24DCCA9E");
// //   final Guid waterDataBufUUID = Guid("6E400006-B5A3-F393-E0A9-E50E24DCCA9E");
// //   BluetoothCharacteristic? _dataChar;
// //   BluetoothCharacteristic? _ackChar;
// //   BluetoothCharacteristic? _hydrationDataChar;
// //   BluetoothCharacteristic? _hydrationChar; // 🔹 NEW for 7-slot hydration data
// //   BluetoothCharacteristic? _waterDataChar;

// //   StreamSubscription<List<ScanResult>>? _scanSub;
// //   StreamSubscription<BluetoothConnectionState>? _connectionSub;

// //   String? savedDeviceName;
// //   String? savedDeviceId;

// //   final bool _isReconnecting = false;
// //   final dbHelper = DatabaseHelper();
// //   final List<HydrationEntry> _pendingSlots = [];

// //   // ---------------------------------------------------------------------------
// //   // BLE initialization and scanning
// //   // ---------------------------------------------------------------------------

// //   Future<void> start() async {
// //     emit(state.copyWith(
// //       status: BleStatus.initializing,
// //       message: "Initializing...",
// //     ));

// //     await _waitForBluetoothOn(() async {
// //       final prefs = await SharedPreferences.getInstance();
// //       savedDeviceName = prefs.getString('last_device_name');
// //       savedDeviceId = prefs.getString('last_device_id');

// //       final bool isFirst = (savedDeviceName == null || savedDeviceId == null);
// //       emit(state.copyWith(
// //         status: BleStatus.initializing,
// //         message: "Initializing Bluetooth",
// //         isFirstConnection: isFirst,
// //       ));

// //       if (!isFirst) {
// //         _scanForLastDevice();
// //       } else {
// //         _scanForAllDevices();
// //       }
// //     });
// //   }

// //   Future<void> _waitForBluetoothOn(Future<void> Function() onReady) async {
// //     if (await FlutterBluePlus.isSupported == false) {
// //       emit(state.copyWith(
// //         status: BleStatus.error,
// //         message: "Bluetooth not supported",
// //       ));
// //       return;
// //     }

// //     final currentState = await FlutterBluePlus.adapterState.first;
// //     if (currentState == BluetoothAdapterState.on) {
// //       await onReady();
// //       return;
// //     }

// //     emit(state.copyWith(
// //       status: BleStatus.error,
// //       message: "Please turn on Bluetooth",
// //     ));

// //     await FlutterBluePlus.adapterState
// //         .where((s) => s == BluetoothAdapterState.on)
// //         .first;

// //     await onReady();
// //   }

// //   void _scanForLastDevice() {
// //     if (savedDeviceId == null && savedDeviceName == null) return;

// //     emit(state.copyWith(
// //       status: BleStatus.scanning,
// //       message: "Scanning for Sipnudge device...",
// //     ));

// //     _scanSub?.cancel();
// //     FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

// //     _scanSub = FlutterBluePlus.scanResults.listen((results) {
// //       for (var r in results) {
// //         // ✅ Filter for only Sipnudge devices
// //         final deviceName = r.device.name.toLowerCase();
// //         if (!deviceName.contains('sipnudge')) continue;

// //         if (r.device.id.id == savedDeviceId ||
// //             r.device.name == savedDeviceName) {
// //           _scanSub?.cancel();
// //           FlutterBluePlus.stopScan();
// //           _connectToDevice(r.device);
// //           return;
// //         }
// //       }
// //     }, onError: (e) {
// //       emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
// //       _rescan(lastDeviceOnly: true);
// //     });

// //     Future.delayed(const Duration(seconds: 20), () {
// //       if (state.status == BleStatus.scanning) {
// //         FlutterBluePlus.stopScan().then((_) => _scanForLastDevice());
// //       }
// //     });
// //   }

// //   // void _scanForLastDevice() {
// //   //   if (savedDeviceId == null && savedDeviceName == null) return;

// //   //   emit(state.copyWith(
// //   //     status: BleStatus.scanning,
// //   //     message: "Scanning for last device...",
// //   //   ));

// //   //   _scanSub?.cancel();
// //   //   FlutterBluePlus.startScan(
// //   //     timeout: const Duration(seconds: 20),
// //   //     withServices: [serviceUUID],
// //   //   );

// //   //   _scanSub = FlutterBluePlus.scanResults.listen((results) {
// //   //     for (var r in results) {
// //   //       if (r.device.id.id == savedDeviceId ||
// //   //           r.device.name == savedDeviceName) {
// //   //         _scanSub?.cancel();
// //   //         FlutterBluePlus.stopScan();
// //   //         _connectToDevice(r.device);
// //   //         return;
// //   //       }
// //   //     }
// //   //   }, onError: (e) {
// //   //     emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
// //   //     _rescan(lastDeviceOnly: true);
// //   //   });

// //   //   Future.delayed(const Duration(seconds: 20), () {
// //   //     if (state.status == BleStatus.scanning) {
// //   //       FlutterBluePlus.stopScan().then((_) => _scanForLastDevice());
// //   //     }
// //   //   });
// //   // }

// //   void _scanForAllDevices() {
// //     emit(state.copyWith(
// //       status: BleStatus.scanning,
// //       message: "Scanning for Sipnudge devices...",
// //     ));

// //     _scanSub?.cancel();
// //     FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

// //     _scanSub = FlutterBluePlus.scanResults.listen((results) {
// //       if (results.isNotEmpty) {
// //         // ✅ Only include devices with "Sipnudge" in their name
// //         var filtered = results.where((it) {
// //           final name = it.device.name.toLowerCase();
// //           return name.contains('sipnudge');
// //         }).toList();

// //         if (filtered.isNotEmpty) {
// //           emit(state.copyWith(scannedDevices: filtered));
// //         }
// //       }
// //     }, onError: (e) {
// //       emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
// //       _rescan();
// //     });

// //     Future.delayed(const Duration(seconds: 20), () async {
// //       if (state.status == BleStatus.scanning) {
// //         FlutterBluePlus.stopScan().then((_) => _scanForAllDevices());
// //       }
// //     });
// //   }

// //   // void _scanForAllDevices() {
// //   //   emit(state.copyWith(
// //   //     status: BleStatus.scanning,
// //   //     message: "Scanning for BLE devices...",
// //   //   ));

// //   //   _scanSub?.cancel();
// //   //   FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

// //   //   _scanSub = FlutterBluePlus.scanResults.listen((results) {
// //   //     if (results.isNotEmpty) {
// //   //       var filtered = results
// //   //           .where(
// //   //               (it) => it.advertisementData.serviceUuids.contains(serviceUUID))
// //   //           .toList();
// //   //       emit(state.copyWith(scannedDevices: filtered));
// //   //     }
// //   //   }, onError: (e) {
// //   //     emit(state.copyWith(status: BleStatus.error, message: "Scan error: $e"));
// //   //     _rescan();
// //   //   });

// //   //   Future.delayed(const Duration(seconds: 20), () async {
// //   //     if (state.status == BleStatus.scanning) {
// //   //       FlutterBluePlus.stopScan().then((_) => _scanForAllDevices());
// //   //     }
// //   //   });
// //   // }

// //   Future<void> _rescan({
// //     bool lastDeviceOnly = false,
// //     Duration delay = const Duration(milliseconds: 200),
// //   }) async {
// //     if (FlutterBluePlus.isScanningNow) return;
// //     await Future.delayed(delay);
// //     if (lastDeviceOnly) {
// //       _scanForLastDevice();
// //     } else {
// //       _scanForAllDevices();
// //     }
// //   }

// //   // ---------------------------------------------------------------------------
// //   // BLE connection
// //   // ---------------------------------------------------------------------------

// //   Future<void> connectToSelectedDevice(BluetoothDevice device) async {
// //     FlutterBluePlus.stopScan();
// //     _scanSub?.cancel();
// //     _connectToDevice(device);
// //   }

// //   Future<void> _connectToDevice(BluetoothDevice device) async {
// //     emit(state.copyWith(
// //       status: BleStatus.connecting,
// //       message: "Connecting to ${device.name}...",
// //     ));

// //     try {
// //       await device.connect(autoConnect: false, timeout: Duration(seconds: 6));
// //       await device.connectionState
// //           .where((s) => s == BluetoothConnectionState.connected)
// //           .first;

// //       _listenToConnection(device);

// //       final prefs = await SharedPreferences.getInstance();
// //       final wasFirst = (savedDeviceId == null || savedDeviceName == null);
// //       await prefs.setString('last_device_id', device.id.id);
// //       await prefs.setString('last_device_name', device.name);

// //       savedDeviceId = device.id.id;
// //       savedDeviceName = device.name;
// //       if (wasFirst) emit(state.copyWith(isFirstConnection: false));

// //       await _discoverServices(device);
// //       await prefs.setBool('ble_connected_once', true);
// //     } catch (e) {
// //       emit(state.copyWith(
// //           status: BleStatus.error, message: "Connection failed: $e"));
// //       _rescan(
// //           lastDeviceOnly: (savedDeviceId != null || savedDeviceName != null));
// //     }
// //   }

// //   // ---------------------------------------------------------------------------
// //   // Service Discovery + Notification setup
// //   // ---------------------------------------------------------------------------

// //   Future<void> _discoverServices(BluetoothDevice device) async {
// //     try {
// //       final services = await device.discoverServices();
// //       for (var s in services) {
// //         if (s.uuid == serviceUUID) {
// //           for (var c in s.characteristics) {
// //             if (c.uuid == dataUUID) _dataChar = c;
// //             if (c.uuid == ackUUID) _ackChar = c;
// //             if (c.uuid == hydrationDataUUID) _hydrationDataChar = c;
// //             if (c.uuid == hydrationCharUUID) _hydrationChar = c;
// //             if (c.uuid == waterDataBufUUID) _waterDataChar = c;
// //           }
// //         }
// //       }

// //       if (_dataChar == null || _ackChar == null) {
// //         final prefs = await SharedPreferences.getInstance();
// //         await prefs.remove('last_device_id');
// //         await prefs.remove('last_device_name');

// //         savedDeviceId = null;
// //         savedDeviceName = null;

// //         emit(state.copyWith(
// //           status: BleStatus.error,
// //           message: "Required characteristics not found",
// //           isFirstConnection: true,
// //         ));

// //         await device.disconnect();
// //         _rescan(lastDeviceOnly: false);
// //         return;
// //       }

// //       // 🩵 Main data (battery, volume, percent)
// //       _dataChar!.onValueReceived.listen((value) {
// //         final data = String.fromCharCodes(value);
// //         log("Received data: $data", name: "BLE_Cubit");
// //         _parseData(data);
// //         _sendAck(device);
// //       });
// //       await _dataChar!.setNotifyValue(true);

// //       // 💧 Hydration history data
// //       _hydrationDataChar?.onValueReceived.listen((value) {
// //         final data = String.fromCharCodes(value);
// //         log("HydrationDataReceived: $data", name: "BLE_Cubit");
// //         var slots = _parseHydrationData(data);
// //         if (slots.isNotEmpty) _hydrationController.add(slots);
// //         _sendAck(device, sendAckToHydrationSlotsCharacteristic: true);
// //       });
// //       await _hydrationDataChar?.setNotifyValue(true);

// //       // 🔹 NEW: Real-time hydration slot data (slotId/Target/Consumed)
// //       // 🔹 NEW: Real-time hydration slot data (slotId/Target/Consumed)
// // if (_hydrationChar != null) {
// //   await _hydrationChar!.setNotifyValue(true);
// //   _hydrationChar!.onValueReceived.listen((value) async {
// //     final data = String.fromCharCodes(value);
// //     final entry = _parseHydrationSlotData(data);

// //     if (entry != null) {
// //       // Update the list of hydration entries in your Cubit state
// //       final updatedList =
// //           List<HydrationEntry>.from(state.hydrationEntries ?? []);
// //       if (entry.slot.index < updatedList.length) {
// //         updatedList[entry.slot.index] = entry;
// //       } else {
// //         updatedList.add(entry);
// //       }

// //       emit(state.copyWith(hydrationEntries: updatedList));
// //     }

// //     log("💧 SlotDataReceived: $data", name: "BLE_Cubit");

// //     // Support for multiple slot updates separated by '|'
// //     final chunks = data.split('|');
// //     List<HydrationEntry> updatedEntries = [];

// //     for (var chunk in chunks) {
// //       if (chunk.trim().isEmpty) continue;
// //       final entry = _parseHydrationSlotData(chunk.trim());
// //       if (entry != null) {
// //         updatedEntries.add(entry);
// //         await dbHelper.insertOrUpdateSlot(entry);
// //       }
// //     }

// //     if (updatedEntries.isNotEmpty) {
// //       _hydrationController.add(updatedEntries);
// //       emit(state.copyWith(
// //         message: "Updated ${updatedEntries.length} hydration slot(s)",
// //       ));
// //     }

// //     _sendAck(device);
// //   });
// // }
// //       // if (_hydrationChar != null) {
// //       //   await _hydrationChar!.setNotifyValue(true);
// //       //   _hydrationChar!.onValueReceived.listen((value) async {
// //       //     final data = String.fromCharCodes(value);
// //       //     log("Hydration Slot Data: $data", name: "BLE_Cubit");

// //       //     final updatedEntry = _parseHydrationSlotData(data);
// //       //     if (updatedEntry != null) {
// //       //       _hydrationController.add([updatedEntry]);
// //       //       await dbHelper.insertOrUpdateSlot(updatedEntry);
// //       //     }

// //       //     _sendAck(device);
// //       //   });
// //       // }

// //       emit(state.copyWith(
// //         status: BleStatus.connected,
// //         message: "Connected to ${device.name}",
// //       ));

// //       await _flushPendingSlots();
// //     } catch (e) {
// //       try {
// //         await device.disconnect();
// //       } catch (_) {}

// //       emit(state.copyWith(
// //         status: BleStatus.error,
// //         message: "Service discovery failed: $e",
// //       ));
// //       _rescan(lastDeviceOnly: savedDeviceId != null || savedDeviceName != null);
// //     }
// //   }

// //   // ---------------------------------------------------------------------------
// //   // Data parsing and ACK
// //   // ---------------------------------------------------------------------------

// //   void _parseData(String data) {
// //     final parts = data.split(';');
// //     int? battery;
// //     double? volume;
// //     int? percent;

// //     for (var p in parts) {
// //       if (p.contains('battery=')) battery = int.tryParse(p.split('=')[1]);
// //       if (p.contains('volume=')) volume = double.tryParse(p.split('=')[1]);
// //       if (p.contains('percent=')) percent = int.tryParse(p.split('=')[1]);
// //     }

// //     emit(state.copyWith(battery: battery, volume: volume, percent: percent));
// //   }

// //   List<HydrationEntry> _parseHydrationData(String payload) {
// //     if (payload.isEmpty || payload.toLowerCase() == "na") return [];
// //     return payload.split("|").map((entry) {
// //       final parts = entry.split("/");
// //       if (parts.length < 5) throw FormatException("Invalid payload: $entry");

// //       final index = int.parse(parts[1]);
// //       final startEpoch = int.parse(parts[2]);
// //       final endEpoch = int.parse(parts[3]);
// //       final amount = int.parse(parts[4]);

// //       final slot = HydrationSlot.values[index];
// //       return HydrationEntry(
// //         slot: slot,
// //         startTime: _epochToTimeOfDay(startEpoch),
// //         endTime: _epochToTimeOfDay(endEpoch),
// //         waterDrank: amount.toDouble(),
// //         amount: 0,
// //         targetIntake: 0,
// //       );
// //     }).toList();
// //   }

// //   HydrationEntry? _parseHydrationSlotData(String data) {
// //     try {
// //       final parts = data.split('/');
// //       if (parts.length != 3) return null;

// //       final slotIndex = int.tryParse(parts[0]) ?? 0;
// //       final target = double.tryParse(parts[1]) ?? 0;
// //       final consumed = double.tryParse(parts[2]) ?? 0;

// //       final slot = HydrationSlot.values[slotIndex];

// //       return HydrationEntry(
// //         slot: slot,
// //         startTime:
// //             const TimeOfDay(hour: 6, minute: 0), // can be replaced with actual
// //         endTime: const TimeOfDay(hour: 7, minute: 0),
// //         amount: 0,
// //         targetIntake: target,
// //         waterDrank: consumed,
// //         status: consumed >= target
// //             ? HydrationStatus.completed
// //             : HydrationStatus.pending,
// //       );
// //     } catch (e) {
// //       debugPrint("⚠️ Failed to parse hydration slot data: $e");
// //       return null;
// //     }
// //   }

// //   Future<void> _sendAck(BluetoothDevice device,
// //       {bool sendAckToHydrationSlotsCharacteristic = false}) async {
// //     try {
// //       if (sendAckToHydrationSlotsCharacteristic) {
// //         await _hydrationDataChar?.write("ACK".codeUnits, withoutResponse: true);
// //       } else {
// //         await _ackChar?.write("ACK".codeUnits, withoutResponse: true);
// //       }
// //     } catch (e) {
// //       log("ACK failed: $e", name: "BLE_Cubit");
// //     }
// //   }

// //   // ---------------------------------------------------------------------------
// //   // Utilities + Hydration sync
// //   // ---------------------------------------------------------------------------

// //   void _listenToConnection(BluetoothDevice device) {
// //     _connectionSub?.cancel();
// //     _connectionSub = device.connectionState.listen((stateChange) {
// //       switch (stateChange) {
// //         case BluetoothConnectionState.connected:
// //           emit(state.copyWith(
// //             status: BleStatus.connected,
// //             message: "Connected to ${device.name}",
// //           ));
// //           break;
// //         case BluetoothConnectionState.disconnected:
// //           emit(state.copyWith(
// //             status: BleStatus.disconnected,
// //             message: "Device disconnected",
// //           ));
// //           if (savedDeviceId != null || savedDeviceName != null) {
// //             _rescan(lastDeviceOnly: true);
// //           }
// //           break;
// //         default:
// //           break;
// //       }
// //     });
// //   }

// //   Future<void> _flushPendingSlots() async {
// //     if (_ackChar == null || _pendingSlots.isEmpty) return;

// //     try {
// //       final payload = _pendingSlots.map((slot) {
// //         final start = _timeOfDayToEpoch(slot.startTime);
// //         final end = _timeOfDayToEpoch(slot.endTime);
// //         return "${slot.slot.label}/${slot.slot.index}/$start/$end/${slot.amount}";
// //       }).join("|");

// //       log("Flushing hydration slots: $payload");
// //       await _ackChar!.write(payload.codeUnits, withoutResponse: true);
// //       _pendingSlots.clear();

// //       emit(state.copyWith(
// //         status: BleStatus.connected,
// //         message: "Hydration slots synced",
// //       ));
// //     } catch (e) {
// //       emit(
// //           state.copyWith(status: BleStatus.error, message: "Flush failed: $e"));
// //     }
// //   }

// //   int _timeOfDayToEpoch(TimeOfDay tod) {
// //     final now = DateTime.now();
// //     final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
// //     return dt.millisecondsSinceEpoch ~/ 1000;
// //   }

// //   TimeOfDay _epochToTimeOfDay(int epoch) {
// //     final date = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
// //     return TimeOfDay(hour: date.hour, minute: date.minute);
// //   }

// //   @override
// //   Future<void> queueHydrationSlots(List<HydrationEntry> entries) async {
// //     _pendingSlots.clear();
// //     _pendingSlots.addAll(entries);
// //     if (state.status == BleStatus.connected) {
// //       await _flushPendingSlots();
// //     } else {
// //       emit(state.copyWith(message: "Device not connected, will sync later"));
// //     }
// //   }

// //   Future<void> forgetDevice() async {
// //     final prefs = await SharedPreferences.getInstance();
// //     await prefs.remove('last_device_id');
// //     await prefs.remove('last_device_name');

// //     savedDeviceId = null;
// //     savedDeviceName = null;

// //     emit(
// //       state.copyWith(
// //         status: BleStatus.scanning,
// //         isFirstConnection: true,
// //         message: "Device forgotten. \nReady to scan for new devices.",
// //       ),
// //     );

// //     if (FlutterBluePlus.isScanningNow) {
// //       await FlutterBluePlus.stopScan();
// //     }
// //     emit(
// //       state.copyWith(
// //         status: BleStatus.scanning,
// //         isFirstConnection: true,
// //         scannedDevices: [],
// //         message: "Device forgotten. \nReady to scan for new devices.",
// //       ),
// //     );

// //     _scanForAllDevices();
// //   }

// //   @override
// //   Stream<List<HydrationEntry>> get hydrationUpdates =>
// //       _hydrationController.stream;
// // }

// // // -----------------------------------------------------------------------------

// import 'dart:async';
// import 'dart:developer';
// import 'package:bloc/bloc.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// import 'package:fluttertoast/fluttertoast.dart';
// import 'package:hydrify/cubit/hydration/hydration_sync.dart';
// import 'package:hydrify/helpers/database_helper.dart';
// import 'package:hydrify/models/hydration_entry.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// part 'ble_state.dart';

// class BleCubit extends Cubit<BleState> implements HydrationSync {
//   BleCubit() : super(const BleState());
//   final _hydrationController =
//       StreamController<List<HydrationEntry>>.broadcast();

//   final Guid serviceUUID = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
//   final Guid dataUUID = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
//   final Guid hydrationDataUUID = Guid("6E400004-B5A3-F393-E0A9-E50E24DCCA9E");
//   final Guid ackUUID = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
//   final Guid hydrationCharUUID = Guid("6E400005-B5A3-F393-E0A9-E50E24DCCA9E");

//   BluetoothCharacteristic? _dataChar;
//   BluetoothCharacteristic? _ackChar;
//   BluetoothCharacteristic? _hydrationDataChar;
//   BluetoothCharacteristic? _hydrationChar; // 🔹 NEW for 7-slot hydration data

//   StreamSubscription<List<ScanResult>>? _scanSub;
//   StreamSubscription<BluetoothConnectionState>? _connectionSub;

//   String? savedDeviceName;
//   String? savedDeviceId;

//   final bool _isReconnecting = false;
//   final dbHelper = DatabaseHelper();
//   final List<HydrationEntry> _pendingSlots = [];

//   Future<void> start() async {
//     emit(
//       state.copyWith(
//         status: BleStatus.initializing,
//         message: "Initializing...",
//       ),
//     );

//     await _waitForBluetoothOn(() async {
//       final prefs = await SharedPreferences.getInstance();
//       savedDeviceName = prefs.getString('last_device_name');
//       savedDeviceId = prefs.getString('last_device_id');

//       final bool isFirst = (savedDeviceName == null || savedDeviceId == null);
//       emit(
//         state.copyWith(
//           status: BleStatus.initializing,
//           message: "Initializing Bluetooth",
//           isFirstConnection: isFirst,
//         ),
//       );

//       // Show one-time message if first time connecting
//       // if (isFirst && !(prefs.getBool('shownReconnectMessage') ?? false)) {
//       //   Fluttertoast.showToast(
//       //       msg: "Long press on bottle cap to reconnect",
//       //       toastLength: Toast.LENGTH_LONG,
//       //       gravity: ToastGravity.CENTER);
//       //   await prefs.setBool('shownReconnectMessage', true);
//       // }

//       if (!isFirst) {
//         _scanForLastDevice();
//       } else {
//         _scanForAllDevices();
//       }
//     });
//   }

//   Future<void> _waitForBluetoothOn(Future<void> Function() onReady) async {
//     if (await FlutterBluePlus.isSupported == false) {
//       emit(
//         state.copyWith(
//           status: BleStatus.error,
//           message: "Bluetooth not supported",
//         ),
//       );
//       return;
//     }

//     final currentState = await FlutterBluePlus.adapterState.first;
//     if (currentState == BluetoothAdapterState.on) {
//       await onReady();
//       return;
//     }

//     emit(
//       state.copyWith(
//         status: BleStatus.error,
//         message: "Please turn on Bluetooth",
//       ),
//     );

//     await FlutterBluePlus.adapterState
//         .where((s) => s == BluetoothAdapterState.on)
//         .first;

//     await onReady();
//   }

//   void _scanForLastDevice() {
//     if (savedDeviceId == null && savedDeviceName == null) {
//       return;
//     }

//     emit(
//       state.copyWith(
//         status: BleStatus.scanning,
//         message: "Scanning for last device...",
//       ),
//     );

//     _scanSub?.cancel();
//     FlutterBluePlus.startScan(
//       timeout: const Duration(seconds: 20),
//       withServices: [serviceUUID],
//     );

//     _scanSub = FlutterBluePlus.scanResults.listen(
//       (results) {
//         for (var r in results) {
//           if (r.device.id.id == savedDeviceId ||
//               r.device.name == savedDeviceName) {
//             _scanSub?.cancel();

//             FlutterBluePlus.stopScan();
//             _connectToDevice(r.device);
//             return;
//           }
//         }
//       },
//       onError: (e) {
//         emit(
//           state.copyWith(status: BleStatus.error, message: "Scan error: $e"),
//         );
//         _rescan(lastDeviceOnly: true);
//       },
//     );

//     Future.delayed(const Duration(seconds: 20), () {
//       if (state.status == BleStatus.scanning) {
//         FlutterBluePlus.stopScan().then((_) {
//           _scanForLastDevice();
//         });
//       }
//     });
//   }

//   void _scanForAllDevices() {
//     emit(
//       state.copyWith(
//         status: BleStatus.scanning,
//         message: "Scanning for BLE devices...",
//       ),
//     );

//     _scanSub?.cancel();

//     FlutterBluePlus.startScan(timeout: const Duration(seconds: 20));

//     _scanSub = FlutterBluePlus.scanResults.listen(
//       (results) {
//         if (results.isNotEmpty) {
//           var filteredDevices = results.where((it) {
//             return it.advertisementData.serviceUuids.contains(serviceUUID);
//           }).toList();
//           emit(state.copyWith(scannedDevices: filteredDevices));
//         }
//       },
//       onError: (e) {
//         emit(
//           state.copyWith(status: BleStatus.error, message: "Scan error: $e"),
//         );
//         _rescan();
//       },
//     );

//     Future.delayed(const Duration(seconds: 20), () async {
//       if (state.status == BleStatus.scanning) {
//         FlutterBluePlus.stopScan().then((_) {
//           _scanForAllDevices();
//         });
//       }
//     });
//   }

//   Future<void> _rescan({
//     bool lastDeviceOnly = false,
//     Duration delay = const Duration(milliseconds: 200),
//   }) async {
//     if (FlutterBluePlus.isScanningNow) {
//       return;
//     }

//     await Future.delayed(delay);

//     if (lastDeviceOnly) {
//       _scanForLastDevice();
//     } else {
//       _scanForAllDevices();
//     }
//   }

//   Future<void> connectToSelectedDevice(BluetoothDevice device) async {
//     FlutterBluePlus.stopScan();
//     _scanSub?.cancel();
//     _connectToDevice(device);
//   }

//   Future<void> _connectToDevice(BluetoothDevice device) async {
//     emit(
//       state.copyWith(
//         status: BleStatus.connecting,
//         message: "Connecting to ${device.name}...",
//       ),
//     );

//     try {
//       await device.connect(autoConnect: false, timeout: Duration(seconds: 6));
//       await device.connectionState
//           .where((s) => s == BluetoothConnectionState.connected)
//           .first;

//       _listenToConnection(device);

//       final prefs = await SharedPreferences.getInstance();
//       final bool wasFirst = (savedDeviceId == null || savedDeviceName == null);
//       await prefs.setString('last_device_id', device.id.id);
//       await prefs.setString('last_device_name', device.name);

//       savedDeviceId = device.id.id;
//       savedDeviceName = device.name;
//       if (wasFirst) {
//         emit(state.copyWith(isFirstConnection: false));
//       }

//       await _discoverServices(device);
//       // ✅ Save flag that BLE connected at least once
//       await prefs.setBool('ble_connected_once', true);
//     } catch (e) {
//       emit(
//         state.copyWith(
//           status: BleStatus.error,
//           message: "Connection failed: $e",
//         ),
//       );
//       _rescan(
//         lastDeviceOnly: (savedDeviceId != null || savedDeviceName != null),
//       );
//     }
//   }

//   Future<void> _discoverServices(BluetoothDevice device) async {
//     try {
//       final services = await device.discoverServices();
//       for (var s in services) {
//         if (s.uuid == serviceUUID) {
//           for (var c in s.characteristics) {
//             if (c.uuid == dataUUID) _dataChar = c;
//             if (c.uuid == ackUUID) _ackChar = c;
//             if (c.uuid == hydrationCharUUID) _hydrationChar = c;
//             if (c.uuid == hydrationDataUUID) {
//               _hydrationDataChar = c;
//             }
//           }
//         }
//       }

//       if (_dataChar == null || _ackChar == null) {
//         final prefs = await SharedPreferences.getInstance();
//         await prefs.remove('last_device_id');
//         await prefs.remove('last_device_name');

//         savedDeviceId = null;
//         savedDeviceName = null;

//         emit(
//           state.copyWith(
//             status: BleStatus.error,
//             message: "Required characteristics not found",
//             isFirstConnection: true,
//           ),
//         );

//         await device.disconnect();
//         _rescan(lastDeviceOnly: false);
//         return;
//       }

//       _dataChar!.onValueReceived.listen((value) {
//         // Fluttertoast.showToast(
//         //     msg: "BottleDataReceived : $value");
//         final data = String.fromCharCodes(value);
//         log("Received data is $data", name: "BLE_Cubit");
//         _parseData(data);
//         _sendAck(device);
//       });

//       _hydrationDataChar!.onValueReceived.listen((value) {
//         Fluttertoast.showToast(msg: "HydrationDataReceived : $value");
//         final data = String.fromCharCodes(value);
//         log("Received data is $data", name: "BLE_Cubit");
//         var hydrationUpdatedSlots = _parseHydrationData(data);
//         if (hydrationUpdatedSlots.isNotEmpty) {
//           _hydrationController.add(hydrationUpdatedSlots);
//         }
//         _sendAck(device, sendAckToHydrationSlotsCharacteristic: true);
//       });

//       if (_hydrationChar != null) {
//         await _hydrationChar!.setNotifyValue(true);
//         _hydrationChar!.onValueReceived.listen((value) async {
//           final data = String.fromCharCodes(value);
//           final entry = _parseHydrationSlotData(data);

//           if (entry != null) {
//             // Update the list of hydration entries in your Cubit state
//             final updatedList =
//                 List<HydrationEntry>.from(state.hydrationEntries ?? []);
//             if (entry.slot.index < updatedList.length) {
//               updatedList[entry.slot.index] = entry;
//             } else {
//               updatedList.add(entry);
//             }

//             emit(state.copyWith(hydrationEntries: updatedList));
//           }

//           log("💧 SlotDataReceived: $data", name: "BLE_Cubit");

//           // Support for multiple slot updates separated by '|'
//           final chunks = data.split('|');
//           List<HydrationEntry> updatedEntries = [];

//           for (var chunk in chunks) {
//             if (chunk.trim().isEmpty) continue;
//             final entry = _parseHydrationSlotData(chunk.trim());
//             if (entry != null) {
//               updatedEntries.add(entry);
//               await dbHelper.insertOrUpdateSlot(entry);
//             }
//           }

//           if (updatedEntries.isNotEmpty) {
//             _hydrationController.add(updatedEntries);
//             emit(state.copyWith(
//               message: "Updated ${updatedEntries.length} hydration slot(s)",
//             ));
//           }

//           _sendAck(device);
//         });
//       }

//       await _dataChar!.setNotifyValue(true);

//       await _hydrationDataChar!.setNotifyValue(true);

//       emit(
//         state.copyWith(
//           status: BleStatus.connected,
//           message: "Connected to ${device.name}",
//         ),
//       );

//       await _flushPendingSlots();
//     } catch (e) {
//       try {
//         await device.disconnect();
//       } catch (_) {}

//       emit(
//         state.copyWith(
//           status: BleStatus.error,
//           message: "Service discovery failed: $e",
//         ),
//       );

//       _rescan(lastDeviceOnly: savedDeviceId != null || savedDeviceName != null);
//     }
//   }

//   void _parseData(String data) {
//     final parts = data.split(';');
//     int? battery;
//     double? volume;
//     int? percent;

//     for (var p in parts) {
//       if (p.contains('battery=')) {
//         battery = int.tryParse(p.split('=')[1]);
//       }
//       if (p.contains('volume=')) {
//         volume = double.tryParse(p.split('=')[1]);
//       }
//       if (p.contains('percent=')) {
//         percent = int.tryParse(p.split('=')[1]);
//       }
//     }

//     emit(state.copyWith(
//       battery: battery,
//       volume: volume,
//       percent: percent,
//     ));
//   }

//   List<HydrationEntry> _parseHydrationData(String payload) {
//     if (payload.isEmpty) return [];
//     if (payload.toLowerCase() == "na") return [];
//     return payload.split("|").map((entry) {
//       final parts = entry.split("/");
//       if (parts.length < 5) {
//         throw FormatException("Invalid payload format: $entry");
//       }

//       final index = int.parse(parts[1]);
//       final startEpoch = int.parse(parts[2]);
//       final endEpoch = int.parse(parts[3]);
//       final amount = int.parse(parts[4]);

//       final slot = HydrationSlot.values[index];

//       return HydrationEntry(
//         slot: slot,
//         startTime: _epochToTimeOfDay(startEpoch),
//         endTime: _epochToTimeOfDay(endEpoch),
//         waterDrank: amount.round().toDouble(),
//         targetIntake: 0,
//         amount: 0,
//       );
//     }).toList();
//   }

//   HydrationEntry? _parseHydrationSlotData(String data) {
//     try {
//       final parts = data.split('/');
//       if (parts.length != 3) return null;

//       final slotIndex = int.tryParse(parts[0]) ?? 0;
//       final target = double.tryParse(parts[1]) ?? 0;
//       final consumed = double.tryParse(parts[2]) ?? 0;

//       final slot = HydrationSlot.values[slotIndex];

//       return HydrationEntry(
//         slot: slot,
//         startTime:
//             const TimeOfDay(hour: 6, minute: 0), // can be replaced with actual
//         endTime: const TimeOfDay(hour: 7, minute: 0),
//         amount: 0,
//         targetIntake: target,
//         waterDrank: consumed,
//         status: consumed >= target
//             ? HydrationStatus.completed
//             : HydrationStatus.pending,
//       );
//     } catch (e) {
//       debugPrint("⚠️ Failed to parse hydration slot data: $e");
//       return null;
//     }
//   }

//   Future<void> _sendAck(BluetoothDevice device,
//       {bool sendAckToHydrationSlotsCharacteristic = false}) async {
//     // try {
//     //   emit(
//     //     state.copyWith(status: BleStatus.sendingAck, message: "Sending ACK..."),
//     //   );
//     //   if (sendAckToHydrationSlotsCharacteristic == true) {
//     //     await _hydrationDataChar?.write("ACK".codeUnits, withoutResponse: true);
//     //     await device.disconnect();
//     //   } else {
//     //     await _ackChar?.write("ACK".codeUnits, withoutResponse: true);
//     //     await device.disconnect();
//     //   }

//     //   emit(
//     //     state.copyWith(
//     //       status: BleStatus.disconnected,
//     //       message: "Device sleeping, will reconnect...",
//     //     ),
//     //   );
//     // } catch (e) {
//     //   emit(state.copyWith(status: BleStatus.error, message: "ACK failed: $e"));
//     // }
//   }

//   Future<void> forgetDevice() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.remove('last_device_id');
//     await prefs.remove('last_device_name');

//     savedDeviceId = null;
//     savedDeviceName = null;

//     emit(
//       state.copyWith(
//         status: BleStatus.scanning,
//         isFirstConnection: true,
//         message: "Device forgotten. \nReady to scan for new devices.",
//       ),
//     );

//     if (FlutterBluePlus.isScanningNow) {
//       await FlutterBluePlus.stopScan();
//     }
//     emit(
//       state.copyWith(
//         status: BleStatus.scanning,
//         isFirstConnection: true,
//         scannedDevices: [],
//         message: "Device forgotten. \nReady to scan for new devices.",
//       ),
//     );

//     _scanForAllDevices();
//   }

//   void _listenToConnection(BluetoothDevice device) {
//     _connectionSub?.cancel();

//     _connectionSub = device.connectionState.listen((stateChange) {
//       switch (stateChange) {
//         case BluetoothConnectionState.connected:
//           emit(state.copyWith(
//             status: BleStatus.connected,
//             message: "Connected to ${device.name}",
//           ));
//           break;

//         case BluetoothConnectionState.disconnected:
//           emit(state.copyWith(
//             status: BleStatus.disconnected,
//             message: "Device disconnected",
//           ));

//           if (savedDeviceId != null || savedDeviceName != null) {
//             _rescan(lastDeviceOnly: true);
//           }
//           break;

//         case BluetoothConnectionState.connecting:
//           emit(state.copyWith(
//             status: BleStatus.connecting,
//             message: "Connecting to ${device.name}...",
//           ));
//           break;

//         default:
//           {}
//       }
//     });
//   }

//   Future<void> _flushPendingSlots() async {
//     if (_ackChar == null || _pendingSlots.isEmpty) return;

//     try {
//       final payload = _pendingSlots.map((slot) {
//         final startEpoch = _timeOfDayToEpoch(slot.startTime);
//         final endEpoch = _timeOfDayToEpoch(slot.endTime);

//         return "${slot.slot.label}/${slot.slot.index}/$startEpoch/$endEpoch/${slot.amount}";
//       }).join("|");

//       log("Flushing hydration slots: $payload");

//       await _ackChar!.write(payload.codeUnits, withoutResponse: true);

//       _pendingSlots.clear();

//       emit(state.copyWith(
//         status: BleStatus.connected,
//         message: "Hydration slots synced",
//       ));
//     } catch (e) {
//       emit(
//           state.copyWith(status: BleStatus.error, message: "Flush failed: $e"));
//     }
//   }

//   Future<void> _fetchUpdatedSlots() async {
//     if (_ackChar == null || _pendingSlots.isEmpty) return;

//     try {
//       final payload = _pendingSlots.map((slot) {
//         final startEpoch = _timeOfDayToEpoch(slot.startTime);
//         final endEpoch = _timeOfDayToEpoch(slot.endTime);

//         return "${slot.slot.label}/${slot.slot.index}/$startEpoch/$endEpoch/${slot.amount}";
//       }).join("|");

//       log("Flushing hydration slots: $payload");

//       await _ackChar!.write(payload.codeUnits, withoutResponse: true);

//       _pendingSlots.clear();

//       emit(state.copyWith(
//         status: BleStatus.connected,
//         message: "Hydration slots synced",
//       ));
//     } catch (e) {
//       emit(
//           state.copyWith(status: BleStatus.error, message: "Flush failed: $e"));
//     }
//   }
//   /* For testing */

//   Future<void> forceFlushSlots() async {
//     try {
//       var slots = await dbHelper.getAllSlots();

//       final payload = slots.map((slot) {
//         final startEpoch = _timeOfDayToEpoch(slot.startTime);
//         final endEpoch = _timeOfDayToEpoch(slot.endTime);

//         return "${slot.slot.label}/${slot.slot.index}/$startEpoch/$endEpoch/${slot.amount}";
//       }).join("|");

//       log("Flushing hydration slots: $payload");

//       await _ackChar!.write(payload.codeUnits, withoutResponse: true);

//       slots.clear();

//       emit(state.copyWith(
//         status: BleStatus.connected,
//         message: "Hydration slots synced",
//       ));
//     } catch (e) {
//       emit(
//           state.copyWith(status: BleStatus.error, message: "Flush failed: $e"));
//     }
//   }

//   int _timeOfDayToEpoch(TimeOfDay tod) {
//     final now = DateTime.now();
//     final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
//     return dt.millisecondsSinceEpoch ~/ 1000; // seconds since epoch
//   }

//   TimeOfDay _epochToTimeOfDay(int epoch) {
//     final hour = epoch ~/ 3600;
//     final minute = (epoch % 3600) ~/ 60;
//     return TimeOfDay(hour: hour, minute: minute);
//   }

//   // @override
//   // Future<void> queueHydrationSlots(List<HydrationEntry> slots) async {
//   //   // Add to pending queue
//   //   _pendingSlots.clear();
//   //   _pendingSlots.addAll(slots);

//   //   if (state.status == BleStatus.connected) {
//   //     await _flushPendingSlots();
//   //   } else {
//   //     emit(state.copyWith(message: "Device not connected, will sync later"));
//   //   }
//   // }

//   @override
//   Future<void> queueHydrationSlots(List<HydrationEntry> entries) async {
//     _pendingSlots.clear();
//     _pendingSlots.addAll(entries);
//     if (state.status == BleStatus.connected) {
//       await _flushPendingSlots();
//     } else {
//       emit(state.copyWith(message: "Device not connected, will sync later"));
//     }
//   }

//   @override
//   Stream<List<HydrationEntry>> get hydrationUpdates =>
//       _hydrationController.stream;
// }
