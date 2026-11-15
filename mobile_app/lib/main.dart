import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'services/api_service.dart';

void main() {
  runApp(const MediaVerifyApp());
}

class MediaVerifyApp extends StatelessWidget {
  const MediaVerifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VeriLens Media Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1D4ED8),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();

  File? _selectedImage;
  bool _isAnalyzing = false;
  MediaAnalysisResponse? _result;
  String? _errorMessage;

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
        _result = null;
        _errorMessage = null;
      });
    }
  }

  Future<void> _runAnalysis() async {
    if (_selectedImage == null) {
      setState(() => _errorMessage = 'Please capture or upload an image first.');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.analyzeMedia(
        imageFile: _selectedImage!,
        description: _captionController.text.trim(),
      );
      setState(() => _result = response);
    } catch (err) {
      setState(() => _errorMessage = err.toString());
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _shareApkLink() async {
    const apkLink = 'https://verilens-api-delta.vercel.app/download/verilens.apk';
    await Clipboard.setData(const ClipboardData(text: apkLink));
    try {
      await ApiService.trackApkShare();
    } catch (_) {}
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('APK Download Link Copied'),
        content: const SelectableText(
          'Share this link via WhatsApp, SMS, or Email:\n\n$apkLink',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Color _verdictColor(String classification) {
    switch (classification) {
      case 'Real':
        return const Color(0xFF15803D);
      case 'Fake':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFFB45309);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VeriLens Detector'),
        actions: [
          IconButton(
            tooltip: 'Share APK Link',
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareApkLink,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: _selectedImage == null
                  ? const Center(
                      child: Text(
                        'Capture a photo or upload media to verify authenticity',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.file(_selectedImage!, fit: BoxFit.cover),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _captionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Written description or social media claim',
                hintText: 'Paste the caption or news context attached to this image...',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isAnalyzing ? null : _runAnalysis,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(_isAnalyzing ? 'Analyzing Media...' : 'Analyze Authenticity'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFFB91C1C)),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Verdict: ${_result!.classification}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _verdictColor(_result!.classification),
                          ),
                        ),
                        Text(
                          '${_result!.confidence}% confidence',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_result!.summary),
                    const SizedBox(height: 12),
                    const Text(
                      'Forensic Signals:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    ..._result!.visualSignals.map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• $s'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}