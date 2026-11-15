import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'screens/auth_screen.dart';
import 'services/api_service.dart';
import 'services/session_store.dart';
import 'services/web_audio.dart';
import 'services/web_camera.dart';

void main() {
  runApp(const MediaVerifyApp());
}

class MediaVerifyApp extends StatefulWidget {
  const MediaVerifyApp({super.key});

  @override
  State<MediaVerifyApp> createState() => _MediaVerifyAppState();
}

class _MediaVerifyAppState extends State<MediaVerifyApp> {
  AuthUser? _currentUser;

  @override
  void initState() {
    super.initState();
    final saved = readStorageItem('verilens_active_user');
    if (saved != null && saved.isNotEmpty) {
      try {
        _currentUser =
            AuthUser.fromJson(jsonDecode(saved) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  void _handleAuthenticated(AuthUser user) {
    saveStorageItem('verilens_active_user', jsonEncode(user.toJson()));
    setState(() => _currentUser = user);
  }

  void _handleLogout() {
    saveStorageItem('verilens_active_user', null);
    setState(() => _currentUser = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VeriLens Forensics',
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
      home: _currentUser == null
          ? AuthScreen(onAuthenticated: _handleAuthenticated)
          : HomeScreen(user: _currentUser!, onLogout: _handleLogout),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final AuthUser user;
  final VoidCallback onLogout;

  const HomeScreen({super.key, required this.user, required this.onLogout});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final ScrollController _imageScrollController = ScrollController();
  final ScrollController _voiceScrollController = ScrollController();
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _voiceClaimController = TextEditingController();
  final TextEditingController _socialController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  int _navIndex = 0;

  Uint8List? _selectedImageBytes;
  String _selectedImageName = '';
  String _selectedImageMime = 'image/jpeg';
  int? _imageSizeKb;
  bool _isAnalyzingImage = false;
  MediaAnalysisResponse? _imageResult;

  Uint8List? _selectedAudioBytes;
  String _selectedAudioName = '';
  String _selectedAudioMime = 'audio/wav';
  int? _audioSizeKb;
  bool _isAnalyzingVoice = false;
  MediaAnalysisResponse? _voiceResult;

  bool _backendOnline = false;
  String _storageMode = 'Checking...';
  String? _errorMessage;
  String _historyFilter = 'All';
  String _socialChannel = 'WhatsApp';
  int _apkShares = 12;

  final List<MediaAnalysisResponse> _scans = [
    MediaAnalysisResponse(
      classification: 'Real',
      confidence: 93,
      summary:
          'Natural camera EXIF signature, ambient illumination, and coherent grain pattern detected.',
      visualSignals: [
        'Camera EXIF header & standard JPEG quantization verified',
        'Consistent shadow falloff across foreground subjects',
        'Written description aligns with observed daytime scene',
      ],
      textConsistency: 'Caption matches visual details accurately.',
      cumoNote: 'CUMO cross-modal check confirmed authentic capture.',
      sourceChannel: 'Mobile App',
      mediaType: 'image',
      fileName: 'IMG_2026_street_market.jpg',
      description: 'Street market morning produce arrival in natural daylight.',
      analyzedAt: '2026-11-15T08:15:00Z',
    ),
    MediaAnalysisResponse(
      classification: 'Fake',
      confidence: 96,
      summary:
          'Synthetic specular skin texture, missing camera EXIF, and diffusion artifacts indicate AI generation.',
      visualSignals: [
        'PNG/synthetic payload lacks camera sensor EXIF metadata',
        'Over-smoothed bilateral skin shading & bokeh artifacts',
        'Claimed unedited photo contradicts generative markers',
      ],
      textConsistency:
          'Claim ("unedited camera photo") conflicts with AI markers.',
      cumoNote: 'Flagged high-frequency diffusion signature.',
      sourceChannel: 'Instagram',
      mediaType: 'image',
      fileName: 'ai_runway_portrait.png',
      description: 'Unedited backstage runway portrait shot on phone.',
      analyzedAt: '2026-11-15T08:42:00Z',
    ),
    MediaAnalysisResponse(
      classification: 'Fake',
      confidence: 94,
      summary:
          'Synthetic harmonic spacing, flat micro-pitch contour, and urgent OTP solicitation indicate an AI voice clone.',
      visualSignals: [
        'Unnaturally uniform pitch contour lacking human micro-tremor',
        'Zero natural inhalation breath pauses across phrasing',
        'High-risk bank OTP voice phishing phrasing detected',
      ],
      textConsistency: 'Caller urgency matches known AI voice scam script.',
      cumoNote: 'Voice Forensics flagged synthetic TTS/VC signature.',
      sourceChannel: 'Voice Forensics',
      mediaType: 'voice',
      fileName: 'bank_otp_voice_clone.mp3',
      description:
          'Urgent bank security officer calling for instant 6-digit OTP code.',
      analyzedAt: '2026-11-15T09:05:00Z',
    ),
    MediaAnalysisResponse(
      classification: 'Suspicious',
      confidence: 81,
      summary:
          'Uneven foreground contrast and sensational breaking-news forward require source verification.',
      visualSignals: [
        'Stripped social metadata & foreground luminance mismatch',
        'Sensational urgent forwarding phrasing flagged',
      ],
      textConsistency: 'Breaking alert lacks verified provenance.',
      cumoNote: 'Cross-modal verification marked Suspicious.',
      sourceChannel: 'WhatsApp',
      mediaType: 'image',
      fileName: 'whatsapp_storm_bridge.jpg',
      description:
          'Breaking forward: Storm struck coastal bridge 10 minutes ago!',
      analyzedAt: '2026-11-15T09:10:00Z',
    ),
  ];

  static const _navItems = [
    (icon: Icons.dashboard_outlined, active: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.image_search_outlined, active: Icons.image_search, label: 'Image Scan'),
    (icon: Icons.graphic_eq_outlined, active: Icons.graphic_eq, label: 'Voice Check'),
    (icon: Icons.hub_outlined, active: Icons.hub, label: 'Social Guard'),
    (icon: Icons.history_rounded, active: Icons.history, label: 'History'),
    (icon: Icons.manage_accounts_outlined, active: Icons.manage_accounts, label: 'APK & Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _checkBackendHealth();
  }

  @override
  void dispose() {
    _imageScrollController.dispose();
    _voiceScrollController.dispose();
    _captionController.dispose();
    _voiceClaimController.dispose();
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
    setState(() => _errorMessage = null);

    if (source == ImageSource.camera && kIsWeb) {
      try {
        final bytes = await captureFromWebCamera(context);
        if (bytes != null && mounted) {
          setState(() {
            _selectedImageBytes = bytes;
            _selectedImageName =
                'webcam_${DateTime.now().millisecondsSinceEpoch}.jpg';
            _selectedImageMime = 'image/jpeg';
            _imageSizeKb = (bytes.length / 1024).round();
            _imageResult = null;
          });
        }
        return;
      } catch (err) {
        if (!mounted) return;
        setState(() => _errorMessage =
            'Webcam error: ${err.toString().replaceFirst('Exception: ', '')}');
        return;
      }
    }

    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      final lowerName = picked.name.toLowerCase();
      String mime = 'image/jpeg';
      if (lowerName.endsWith('.png')) mime = 'image/png';
      if (lowerName.endsWith('.webp')) mime = 'image/webp';
      if (lowerName.endsWith('.gif')) mime = 'image/gif';

      if (!mounted) return;
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = picked.name;
        _selectedImageMime = mime;
        _imageSizeKb = (bytes.length / 1024).round();
        _imageResult = null;
        _errorMessage = null;
      });
    }
  }

  Future<void> _pickAudioFile() async {
    setState(() => _errorMessage = null);
    if (!kIsWeb) {
      setState(() => _errorMessage =
          'Use the 1-tap Voice Deepfake test presets below on Android, or upload MP3/WAV directly on Chrome Desktop.');
      return;
    }
    final picked = await pickAudioFromWeb();
    if (picked != null && mounted) {
      setState(() {
        _selectedAudioBytes = picked.bytes;
        _selectedAudioName = picked.fileName;
        _selectedAudioMime = picked.mimeType;
        _audioSizeKb = (picked.bytes.length / 1024).round();
        _voiceResult = null;
      });
    }
  }

  Future<void> _recordVoice() async {
    setState(() => _errorMessage = null);
    if (!kIsWeb) {
      setState(() => _errorMessage =
          'Live microphone recording works in Chrome Desktop. On Android, use the Voice Test presets below.');
      return;
    }
    try {
      final recorded = await recordVoiceFromWeb(context);
      if (recorded != null && mounted) {
        setState(() {
          _selectedAudioBytes = recorded.bytes;
          _selectedAudioName = recorded.fileName;
          _selectedAudioMime = recorded.mimeType;
          _audioSizeKb = (recorded.bytes.length / 1024).round();
          _voiceResult = null;
        });
      }
    } catch (err) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'Mic error: ${err.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<void> _runImageAnalysis({
    String sourceChannel = 'Mobile App',
    String? overrideDescription,
    String? sampleTag,
    bool openSheetOnDone = false,
  }) async {
    final desc = (overrideDescription ?? _captionController.text).trim();
    if (_selectedImageBytes == null && sampleTag == null) {
      setState(() => _errorMessage =
          'Please capture a photo or upload an image from Gallery first.');
      return;
    }

    setState(() {
      _isAnalyzingImage = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.analyzeMedia(
        imageBytes: sampleTag == null ? _selectedImageBytes : null,
        fileName:
            sampleTag == null ? _selectedImageName : '$sampleTag.jpg',
        mimeType: _selectedImageMime,
        sampleTag: sampleTag,
        description: desc,
        sourceChannel: sourceChannel,
      );
      if (!mounted) return;
      setState(() {
        _imageResult = response;
        _scans.insert(0, response);
      });
      if (openSheetOnDone) {
        _openScanDetailSheet(response);
      } else if (_imageScrollController.hasClients) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (_imageScrollController.hasClients) {
          _imageScrollController.animateTo(
            _imageScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (err) {
      if (!mounted) return;
      setState(() =>
          _errorMessage = err.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingImage = false);
      }
    }
  }

  Future<void> _runVoiceAnalysis({
    String? overrideClaim,
    String? sampleTag,
  }) async {
    final claim = (overrideClaim ?? _voiceClaimController.text).trim();
    if (_selectedAudioBytes == null && sampleTag == null && claim.isEmpty) {
      setState(() => _errorMessage =
          'Please record voice, upload an audio file, or enter a voice claim/transcript.');
      return;
    }

    setState(() {
      _isAnalyzingVoice = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.analyzeVoice(
        audioBytes: sampleTag == null ? _selectedAudioBytes : null,
        fileName:
            sampleTag == null ? _selectedAudioName : '$sampleTag.wav',
        mimeType: _selectedAudioMime,
        sampleTag: sampleTag,
        transcriptOrClaim: claim,
      );
      if (!mounted) return;
      setState(() {
        _voiceResult = response;
        _scans.insert(0, response);
      });
      if (_voiceScrollController.hasClients) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (_voiceScrollController.hasClients) {
          _voiceScrollController.animateTo(
            _voiceScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (err) {
      if (!mounted) return;
      setState(() =>
          _errorMessage = err.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingVoice = false);
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
    final count =
        await ApiService.trackApkShare().catchError((_) => _apkShares + 1);
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

  void _selectNav(int index) {
    setState(() {
      _navIndex = index;
      _errorMessage = null;
    });
    if (index == 4) _syncHistoryFromCloud();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 920;

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D4ED8),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.shield_outlined,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VeriLens',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _navItems[_navIndex].label,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF64748B)),
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
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: const Color(0xFFE2E8F0)),
              ),
            ),
      drawer: isDesktop ? null : Drawer(child: _buildSidebar(inDrawer: true)),
      body: Row(
        children: [
          if (isDesktop) SizedBox(width: 264, child: _buildSidebar()),
          Expanded(
            child: Column(
              children: [
                if (isDesktop) _buildDesktopTopHeader(),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: IndexedStack(
                        index: _navIndex,
                        children: [
                          _buildDashboardTab(),
                          _buildImageScannerTab(),
                          _buildVoiceTab(),
                          _buildSocialTab(),
                          _buildHistoryTab(),
                          _buildAccountAndApkTab(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _navIndex < 5 ? _navIndex : 4,
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xFFDBEAFE),
              onDestinationSelected: _selectNav,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard, color: Color(0xFF1D4ED8)),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.image_search_outlined),
                  selectedIcon:
                      Icon(Icons.image_search, color: Color(0xFF1D4ED8)),
                  label: 'Image',
                ),
                NavigationDestination(
                  icon: Icon(Icons.graphic_eq_outlined),
                  selectedIcon:
                      Icon(Icons.graphic_eq, color: Color(0xFF1D4ED8)),
                  label: 'Voice',
                ),
                NavigationDestination(
                  icon: Icon(Icons.hub_outlined),
                  selectedIcon: Icon(Icons.hub, color: Color(0xFF1D4ED8)),
                  label: 'Social',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  selectedIcon: Icon(Icons.history, color: Color(0xFF1D4ED8)),
                  label: 'History',
                ),
              ],
            ),
    );
  }

  Widget _buildDesktopTopHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                _navItems[_navIndex].label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _backendOnline
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: _backendOnline
                          ? const Color(0xFF15803D)
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _backendOnline
                          ? 'Vercel Cloud Live ($_storageMode)'
                          : 'Offline Mode',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _backendOnline
                            ? const Color(0xFF15803D)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _shareApkLink,
                icon: const Icon(Icons.download_for_offline_outlined, size: 17),
                label: const Text('Share APK'),
              ),
              const SizedBox(width: 10),
              Text(
                widget.user.name,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Color(0xFF334155)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar({bool inDrawer = false}) {
    return Container(
      color: const Color(0xFF0F172A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.shield_outlined,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VeriLens AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Forensic Studio',
                        style:
                            TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF1E293B), height: 1),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _navItems.length,
                itemBuilder: (ctx, i) {
                  final item = _navItems[i];
                  final selected = _navIndex == i;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: selected
                          ? const Color(0xFF1D4ED8)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          _selectNav(i);
                          if (inDrawer) Navigator.of(context).pop();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                selected ? item.active : item.icon,
                                size: 20,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: const Color(0xFF2563EB),
                        child: Text(
                          widget.user.name.isNotEmpty
                              ? widget.user.name[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                            Text(
                              widget.user.role,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFCA5A5),
                        side: const BorderSide(color: Color(0xFF334155)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: widget.onLogout,
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('Sign Out',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    final realCount = _scans.where((s) => s.classification == 'Real').length;
    final fakeCount = _scans.where((s) => s.classification == 'Fake').length;
    final voiceCount = _scans.where((s) => s.mediaType == 'voice').length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back, ${widget.user.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Verify images, detect AI voice clones, and inspect viral social forwards with real-time forensic scoring.',
                style: TextStyle(
                    color: Color(0xFFCBD5E1), fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB)),
                    onPressed: () => _selectNav(1),
                    icon: const Icon(Icons.image_search, size: 18),
                    label: const Text('Scan Image'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E)),
                    onPressed: () => _selectNav(2),
                    icon: const Icon(Icons.graphic_eq, size: 18),
                    label: const Text('Check Voice Deepfake'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF64748B)),
                    ),
                    onPressed: () => _selectNav(3),
                    icon: const Icon(Icons.hub_outlined, size: 18),
                    label: const Text('Verify Social Post'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _statBox('Total Scans', _scans.length, const Color(0xFF0F172A)),
            const SizedBox(width: 10),
            _statBox('Verified Real', realCount, const Color(0xFF15803D)),
            const SizedBox(width: 10),
            _statBox('Fakes Caught', fakeCount, const Color(0xFFB91C1C)),
            const SizedBox(width: 10),
            _statBox('Voice Checks', voiceCount, const Color(0xFF1D4ED8)),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Recent Forensic Verdicts',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ..._scans.take(4).map(_scanCardTile),
      ],
    );
  }

  Widget _buildImageScannerTab() {
    return SingleChildScrollView(
      controller: _imageScrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  child: Stack(
                    children: [
                      SizedBox(
                        height: 250,
                        width: double.infinity,
                        child: _selectedImageBytes == null
                            ? Container(
                                color: const Color(0xFFF1F5F9),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate_outlined,
                                        size: 46, color: Color(0xFF64748B)),
                                    SizedBox(height: 10),
                                    Text(
                                      'Attach an Image or Capture with Camera',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF334155)),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Supports JPEG, PNG, WebP · EXIF & AI pixel checks',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              )
                            : Image.memory(
                                _selectedImageBytes!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFFF1F5F9),
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.image_outlined,
                                          size: 42, color: Color(0xFF1D4ED8)),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Attached: $_selectedImageName (${_imageSizeKb ?? 0} KB)',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      if (_imageResult != null && _selectedImageBytes != null)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _verdictColor(_imageResult!.classification),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_imageResult!.classification.toUpperCase()} · ${_imageResult!.confidence}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
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
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text(kIsWeb ? 'Live Webcam' : 'Camera'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.photo_library_outlined,
                              size: 18),
                          label: const Text('Upload Image'),
                        ),
                      ),
                      if (_selectedImageBytes != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Clear image',
                          onPressed: () => setState(() {
                            _selectedImageBytes = null;
                            _selectedImageName = '';
                            _imageSizeKb = null;
                            _imageResult = null;
                          }),
                          icon: const Icon(Icons.close,
                              color: Color(0xFF64748B)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_selectedImageBytes != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            size: 15, color: Color(0xFF15803D)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Attached: $_selectedImageName · $_imageSizeKb KB · Ready to Analyze',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF334155)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Written Description / Context Claim (Optional)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _presetChip(
                'Camera Original',
                'Original smartphone photograph taken outdoors in natural daylight.',
                _captionController,
              ),
              _presetChip(
                'Breaking Forward',
                'Breaking news: viral photo shared urgently across social media!',
                _captionController,
              ),
              _presetChip(
                'AI Portrait Check',
                'Unedited studio portrait claimed as live raw camera capture.',
                _captionController,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _captionController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText:
                  'Describe the photo or paste social media claim to cross-check...',
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
            onPressed: _isAnalyzingImage ? null : () => _runImageAnalysis(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: _isAnalyzingImage
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.verified_user_outlined, size: 20),
            label: Text(
              _isAnalyzingImage
                  ? 'Inspecting Image Bytes & EXIF...'
                  : 'Detect Real vs. Fake Image',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (_errorMessage != null) _errorBox(_errorMessage!),
          if (_imageResult != null) ...[
            const SizedBox(height: 20),
            _buildResultCard(_imageResult!),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceTab() {
    return SingleChildScrollView(
      controller: _voiceScrollController,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF0F766E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Voice Deepfake & Clone Detector',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  'Record live speech or upload an audio clip (MP3, WAV, M4A, WebM) to detect ElevenLabs/TTS voice clones vs. natural human speech.',
                  style: TextStyle(
                      color: Color(0xFFCCFBF1), fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _selectedAudioBytes == null
                        ? const Color(0xFFF1F5F9)
                        : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedAudioBytes == null
                            ? Icons.graphic_eq
                            : Icons.audio_file_rounded,
                        size: 34,
                        color: _selectedAudioBytes == null
                            ? const Color(0xFF64748B)
                            : const Color(0xFF0F766E),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedAudioBytes == null
                                  ? 'No voice recording attached'
                                  : _selectedAudioName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            Text(
                              _selectedAudioBytes == null
                                  ? 'Record mic or upload an audio file below'
                                  : '$_selectedAudioMime · ${_audioSizeKb ?? 0} KB ready',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      if (_selectedAudioBytes != null)
                        IconButton(
                          onPressed: () => setState(() {
                            _selectedAudioBytes = null;
                            _selectedAudioName = '';
                            _audioSizeKb = null;
                            _voiceResult = null;
                          }),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _recordVoice,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.mic_none_rounded, size: 19),
                        label: const Text('Record Mic'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickAudioFile,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.upload_file_outlined, size: 19),
                        label: const Text('Upload Audio'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _voiceClaimController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText:
                        'Optional: What did the caller or voice note say? (e.g., asking for OTP / urgent money)',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF0F766E)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed:
                      _isAnalyzingVoice ? null : () => _runVoiceAnalysis(),
                  icon: _isAnalyzingVoice
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.record_voice_over_outlined, size: 20),
                  label: Text(
                    _isAnalyzingVoice
                        ? 'Analyzing Voice Harmonics...'
                        : 'Detect Real vs. Fake Voice',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          if (_errorMessage != null) _errorBox(_errorMessage!),
          if (_voiceResult != null) ...[
            const SizedBox(height: 18),
            _buildResultCard(_voiceResult!),
          ],
          const SizedBox(height: 18),
          const Text(
            'One-Tap Voice Deepfake Demo Cases',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _voiceDemoTile(
            title: 'Bank Security OTP Clone Call',
            subtitle:
                'Urgent synthetic caller asking for 6-digit OTP verification.',
            sampleTag: 'voice_ai_bank_clone',
          ),
          _voiceDemoTile(
            title: 'WhatsApp Urgent Family Voice Note',
            subtitle:
                'Forwarded emergency money request with re-encoded compression.',
            sampleTag: 'voice_whatsapp_scam',
          ),
          _voiceDemoTile(
            title: 'Natural Outdoor Voice Memo',
            subtitle:
                'Authentic human speech with natural breath pauses and ambient background.',
            sampleTag: 'voice_human_memo',
          ),
        ],
      ),
    );
  }

  Widget _voiceDemoTile({
    required String title,
    required String subtitle,
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
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFCCFBF1),
          child: Icon(Icons.graphic_eq, color: Color(0xFF0F766E)),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: TextButton(
          onPressed: _isAnalyzingVoice
              ? null
              : () => _runVoiceAnalysis(
                  overrideClaim: subtitle, sampleTag: sampleTag),
          child: const Text('Run Test'),
        ),
      ),
    );
  }

  Widget _buildSocialTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
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
                'WhatsApp, Instagram & SMS Verification',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Verify forwarded viral messages and attached screenshots before resharing.',
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
              if (_selectedImageBytes != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: Image.memory(_selectedImageBytes!, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Attached screenshot: $_selectedImageName ($_imageSizeKb KB)',
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                ),
              ],
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
                      label: Text(_selectedImageBytes == null
                          ? 'Attach Screenshot'
                          : 'Change Image'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1D4ED8)),
                      onPressed: _isAnalyzingImage
                          ? null
                          : () => _runImageAnalysis(
                                sourceChannel: _socialChannel,
                                overrideDescription: _socialController.text,
                                sampleTag: _selectedImageBytes == null
                                    ? 'social_$_socialChannel'
                                    : null,
                                openSheetOnDone: true,
                              ),
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
                  onPressed: _isAnalyzingImage
                      ? null
                      : () => _runImageAnalysis(
                            sourceChannel: channel,
                            overrideDescription: caption,
                            sampleTag: sampleTag,
                            openSheetOnDone: true,
                          ),
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

  Widget _buildHistoryTab() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _scans.where((scan) {
      final matchesFilter = _historyFilter == 'All' ||
          (_historyFilter == 'Voice'
              ? scan.mediaType == 'voice'
              : scan.classification == _historyFilter);
      final matchesSearch = query.isEmpty ||
          scan.description.toLowerCase().contains(query) ||
          scan.summary.toLowerCase().contains(query) ||
          scan.fileName.toLowerCase().contains(query) ||
          scan.sourceChannel.toLowerCase().contains(query);
      return matchesFilter && matchesSearch;
    }).toList();

    return RefreshIndicator(
      onRefresh: _syncHistoryFromCloud,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Search image & voice scans...',
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
              children: ['All', 'Real', 'Fake', 'Suspicious', 'Voice'].map((f) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f),
                    selected: _historyFilter == f,
                    onSelected: (_) => setState(() => _historyFilter = f),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Card(
              color: Colors.white,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No matching scans found.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                ),
              ),
            )
          else
            ...filtered.map(_scanCardTile),
        ],
      ),
    );
  }

  Widget _scanCardTile(MediaAnalysisResponse scan) {
    return Card(
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
          child: Icon(
            scan.mediaType == 'voice'
                ? Icons.graphic_eq
                : _verdictIcon(scan.classification),
            color: _verdictColor(scan.classification),
            size: 20,
          ),
        ),
        title: Text(
          scan.description.isNotEmpty
              ? scan.description
              : (scan.fileName.isNotEmpty ? scan.fileName : 'Media Check'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          '${scan.classification} · ${scan.confidence}% · ${scan.mediaType.toUpperCase()} · ${scan.sourceChannel}',
          style: TextStyle(
            fontSize: 12,
            color: _verdictColor(scan.classification),
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
      ),
    );
  }

  Widget _buildAccountAndApkTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF1D4ED8),
                child: Text(
                  widget.user.name.isNotEmpty
                      ? widget.user.name[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.user.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    Text(widget.user.email,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF64748B))),
                    const SizedBox(height: 4),
                    Text(widget.user.role,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1D4ED8),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: widget.onLogout,
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Sign Out'),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'APK Distribution & Cloud Status',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Share VeriLens Android APK v1.0.0+1 or verify live Vercel backend connectivity.',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _statBox('APK Shares', _apkShares, const Color(0xFF1D4ED8)),
                  const SizedBox(width: 10),
                  _statBox('Total Scans', _scans.length,
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
      ],
    );
  }

  Widget _presetChip(
      String label, String text, TextEditingController controller) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFCBD5E1)),
      onPressed: () => setState(() => controller.text = text),
    );
  }

  Widget _errorBox(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Text(
          message,
          style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
        ),
      ),
    );
  }

  Widget _statBox(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(MediaAnalysisResponse result) {
    final color = _verdictColor(result.classification);
    final bg = _verdictBg(result.classification);
    final isVoice = result.mediaType == 'voice';

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
                              color: color, size: 28),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              isVoice
                                  ? 'Voice Verdict: ${result.classification}'
                                  : 'Verdict: ${result.classification}',
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
                Text(
                  isVoice
                      ? 'Acoustic & Voice Clone Signals'
                      : 'Forensic Visual & Metadata Signals',
                  style: const TextStyle(
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
                  'Context Check: ${result.textConsistency}',
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
}