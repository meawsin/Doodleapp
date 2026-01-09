import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart'; // Gallery Saver
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const DoodleApp());
}

class DoodleApp extends StatelessWidget {
  const DoodleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pro Doodle',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const CanvasScreen(),
    );
  }
}

// ==========================================
//                 MODELS
// ==========================================

/// A single point in a stroke
class Point {
  final double dx;
  final double dy;

  Point(this.dx, this.dy);

  Map<String, dynamic> toJson() => {'x': dx, 'y': dy};

  factory Point.fromJson(Map<String, dynamic> json) {
    return Point(json['x'] as double, json['y'] as double);
  }

  Offset toOffset() => Offset(dx, dy);
}

/// A continuous line (stroke) with style
class Stroke {
  final List<Point> points;
  final int colorValue;
  final double size;
  final double opacity;

  Stroke({
    required this.points,
    required this.colorValue,
    required this.size,
    required this.opacity,
  });

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => p.toJson()).toList(),
        'color': colorValue,
        'size': size,
        'opacity': opacity,
      };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    return Stroke(
      points: (json['points'] as List).map((e) => Point.fromJson(e)).toList(),
      colorValue: json['color'] as int,
      size: (json['size'] as num).toDouble(),
      opacity: (json['opacity'] as num).toDouble(),
    );
  }

  Color get color => Color(colorValue).withOpacity(opacity);
}

/// A saved drawing session
class Draft {
  final String id;
  final String name;
  final List<Stroke> strokes;
  final int bgColorValue;
  final String lastModified;

  Draft({
    required this.id,
    required this.name,
    required this.strokes,
    required this.bgColorValue,
    required this.lastModified,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'bgColor': bgColorValue,
        'lastModified': lastModified,
      };

  factory Draft.fromJson(Map<String, dynamic> json) {
    return Draft(
      id: json['id'],
      name: json['name'],
      strokes: (json['strokes'] as List).map((e) => Stroke.fromJson(e)).toList(),
      bgColorValue: json['bgColor'] ?? Colors.white.value,
      lastModified: json['lastModified'],
    );
  }
}

// ==========================================
//              MAIN SCREEN
// ==========================================

class CanvasScreen extends StatefulWidget {
  const CanvasScreen({super.key});

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  // --- State Variables ---
  
  // Canvas Data
  List<Stroke> _strokes = [];
  List<Stroke> _redoStack = [];
  Color _bgColor = Colors.white;
  String? _currentDraftId;

  // Tools
  Color _brushColor = Colors.black;
  double _brushSize = 5.0;
  double _brushOpacity = 1.0;
  bool _isPanMode = false; // Toggle between Draw (false) and Pan/Zoom (true)

  // System
  final GlobalKey _canvasKey = GlobalKey();
  final TransformationController _transformController = TransformationController();
  List<Point> _currentActiveLine = []; // Points currently being drawn

  @override
  void initState() {
    super.initState();
    // Optional: Auto-load latest draft could go here
  }

  // --- Drawing Logic ---

  void _startStroke(DragStartDetails details) {
    setState(() {
      final point = _getLocalPoint(details.localPosition);
      _currentActiveLine = [Point(point.dx, point.dy)];
      _redoStack.clear(); // Drawing a new line kills the redo history
    });
  }

  void _updateStroke(DragUpdateDetails details) {
    setState(() {
      final point = _getLocalPoint(details.localPosition);
      _currentActiveLine.add(Point(point.dx, point.dy));
    });
  }

  void _endStroke(DragEndDetails details) {
    setState(() {
      if (_currentActiveLine.isNotEmpty) {
        _strokes.add(Stroke(
          points: List.from(_currentActiveLine),
          colorValue: _brushColor.value,
          size: _brushSize,
          opacity: _brushOpacity,
        ));
        _currentActiveLine = [];
      }
    });
  }

  // Helper to account for Zoom/Pan in coordinates
  Offset _getLocalPoint(Offset rawPos) {
    // When drawing inside InteractiveViewer, the localPosition is usually correct
    // relative to the child if the GestureDetector is inside the InteractiveViewer content.
    return rawPos; 
  }

