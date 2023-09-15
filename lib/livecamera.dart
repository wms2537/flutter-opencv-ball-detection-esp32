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
    required this.camera,
    required this.callback,
  }) : super(key: key);

  final CameraDescription camera;
  final Future<void> Function(List<int> data) callback;

  @override
  TakePictureScreenState createState() => TakePictureScreenState();
}

class TakePictureScreenState extends State<TakePictureScreen> {
  final dylib = Platform.isAndroid
      ? DynamicLibrary.open("libOpenCV_ffi.so")
      : DynamicLibrary.process();
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isStreaming = false;
  Image _img = Image.asset('assets/img/default.jpg');
  Image _old = Image.asset('assets/img/default.jpg');
  int _frameCount = 0;
  late Pointer<Uint8> p;
  Pointer<Uint8>? oldp;
  Pointer<Uint32> s = malloc.allocate(1);
  Pointer<Uint8> res = malloc.allocate(2);
  double _kp = 1, _ki = 0, _kd = 0;
  @override
  void initState() {
    super.initState();
    // To display the current output from the Camera,
    // create a CameraController.
    _controller = CameraController(
        // Get a specific camera from the list of available cameras.
        widget.camera,
        // Define the resolution to use.
        ResolutionPreset.low,
        imageFormatGroup: ImageFormatGroup.jpeg);

    // Next, initialize the controller. This returns a Future.
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    // Dispose of the controller when the widget is disposed.
    _controller.dispose();
    malloc.free(s);
    malloc.free(res);
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
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // If the Future is complete, display the preview.
            return Center(
                child: Column(
              children: [
                Text("Kp"),
                Slider(
                  value: _kp,
                  max: 10,
                  divisions: 100,
                  label: _kp.toString(),
                  onChanged: (double value) {
                    setState(() {
                      _kp = value;
                    });
                  },
                ),
                Text("Ki"),
                Slider(
                  value: _ki,
                  max: 10,
                  divisions: 100,
                  label: _kp.toString(),
                  onChanged: (double value) {
                    setState(() {
                      _ki = value;
                    });
                  },
                ),
                Text("Kd"),
                Slider(
                  value: _kd,
                  max: 10,
                  divisions: 100,
                  label: _kp.toString(),
                  onChanged: (double value) {
                    setState(() {
                      _kd = value;
                    });
                  },
                ),
                Expanded(
                  child: Stack(
                    children: [_old, _img],
                  ),
                ),
              ],
            ));
            //CameraPreview(_controller);
          } else {
            // Otherwise, display a loading indicator.
            return const Center(child: CircularProgressIndicator());
          }
        },
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
              await _controller.stopImageStream();
              print("Stopped");
              setState(() => _isStreaming = false);
            } else {
              setState(() => _isStreaming = true);
              print("Starting");

              await _controller
                  .startImageStream((CameraImage availableImage) async {
                _frameCount++;
                s[0] = availableImage.planes[0].bytes.length;
                // Pointer<Uint8> p = malloc.allocate(4 *
                //     availableImage.height *
                //     availableImage.width); // Taking extra space for buffer
                // p
                //     .asTypedList(s[0])
                //     .setRange(0, s[0], availableImage.planes[0].bytes);

                final imageffi = dylib.lookupFunction<
                    Void Function(Pointer<Uint8>, Pointer<Uint32>,
                        Pointer<Uint8>, Double),
                    void Function(Pointer<Uint8>, Pointer<Uint32>,
                        Pointer<Uint8>, double)>('image_ffi');
                imglib.Image img = imglib.Image.fromBytes(
                  availableImage.width,
                  availableImage.height,
                  availableImage.planes[0].bytes,
                  format: imglib.Format.bgra,
                );
                imglib.JpegEncoder jpegEncoder = imglib.JpegEncoder();
                List<int> bytes = jpegEncoder.encodeImage(img);
                s[0] = bytes.length;
                p = malloc.allocate(3 *
                    availableImage.height *
                    availableImage.width); // Taking extra space for buffer
                p.asTypedList(s[0]).setRange(0, s[0], bytes);
                // p = malloc.allocate(bytes.length);
                // p.asTypedList(bytes.length).setRange(0, bytes.length, bytes);

                imageffi(p, s, res, _kp);

                if (mounted) {
                  setState(() {
                    _old = _img;
                    _img = Image.memory(p.asTypedList(s[0]));
                  });
                  if (oldp != null) {
                    malloc.free(oldp!);
                    oldp = p;
                  }
                }
                if (_frameCount % 3 == 0)
                  await widget.callback(res.asTypedList(2).toList());
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
