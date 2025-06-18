import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext ctx) => MaterialApp(
    title: '中醫穴位定位',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Interpreter? _interpreter;
  XFile? _pickedFile;
  ui.Image? _displayImage;
  List<Offset> _points = [];

  final int inputSize = 224;
  final String modelAsset = 'assets/model7.tflite';

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    _interpreter = await Interpreter.fromAsset(modelAsset);
    debugPrint('Interpreter loaded: $_interpreter');
  }

  Future<void> _processFile(XFile file) async {
    // decode image
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    // update display image and clear points
    setState(() {
      _displayImage = img;
      _points = [];
    });

    // preprocess: resize + normalize
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, inputSize.toDouble(), inputSize.toDouble()),
      Paint(),
    );
    final resized = await recorder.endRecording().toImage(inputSize, inputSize);
    final bd = await resized.toByteData(format: ui.ImageByteFormat.rawRgba);
    final buffer = bd!.buffer.asUint8List();
    final input = Float32List(inputSize * inputSize * 3);
    int offset = 0;
    for (int i = 0; i < buffer.length; i += 4) {
      input[offset++] = buffer[i] / 255.0;
      input[offset++] = buffer[i + 1] / 255.0;
      input[offset++] = buffer[i + 2] / 255.0;
    }

    // inference: output shape [1,12]
    List<List<double>> output = List.generate(1, (_) => List.filled(12, 0.0));
    _interpreter!.run(input.buffer, output);
    final raw = output[0];
    debugPrint('Model output raw: $raw');

    // map to original image coords
    final w = img.width.toDouble(), h = img.height.toDouble();
    final pts = <Offset>[];
    for (int i = 0; i < raw.length; i += 2) {
      pts.add(Offset(raw[i] * w, raw[i + 1] * h));
    }

    setState(() {
      _points = pts;
    });
  }

  Future<void> _pickFromGallery() async {
    _pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    setState(() {});
  }

  Future<void> _takePhoto() async {
    _pickedFile = await ImagePicker().pickImage(source: ImageSource.camera);
    setState(() {});
  }

  Future<void> _analyze() async {
    if (_pickedFile != null) {
      await _processFile(_pickedFile!);
    }
  }

  void _clear() {
    setState(() {
      _pickedFile = null;
      _displayImage = null;
      _points = [];
    });
  }

  @override
  Widget build(BuildContext ctx) {
    // screen width
    final screenW = MediaQuery.of(ctx).size.width;
    if (_displayImage == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('中醫穴位定位'),
          actions: [
            if (_pickedFile != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.check, color: Colors.green),
              ),
            if (_pickedFile != null)
              IconButton(
                icon: const Icon(Icons.clear),
                tooltip: '清除',
                onPressed: _clear,
              ),
          ],
        ),
        body: const Center(
          child: Text(
            '請先從相簿選圖或拍照，再點右下方 🔍 進行分析',
            textAlign: TextAlign.center,
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _pickedFile == null ? null : _analyze,
          tooltip: '分析',
          child: const Icon(Icons.search),
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('相簿選圖'),
                  onPressed: _pickFromGallery,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('拍照'),
                  onPressed: _takePhoto,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final imgW = _displayImage!.width.toDouble();
    final imgH = _displayImage!.height.toDouble();
    final displayH = screenW * imgH / imgW;
    final scaleX = screenW / imgW;
    final scaleY = displayH / imgH;
    final scaledPoints = _points
        .map((pt) => Offset(pt.dx * scaleX, pt.dy * scaleY))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('中醫穴位定位'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(Icons.check, color: Colors.green),
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: '清除',
            onPressed: _clear,
          ),
        ],
      ),
      body: Center(
        child: SizedBox(
          width: screenW,
          height: displayH,
          child: Stack(
            children: [
              Image.file(
                File(_pickedFile!.path),
                width: screenW,
                height: displayH,
                fit: BoxFit.fill,
              ),
              CustomPaint(
                size: Size(screenW, displayH),
                painter: PointPainter(scaledPoints),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _analyze,
        tooltip: '分析',
        child: const Icon(Icons.search),
      ),
    );
  }
}

class PointPainter extends CustomPainter {
  final List<Offset> points;
  PointPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
    for (var pt in points) {
      canvas.drawCircle(pt, 8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PointPainter old) => old.points != points;
}
