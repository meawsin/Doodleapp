import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const DoodleApp());
}

class DoodleApp extends StatelessWidget {
  const DoodleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DoodleScreen(),
    );
  }
}

class DoodleScreen extends StatefulWidget {
  const DoodleScreen({super.key});

  @override
  _DoodleScreenState createState() => _DoodleScreenState();
}

class _DoodleScreenState extends State<DoodleScreen> {
  Color _penColor = Colors.black;
  double _penSize = 4.0;
  Color _bgColor = Colors.white;
  final List<DrawingPoint> _points = [];
  final GlobalKey _globalKey = GlobalKey(); // Key for RepaintBoundary

  void _changePenColor(Color color) {
    setState(() {
      _penColor = color;
    });
  }

  void _changePenSize(double size) {
    setState(() {
      _penSize = size;
    });
  }

  void _changeBackgroundColor(Color color) {
    setState(() {
      _bgColor = color;
    });
  }

  void _clearCanvas() {
    setState(() {
      _points.clear();
    });
  }

  Future<void> saveImageToFile(Uint8List imageBytes) async {
    // Request necessary permissions
    await _requestPermission();

    String path;
    // For Android 10+ use MediaStore
    if (Platform.isAndroid && await _isAndroid10orAbove()) {
      path = await _getPublicDirectoryForAndroid10AndAbove();
    } else {
      // For older Android versions, use the old method
      path = await _getPublicDirectoryForOlderVersions();
    }

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('$path/doodle_$timestamp.png');

    await file.writeAsBytes(imageBytes);
    print('Image saved to: ${file.path}');
  }

// Request permissions for storage
  Future<void> _requestPermission() async {
    final permissionStatus = await Permission.storage.request();
    if (!permissionStatus.isGranted) {
      throw 'Permission not granted. Please enable storage permissions.';
    }
  }

// Check if the Android version is 10 or above
  Future<bool> _isAndroid10orAbove() async {
    return Platform.isAndroid && (await _getSdkVersion()) >= 29;
  }

// Get SDK version
  Future<int> _getSdkVersion() async {
    final sdkVersion = await _getSdkVersionNative(); // Call the native method
    return sdkVersion;
  }

  // Define the native method to get SDK version
  Future<int> _getSdkVersionNative() async {
    // Replace this with actual implementation to fetch SDK version
    return 30; // Example: returning a hardcoded value
  }

// For Android 10+ and above, save file to Pictures directory in MediaStore
  Future<String> _getPublicDirectoryForAndroid10AndAbove() async {
    final directory = await getExternalStorageDirectory();
    final path = '${directory?.path}/Pictures';

    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(
          recursive: true); // Create the directory if it doesn't exist
    }
    return path;
  }

// For devices below Android 10, save file to Pictures folder
  Future<String> _getPublicDirectoryForOlderVersions() async {
    final directory = await getExternalStorageDirectory();
    final path = '${directory?.path}/Pictures';

    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(
          recursive: true); // Create the directory if it doesn't exist
    }
    return path;
  }

  void _showColorPicker(Function(Color) onColorSelected) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Pick a Color"),
        content: Wrap(
          children: [
            Colors.black,
            Colors.white,
            Colors.red,
            Colors.blue,
            Colors.green,
            Colors.yellow,
            Colors.orange,
            Colors.purple,
            Colors.pink,
            Colors.brown,
            Colors.grey,
            Colors.teal,
            Colors.cyan,
            Colors.indigo,
            Colors.lime
          ].map((color) {
            return GestureDetector(
              onTap: () {
                onColorSelected(color);
                Navigator.pop(context);
              },
              child: Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showPenSizePicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Select Pen Size"),
        content: Wrap(
          children: [2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0].map((size) {
            return GestureDetector(
              onTap: () {
                _changePenSize(size);
                Navigator.pop(context);
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text("${size.toInt()} px",
                    style: const TextStyle(fontSize: 16)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueGrey,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              iconSize: 30.0,
              padding: EdgeInsets.all(10),
              icon: const Icon(Icons.brush_sharp),
              onPressed: () => _showColorPicker(_changePenColor),
            ),
            IconButton(
              iconSize: 30.0,
              padding: EdgeInsets.all(10),
              icon: const Icon(Icons.format_size),
              onPressed: _showPenSizePicker,
            ),
            IconButton(
              iconSize: 30.0,
              padding: EdgeInsets.all(10),
              icon: const Icon(Icons.format_paint_sharp),
              onPressed: () => _showColorPicker(_changeBackgroundColor),
            ),
            IconButton(
              iconSize: 30.0,
              padding: EdgeInsets.all(10),
              icon: const Icon(Icons.restart_alt),
              onPressed: _clearCanvas,
            ),
            IconButton(
              iconSize: 30.0,
              padding: EdgeInsets.all(10),
              icon: const Icon(Icons.save_alt_outlined),
              onPressed: () async {
                // Call the saveImageToFile function here
                final boundary = _globalKey.currentContext?.findRenderObject()
                    as RenderRepaintBoundary?;
                if (boundary != null) {
                  final image = await boundary.toImage();
                  final byteData =
                      await image.toByteData(format: ui.ImageByteFormat.png);
                  if (byteData != null) {
                    await saveImageToFile(byteData.buffer.asUint8List());
                  }
                }
              },
            ),
          ],
        ),
      ),
      body: RepaintBoundary(
        key: _globalKey, // Wraps the drawing area
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _points.add(
                DrawingPoint(details.localPosition, _penColor, _penSize),
              );
            });
          },
          onPanEnd: (details) {
            _points.add(DrawingPoint(Offset.zero, Colors.transparent, 0));
          },
          child: CustomPaint(
            painter: DoodlePainter(_points, _bgColor),
            child: Container(width: double.infinity, height: double.infinity),
          ),
        ),
      ),
    );
  }
}

class DrawingPoint {
  Offset offset;
  Color color;
  double size;
  DrawingPoint(this.offset, this.color, this.size);
}

class DoodlePainter extends CustomPainter {
  final List<DrawingPoint> points;
  final Color bgColor;
  DoodlePainter(this.points, this.bgColor);

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = bgColor;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    for (var i = 0; i < points.length - 1; i++) {
      if (points[i].offset != Offset.zero &&
          points[i + 1].offset != Offset.zero) {
        final pen = Paint()
          ..color = points[i].color
          ..strokeWidth = points[i].size
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(points[i].offset, points[i + 1].offset, pen);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
