import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

const String _transferQrPrefix = 'CSEXAM|QXFER|1|';

class QrAttendanceSection extends StatelessWidget {
  const QrAttendanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const AttendanceHomePage();
  }
}

class AttendanceHomePage extends StatefulWidget {
  const AttendanceHomePage({super.key});

  @override
  State<AttendanceHomePage> createState() => _AttendanceHomePageState();
}

class _AttendanceHomePageState extends State<AttendanceHomePage> {
  static const MethodChannel _speechChannel = MethodChannel(
    'csexam_qr_attendance/speech',
  );

  final AttendanceRepository _repository = AttendanceRepository();
  final SyncService _syncService = SyncService();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final MobileScannerController _transferScannerController =
      MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [BarcodeFormat.qrCode],
      );
  final TextEditingController _apiUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  AppSettings _settings = AppSettings.empty();
  List<AttendanceScan> _scans = const [];
  DashboardStats _stats = DashboardStats.empty();
  String _status = 'Ready';
  String? _lastScan;
  bool _busy = true;
  bool _syncing = false;
  bool _finished = false;
  bool _acceptingTransfer = false;
  int _selectedTab = 0;
  DateTime? _lastScanAt;
  String? _lastScanCode;
  DateTime? _lastTransferScanAt;
  String? _lastTransferCode;
  String? _selectedTransferDate;
  String? _selectedTransferShift;
  String _transferStatus =
      'After attendance is marked, the send QR will appear here.';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    unawaited(_stopSpeech());
    _scannerController.dispose();
    _transferScannerController.dispose();
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _stopSpeech() async {
    try {
      await _speechChannel.invokeMethod<void>('stop');
    } catch (_) {
      // Attendance saving should keep working even if phone TTS is unavailable.
    }
  }

  Future<void> _speak(String message) async {
    final text = message.trim();
    if (text.isEmpty) return;
    try {
      await _speechChannel.invokeMethod<void>('speak', {'message': text});
    } catch (_) {
      // Ignore speech failures; local scan saving is the primary workflow.
    }
  }

  Future<void> _bootstrap() async {
    await _repository.open();
    final seedCount = await _repository.importBundledSeed();
    final prefs = await SharedPreferences.getInstance();
    final didResetOldData =
        prefs.getBool('attendance_reset_2026_05_20') ?? false;
    if (!didResetOldData) {
      await _repository.deleteAllAttendanceData();
      await prefs.setBool('attendance_reset_2026_05_20', true);
    }
    final resetMessage = didResetOldData
        ? ''
        : 'Old local attendance data cleared. ';
    final settings = await AppSettings.load();
    final scans = await _repository.loadScans();
    final stats = await _repository.loadStats();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _apiUrlController.text = settings.apiUrl;
      _apiKeyController.text = settings.apiKey;
      _deviceNameController.text = settings.deviceName;
      _scans = scans;
      _stats = stats;
      _busy = false;
      _transferStatus = scans.isEmpty
          ? 'After attendance is marked, the send QR will appear here.'
          : 'Select a date and shift to share attendance.';
      _status = settings.apiUrl.isEmpty
          ? '${resetMessage}Offline QR data ready ($seedCount records). Save the Hostinger API URL in Settings.'
          : '${resetMessage}Offline QR data ready ($seedCount records). Pending scans will sync when internet is available.';
    });
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (_hasNetwork(results)) {
        unawaited(_syncPending(silent: true));
      }
    });
    final connectivity = await Connectivity().checkConnectivity();
    if (_hasNetwork(connectivity)) {
      unawaited(_syncPending(silent: true));
    }
  }

  Future<void> _reload() async {
    final scans = await _repository.loadScans();
    final stats = await _repository.loadStats();
    if (!mounted) return;
    setState(() {
      _scans = scans;
      _stats = stats;
    });
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_finished) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;

    final now = DateTime.now();
    if (_lastScanCode == raw &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!).inSeconds < 3) {
      return;
    }
    _lastScanCode = raw;
    _lastScanAt = now;
    await _saveScan(raw);
  }

  Future<void> _saveScan(String rawPayload) async {
    final parsed = ParsedQrPayload.fromRaw(rawPayload);
    if (!parsed.isValid) {
      setState(() {
        _status = 'Invalid CSEXAM QR: ${parsed.errorMessage}';
        _lastScan = rawPayload;
      });
      return;
    }

    final seed = await _repository.findSeedTokenOrRollNo(
      token: parsed.token,
      rollNo: parsed.rollNo,
    );
    final scan = parsed.toScan(
      deviceId: _settings.deviceId,
      deviceName: _settings.deviceName,
      seed: seed,
    );
    final result = await _repository.saveScan(scan);
    await _reload();
    if (!mounted) return;
    final displayName = seed?.studentName.isNotEmpty == true
        ? seed!.studentName
        : parsed.rollNo;
    final voicePrompt = result == SaveScanResult.duplicate
        ? 'Already marked'
        : _nextScanPrompt(scan, parsed: parsed);
    setState(() {
      _lastScan = [
        displayName,
        if (scan.program.isNotEmpty) scan.program,
        parsed.hallCode,
        parsed.shift,
      ].join(' | ');
      _status = result == SaveScanResult.inserted
          ? 'Saved locally: $displayName. Audio: $voicePrompt'
          : 'Already marked: $displayName.';
      _transferStatus = result == SaveScanResult.inserted
          ? 'Attendance saved. Select a date and shift to share the batch.'
          : 'Already marked. Select a date and shift to share the saved batch.';
    });
    unawaited(_speak(voicePrompt));

    final connectivity = await Connectivity().checkConnectivity();
    if (_hasNetwork(connectivity)) {
      unawaited(_syncPending(silent: true));
    }
  }

  Future<void> _handleTransferBarcode(BarcodeCapture capture) async {
    if (!_acceptingTransfer) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;

    final now = DateTime.now();
    if (_lastTransferCode == raw &&
        _lastTransferScanAt != null &&
        now.difference(_lastTransferScanAt!).inSeconds < 3) {
      return;
    }
    _lastTransferCode = raw;
    _lastTransferScanAt = now;
    await _importTransferQr(raw);
  }

  Future<void> _importTransferQr(String rawPayload) async {
    final package = TransferPackage.fromRaw(rawPayload);
    if (!package.isValid) {
      if (!mounted) return;
      setState(() {
        _transferStatus = 'Invalid transfer QR: ${package.errorMessage}';
      });
      return;
    }

    final result = await _repository.importTransferredScans(package.scans);
    if (result.inserted > 0) {
      await _repository.recordTransferEvent(
        direction: TransferDirection.accepted,
        examDate: package.examDate,
        shift: package.shift,
        recordCount: result.inserted,
        payload: package.raw,
      );
    }
    await _reload();
    await _transferScannerController.stop();
    if (!mounted) return;
    setState(() {
      _acceptingTransfer = false;
      _transferStatus = result.inserted == 0
          ? 'No new records were added. This transfer was already accepted.'
          : result.duplicates == 0
          ? 'Accepted ${result.inserted} new record(s).'
          : 'Accepted ${result.inserted} new record(s). Existing records were skipped.';
    });
    unawaited(_speak('Transfer received'));
  }

  Future<void> _markTransferSent({
    required List<AttendanceScan> scans,
    required String? examDate,
    required String? shift,
    required String? payload,
  }) async {
    if (scans.isEmpty || payload == null) return;
    await _repository.recordTransferEvent(
      direction: TransferDirection.sent,
      examDate: examDate ?? '',
      shift: shift ?? '',
      recordCount: scans.length,
      payload: payload,
    );
    await _reload();
    if (!mounted) return;
    setState(() {
      _transferStatus = 'Transfer marked as sent: ${scans.length} record(s).';
    });
  }

  Future<void> _startAcceptTransfer() async {
    if (_acceptingTransfer) return;
    setState(() {
      _acceptingTransfer = true;
      _transferStatus =
          'Accept mode: scan the transfer QR from the other mobile.';
    });
    await _transferScannerController.start();
  }

  Future<void> _stopAcceptTransfer() async {
    if (!_acceptingTransfer) return;
    await _transferScannerController.stop();
    if (!mounted) return;
    setState(() {
      _acceptingTransfer = false;
      _transferStatus = 'Accept cancelled.';
    });
  }

  void _selectTransferDate(String? value) {
    setState(() {
      _selectedTransferDate = value;
      _selectedTransferShift = null;
      _transferStatus = 'Transfer date updated.';
    });
  }

  void _selectTransferShift(String? value) {
    setState(() {
      _selectedTransferShift = value;
      _transferStatus = 'Transfer shift updated.';
    });
  }

  Future<void> _finishAttendance() async {
    if (_finished) return;
    await _scannerController.stop();
    if (!mounted) return;
    setState(() {
      _finished = true;
      _status = 'Attendance finished. Pending scans are being synced.';
    });
    unawaited(_speak('Finish'));
    final connectivity = await Connectivity().checkConnectivity();
    if (_hasNetwork(connectivity)) {
      unawaited(_syncPending(silent: true));
    }
  }

  Future<void> _syncPending({bool silent = false}) async {
    if (_syncing) return;
    if (_settings.apiUrl.trim().isEmpty) {
      if (!silent && mounted) {
        setState(() {
          _status = 'Save the Hostinger API URL in Settings.';
        });
      }
      return;
    }
    final pending = await _repository.loadPendingScans(limit: 100);
    if (pending.isEmpty) {
      if (!silent && mounted) {
        setState(() {
          _status = 'No pending scans. Everything is synced.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _syncing = true;
        if (!silent) {
          _status = 'Syncing ${pending.length} pending scan(s)...';
        }
      });
    }

    try {
      final result = await _syncService.upload(
        settings: _settings,
        scans: pending,
      );
      if (result.success) {
        await _repository.markSynced(
          result.syncedTokens.isEmpty
              ? pending.map((scan) => scan.token).toList()
              : result.syncedTokens,
        );
      } else {
        await _repository.markSyncFailed(pending, result.message);
      }
      await _reload();
      if (!mounted) return;
      setState(() {
        _status = result.message;
      });
    } catch (error) {
      await _repository.markSyncFailed(pending, error.toString());
      if (!mounted) return;
      setState(() {
        _status = 'Sync failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    final updated = _settings.copyWith(
      apiUrl: _apiUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      deviceName: _deviceNameController.text.trim().isEmpty
          ? _settings.deviceName
          : _deviceNameController.text.trim(),
    );
    await updated.save();
    if (!mounted) return;
    setState(() {
      _settings = updated;
      _status = 'Settings saved.';
    });
    final connectivity = await Connectivity().checkConnectivity();
    if (_hasNetwork(connectivity)) {
      unawaited(_syncPending(silent: true));
    }
  }

  Future<void> _clearSynced() async {
    await _repository.deleteSynced();
    await _reload();
    if (!mounted) return;
    setState(() {
      _status = 'Synced records cleared from phone.';
    });
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear all data?'),
          content: const Text(
            'This will remove all saved attendance records and transfer stats from this phone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear All'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _repository.deleteAllAttendanceData();
    await _reload();
    if (!mounted) return;
    setState(() {
      _lastScan = null;
      _lastScanCode = null;
      _lastTransferCode = null;
      _selectedTransferDate = null;
      _selectedTransferShift = null;
      _status = 'All local attendance data cleared.';
      _transferStatus =
          'After attendance is marked, the send QR will appear here.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final transferDates = _transferDates(_scans);
    final selectedTransferDate = _validSelectedValue(
      _selectedTransferDate,
      transferDates,
    );
    final transferShifts = _transferShifts(_scans, selectedTransferDate);
    final selectedTransferShift = _validSelectedValue(
      _selectedTransferShift,
      transferShifts,
    );
    final transferScans = _transferScansForSlot(
      _scans,
      selectedTransferDate,
      selectedTransferShift,
    );
    final transferPayload = transferScans.isEmpty
        ? null
        : TransferPackage.encode(
            scans: transferScans,
            settings: _settings,
            examDate: selectedTransferDate,
            shift: selectedTransferShift,
          );
    final pages = [
      _ScanTab(
        scannerController: _scannerController,
        stats: _stats,
        status: _status,
        lastScan: _lastScan,
        syncing: _syncing,
        finished: _finished,
        onDetect: _handleBarcode,
        onSync: () => _syncPending(),
        onFinish: _finishAttendance,
      ),
      _RecordsTab(
        scans: _scans,
        stats: _stats,
        syncing: _syncing,
        onRefresh: _reload,
        onSync: () => _syncPending(),
        onClearSynced: _clearSynced,
        onClearAll: _clearAllData,
      ),
      _TransferTab(
        dates: transferDates,
        shifts: transferShifts,
        selectedDate: selectedTransferDate,
        selectedShift: selectedTransferShift,
        selectedScans: transferScans,
        transferPayload: transferPayload,
        status: _transferStatus,
        accepting: _acceptingTransfer,
        scannerController: _transferScannerController,
        onDetect: _handleTransferBarcode,
        onDateChanged: _selectTransferDate,
        onShiftChanged: _selectTransferShift,
        onMarkSent: () => _markTransferSent(
          scans: transferScans,
          examDate: selectedTransferDate,
          shift: selectedTransferShift,
          payload: transferPayload,
        ),
        onAccept: _startAcceptTransfer,
        onCancelAccept: _stopAcceptTransfer,
      ),
      _SettingsTab(
        apiUrlController: _apiUrlController,
        apiKeyController: _apiKeyController,
        deviceNameController: _deviceNameController,
        settings: _settings,
        onSave: _saveSettings,
      ),
    ];

    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }

    const tabs = [
      ('Scan', Icons.qr_code_scanner_rounded),
      ('Records', Icons.list_alt_rounded),
      ('Transfer', Icons.swap_horiz_rounded),
      ('Settings', Icons.settings_rounded),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE6E9F4)),
            ),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Exam Attendance',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sync now',
                onPressed: _syncing ? null : () => _syncPending(),
                icon: _syncing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_rounded),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (var index = 0; index < tabs.length; index++) ...[
                _AttendanceTabChip(
                  label: tabs[index].$1,
                  icon: tabs[index].$2,
                  selected: _selectedTab == index,
                  onTap: () => setState(() => _selectedTab = index),
                ),
                if (index < tabs.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(child: pages[_selectedTab]),
      ],
    );
  }
}

class _AttendanceTabChip extends StatelessWidget {
  const _AttendanceTabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFE8EDFF) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? const Color(0xFF2948B7)
                    : const Color(0xFF667085),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF2948B7)
                      : const Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanTab extends StatelessWidget {
  const _ScanTab({
    required this.scannerController,
    required this.stats,
    required this.status,
    required this.lastScan,
    required this.syncing,
    required this.finished,
    required this.onDetect,
    required this.onSync,
    required this.onFinish,
  });

  final MobileScannerController scannerController;
  final DashboardStats stats;
  final String status;
  final String? lastScan;
  final bool syncing;
  final bool finished;
  final void Function(BarcodeCapture capture) onDetect;
  final VoidCallback onSync;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatsGrid(stats: stats),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (finished)
                  const ColoredBox(color: Colors.black87)
                else
                  MobileScanner(
                    controller: scannerController,
                    onDetect: onDetect,
                  ),
                const _ScannerFrame(),
                if (finished)
                  const Center(
                    child: Text(
                      'Attendance Finished',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.60),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        lastScan == null
                            ? 'Keep the QR code inside the camera frame.'
                            : 'Last: $lastScan',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _StatusCard(message: status, syncing: syncing, onSync: onSync),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: finished ? null : onFinish,
          icon: const Icon(Icons.check_circle_rounded),
          label: const Text('Finish'),
        ),
      ],
    );
  }
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ),
    );
  }
}

