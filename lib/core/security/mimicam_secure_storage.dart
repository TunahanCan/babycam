import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const mimicamSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  ),
);
