import 'dart:async';

import 'package:camera/camera.dart' as camera;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/media/camera_permission_gateway.dart';
import '../../../l10n/app_strings.dart';

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({
    super.key,
    this.permissionGateway = const MethodChannelCameraPermissionGateway(),
    this.cameraAvailabilityGateway =
        const CameraPackageQRCameraAvailabilityGateway(),
  });

  final CameraPermissionGateway permissionGateway;
  final QRCameraAvailabilityGateway cameraAvailabilityGateway;

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

abstract interface class QRCameraAvailabilityGateway {
  Future<bool> hasCamera();
}

class CameraPackageQRCameraAvailabilityGateway
    implements QRCameraAvailabilityGateway {
  const CameraPackageQRCameraAvailabilityGateway();

  @override
  Future<bool> hasCamera() async {
    final cameras = await camera.availableCameras();
    return cameras.isNotEmpty;
  }
}

enum _QrCameraState {
  checking,
  ready,
  blocked,
  unavailable,
  processing,
}

class _QRScanScreenState extends State<QRScanScreen>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  final _manualController = TextEditingController();
  StreamSubscription<BarcodeCapture>? _barcodeSubscription;
  bool _handled = false;
  bool _startingScanner = false;
  _QrCameraState _cameraState = _QrCameraState.checking;
  String? _cameraErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prepareCamera());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualController.dispose();
    unawaited(_barcodeSubscription?.cancel());
    _barcodeSubscription = null;
    unawaited(_disposeScannerController());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_cameraState == _QrCameraState.blocked) {
          unawaited(_prepareCamera(requestIfNeeded: false));
        } else if (_cameraState == _QrCameraState.ready) {
          _listenForBarcodes();
          _scheduleScannerStart();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_barcodeSubscription?.cancel());
        _barcodeSubscription = null;
        unawaited(_stopScanner());
        break;
    }
  }

  Future<void> _prepareCamera({bool requestIfNeeded = true}) async {
    if (!mounted) return;
    setState(() {
      _cameraState = _QrCameraState.checking;
      _cameraErrorMessage = null;
    });

    CameraPermissionStatus status;
    try {
      status = await widget.permissionGateway.status();
      if (status.isDenied && requestIfNeeded) {
        status = await widget.permissionGateway.request();
      }
    } catch (error) {
      _markCameraUnavailable('$error');
      return;
    }

    if (!mounted) return;
    if (status.isGranted) {
      final hasCamera = await _hasAvailableCamera();
      if (!mounted) return;
      if (!hasCamera) {
        _markCameraUnavailable(AppStrings.of(context).cameraNotFound);
        return;
      }
      setState(() => _cameraState = _QrCameraState.ready);
      _scheduleScannerStart();
      return;
    }

    await _stopScanner();
    unawaited(_barcodeSubscription?.cancel());
    _barcodeSubscription = null;
    if (!mounted) return;
    setState(() => _cameraState = _QrCameraState.blocked);
  }

  Future<bool> _hasAvailableCamera() async {
    try {
      return widget.cameraAvailabilityGateway.hasCamera();
    } catch (_) {
      return false;
    }
  }

  void _scheduleScannerStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cameraState != _QrCameraState.ready) return;
      unawaited(_startScanner());
    });
  }

  Future<void> _startScanner() async {
    if (_startingScanner || _controller.value.isRunning) return;
    _startingScanner = true;
    try {
      _listenForBarcodes();
      await _controller.start();
      final error = _controller.value.error;
      if (!mounted || error == null) return;
      if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
        unawaited(_barcodeSubscription?.cancel());
        _barcodeSubscription = null;
        setState(() => _cameraState = _QrCameraState.blocked);
      } else {
        unawaited(_barcodeSubscription?.cancel());
        _barcodeSubscription = null;
        _markCameraUnavailable(error.errorDetails?.message);
      }
    } catch (error) {
      unawaited(_barcodeSubscription?.cancel());
      _barcodeSubscription = null;
      _markCameraUnavailable('$error');
    } finally {
      _startingScanner = false;
    }
  }

  void _listenForBarcodes() {
    if (_barcodeSubscription != null) return;
    _barcodeSubscription = _controller.barcodes.listen(
      _onDetect,
      onError: (Object error) {
        if (_handled) return;
        _markCameraUnavailable('$error');
      },
      cancelOnError: false,
    );
  }

  Future<void> _disposeScannerController() async {
    await _stopScanner();
    await _controller.dispose();
  }

  Future<void> _stopScanner() async {
    try {
      await _controller.stop();
    } catch (_) {
      return;
    }
  }

  void _markCameraUnavailable(String? message) {
    if (!mounted) return;
    setState(() {
      _cameraState = _QrCameraState.unavailable;
      _cameraErrorMessage = message;
    });
  }

  Future<void> _openSettings() async {
    try {
      await widget.permissionGateway.openSettings();
    } catch (_) {
      return;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code != null && code.isNotEmpty) {
        _handled = true;
        unawaited(_completeWithCode(code));
        return;
      }
    }
  }

  Future<void> _submit(String code) async {
    final trimmed = code.trim();
    if (_handled || trimmed.isEmpty) return;
    _handled = true;
    await _completeWithCode(trimmed);
  }

  Future<void> _completeWithCode(String code) async {
    await _barcodeSubscription?.cancel();
    _barcodeSubscription = null;
    if (!mounted) return;
    setState(() => _cameraState = _QrCameraState.processing);
    // Let the iOS capture callback unwind before stopping the native session.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _stopScanner();
    if (!mounted) return;
    Navigator.of(context).pop(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07111F),
        foregroundColor: Colors.white,
        title: Text(strings.ui('scanQr')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCameraStage(strings),
                  if (_cameraState == _QrCameraState.ready)
                    Center(
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 3),
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualController,
                      minLines: 1,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: strings.ui('qrCodeText'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: () =>
                          unawaited(_submit(_manualController.text)),
                      child: const Icon(Icons.check_rounded),
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

  Widget _buildCameraStage(AppStrings strings) {
    return switch (_cameraState) {
      _QrCameraState.ready => MobileScanner(
          controller: _controller,
          useAppLifecycleState: false,
          errorBuilder: (context, error) => _CameraStatePanel(
            busy: false,
            message: _scannerErrorText(strings, error),
            onOpenSettings:
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? _openSettings
                    : null,
            onRetry: () => unawaited(_prepareCamera()),
            strings: strings,
          ),
        ),
      _QrCameraState.checking => _CameraStatePanel(
          busy: true,
          message: strings.ui('qrScanPreparingCamera'),
          strings: strings,
        ),
      _QrCameraState.blocked => _CameraStatePanel(
          busy: false,
          message: strings.ui('qrScanCameraPermissionRequired'),
          onOpenSettings: _openSettings,
          onRetry: () => unawaited(_prepareCamera()),
          strings: strings,
        ),
      _QrCameraState.unavailable => _CameraStatePanel(
          busy: false,
          message: _cameraErrorMessage ?? strings.ui('qrScanCameraError'),
          onRetry: () => unawaited(_prepareCamera()),
          strings: strings,
        ),
      _QrCameraState.processing => _CameraStatePanel(
          busy: true,
          message: strings.ui('qrScanProcessing'),
          strings: strings,
        ),
    };
  }

  String _scannerErrorText(AppStrings strings, MobileScannerException error) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return strings.ui('qrScanCameraPermissionRequired');
    }
    return error.errorDetails?.message ?? strings.ui('qrScanCameraError');
  }
}

class _CameraStatePanel extends StatelessWidget {
  const _CameraStatePanel({
    required this.busy,
    required this.message,
    required this.strings,
    this.onOpenSettings,
    this.onRetry,
  });

  final bool busy;
  final String message;
  final AppStrings strings;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF07111F),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.white,
                    size: 34,
                  ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.35,
                  ),
                ),
                if (onOpenSettings != null || onRetry != null) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      if (onOpenSettings != null)
                        FilledButton.icon(
                          onPressed: onOpenSettings,
                          icon: const Icon(Icons.settings_rounded),
                          label: Text(strings.ui('openAppSettings')),
                        ),
                      if (onRetry != null)
                        OutlinedButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(strings.ui('tryAgain')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