class _RecordsTab extends StatelessWidget {
  const _RecordsTab({
    required this.scans,
    required this.stats,
    required this.syncing,
    required this.onRefresh,
    required this.onSync,
    required this.onClearSynced,
    required this.onClearAll,
  });

  final List<AttendanceScan> scans;
  final DashboardStats stats;
  final bool syncing;
  final VoidCallback onRefresh;
  final VoidCallback onSync;
  final VoidCallback onClearSynced;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatsGrid(stats: stats),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: syncing ? null : onSync,
                icon: const Icon(Icons.cloud_upload_rounded),
                label: Text(syncing ? 'Syncing...' : 'Sync Pending'),
              ),
              OutlinedButton.icon(
                onPressed: stats.synced == 0 ? null : onClearSynced,
                icon: const Icon(Icons.cleaning_services_rounded),
                label: const Text('Clear Synced'),
              ),
              OutlinedButton.icon(
                onPressed:
                    stats.total == 0 &&
                        stats.transfersSent == 0 &&
                        stats.transfersAccepted == 0
                    ? null
                    : onClearAll,
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('Clear All'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (scans.isEmpty)
            const _EmptyCard()
          else
            for (final scan in scans) _ScanRecordTile(scan: scan),
        ],
      ),
    );
  }
}

class _TransferTab extends StatelessWidget {
  const _TransferTab({
    required this.dates,
    required this.shifts,
    required this.selectedDate,
    required this.selectedShift,
    required this.selectedScans,
    required this.transferPayload,
    required this.status,
    required this.accepting,
    required this.scannerController,
    required this.onDetect,
    required this.onDateChanged,
    required this.onShiftChanged,
    required this.onMarkSent,
    required this.onAccept,
    required this.onCancelAccept,
  });

