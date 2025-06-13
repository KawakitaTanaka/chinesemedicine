import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext ctx) => MaterialApp(
    title: '穴位定位',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: HomePage(),
  );
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Interpreter? _interpreter;
  List<Offset> _points = [];
  ui.Image? _displayImage;

  final int inputSize = 224; // 与模型训练保持一致
  final String modelPath = 'assets/model8.tflite';

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    _interpreter = await Interpreter.fromAsset(modelPath);
  }

  /// 通用打点流程：pickImage / takePhoto 调用此方法
  Future<void> _processFile(XFile file) async {
    // 1. 解码并显示
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() => _displayImage = frame.image);

    // 2. 前处理成 224×224 float32 ByteBuffer
    final img = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(0, 0, inputSize.toDouble(), inputSize.toDouble()),
      Paint(),
    );
    final picture = recorder.endRecording();
    final resized = await picture.toImage(inputSize, inputSize);
    final byteData = await resized.toByteData(format: ui.ImageByteFormat.rawRgba);
    final buffer = byteData!.buffer.asUint8List();

    // Build Float32 input tensor in [1,224,224,3]
    final input = Float32List(1 * inputSize * inputSize * 3);
    int offset = 0;
    for (int i = 0; i < buffer.lengthInBytes; i += 4) {
      // RGBA bytes → normalize RGB
      final r = buffer[i] / 255.0;
      final g = buffer[i + 1] / 255.0;
      final b = buffer[i + 2] / 255.0;
      input[offset++] = r;
      input[offset++] = g;
      input[offset++] = b;
    }
    final inputBuffer = input.buffer;

    // 3. 推论
    final output = Float32List(12); // 6 点 × 2 维
    _interpreter!.run(inputBuffer, output);

    // 4. 后处理：乘回原图尺寸
    final w = img.width.toDouble();
    final h = img.height.toDouble();
    _points = [];
    for (int i = 0; i < output.length; i += 2) {
      final x = output[i] * w;
      final y = output[i + 1] * h;
      _points.add(Offset(x, y));
    }

    setState(() {});
  }

  Future<void> _pickFromGallery() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file != null) await _processFile(file);
  }

  Future<void> _takePhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file != null) await _processFile(file);
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text('穴位定位')),
      body: Column(
        children: [
          Expanded(
            child: _displayImage == null
                ? Center(child: Text('請從相簿選圖或拍照以進行預測'))
                : FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _displayImage!.width.toDouble(),
                height: _displayImage!.height.toDouble(),
                child: CustomPaint(
                    painter: PointPainter(_displayImage!, _points)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.photo_library),
                    label: Text('相簿選圖'),
                    onPressed: _pickFromGallery,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.camera_alt),
                    label: Text('拍照'),
                    onPressed: _takePhoto,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PointPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> points;
  PointPainter(this.image, this.points);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(image, Offset.zero, Paint());
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill
      ..strokeWidth = 8;
    for (var pt in points) {
      canvas.drawCircle(pt, 10, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PointPainter old) =>
      old.image != image || old.points != points;
}