  // --- Actions ---

  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _redoStack.add(_strokes.removeLast());
      });
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      setState(() {
        _strokes.add(_redoStack.removeLast());
      });
    }
  }

  void _clearCanvas() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear Canvas?"),
        content: const Text("This cannot be undone fully if you exit."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              setState(() {
                _strokes.clear();
                _redoStack.clear();
                _currentDraftId = null;
                _bgColor = Colors.white;
              });
              Navigator.pop(ctx);
            },
            child: const Text("Clear", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- Saving ---

  Future<void> _saveToGallery() async {
    try {
      // 1. Reset zoom to 1.0 temporarily to capture full resolution? 
      // Actually RepaintBoundary captures the widget state. 
      // Ideally, we want to capture the inner content, not the viewport.
      
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      // Higher pixelRatio for better quality
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // Check Permissions (Gal handles logic internally for Android 10+)
      if (Platform.isAndroid && !(await Gal.hasAccess())) {
        await Gal.requestAccess();
      }

      await Gal.putImageBytes(pngBytes, name: 'doodle_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved to Gallery!")));

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _saveDraft() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nothing to save!")));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final draftsJson = prefs.getString('drafts_v2') ?? '[]'; // Use v2 key for new format
    List<dynamic> decoded = jsonDecode(draftsJson);
    List<Draft> drafts = decoded.map((e) => Draft.fromJson(e)).toList();

    final now = DateTime.now();
    final name = "Drawing ${DateFormat('MM/dd HH:mm').format(now)}";

    if (_currentDraftId != null) {
      // Update existing
      final idx = drafts.indexWhere((d) => d.id == _currentDraftId);
      if (idx != -1) {
        drafts[idx] = Draft(
          id: _currentDraftId!,
          name: drafts[idx].name,
          strokes: List.from(_strokes),
          bgColorValue: _bgColor.value,
          lastModified: now.toIso8601String(),
        );
      }
    } else {
      // Create new
      final newId = const Uuid().v4();
      final newDraft = Draft(
        id: newId,
        name: name,
        strokes: List.from(_strokes),
        bgColorValue: _bgColor.value,
        lastModified: now.toIso8601String(),
      );
      drafts.insert(0, newDraft);
      _currentDraftId = newId;
    }

    await prefs.setString('drafts_v2', jsonEncode(drafts.map((e) => e.toJson()).toList()));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Draft Saved!")));
  }

  // --- UI Builders ---

  void _showBrushSettings() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder( // Use StatefulBuilder to update slider visually
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(20),
            height: 250,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Brush Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.circle, size: 16),
                    const SizedBox(width: 10),
                    const Text("Size"),
                    Expanded(
                      child: Slider(
                        value: _brushSize,
                        min: 1.0,
                        max: 30.0,
                        onChanged: (v) {
                          setModalState(() => _brushSize = v); // Update slider
                          setState(() => _brushSize = v); // Update app
                        },
                      ),
                    ),
                    Text("${_brushSize.toInt()}px"),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.opacity, size: 16),
                    const SizedBox(width: 10),
                    const Text("Opacity"),
                    Expanded(
                      child: Slider(
                        value: _brushOpacity,
                        min: 0.1,
                        max: 1.0,
                        onChanged: (v) {
                          setModalState(() => _brushOpacity = v);
                          setState(() => _brushOpacity = v);
                        },
                      ),
                    ),
                    Text("${(_brushOpacity * 100).toInt()}%"),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showColorPicker(bool isBackground) {
    final colors = [
      Colors.black, Colors.white, Colors.grey, Colors.red, Colors.pink,
      Colors.purple, Colors.deepPurple, Colors.indigo, Colors.blue, Colors.lightBlue,
      Colors.cyan, Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange, Colors.brown,
    ];

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(isBackground ? "Canvas Color" : "Brush Color", 
                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5, crossAxisSpacing: 12, mainAxisSpacing: 12,
                ),
                itemCount: colors.length,
                itemBuilder: (context, index) {
                  final c = colors[index];
                  final isSelected = isBackground ? (_bgColor == c) : (_brushColor == c);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isBackground) {
                          _bgColor = c;
                        } else {
                          _brushColor = c;
                        }
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.blueAccent : Colors.grey.shade300,
                          width: isSelected ? 3 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0,2))
                        ]
                      ),
                      child: isSelected ? Icon(Icons.check, color: c.computeLuminance() > 0.5 ? Colors.black : Colors.white) : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDrafts() {
    Navigator.push(context, MaterialPageRoute(builder: (ctx) => DraftsScreen(onSelect: (draft) {
      setState(() {
        _strokes = List.from(draft.strokes);
        _bgColor = Color(draft.bgColorValue);
        _currentDraftId = draft.id;
        _redoStack.clear();
      });
    })));
  }

  @override
  Widget build(BuildContext context) {
    // Determine cursor/pointer logic based on mode
    final canUndo = _strokes.isNotEmpty;
    final canRedo = _redoStack.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        elevation: 1,
        backgroundColor: Colors.white,
        title: const Text("Digital Doodle Pro", style: TextStyle(color: Colors.black87, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: Icon(Icons.undo, color: canUndo ? Colors.black : Colors.grey[300]),
            onPressed: canUndo ? _undo : null,
            tooltip: "Undo",
          ),
          IconButton(
            icon: Icon(Icons.redo, color: canRedo ? Colors.black : Colors.grey[300]),
            onPressed: canRedo ? _redo : null,
            tooltip: "Redo",
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: _openDrafts,
            tooltip: "Drafts",
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            onPressed: _saveDraft,
            tooltip: "Save Draft",
          ),
          IconButton(
            icon: const Icon(Icons.image_outlined, color: Colors.blueAccent),
            onPressed: _saveToGallery,
            tooltip: "Export to Gallery",
          ),
        ],
      ),
      body: Column(
        children: [
          // --- CANVAS AREA ---
          Expanded(
            child: Container(
              color: Colors.grey[200], // App background (behind canvas)
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: 0.1,
                maxScale: 5.0,
                // Only enable Pan/Zoom interactions if in Pan Mode
                panEnabled: _isPanMode, 
                scaleEnabled: _isPanMode, 
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: Center(
                  // The actual drawing paper
                  child: AspectRatio(
                    aspectRatio: 1.0, // Force square for simplicity, or remove for infinite
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black.withOpacity(0.1))],
                      ),
                      child: RepaintBoundary(
                        key: _canvasKey,
                        child: ClipRect(
                          child: CustomPaint(
                            painter: StrokePainter(strokes: _strokes, activeStroke: _currentActiveLine, activeColor: _brushColor, activeSize: _brushSize, activeOpacity: _brushOpacity, bgColor: _bgColor),
                            child: GestureDetector(
                              // Only accept drawing gestures if NOT in Pan Mode
                              onPanStart: _isPanMode ? null : _startStroke,
                              onPanUpdate: _isPanMode ? null : _updateStroke,
                              onPanEnd: _isPanMode ? null : _endStroke,
                              child: Container(
                                width: 1000, // Large logical size
                                height: 1000,
                                color: Colors.transparent, // Necessary for hit testing
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // --- BOTTOM TOOLBAR ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0,-2), blurRadius: 10)],
            ),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 1. Mode Toggle
                  FloatingActionButton.small(
                    heroTag: "mode",
                    backgroundColor: _isPanMode ? Colors.orangeAccent : Colors.teal,
                    child: Icon(_isPanMode ? Icons.pan_tool : Icons.edit, color: Colors.white),
                    onPressed: () => setState(() => _isPanMode = !_isPanMode),
                  ),
                  
                  // 2. Brush Color
                  GestureDetector(
                    onTap: () => _showColorPicker(false),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _brushColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300, width: 2),
                      ),
                    ),
                  ),

                  // 3. Brush Settings (Size/Opacity)
                  IconButton.filledTonal(
                    icon: const Icon(Icons.tune),
                    onPressed: _showBrushSettings,
                  ),

                  // 4. Background Color
                  IconButton(
                    icon: Icon(Icons.format_paint, color: _bgColor == Colors.white ? Colors.black : _bgColor),
                    onPressed: () => _showColorPicker(true),
                  ),

                  // 5. Clear
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: _clearCanvas,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
//              DRAFTS SCREEN
// ==========================================

class DraftsScreen extends StatefulWidget {
  final Function(Draft) onSelect;
  const DraftsScreen({super.key, required this.onSelect});

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  List<Draft> _drafts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('drafts_v2') ?? '[]';
    final List decoded = jsonDecode(jsonStr);
    setState(() {
      _drafts = decoded.map((e) => Draft.fromJson(e)).toList();
    });
  }

  Future<void> _delete(String id) async {
    setState(() => _drafts.removeWhere((d) => d.id == id));
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('drafts_v2', jsonEncode(_drafts.map((e) => e.toJson()).toList()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Saved Drafts")),
      body: _drafts.isEmpty
          ? const Center(child: Text("No drafts saved yet", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: _drafts.length,
              itemBuilder: (ctx, i) {
                final d = _drafts[i];
                final date = DateTime.parse(d.lastModified);
                return Dismissible(
                  key: Key(d.id),
                  background: Container(color: Colors.red),
                  onDismissed: (_) => _delete(d.id),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(d.bgColorValue),
                      child: const Icon(Icons.edit, size: 16, color: Colors.grey),
                    ),
                    title: Text(d.name),
                    subtitle: Text(DateFormat.yMMMd().add_jm().format(date)),
                    onTap: () {
                      widget.onSelect(d);
                      Navigator.pop(context);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () => _delete(d.id),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ==========================================
//              PAINTER ENGINE
// ==========================================

class StrokePainter extends CustomPainter {
  final List<Stroke> strokes;
  final List<Point> activeStroke;
  final Color activeColor;
  final double activeSize;
  final double activeOpacity;
  final Color bgColor;

  StrokePainter({
    required this.strokes,
    required this.activeStroke,
    required this.activeColor,
    required this.activeSize,
    required this.activeOpacity,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = bgColor);

    // 2. Draw History
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke.points, stroke.color, stroke.size);
    }

    // 3. Draw Active Line
    if (activeStroke.isNotEmpty) {
      _drawStroke(canvas, activeStroke, activeColor.withOpacity(activeOpacity), activeSize);
    }
  }

  void _drawStroke(Canvas canvas, List<Point> points, Color color, double width) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    
    // Smooth curves using quadratic bezier if lots of points, 
    // but lineTo is faster and sufficient for handwriting usually.
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant StrokePainter old) => true;
}