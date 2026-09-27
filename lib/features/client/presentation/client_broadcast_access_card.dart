import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/broadcast_purchase_coordinator.dart';
import '../../../l10n/app_strings.dart';
import '../../shared/presentation/localized_room_name.dart';
import '../../shared/presentation/miucam_design_tokens.dart';
import '../client_runtime.dart';

class ClientBroadcastAccessCard extends StatefulWidget {
  const ClientBroadcastAccessCard({
    super.key,
    required this.runtime,
    this.onActivated,
  });

  final ClientRuntime runtime;
  final Future<void> Function()? onActivated;

  @override
  State<ClientBroadcastAccessCard> createState() =>
      _ClientBroadcastAccessCardState();
}

class _ClientBroadcastAccessCardState extends State<ClientBroadcastAccessCard> {
  Future<void> _run({bool restore = false}) async {
    final runtime = widget.runtime;
    final roomId = runtime.currentState.session?.deviceId;
    try {
      if (restore) {
        await runtime.restoreBroadcastAccessPurchase();
      } else {
        await runtime.unlockBroadcastAccess();
      }
      if (!mounted || runtime.currentState.session?.deviceId != roomId) return;
      if (runtime.currentState.broadcastAccess?.unlocked == true) {
        await widget.onActivated?.call();
      }
    } catch (_) {
      if (!mounted || runtime.currentState.session?.deviceId != roomId) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppStrings.of(context).ui('familyPurchaseFailed')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final purchases = runtime.purchases;
    final session = runtime.currentState.session;
    if (purchases == null || session == null) return const SizedBox.shrink();
    final strings = AppStrings.of(context);
    final state = runtime.purchaseState;
    final access = runtime.currentState.broadcastAccess;
    final active = access?.unlocked == true;
    final price = purchases.localPrice;
    final busy = state.isBusy || purchases.operationInProgress;
    final pendingVerification =
        state.phase == ParentPurchasePhase.verificationPending ||
            state.phase == ParentPurchasePhase.purchasePending;
    final ready = (purchases.hasLicense
            ? purchases.activationConfigured
            : purchases.checkoutConfigured) &&
        !busy;
    final bodyKey = switch (state.phase) {
      ParentPurchasePhase.purchasing => 'familyPurchaseProcessing',
      ParentPurchasePhase.purchasePending => 'familyPurchasePending',
      ParentPurchasePhase.verificationPending => 'familyVerificationPending',
      ParentPurchasePhase.activating => 'familyLicenseActivating',
      ParentPurchasePhase.activationPending => 'familyActivationPending',
      ParentPurchasePhase.unavailable => 'familyPurchaseUnavailable',
      ParentPurchasePhase.roomUpdateRequired => 'familyRoomUpdateRequired',
      ParentPurchasePhase.noPurchaseFound => 'familyNoPurchaseFound',
      ParentPurchasePhase.revoked => 'familyLicenseRevoked',
      ParentPurchasePhase.failed => 'familyPurchaseFailed',
      ParentPurchasePhase.canceled => 'purchaseCanceled',
      _ => active
          ? 'familyLicenseActive'
          : !ready && !busy
              ? 'familyPurchaseUnavailable'
              : purchases.requiresRestore
                  ? 'familyRestoreRequired'
                  : 'familyPurchaseExplanation',
    };
    final room = localizedRoomName(strings, session.payload.deviceName);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: MiuCamDesignTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.uiFormat('familyLicenseRoom', {'room': room}),
              style: MiuCamDesignTokens.cardTitle),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(strings.ui(bodyKey),
                style: MiuCamDesignTokens.subtitle.copyWith(fontSize: 14)),
          ),
          if (busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (!active) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (!purchases.requiresRestore && !pendingVerification)
                  FilledButton.icon(
                    key: const ValueKey('parent-license-purchase'),
                    onPressed: ready ? () => unawaited(_run()) : null,
                    icon: Icon(purchases.hasLicense
                        ? Icons.sync_rounded
                        : Icons.lock_open_rounded),
                    label: Text(purchases.hasLicense
                        ? strings.ui('familyActivateRoom')
                        : price != null
                            ? strings.uiFormat(
                                'familyPurchasePrice', {'price': price})
                            : strings.ui('familyPurchase')),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('parent-license-restore'),
                  onPressed: purchases.checkoutConfigured && !busy
                      ? () => unawaited(_run(restore: true))
                      : null,
                  icon: const Icon(Icons.restore_rounded),
                  label: Text(strings.ui('restorePurchase')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