  final List<String> dates;
  final List<String> shifts;
  final String? selectedDate;
  final String? selectedShift;
  final List<AttendanceScan> selectedScans;
  final String? transferPayload;
  final String status;
  final bool accepting;
  final MobileScannerController scannerController;
  final void Function(BarcodeCapture capture) onDetect;
  final ValueChanged<String?> onDateChanged;
  final ValueChanged<String?> onShiftChanged;
  final VoidCallback onMarkSent;
  final VoidCallback onAccept;
  final VoidCallback onCancelAccept;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Send Attendance',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (dates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No attendance has been marked yet.'),
                    ),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: selectedDate,
                    items: [
                      for (final date in dates)
                        DropdownMenuItem(value: date, child: Text(date)),
                    ],
                    onChanged: onDateChanged,
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_month_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedShift,
                    items: [
                      for (final shift in shifts)
                        DropdownMenuItem(value: shift, child: Text(shift)),
                    ],
                    onChanged: onShiftChanged,
                    decoration: const InputDecoration(
                      labelText: 'Shift',
                      prefixIcon: Icon(Icons.schedule_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (transferPayload == null || selectedScans.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No records found for this date and shift.',
                        ),
                      ),
                    )
                  else ...[
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: transferPayload!,
                            version: QrVersions.auto,
                            size: 250,
                            gapless: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      [
                        selectedDate ?? '',
                        selectedShift ?? '',
                        '${selectedScans.length} record(s)',
                      ].where((value) => value.isNotEmpty).join(' | '),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: onMarkSent,
                      icon: const Icon(Icons.send_to_mobile_rounded),
                      label: const Text('Mark Transfer Sent'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Accept Attendance',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (accepting)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: scannerController,
                            onDetect: onDetect,
                          ),
                          const _ScannerFrame(),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: accepting ? onCancelAccept : onAccept,
                  icon: Icon(
                    accepting
                        ? Icons.close_rounded
                        : Icons.qr_code_scanner_rounded,
                  ),
                  label: Text(accepting ? 'Cancel Accept' : 'Accept QR'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  accepting
                      ? Icons.qr_code_scanner_rounded
                      : Icons.swap_horiz_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.apiUrlController,
    required this.apiKeyController,
    required this.deviceNameController,
    required this.settings,
    required this.onSave,
  });

  final TextEditingController apiUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController deviceNameController;
  final AppSettings settings;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hostinger Sync',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'API URL',
                    hintText:
                        'https://yourdomain.com/csexam/sync_attendance.php',
                    prefixIcon: Icon(Icons.link_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: 'Optional secret key',
                    prefixIcon: Icon(Icons.key_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: deviceNameController,
                  decoration: const InputDecoration(
                    labelText: 'Device Name',
                    prefixIcon: Icon(Icons.phone_android_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Settings'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Device ID: ${settings.deviceId}\n\nScans are saved in the local database even when the phone is offline. When internet is available, pending scans are uploaded to the API URL.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 20) / 3;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                label: 'Total',
                value: stats.total.toString(),
                color: Colors.blue,
                icon: Icons.fact_check_rounded,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                label: 'Pending',
                value: stats.pending.toString(),
                color: Colors.orange,
                icon: Icons.pending_actions_rounded,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                label: 'Synced',
                value: stats.synced.toString(),
                color: Colors.green,
                icon: Icons.cloud_done_rounded,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                label: 'Sent',
                value: stats.transfersSent.toString(),
                color: Colors.indigo,
                icon: Icons.send_to_mobile_rounded,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                label: 'Received',
                value: stats.transfersAccepted.toString(),
                color: Colors.teal,
                icon: Icons.call_received_rounded,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.message,
    required this.syncing,
    required this.onSync,
  });

  final String message;
  final bool syncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              syncing ? Icons.sync_rounded : Icons.info_outline_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: syncing ? null : onSync,
              icon: const Icon(Icons.cloud_sync_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanRecordTile extends StatelessWidget {
  const _ScanRecordTile({required this.scan});

  final AttendanceScan scan;

  @override
  Widget build(BuildContext context) {
    final synced = scan.syncedAt != null;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: synced
              ? Colors.green.shade50
              : Colors.orange.shade50,
          child: Icon(
            synced ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded,
            color: synced ? Colors.green : Colors.orange,
          ),
        ),
        title: Text(
          scan.rollNo.isEmpty ? scan.token : scan.rollNo,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          [
            if (scan.studentName.isNotEmpty) scan.studentName,
            if (scan.examDate.isNotEmpty) scan.examDate,
            if (scan.shift.isNotEmpty) scan.shift,
            if (scan.hallCode.isNotEmpty) 'Hall ${scan.hallCode}',
            if (scan.seatLabel.isNotEmpty) scan.seatLabel,
            if (scan.subject.isNotEmpty) scan.subject,
            _formatDateTime(scan.scannedAt),
            if (scan.lastError != null) 'Error: ${scan.lastError}',
          ].join(' | '),
        ),
        trailing: Text(synced ? 'Synced' : 'Pending'),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text('No QR scan records yet.'),
      ),
    );
  }
}

