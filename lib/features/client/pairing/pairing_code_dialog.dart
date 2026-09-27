import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_strings.dart';

class PairingCodeDialog extends StatefulWidget {
  const PairingCodeDialog({super.key, required this.canSubmit});

  final bool Function() canSubmit;

  @override
  State<PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<PairingCodeDialog> {
  final _controller = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _submitted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    if (!widget.canSubmit()) {
      _submitted = true;
      Navigator.of(context).pop();
      return;
    }
    if (_form.currentState?.validate() != true) return;
    _submitted = true;
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.ui('pairingCodeTitle')),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.ui('enterPairingCodeHelp')),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('pairing-code-input'),
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration:
                    InputDecoration(labelText: strings.ui('pairingCodeLabel')),
                validator: (value) =>
                    RegExp(r'^[0-9]{6}$').hasMatch(value ?? '')
                        ? null
                        : strings.ui('pairingCodeInvalidFormat'),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.ui('cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(strings.ui('confirmPairingCode')),
        ),
      ],
    );
  }
}
