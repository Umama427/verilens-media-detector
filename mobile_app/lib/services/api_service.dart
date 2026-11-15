import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class MediaAnalysisResponse {
  final String classification; // Real | Fake | Suspicious
  final int confidence;
  final String summary;
  final List<String> visualSignals;
  final String textConsistency;
  final String analyzedAt;

  MediaAnalysisResponse({
    required this.classification,
    required this.confidence,
    required this.summary,
    required this.visualSignals,
    required this.textConsistency,
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
      analyzedAt: (json['analyzedAt'] ?? DateTime.now().toIso8601String()).toString(),
    );
  }
}

class ApiService {
  // Deployed Vercel backend URL (MongoDB Atlas + CUMO / ML inference)
  static const String baseUrl = 'https://verilens-api-delta.vercel.app';

  static Future<MediaAnalysisResponse> analyzeMedia({
    required File imageFile,
    required String description,
    String sourceChannel = 'Mobile App',
  }) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse('$baseUrl/api/analyze'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'imageBase64': base64Image,
        'mimeType': 'image/jpeg',
        'description': description,
        'sourceChannel': sourceChannel,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Analysis failed (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return MediaAnalysisResponse.fromJson(decoded);
  }

  static Future<List<Map<String, dynamic>>> fetchScanHistory() async {
    final response = await http.get(Uri.parse('$baseUrl/api/scans'));
    if (response.statusCode != 200) {
      throw Exception('Failed to load scans from MongoDB Atlas');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(decoded['scans'] ?? []);
  }

  static Future<void> trackApkShare() async {
    await http.post(Uri.parse('$baseUrl/api/apk/track'));
  }
}