class AttendanceRepository {
  Database? _db;

  Future<void> open() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'csexam_qr_attendance.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _ensureSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureSchema(db);
      },
    );
  }

  Future<int> importBundledSeed() async {
    final db = _requireDb();
    await _ensureSchema(db);
    final rawJson = await rootBundle.loadString('assets/qr_seed.json');
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map || decoded['tokens'] is! List) {
      return 0;
    }
    final tokens = (decoded['tokens'] as List)
        .whereType<Map>()
        .map((row) => SeedToken.fromJson(row.cast<String, Object?>()))
        .where((token) => token.token.isNotEmpty)
        .toList(growable: false);
    final batch = db.batch();
    for (final token in tokens) {
      batch.insert(
        'qr_seed_tokens',
        token.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    return tokens.length;
  }

  Future<SeedToken?> findSeedTokenOrRollNo({
    required String token,
    required String rollNo,
  }) async {
    final db = _requireDb();
    final normalizedToken = token.trim().toUpperCase();
    if (normalizedToken.isNotEmpty) {
      final tokenRows = await db.query(
        'qr_seed_tokens',
        where: 'token = ?',
        whereArgs: [normalizedToken],
        limit: 1,
      );
      if (tokenRows.isNotEmpty) {
        return SeedToken.fromMap(tokenRows.first);
      }
    }

    final normalizedRollNo = rollNo.trim().toUpperCase();
    if (normalizedRollNo.isEmpty) {
      return null;
    }
    final rollRows = await db.query(
      'qr_seed_tokens',
      where: 'UPPER(roll_no) = ?',
      whereArgs: [normalizedRollNo],
      limit: 1,
    );
    return rollRows.isEmpty ? null : SeedToken.fromMap(rollRows.first);
  }

  Future<SaveScanResult> saveScan(AttendanceScan scan) async {
    final db = _requireDb();
    final existing = await db.query(
      'scans',
      columns: const ['id'],
      where: 'token = ?',
      whereArgs: [scan.token],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return SaveScanResult.duplicate;
    }
    await db.insert('scans', scan.toMap());
    return SaveScanResult.inserted;
  }

  Future<TransferImportResult> importTransferredScans(
    List<AttendanceScan> scans,
  ) async {
    var inserted = 0;
    var duplicates = 0;
    for (final scan in scans) {
      final result = await saveScan(scan);
      if (result == SaveScanResult.inserted) {
        inserted += 1;
      } else {
        duplicates += 1;
      }
    }
    return TransferImportResult(inserted: inserted, duplicates: duplicates);
  }

  Future<void> recordTransferEvent({
    required TransferDirection direction,
    required String examDate,
    required String shift,
    required int recordCount,
    required String payload,
  }) async {
    await _requireDb().insert('transfer_events', {
      'direction': direction.name,
      'payload_hash': _stableHash(payload),
      'exam_date': examDate,
      'shift': shift,
      'record_count': recordCount,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<AttendanceScan>> loadScans() async {
    final rows = await _requireDb().query('scans', orderBy: 'id DESC');
    return rows.map(AttendanceScan.fromMap).toList(growable: false);
  }

  Future<List<AttendanceScan>> loadPendingScans({int limit = 100}) async {
    final rows = await _requireDb().query(
      'scans',
      where: 'synced_at IS NULL',
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(AttendanceScan.fromMap).toList(growable: false);
  }

  Future<DashboardStats> loadStats() async {
    final db = _requireDb();
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN synced_at IS NULL THEN 1 ELSE 0 END) AS pending,
        SUM(CASE WHEN synced_at IS NOT NULL THEN 1 ELSE 0 END) AS synced
      FROM scans
    ''');
    final row = rows.first;
    final transferRows = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN direction = 'sent' THEN 1 ELSE 0 END) AS sent,
        SUM(CASE WHEN direction = 'accepted' THEN 1 ELSE 0 END) AS accepted
      FROM transfer_events
    ''');
    final transferRow = transferRows.first;
    return DashboardStats(
      total: _intFromDb(row['total']),
      pending: _intFromDb(row['pending']),
      synced: _intFromDb(row['synced']),
      transfersSent: _intFromDb(transferRow['sent']),
      transfersAccepted: _intFromDb(transferRow['accepted']),
    );
  }

  Future<void> markSynced(List<String> tokens) async {
    if (tokens.isEmpty) return;
    final db = _requireDb();
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final token in tokens) {
      batch.update(
        'scans',
        {'synced_at': now, 'last_error': null},
        where: 'token = ?',
        whereArgs: [token],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> markSyncFailed(
    List<AttendanceScan> scans,
    String errorMessage,
  ) async {
    final db = _requireDb();
    final batch = db.batch();
    for (final scan in scans) {
      batch.update(
        'scans',
        {'attempts': scan.attempts + 1, 'last_error': errorMessage},
        where: 'token = ?',
        whereArgs: [scan.token],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteSynced() async {
    await _requireDb().delete('scans', where: 'synced_at IS NOT NULL');
  }

  Future<void> deleteAllAttendanceData() async {
    final db = _requireDb();
    await db.delete('scans');
    await db.delete('transfer_events');
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        token TEXT NOT NULL UNIQUE,
        payload TEXT NOT NULL,
        exam_date TEXT NOT NULL DEFAULT '',
        shift TEXT NOT NULL DEFAULT '',
        hall_code TEXT NOT NULL DEFAULT '',
        program TEXT NOT NULL DEFAULT '',
        subject TEXT NOT NULL DEFAULT '',
        faculty TEXT NOT NULL DEFAULT '',
        course_code TEXT NOT NULL DEFAULT '',
        roll_no TEXT NOT NULL DEFAULT '',
        student_name TEXT NOT NULL DEFAULT '',
        col_no INTEGER NOT NULL DEFAULT 0,
        chair_no INTEGER NOT NULL DEFAULT 0,
        seat_label TEXT NOT NULL DEFAULT '',
        scanned_at TEXT NOT NULL,
        synced_at TEXT,
        device_id TEXT NOT NULL DEFAULT '',
        device_name TEXT NOT NULL DEFAULT '',
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
    await _ensureColumn(db, 'scans', 'program', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'scans', 'subject', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'scans', 'faculty', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(db, 'scans', 'course_code', "TEXT NOT NULL DEFAULT ''");
    await _ensureColumn(
      db,
      'scans',
      'student_name',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(db, 'scans', 'seat_label', "TEXT NOT NULL DEFAULT ''");
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scans_synced ON scans(synced_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scans_roll ON scans(roll_no)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scans_slot ON scans(exam_date, shift)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transfer_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        direction TEXT NOT NULL,
        payload_hash TEXT NOT NULL DEFAULT '',
        exam_date TEXT NOT NULL DEFAULT '',
        shift TEXT NOT NULL DEFAULT '',
        record_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transfer_events_direction ON transfer_events(direction)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS qr_seed_tokens(
        token TEXT PRIMARY KEY,
        payload TEXT NOT NULL DEFAULT '',
        exam_date TEXT NOT NULL DEFAULT '',
        shift TEXT NOT NULL DEFAULT '',
        hall_code TEXT NOT NULL DEFAULT '',
        program TEXT NOT NULL DEFAULT '',
        subject TEXT NOT NULL DEFAULT '',
        faculty TEXT NOT NULL DEFAULT '',
        course_code TEXT NOT NULL DEFAULT '',
        roll_no TEXT NOT NULL DEFAULT '',
        student_name TEXT NOT NULL DEFAULT '',
        col_no INTEGER NOT NULL DEFAULT 0,
        chair_no INTEGER NOT NULL DEFAULT 0,
        seat_label TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qr_seed_slot ON qr_seed_tokens(exam_date, shift, hall_code)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qr_seed_roll ON qr_seed_tokens(roll_no)',
    );
  }

  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any(
      (row) =>
          (row['name'] ?? '').toString().toLowerCase() == column.toLowerCase(),
    );
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('Database not open.');
    }
    return db;
  }
}

class SyncService {
  Future<SyncResult> upload({
    required AppSettings settings,
    required List<AttendanceScan> scans,
  }) async {
    final uri = Uri.tryParse(settings.apiUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return const SyncResult(
        success: false,
        message: 'Invalid Hostinger API URL.',
      );
    }

    final response = await http
        .post(
          uri,
          headers: {
            'content-type': 'application/json',
            'accept': 'application/json',
            if (settings.apiKey.isNotEmpty) 'X-API-Key': settings.apiKey,
          },
          body: jsonEncode({
            'device_id': settings.deviceId,
            'device_name': settings.deviceName,
            'scans': scans.map((scan) => scan.toJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return SyncResult(
        success: false,
        message: 'Server ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = _tryDecodeJson(response.body);
    if (decoded is Map && decoded['ok'] == false) {
      return SyncResult(
        success: false,
        message: (decoded['message'] ?? 'Server rejected scans.').toString(),
      );
    }
    final tokens = <String>[];
    if (decoded is Map && decoded['tokens'] is List) {
      tokens.addAll(
        (decoded['tokens'] as List).map((value) => value.toString()),
      );
    }
    return SyncResult(
      success: true,
      syncedTokens: tokens,
      message: 'Synced ${scans.length} scan(s) to hosting.',
    );
  }
}

class TransferPackage {
  const TransferPackage({
    required this.raw,
    required this.scans,
    required this.examDate,
    required this.shift,
    required this.errorMessage,
  });

  factory TransferPackage.fromRaw(String rawPayload) {
    final raw = rawPayload.trim();
    if (!raw.startsWith(_transferQrPrefix)) {
      return TransferPackage.invalid(raw, 'This is not a CSEXAM transfer QR.');
    }

    try {
      final encoded = raw.substring(_transferQrPrefix.length);
      final bytes = base64Url.decode(_withBase64Padding(encoded));
      final body = _decodeTransferBody(bytes);
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['type'] != 'csexam_attendance_transfer') {
        return TransferPackage.invalid(raw, 'Invalid transfer type.');
      }
      final scanRows = decoded['scans'];
      if (scanRows is! List || scanRows.isEmpty) {
        return TransferPackage.invalid(
          raw,
          'No scans were found in this transfer QR.',
        );
      }
      final scans = scanRows
          .whereType<Map>()
          .map((row) => AttendanceScan.fromTransferJson(row))
          .where((scan) => scan.token.isNotEmpty)
          .toList(growable: false);
      if (scans.isEmpty) {
        return TransferPackage.invalid(raw, 'Transfer scan data is empty.');
      }
      return TransferPackage(
        raw: raw,
        scans: scans,
        examDate: (decoded['exam_date'] ?? '').toString(),
        shift: (decoded['shift'] ?? '').toString(),
        errorMessage: '',
      );
    } catch (error) {
      return TransferPackage.invalid(raw, error.toString());
    }
  }

  factory TransferPackage.invalid(String raw, String message) {
    return TransferPackage(
      raw: raw,
      scans: const [],
      examDate: '',
      shift: '',
      errorMessage: message,
    );
  }

  static String encode({
    required List<AttendanceScan> scans,
    required AppSettings settings,
    String? examDate,
    String? shift,
  }) {
    final body = {
      'type': 'csexam_attendance_transfer',
      'version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'device_id': settings.deviceId,
      'device_name': settings.deviceName,
      'exam_date': examDate ?? '',
      'shift': shift ?? '',
      'count': scans.length,
      'scans': scans
          .map((scan) => scan.toTransferJson())
          .toList(growable: false),
    };
    final encoded = base64Url.encode(
      GZipEncoder().encode(utf8.encode(jsonEncode(body))),
    );
    return '$_transferQrPrefix$encoded';
  }

  final String raw;
  final List<AttendanceScan> scans;
  final String examDate;
  final String shift;
  final String errorMessage;

  bool get isValid => scans.isNotEmpty && errorMessage.isEmpty;
}

class ParsedQrPayload {
  ParsedQrPayload({
    required this.raw,
    required this.token,
    required this.examDate,
    required this.shift,
    required this.hallCode,
    required this.rollNo,
    required this.col,
    required this.chairNo,
    required this.errorMessage,
  });

  factory ParsedQrPayload.fromRaw(String rawPayload) {
    final raw = rawPayload.trim();
    final parts = raw.split('|').map((value) => value.trim()).toList();
    if (parts.length < 10 ||
        parts[0].toUpperCase() != 'CSEXAM' ||
        parts[1].toUpperCase() != 'QPATT') {
      return ParsedQrPayload.invalid(raw, 'Expected format is CSEXAM|QPATT.');
    }
    final token = parts[3].trim().toUpperCase();
    if (token.isEmpty) {
      return ParsedQrPayload.invalid(raw, 'Token is empty.');
    }
    return ParsedQrPayload(
      raw: raw,
      token: token,
      examDate: parts[4],
      shift: parts[5],
      hallCode: parts[6],
      rollNo: parts[7],
      col: int.tryParse(parts[8]) ?? 0,
      chairNo: int.tryParse(parts[9]) ?? 0,
      errorMessage: '',
    );
  }

  factory ParsedQrPayload.invalid(String raw, String message) {
    return ParsedQrPayload(
      raw: raw,
      token: '',
      examDate: '',
      shift: '',
      hallCode: '',
      rollNo: '',
      col: 0,
      chairNo: 0,
      errorMessage: message,
    );
  }

  final String raw;
  final String token;
  final String examDate;
  final String shift;
  final String hallCode;
  final String rollNo;
  final int col;
  final int chairNo;
  final String errorMessage;

  bool get isValid => token.isNotEmpty && errorMessage.isEmpty;

  AttendanceScan toScan({
    required String deviceId,
    required String deviceName,
    SeedToken? seed,
  }) {
    return AttendanceScan(
      token: token,
      payload: raw,
      examDate: seed?.examDate ?? examDate,
      shift: seed?.shift ?? shift,
      hallCode: seed?.hallCode ?? hallCode,
      program: seed?.program ?? '',
      subject: seed?.subject ?? '',
      faculty: seed?.faculty ?? '',
      courseCode: seed?.courseCode ?? '',
      rollNo: seed?.rollNo ?? rollNo,
      studentName: seed?.studentName ?? '',
      col: seed?.col ?? col,
      chairNo: seed?.chairNo ?? chairNo,
      seatLabel: seed?.seatLabel ?? '',
      scannedAt: DateTime.now(),
      syncedAt: null,
      deviceId: deviceId,
      deviceName: deviceName,
      attempts: 0,
      lastError: null,
    );
  }
}

class AttendanceScan {
  const AttendanceScan({
    this.id,
    required this.token,
    required this.payload,
    required this.examDate,
    required this.shift,
    required this.hallCode,
    required this.program,
    required this.subject,
    required this.faculty,
    required this.courseCode,
    required this.rollNo,
    required this.studentName,
    required this.col,
    required this.chairNo,
    required this.seatLabel,
    required this.scannedAt,
    required this.syncedAt,
    required this.deviceId,
    required this.deviceName,
    required this.attempts,
    required this.lastError,
  });

  final int? id;
  final String token;
  final String payload;
  final String examDate;
  final String shift;
  final String hallCode;
  final String program;
  final String subject;
  final String faculty;
  final String courseCode;
  final String rollNo;
  final String studentName;
  final int col;
  final int chairNo;
  final String seatLabel;
  final DateTime scannedAt;
  final DateTime? syncedAt;
  final String deviceId;
  final String deviceName;
  final int attempts;
  final String? lastError;

  factory AttendanceScan.fromMap(Map<String, Object?> map) {
    return AttendanceScan(
      id: _intFromDb(map['id']),
      token: (map['token'] ?? '').toString(),
      payload: (map['payload'] ?? '').toString(),
      examDate: (map['exam_date'] ?? '').toString(),
      shift: (map['shift'] ?? '').toString(),
      hallCode: (map['hall_code'] ?? '').toString(),
      program: (map['program'] ?? '').toString(),
      subject: (map['subject'] ?? '').toString(),
      faculty: (map['faculty'] ?? '').toString(),
      courseCode: (map['course_code'] ?? '').toString(),
      rollNo: (map['roll_no'] ?? '').toString(),
      studentName: (map['student_name'] ?? '').toString(),
      col: _intFromDb(map['col_no']),
      chairNo: _intFromDb(map['chair_no']),
      seatLabel: (map['seat_label'] ?? '').toString(),
      scannedAt:
          DateTime.tryParse((map['scanned_at'] ?? '').toString()) ??
          DateTime.now(),
      syncedAt: _dateOrNull(map['synced_at']),
      deviceId: (map['device_id'] ?? '').toString(),
      deviceName: (map['device_name'] ?? '').toString(),
      attempts: _intFromDb(map['attempts']),
      lastError: _stringOrNull(map['last_error']),
    );
  }

  factory AttendanceScan.fromTransferJson(Map<dynamic, dynamic> map) {
    return AttendanceScan(
      token: _transferString(map, 'token', 't').trim().toUpperCase(),
      payload: _transferString(map, 'payload', 'p'),
      examDate: _transferString(map, 'exam_date', 'd'),
      shift: _transferString(map, 'shift', 'sh'),
      hallCode: _transferString(map, 'hall_code', 'h'),
      program: _transferString(map, 'program', 'pr'),
      subject: _transferString(map, 'subject', 'su'),
      faculty: _transferString(map, 'faculty', 'f'),
      courseCode: _transferString(map, 'course_code', 'cc'),
      rollNo: _transferString(map, 'roll_no', 'r'),
      studentName: _transferString(map, 'student_name', 'n'),
      col: _intFromDb(map['col_no'] ?? map['cn']),
      chairNo: _intFromDb(map['chair_no'] ?? map['ch']),
      seatLabel: _transferString(map, 'seat_label', 'sl'),
      scannedAt:
          DateTime.tryParse(_transferString(map, 'scanned_at', 'at')) ??
          DateTime.now(),
      syncedAt: null,
      deviceId: _transferString(map, 'device_id', 'di'),
      deviceName: _transferString(map, 'device_name', 'dn'),
      attempts: 0,
      lastError: null,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'token': token,
      'payload': payload,
      'exam_date': examDate,
      'shift': shift,
      'hall_code': hallCode,
      'program': program,
      'subject': subject,
      'faculty': faculty,
      'course_code': courseCode,
      'roll_no': rollNo,
      'student_name': studentName,
      'col_no': col,
      'chair_no': chairNo,
      'seat_label': seatLabel,
      'scanned_at': scannedAt.toIso8601String(),
      'synced_at': syncedAt?.toIso8601String(),
      'device_id': deviceId,
      'device_name': deviceName,
      'attempts': attempts,
      'last_error': lastError,
    };
  }

  Map<String, Object?> toJson() {
    return {
      'token': token,
      'payload': payload,
      'exam_date': examDate,
      'shift': shift,
      'hall_code': hallCode,
      'program': program,
      'subject': subject,
      'faculty': faculty,
      'course_code': courseCode,
      'roll_no': rollNo,
      'student_name': studentName,
      'col_no': col,
      'chair_no': chairNo,
      'seat_label': seatLabel,
      'scanned_at': scannedAt.toIso8601String(),
      'device_id': deviceId,
      'device_name': deviceName,
    };
  }

  Map<String, Object?> toTransferJson() {
    return {
      't': token,
      'p': payload,
      'd': examDate,
      'sh': shift,
      'h': hallCode,
      'pr': program,
      'su': subject,
      'f': faculty,
      'cc': courseCode,
      'r': rollNo,
      'n': studentName,
      'cn': col,
      'ch': chairNo,
      'sl': seatLabel,
      'at': scannedAt.toIso8601String(),
      'di': deviceId,
      'dn': deviceName,
    };
  }
}

class SeedToken {
  const SeedToken({
    required this.token,
    required this.payload,
    required this.examDate,
    required this.shift,
    required this.hallCode,
    required this.program,
    required this.subject,
    required this.faculty,
    required this.courseCode,
    required this.rollNo,
    required this.studentName,
    required this.col,
    required this.chairNo,
    required this.seatLabel,
  });

  final String token;
  final String payload;
  final String examDate;
  final String shift;
  final String hallCode;
  final String program;
  final String subject;
  final String faculty;
  final String courseCode;
  final String rollNo;
  final String studentName;
  final int col;
  final int chairNo;
  final String seatLabel;

  factory SeedToken.fromJson(Map<String, Object?> map) {
    return SeedToken.fromMap(map);
  }

  factory SeedToken.fromMap(Map<String, Object?> map) {
    return SeedToken(
      token: (map['token'] ?? '').toString().trim().toUpperCase(),
      payload: (map['payload'] ?? '').toString().trim(),
      examDate: (map['exam_date'] ?? '').toString().trim(),
      shift: (map['shift'] ?? '').toString().trim(),
      hallCode: (map['hall_code'] ?? '').toString().trim(),
      program: (map['program'] ?? '').toString().trim(),
      subject: (map['subject'] ?? '').toString().trim(),
      faculty: (map['faculty'] ?? '').toString().trim(),
      courseCode: (map['course_code'] ?? '').toString().trim(),
      rollNo: (map['roll_no'] ?? '').toString().trim(),
      studentName: (map['student_name'] ?? '').toString().trim(),
      col: _intFromDb(map['col_no']),
      chairNo: _intFromDb(map['chair_no']),
      seatLabel: (map['seat_label'] ?? '').toString().trim(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'token': token,
      'payload': payload,
      'exam_date': examDate,
      'shift': shift,
      'hall_code': hallCode,
      'program': program,
      'subject': subject,
      'faculty': faculty,
      'course_code': courseCode,
      'roll_no': rollNo,
      'student_name': studentName,
      'col_no': col,
      'chair_no': chairNo,
      'seat_label': seatLabel,
    };
  }
}

class AppSettings {
  const AppSettings({
    required this.apiUrl,
    required this.apiKey,
    required this.deviceId,
    required this.deviceName,
  });

  factory AppSettings.empty() {
    final id = 'phone-${DateTime.now().millisecondsSinceEpoch}';
    return AppSettings(
      apiUrl: '',
      apiKey: '',
      deviceId: id,
      deviceName: 'CSEXAM Phone',
    );
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');
    if (deviceId == null || deviceId.trim().isEmpty) {
      deviceId = 'phone-${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', deviceId);
    }
    return AppSettings(
      apiUrl: prefs.getString('api_url') ?? '',
      apiKey: prefs.getString('api_key') ?? '',
      deviceId: deviceId,
      deviceName: prefs.getString('device_name') ?? 'CSEXAM Phone',
    );
  }

  final String apiUrl;
  final String apiKey;
  final String deviceId;
  final String deviceName;

  AppSettings copyWith({String? apiUrl, String? apiKey, String? deviceName}) {
    return AppSettings(
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_url', apiUrl);
    await prefs.setString('api_key', apiKey);
    await prefs.setString('device_id', deviceId);
    await prefs.setString('device_name', deviceName);
  }
}

class DashboardStats {
  const DashboardStats({
    required this.total,
    required this.pending,
    required this.synced,
    required this.transfersSent,
    required this.transfersAccepted,
  });

  factory DashboardStats.empty() {
    return const DashboardStats(
      total: 0,
      pending: 0,
      synced: 0,
      transfersSent: 0,
      transfersAccepted: 0,
    );
  }

  final int total;
  final int pending;
  final int synced;
  final int transfersSent;
  final int transfersAccepted;
}

class SyncResult {
  const SyncResult({
    required this.success,
    required this.message,
    this.syncedTokens = const [],
  });

  final bool success;
  final String message;
  final List<String> syncedTokens;
}

class TransferImportResult {
  const TransferImportResult({
    required this.inserted,
    required this.duplicates,
  });

  final int inserted;
  final int duplicates;
}

enum SaveScanResult { inserted, duplicate }

enum TransferDirection { sent, accepted }

bool _hasNetwork(List<ConnectivityResult> results) {
  return results.any((result) => result != ConnectivityResult.none);
}

Object? _tryDecodeJson(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

String _withBase64Padding(String value) {
  final remainder = value.length % 4;
  return remainder == 0
      ? value
      : value.padRight(value.length + 4 - remainder, '=');
}

String _decodeTransferBody(List<int> bytes) {
  try {
    return utf8.decode(GZipDecoder().decodeBytes(bytes));
  } catch (_) {
    return utf8.decode(bytes);
  }
}

String _transferString(Map<dynamic, dynamic> map, String fullKey, String key) {
  return (map[fullKey] ?? map[key] ?? '').toString();
}

String _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

List<String> _transferDates(List<AttendanceScan> scans) {
  final values = <String>{};
  for (final scan in scans) {
    final value = scan.examDate.trim();
    if (value.isNotEmpty) {
      values.add(value);
    }
  }
  return values.toList(growable: false)..sort();
}

List<String> _transferShifts(List<AttendanceScan> scans, String? date) {
  if (date == null) return const [];
  final values = <String>{};
  for (final scan in scans) {
    if (scan.examDate.trim() != date) continue;
    final value = scan.shift.trim();
    if (value.isNotEmpty) {
      values.add(value);
    }
  }
  return values.toList(growable: false)..sort();
}

String? _validSelectedValue(String? selected, List<String> values) {
  if (values.isEmpty) return null;
  if (selected != null && values.contains(selected)) {
    return selected;
  }
  return values.first;
}

List<AttendanceScan> _transferScansForSlot(
  List<AttendanceScan> scans,
  String? date,
  String? shift,
) {
  if (date == null || shift == null) return const [];
  return scans
      .where(
        (scan) => scan.examDate.trim() == date && scan.shift.trim() == shift,
      )
      .toList(growable: false);
}

DateTime? _dateOrNull(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : DateTime.tryParse(text);
}

String? _stringOrNull(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

int _intFromDb(Object? value) {
  return int.tryParse((value ?? '0').toString()) ?? 0;
}

String _formatDateTime(DateTime value) {
  return DateFormat('dd-MM-yyyy HH:mm').format(value.toLocal());
}

String _nextScanPrompt(AttendanceScan scan, {ParsedQrPayload? parsed}) {
  final programAndSection = scan.program.trim();
  if (programAndSection.isNotEmpty) {
    final parts = programAndSection.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      return 'Program $programAndSection. Next';
    }
    final section = parts.last;
    final program = parts.take(parts.length - 1).join(' ');
    return 'Program $program. Section $section. Next';
  }

  final program = _programFromRollNo(parsed?.rollNo ?? scan.rollNo);
  final hallCode = (parsed?.hallCode ?? scan.hallCode).trim();
  final shift = (parsed?.shift ?? scan.shift).trim();
  final parts = <String>[
    if (program.isNotEmpty) 'Program $program',
    if (hallCode.isNotEmpty) 'Hall $hallCode',
    if (shift.isNotEmpty) 'Shift $shift',
    'Next',
  ];
  return parts.join('. ');
}

String _programFromRollNo(String rollNo) {
  final text = rollNo.trim().toUpperCase();
  if (text.isEmpty) return '';
  final parts = text.split('-').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  final directProgram = parts.firstWhere(
    (part) => RegExp(r'^[A-Z]{2,}[A-Z0-9]*$').hasMatch(part),
    orElse: () => '',
  );
  return directProgram;
}
