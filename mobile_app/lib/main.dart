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
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D4ED8),
          surface: const Color(0xFFF8FAFC),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
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
  final TextEditingController _socialController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  int _navIndex = 0;
  File? _selectedImage;
  int? _imageSizeKb;
  bool _isAnalyzing = false;
  bool _backendOnline = false;
  String _storageMode = 'Checking...';
  MediaAnalysisResponse? _result;
  String? _errorMessage;

  String _historyFilter = 'All';
  String _socialChannel = 'WhatsApp';
  int _apkShares = 12;

  final List<MediaAnalysisResponse> _scans = [
    MediaAnalysisResponse(
      classification: 'Real',
      confidence: 92,
      summary:
          'Natural ambient illumination, consistent camera noise grain, and authentic scene geometry.',
      visualSignals: [
        'Consistent shadow falloff across foreground subjects',
        'Natural optical depth-of-field and sensor texture',
        'Caption aligns with observed daytime environment',
      ],
      textConsistency: 'Description matches visual scene details.',
      cumoNote: 'CUMO cross-modal alignment confirmed authentic provenance.',
      sourceChannel: 'Mobile App',
      description: 'Street market morning produce arrival in natural daylight.',
      analyzedAt: '2026-11-15T08:15:00Z',
    ),
    MediaAnalysisResponse(
      classification: 'Fake',
      confidence: 95,
      summary:
          'Hyper-smooth specular skin texture and diffusion edge artifacts contradict unedited camera claim.',
      visualSignals: [
        'Bilateral facial symmetry & synthetic pore-free shading',
        'Background bokeh quantization blocks detected',
        'Claimed unedited photo contradicts generative markers',
      ],
      textConsistency:
          'Written claim ("unedited camera photo") conflicts with synthetic cues.',
      cumoNote: 'Flagged high-frequency diffusion signature.',
      sourceChannel: 'Instagram',
      description: 'Unedited backstage runway portrait shot on phone.',
      analyzedAt: '2026-11-15T08:42:00Z',
    ),
    MediaAnalysisResponse(
      classification: 'Suspicious',
      confidence: 81,
      summary:
          'Dramatic storm lighting contrast and unverified breaking-news caption require manual corroboration.',
      visualSignals: [
        'Foreground sunlight luminance mismatches dark storm sky',
        'Sensational urgent forwarding language detected',
      ],
      textConsistency:
          'Breaking storm alert lacks verified location/time metadata.',
      cumoNote: 'Cross-modal verification flagged for secondary review.',
      sourceChannel: 'WhatsApp',
      description:
          'Breaking forward: Storm struck coastal bridge 10 minutes ago!',
      analyzedAt: '2026-11-15T09:10:00Z',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkBackendHealth();
  }

  @override
  void dispose() {
    _captionController.dispose();
    _socialController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkBackendHealth() async {
    try {
      final health = await ApiService.checkHealth();
      if (!mounted) return;
      setState(() {
        _backendOnline = health['ok'] == true;
        _storageMode = (health['storage'] ?? 'vercel').toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _backendOnline = false;
        _storageMode = 'offline';
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      final file = File(picked.path);
      final bytes = await file.length();
      if (!mounted) return;
      setState(() {
        _selectedImage = file;
        _imageSizeKb = (bytes / 1024).round();
        _result = null;
        _errorMessage = null;
      });
    }
  }

  Future<void> _runAnalysis({
    String sourceChannel = 'Mobile App',
    String? overrideDescription,
    String? sampleTag,
  }) async {
    final desc = (overrideDescription ?? _captionController.text).trim();
    if (_selectedImage == null && sampleTag == null) {
      setState(() => _errorMessage =
          'Please capture a photo or upload an image from Gallery first.');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.analyzeMedia(
        imageFile: sampleTag == null ? _selectedImage : null,
        sampleTag: sampleTag,
        description: desc,
        sourceChannel: sourceChannel,
      );
      if (!mounted) return;
      setState(() {
        _result = response;
        _scans.insert(0, response);
      });
    } catch (err) {
      if (!mounted) return;
      setState(() =>
          _errorMessage = err.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  Future<void> _syncHistoryFromCloud() async {
    try {
      final remote = await ApiService.fetchScanHistory();
      if (!mounted) return;
      if (remote.isNotEmpty) {
        setState(() {
          for (final item in remote.reversed) {
            final exists = _scans.any((s) => s.analyzedAt == item.analyzedAt);
            if (!exists) {
              _scans.insert(0, item);
            }
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _shareApkLink() async {
    const apkLink = '${ApiService.baseUrl}/download/verilens.apk';
    await Clipboard.setData(const ClipboardData(text: apkLink));
    final count = await ApiService.trackApkShare().catchError((_) => _apkShares + 1);
    if (!mounted) return;
    setState(() => _apkShares = count > _apkShares ? count : _apkShares + 1);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('APK Download Link Copied'),
        content: const SelectableText(
          'Share this VeriLens Android APK link via WhatsApp, SMS, or Email:\n\n$apkLink',
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

  Color _verdictBg(String classification) {
    switch (classification) {
      case 'Real':
        return const Color(0xFFECFDF5);
      case 'Fake':
        return const Color(0xFFFEF2F2);
      default:
        return const Color(0xFFFFFBEB);
    }
  }

  IconData _verdictIcon(String classification) {
    switch (classification) {
      case 'Real':
        return Icons.verified_rounded;
      case 'Fake':
        return Icons.dangerous_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  void _openScanDetailSheet(MediaAnalysisResponse scan) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildResultCard(scan),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF1D4ED8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.shield_outlined,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VeriLens',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2),
                ),
                Text(
                  _backendOnline ? 'Cloud API Live' : 'Local Mode',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _backendOnline
                        ? const Color(0xFF15803D)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share APK Link',
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareApkLink,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE2E8F0)),
        ),
      ),
      body: IndexedStack(
        index: _navIndex,
        children: [
          _buildScannerTab(),
          _buildHistoryTab(),
          _buildSocialTab(),
          _buildShareTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDBEAFE),
        onDestinationSelected: (idx) {
          setState(() => _navIndex = idx);
          if (idx == 1) _syncHistoryFromCloud();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon:
                Icon(Icons.document_scanner, color: Color(0xFF1D4ED8)),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history, color: Color(0xFF1D4ED8)),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub, color: Color(0xFF1D4ED8)),
            label: 'Social',
          ),
          NavigationDestination(
            icon: Icon(Icons.ios_share_outlined),
            selectedIcon: Icon(Icons.ios_share, color: Color(0xFF1D4ED8)),
            label: 'APK & Info',
          ),
        ],
      ),
    );
  }

  Widget _buildScannerTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Real vs. Fake Media Detector',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Capture or upload an image and attach its caption to verify authenticity against AI manipulation & deepfakes.',
                  style: TextStyle(
                      color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(17)),
                  child: SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: _selectedImage == null
                        ? Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 44, color: Color(0xFF64748B)),
                                SizedBox(height: 10),
                                Text(
                                  'No media selected yet',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF334155)),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Use Camera or Gallery below to scan an image',
                                  style: TextStyle(
                                      fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          )
                        : Image.file(_selectedImage!, fit: BoxFit.cover),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.photo_library_outlined,
                              size: 18),
                          label: const Text('Gallery'),
                        ),
                      ),
                      if (_selectedImage != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Clear image',
                          onPressed: () => setState(() {
                            _selectedImage = null;
                            _imageSizeKb = null;
                            _result = null;
                          }),
                          icon: const Icon(Icons.close,
                              color: Color(0xFF64748B)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_imageSizeKb != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Selected payload: $_imageSizeKb KB · Ready for CUMO check',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Written Description / Social Media Claim',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _presetChip(
                  'Camera Original',
                  'Original smartphone photograph taken outdoors in natural daylight.'),
              _presetChip('Breaking Forward',
                  'Breaking news: viral photo shared urgently across social media!'),
              _presetChip('AI Suspect Check',
                  'Unedited studio portrait claimed as live raw camera capture.'),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _captionController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText:
                  'Paste the headline, WhatsApp forward, or Instagram caption...',
              hintStyle:
                  const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Color(0xFF1D4ED8), width: 1.8),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _isAnalyzing ? null : () => _runAnalysis(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: _isAnalyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.verified_user_outlined, size: 20),
            label: Text(
              _isAnalyzing ? 'Analyzing Media...' : 'Analyze Authenticity',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 20),
            _buildResultCard(_result!),
          ],
        ],
      ),
    );
  }

  Widget _presetChip(String label, String text) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFCBD5E1)),
      onPressed: () => setState(() => _captionController.text = text),
    );
  }

  Widget _buildResultCard(MediaAnalysisResponse result) {
    final color = _verdictColor(result.classification);
    final bg = _verdictBg(result.classification);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(_verdictIcon(result.classification),
                              color: color, size: 26),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Verdict: ${result.classification}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${result.confidence}%',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: result.confidence / 100.0,
                    minHeight: 7,
                    backgroundColor: const Color(0xCCFFFFFF),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.summary,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF1E293B), height: 1.45),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Forensic Visual Signals',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 6),
                ...result.visualSignals.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '0${entry.key + 1}. ',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                entry.value,
                                style: const TextStyle(
                                    fontSize: 13, color: Color(0xFF475569)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                const Divider(height: 24, color: Color(0xFFE2E8F0)),
                Text(
                  'Caption Check: ${result.textConsistency}',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF475569), height: 1.4),
                ),
                const SizedBox(height: 6),
                Text(
                  'CUMO Note: ${result.cumoNote} · Source: ${result.sourceChannel}',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF64748B), height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _scans.where((scan) {
      final matchesFilter =
          _historyFilter == 'All' || scan.classification == _historyFilter;
      final matchesSearch = query.isEmpty ||
          scan.description.toLowerCase().contains(query) ||
          scan.summary.toLowerCase().contains(query) ||
          scan.sourceChannel.toLowerCase().contains(query);
      return matchesFilter && matchesSearch;
    }).toList();

    final realCount = _scans.where((s) => s.classification == 'Real').length;
    final fakeCount = _scans.where((s) => s.classification == 'Fake').length;
    final suspCount =
        _scans.where((s) => s.classification == 'Suspicious').length;

    return RefreshIndicator(
      onRefresh: _syncHistoryFromCloud,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _statBox('Total', _scans.length, const Color(0xFF0F172A)),
              const SizedBox(width: 8),
              _statBox('Real', realCount, const Color(0xFF15803D)),
              const SizedBox(width: 8),
              _statBox('Fake', fakeCount, const Color(0xFFB91C1C)),
              const SizedBox(width: 8),
              _statBox('Suspect', suspCount, const Color(0xFFB45309)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Search scan history...',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1D4ED8)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', 'Real', 'Fake', 'Suspicious'].map((f) {
                final selected = _historyFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f),
                    selected: selected,
                    onSelected: (_) => setState(() => _historyFilter = f),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Text(
                  'No matching scans found. Run a scan or pull down to refresh.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            ...filtered.map(
              (scan) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: ListTile(
                  onTap: () => _openScanDetailSheet(scan),
                  leading: CircleAvatar(
                    backgroundColor: _verdictBg(scan.classification),
                    child: Icon(_verdictIcon(scan.classification),
                        color: _verdictColor(scan.classification), size: 20),
                  ),
                  title: Text(
                    scan.description.isEmpty
                        ? 'Image Authenticity Check'
                        : scan.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${scan.classification} · ${scan.confidence}% · ${scan.sourceChannel}',
                    style: TextStyle(
                      fontSize: 12,
                      color: _verdictColor(scan.classification),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: Color(0xFF94A3B8)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statBox(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
              const Text(
                'WhatsApp, Instagram & SMS Verification',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Verify forwarded viral messages and attached screenshots before sharing.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: ['WhatsApp', 'Instagram', 'SMS'].map((channel) {
                  return ChoiceChip(
                    label: Text(channel),
                    selected: _socialChannel == channel,
                    onSelected: (_) =>
                        setState(() => _socialChannel = channel),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _socialController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText:
                      'Paste forwarded $_socialChannel message or claim...',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1D4ED8)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.attach_file, size: 18),
                      label: Text(_selectedImage == null
                          ? 'Attach Screenshot'
                          : 'Image Attached'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1D4ED8)),
                      onPressed: _isAnalyzing
                          ? null
                          : () async {
                              await _runAnalysis(
                                sourceChannel: _socialChannel,
                                overrideDescription: _socialController.text,
                                sampleTag: _selectedImage == null
                                    ? 'social_$_socialChannel'
                                    : null,
                              );
                              if (_result != null && mounted) {
                                _openScanDetailSheet(_result!);
                              }
                            },
                      child: const Text('Verify Post'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'One-Tap Social Media Test Cases',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _socialDemoTile(
          channel: 'WhatsApp',
          title: 'Forwarded Storm Bridge Alert',
          caption:
              'Breaking forward: Hurricane lightning closed coastal bridge 10 minutes ago! Share immediately!',
          sampleTag: 'whatsapp_storm_bridge',
        ),
        _socialDemoTile(
          channel: 'Instagram',
          title: 'Viral AI Fashion Portrait',
          caption:
              'Unedited raw backstage photo of runway model taken tonight.',
          sampleTag: 'instagram_ai_portrait',
        ),
        _socialDemoTile(
          channel: 'SMS',
          title: 'Neighborhood Market Photo',
          caption: 'Morning produce delivery at local street market.',
          sampleTag: 'sms_market_photo',
        ),
      ],
    );
  }

  Widget _socialDemoTile({
    required String channel,
    required String title,
    required String caption,
    required String sampleTag,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$channel Hook',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D4ED8)),
                ),
                TextButton(
                  onPressed: _isAnalyzing
                      ? null
                      : () async {
                          await _runAnalysis(
                            sourceChannel: channel,
                            overrideDescription: caption,
                            sampleTag: sampleTag,
                          );
                          if (_result != null && mounted) {
                            _openScanDetailSheet(_result!);
                          }
                        },
                  child: const Text('Run Test'),
                ),
              ],
            ),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            Text(caption,
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }

  Widget _buildShareTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'APK Distribution & Activity',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Share VeriLens Android APK v1.0.0+1 with friends or transfer directly between PC and Android.',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _statBox('APK Shares', _apkShares, const Color(0xFF1D4ED8)),
                  const SizedBox(width: 10),
                  _statBox('Saved Scans', _scans.length,
                      const Color(0xFF0F172A)),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _shareApkLink,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Copy & Share APK Link'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await _checkBackendHealth();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_backendOnline
                          ? 'Vercel API Online ($_storageMode)'
                          : 'Could not reach Vercel API'),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.cloud_done_outlined),
                label: const Text('Test Cloud Backend Connection'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Technology Stack & ML Reference',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                '• Mobile App: Flutter & Dart (Material 3)\n'
                '• Cloud Backend: Node.js Express on Vercel\n'
                '• Database Ready: MongoDB Atlas & Compass\n'
                '• Multimodal Reference: github.com/shi-labs/cumo',
                style: TextStyle(
                    fontSize: 13, color: Color(0xFF475569), height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}