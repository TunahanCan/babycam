import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class MimiCamTestDashboardAssets {
  const MimiCamTestDashboardAssets({
    AssetBundle? bundle,
  }) : _bundle = bundle;

  static const htmlAsset = 'assets/test_dashboard/index.html';
  static const scriptAsset = 'assets/test_dashboard/dashboard.js';

  final AssetBundle? _bundle;

  Future<String> loadHtml({required String title}) async {
    final escapedTitle = const HtmlEscape().convert(title);
    final html = await _loadString(htmlAsset);
    return html.replaceAll('__TITLE__', escapedTitle);
  }

  Future<String> loadScript() => _loadString(scriptAsset);

  Future<String> _loadString(String asset) async {
    final bundle = _bundle;
    if (bundle != null) return bundle.loadString(asset);
    try {
      return await rootBundle.loadString(asset);
    } catch (_) {
      return File(asset).readAsString();
    }
  }
}
