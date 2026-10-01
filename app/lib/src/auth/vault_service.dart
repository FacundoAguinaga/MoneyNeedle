import 'package:biometric_storage/biometric_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../rust/api.dart/api.dart';

class VaultService {
  static const _prefPayloadKey = 'vault_recovery_payload';
  static const _biometricStorageName = 'moneyneedle_master_key';

  static Future<String> getDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/moneyneedle.db';
  }

  static Future<bool> hasVault() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_prefPayloadKey);
  }

  static Future<String?> getRecoveryPayload() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPayloadKey);
  }

  static Future<void> saveRecoveryPayload(String payload) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPayloadKey, payload);
  }

  static Future<BiometricStorageFile> _getBiometricFile() async {
    return await BiometricStorage().getStorage(
      _biometricStorageName,
      options: StorageFileInitOptions(
        authenticationRequired: true,
      ),
    );
  }

  static Future<void> saveMasterKeyBiometric(String masterKeyHex) async {
    final file = await _getBiometricFile();
    await file.write(masterKeyHex);
  }

  static Future<String?> readMasterKeyBiometric() async {
    try {
      final file = await _getBiometricFile();
      return await file.read();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> unlockAndInitDb(String masterKeyHex) async {
    final dbPath = await getDbPath();
    return await initDatabase(dbPath: dbPath, rawKeyHex: masterKeyHex);
  }
}
