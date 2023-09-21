import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import 'package:image/image.dart' as imglib;

// A screen that allows users to take a picture using a given camera.
class TakePictureScreen extends StatefulWidget {
  const TakePictureScreen({
    Key? key,
    required this.callback,
  }) : super(key: key);

  final Future<void> Function(List<int> data) callback;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  final dylib = Platform.isAndroid
      ? DynamicLibrary.open("libOpenCV_ffi.so")
      : DynamicLibrary.process();
  CameraController? _controller;
  bool _isStreaming = false, _isProcessing = false;
  Image _img = Image.asset('assets/img/default.jpg');
  Image _old = Image.asset('assets/img/default.jpg');
  int _frameCount = 0;
  late Pointer<Uint8> p;
  Pointer<Uint8>? oldp;
  Pointer<Uint32> s = malloc.allocate(1);
  Pointer<Uint8> res = malloc.allocate(2);
  Pointer<Double> integral = malloc.allocate(1);
  Pointer<Double> lastErr = malloc.allocate(1);
  double _kp = 0.3, _ki = 0, _kd = 0, _maxVal = 200;

  Future<void> _initializeControllerFuture() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Obtain a list of the available cameras on the device.
    final cameras = await availableCameras();
    // Get a specific camera from the list of available cameras.
    final firstCamera = cameras.first;
    // To display the current output from the Camera,
    // create a CameraController.
    _controller = CameraController(
        // Get a specific camera from the list of available cameras.
        firstCamera,
        // Define the resolution to use.
        ResolutionPreset.low,
        imageFormatGroup: ImageFormatGroup.jpeg);

    // Next, initialize the controller. This returns a Future.
    await _controller!.initialize();
    integral.asTypedList(1).setRange(0, 1, [0]);
    lastErr.asTypedList(1).setRange(0, 1, [0]);
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _controller?.dispose();
    malloc.free(s);
    malloc.free(res);
    malloc.free(lastErr);
    malloc.free(integral);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isStreaming ? 'Live' : 'Start Camera')),
      // You must wait until the controller is initialized before displaying the
      // camera preview. Use a FutureBuilder to display a loading spinner until the
      // controller has finished initializing.
      body: FutureBuilder<void>(
        future: _controller == null ? _initializeControllerFuture() : null,
        builder: (context, snapshot) =>
            snapshot.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                :
                // If the Future is complete, display the preview.
                Center(
                    child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text("Kp"),
                            Expanded(
                              child: Slider(
                                value: _kp,
                                max: 2,
                                divisions: 100,
                                label: _kp.toString(),
                                onChanged: (double value) {
                                  setState(() {
                                    _kp = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text("Ki"),
                            Expanded(
                              child: Slider(
                                value: _ki,
                                max: 1,
                                divisions: 100,
                                label: _ki.toString(),
                                onChanged: (double value) {
                                  setState(() {
                                    _ki = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text("Kd"),
                            Expanded(
                              child: Slider(
                                value: _kd,
                                max: 10,
                                divisions: 100,
                                label: _kd.toString(),
                                onChanged: (double value) {
                                  setState(() {
                                    _kd = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Text("max val"),
                            Expanded(
                              child: Slider(
                                value: _maxVal,
                                min: 100,
                                max: 255,
                                divisions: 155,
                                label: _maxVal.toString(),
                                onChanged: (double value) {
                                  setState(() {
                                    _maxVal = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _img,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              res.asTypedList(2)[0].toRadixString(10),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              res.asTypedList(2)[1].toRadixString(10),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    ],
                  )),
      ),
      floatingActionButton: FloatingActionButton(
        // Provide an onPressed callback.
        onPressed: () async {
          // Take the Picture in a try / catch block. If anything goes wrong,
          // catch the error.
          try {
            // Ensure that the camera is initialized.
            await _initializeControllerFuture;
            if (_isStreaming) {
              await _controller!.stopImageStream();
              print("Stopped");
              setState(() => _isStreaming = false);
            } else {
              setState(() => _isStreaming = true);
              print("Starting");

              await _controller!
                  .startImageStream((CameraImage availableImage) async {
                if (_isProcessing) return;
                _frameCount++;
                _isProcessing = true;
                if (Platform.isAndroid) {
                  s[0] = availableImage.planes[0].bytes.length;
                  p = malloc.allocate(3 *
                      availableImage.height *
                      availableImage.width); // Taking extra space for buffer
                  p
                      .asTypedList(s[0])
                      .setRange(0, s[0], availableImage.planes[0].bytes);
                } else {
                  imglib.Image img = imglib.Image.fromBytes(
                    width: (availableImage.planes[0].bytesPerRow / 4).round(),
                    height: availableImage.height,
                    bytes: availableImage.planes[0].bytes.buffer,
                    order: imglib.ChannelOrder.bgra,
                    format: imglib.Format.uint8,
                  );
                  imglib.JpegEncoder jpegEncoder = imglib.JpegEncoder();
                  List<int> bytes = jpegEncoder.encode(img);
                  s[0] = bytes.length;
                  p = malloc.allocate(3 *
                      availableImage.height *
                      availableImage.width); // Taking extra space for buffer
                  p.asTypedList(s[0]).setRange(0, s[0], bytes);
                }

                final imageffi = dylib.lookupFunction<
                    Void Function(
                      Pointer<Uint8>,
                      Pointer<Uint32>,
                      Pointer<Uint8>,
                      Pointer<Double>,
                      Pointer<Double>,
                      Double,
                      Double,
                      Double,
                      Double,
                    ),
                    void Function(
                      Pointer<Uint8>,
                      Pointer<Uint32>,
                      Pointer<Uint8>,
                      Pointer<Double>,
                      Pointer<Double>,
                      double,
                      double,
                      double,
                      double,
                    )>('image_ffi');

                // p = malloc.allocate(bytes.length);
                // p.asTypedList(bytes.length).setRange(0, bytes.length, bytes);

                imageffi(p, s, res, integral, lastErr, _kp, _ki, _kd, _maxVal);

                if (_frameCount % 5 == 0) {
                  await widget.callback(res.asTypedList(2).toList());
                }

                if (mounted) {
                  setState(() {
                    _img = Image.memory(
                      p.asTypedList(s[0]),
                      gaplessPlayback: true,
                    );
                  });
                  malloc.free(p);
                }
                _isProcessing = false;
              });
            }
          } catch (e) {
            // If an error occurs, log the error to the console.
            print(e);
          }
        },
        child: _isStreaming
            ? const Icon(Icons.visibility)
            : const Icon(Icons.camera_alt),
      ),
    );
  }
}
