import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'dart:io';
import 'package:opencv_flutter_ffi/error_dialog.dart';
import 'package:opencv_flutter_ffi/scan_result_tile.dart';
import 'package:permission_handler/permission_handler.dart';

import 'livecamera.dart';

void main() {
  if (Platform.isAndroid) {
    WidgetsFlutterBinding.ensureInitialized();
    [
      Permission.location,
      Permission.storage,
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan
    ].request().then((status) {
      runApp(const MyApp());
    });
  } else {
    runApp(const MyApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ball Tracker',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MyHomePage(title: 'Connect BLE'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _c;

  @override
  void initState() {
    FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15), androidUsesFineLocation: false);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
              onPressed: () {
                if (FlutterBluePlus.isScanningNow == false) {
                  FlutterBluePlus.startScan(
                      timeout: const Duration(seconds: 15),
                      androidUsesFineLocation: false);
                }
              },
              icon: Icon(Icons.refresh))
        ],
      ),
      body: Center(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  // setState(() {}); // force refresh of connectedSystemDevices
                  if (FlutterBluePlus.isScanningNow == false) {
                    FlutterBluePlus.startScan(
                        timeout: const Duration(seconds: 15),
                        androidUsesFineLocation: false);
                  }
                  return Future.delayed(
                      Duration(milliseconds: 500)); // show refresh icon breifly
                },
                child: SingleChildScrollView(
                  child: StreamBuilder<List<ScanResult>>(
                    stream: FlutterBluePlus.scanResults,
                    builder: (context, snapshot) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("Devices"),
                          ...(snapshot.data ?? [])
                              .map(
                                (r) => ScanResultTile(
                                  result: r,
                                  onTap: () async {
                                    setState(() {
                                      _device = r.device;
                                    });
                                    try {
                                      await _device!.connect();
                                      // Note: You must call discoverServices after every connection!
                                      List<BluetoothService> services =
                                          await _device!.discoverServices();
                                      services.forEach((service) {
                                        print(service.uuid.toString());
                                      });
                                      final serviceIndex = services.indexWhere(
                                          (service) =>
                                              service.uuid.toString() ==
                                              "457ec52f-15ab-4e93-8f29-c9c9ae9b22c2");
                                      if (serviceIndex >= 0) {
                                        final service = services[serviceIndex];
                                        // Reads all characteristics
                                        final characteristics =
                                            service.characteristics;
                                        for (BluetoothCharacteristic c
                                            in characteristics) {
                                          if (c.uuid.toString() ==
                                              "fcdf225f-b0fa-44b4-9f5b-765c874117cc") {
                                            _c = c;
                                          }
                                          // List<int> value = await c.read();
                                          // print(value);
                                        }
                                      }
                                    } catch (e) {
                                      showErrorDialog(e.toString(), context);
                                      return;
                                    }
                                    if (_c == null) {
                                      final res = await showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Warning'),
                                          content: const Text(
                                              'Not Expected BLE Device, are you sure to continue?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(),
                                              child: const Text('No'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(true),
                                              child: const Text('Yes'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (res != true) return;
                                    }
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TakePictureScreen(
                                          callback: (data) async {
                                            await _c?.write(data);
                                          },
                                        ),
                                      ),
                                    );
                                    await _device?.disconnect();
                                    _device = null;
                                    setState(() {});
                                  },
                                ),
                              )
                              .toList()
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            if (_device != null)
              ElevatedButton(
                onPressed: () async {
                  await _device?.disconnect();
                  _device = null;
                  setState(() {});
                },
                child: const Text("Disconnect"),
              ),
          ],
        ),
      ),
    );
  }
}
