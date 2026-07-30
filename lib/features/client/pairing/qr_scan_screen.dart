import 'dart:async';

import 'package:camera/camera.dart' as camera;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/media/camera_permission_gateway.dart';
import '../../../core/protocol/pairing_payload.dart';
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
  final _manualFocusNode = FocusNode(debugLabel: 'qr-manual-entry');
  // Reparent the live native scanner without recreating/stopping it when the
  // keyboard switches the body to its compact scroll layout.
  final _scannerAreaKey = GlobalKey(debugLabel: 'qr-scanner-area');
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
    _manualFocusNode.dispose();
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
      _reportCameraError(error);
      _markCameraUnavailable();
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
        _reportCameraError(error);
        _markCameraUnavailable();
      }
    } catch (error) {
      unawaited(_barcodeSubscription?.cancel());
      _barcodeSubscription = null;
      _reportCameraError(error);
      _markCameraUnavailable();
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
        _reportCameraError(error);
        _markCameraUnavailable();
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

  void _markCameraUnavailable([String? message]) {
    if (!mounted) return;
    setState(() {
      _cameraState = _QrCameraState.unavailable;
      _cameraErrorMessage = message;
    });
  }

  void _reportCameraError(Object error) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        library: 'MiuCam QR scanner',
        context: ErrorDescription('while preparing or running the QR camera'),
      ),
    );
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
    final trimmed = code.trim();
    if (PairingPayload.parseUri(trimmed) == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.of(context).ui('invalidQrCode'))),
        );
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) setState(() => _handled = false);
      return;
    }
    await _barcodeSubscription?.cancel();
    _barcodeSubscription = null;
    if (!mounted) return;
    setState(() => _cameraState = _QrCameraState.processing);
    // Let the iOS capture callback unwind before stopping the native session.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _stopScanner();
    if (!mounted) return;
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    // Scaffold removes the bottom view inset from its body MediaQuery when it
    // resizes for the keyboard, so capture the keyboard state above it.
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07111F),
        foregroundColor: Colors.white,
        title: Text(strings.ui('scanQr')),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (keyboardVisible) {
              // Landscape keyboards can leave less height than the manual
              // entry panel needs at large text scales. Keep the entry first
              // and make the whole surface scrollable instead of squeezing
              // the camera and overflowing the panel.
              final cameraHeight =
                  (constraints.maxHeight * .5).clamp(96.0, 180.0).toDouble();
              return SingleChildScrollView(
                key: const ValueKey('qr-keyboard-scroll'),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildManualEntry(strings),
                      SizedBox(
                        height: cameraHeight,
                        child: _buildScannerArea(strings),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: [
                Expanded(child: _buildScannerArea(strings)),
                _buildManualEntry(strings),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildScannerArea(AppStrings strings) {
    return Stack(
      key: _scannerAreaKey,
      fit: StackFit.expand,
      children: [
        _buildCameraStage(strings),
        if (_cameraState == _QrCameraState.ready)
          LayoutBuilder(
            builder: (context, constraints) {
              final shortestSide = constraints.biggest.shortestSide.isFinite
                  ? constraints.biggest.shortestSide
                  : 250.0;
              final overlaySize =
                  (shortestSide - 32).clamp(72.0, 250.0).toDouble();
              return Center(
                child: Container(
                  width: overlaySize,
                  height: overlaySize,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildManualEntry(AppStrings strings) {
    return Container(
      key: const ValueKey('qr-manual-entry-panel'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _manualController,
              focusNode: _manualFocusNode,
              minLines: 1,
              maxLines: 2,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              onSubmitted: (value) => unawaited(_submit(value)),
              decoration: InputDecoration(
                labelText: strings.ui('qrCodeText'),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _manualController,
            builder: (context, value, _) => Tooltip(
              message: strings.ui('connectDiscoveredRoom'),
              child: SizedBox(
                height: 56,
                child: FilledButton(
                  key: const ValueKey('qr-manual-submit'),
                  onPressed: value.text.trim().isEmpty || _handled
                      ? null
                      : () => unawaited(_submit(value.text)),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    semanticLabel: strings.ui('connectDiscoveredRoom'),
                  ),
                ),
              ),
            ),
          ),
        ],
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
    _reportCameraError(error);
    return strings.ui('qrScanCameraError');
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          const padding = 16.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(padding),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - padding * 2)
                    .clamp(0.0, double.infinity)
                    .toDouble(),
              ),
              child: Center(
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
        },
      ),
    );
  }
}
