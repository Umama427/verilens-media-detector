import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class MediaAnalysisResponse {
  final String classification; // Real | Fake | Suspicious
  final int confidence;
  final String summary;
  final List<String> visualSignals;
  final String textConsistency;
  final String cumoNote;
  final String sourceChannel;
  final String description;
  final String analyzedAt;

  MediaAnalysisResponse({
    required this.classification,
    required this.confidence,
    required this.summary,
    required this.visualSignals,
    required this.textConsistency,
    required this.cumoNote,
    required this.sourceChannel,
    required this.description,
    required this.analyzedAt,
  });

  factory MediaAnalysisResponse.fromJson(Map<String, dynamic> json) {
    return MediaAnalysisResponse(
      classification: (json['classification'] ?? 'Suspicious').toString(),
      confidence: (json['confidence'] as num?)?.toInt() ?? 50,
      summary: (json['summary'] ?? '').toString(),
      visualSignals: (json['visualSignals'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      textConsistency: (json['textConsistency'] ?? '').toString(),
      cumoNote: (json['cumoNote'] ??
              'Cross-modal visual-caption verification completed.')
          .toString(),
      sourceChannel: (json['sourceChannel'] ?? 'Mobile App').toString(),
      description: (json['description'] ?? '').toString(),
      analyzedAt:
          (json['analyzedAt'] ?? DateTime.now().toIso8601String()).toString(),
    );
  }
}

class ApiService {
  static const String baseUrl = 'https://verilens-api-delta.vercel.app';

  static Future<Map<String, dynamic>> checkHealth() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/health'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Backend offline (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<MediaAnalysisResponse> analyzeMedia({
    File? imageFile,
    String? sampleTag,
    required String description,
    String sourceChannel = 'Mobile App',
  }) async {
    String base64Image = '';
    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      base64Image = base64Encode(bytes);
    } else if (sampleTag != null) {
      base64Image = base64Encode(utf8.encode('SAMPLE_MEDIA::$sampleTag'));
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/analyze'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'imageBase64': base64Image,
            'mimeType': 'image/jpeg',
            'description': description,
            'sourceChannel': sourceChannel,
            'sampleTag': sampleTag ?? '',
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Analysis failed (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return MediaAnalysisResponse.fromJson(decoded);
  }

  static Future<List<MediaAnalysisResponse>> fetchScanHistory() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/scans'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Failed to load scans (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final items = List<Map<String, dynamic>>.from(decoded['scans'] ?? []);
    return items.map(MediaAnalysisResponse.fromJson).toList();
  }

  static Future<int> trackApkShare() async {
    final response = await http
        .post(Uri.parse('$baseUrl/api/apk/track'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return (decoded['totalShares'] as num?)?.toInt() ?? 1;
    }
    return 1;
  }
}