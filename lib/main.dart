import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:io';
import 'package:camera/camera.dart';
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
      title: 'OpenCV on Flutter',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MyHomePage(title: 'OpenCV C++ on dart:ffi'),
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
      appBar: AppBar(title: Text(widget.title)),
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
                                    _device = r.device;
                                    try {
                                      await _device!.connect();
                                      // Note: You must call discoverServices after every connection!
                                      List<BluetoothService> services =
                                          await _device!.discoverServices();
                                      services.forEach((service) {
                                        print(service.uuid.toString());
                                      });
                                      final service = services.firstWhere(
                                          (service) =>
                                              service.uuid.toString() ==
                                              "457ec52f-15ab-4e93-8f29-c9c9ae9b22c2");
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
                                    } catch (e) {
                                      showErrorDialog(e.toString(), context);
                                      return;
                                    }
                                    if (_c == null) return;
                                    WidgetsFlutterBinding.ensureInitialized();
                                    // Obtain a list of the available cameras on the device.
                                    final cameras = await availableCameras();
                                    // Get a specific camera from the list of available cameras.
                                    final firstCamera = cameras.first;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TakePictureScreen(
                                          camera: firstCamera,
                                          callback: (data) {
                                            return _c!.write(data);
                                          },
                                        ),
                                      ),
                                    );
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
            // if (_device != null)
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
