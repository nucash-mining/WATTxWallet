import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the WATTx daemon bundled in the APK.
///
/// The wallet's keys stay in the Android Keystore either way; what changes in
/// full-node mode is *who* the wallet asks about the chain. Instead of trusting
/// a public indexer, the phone validates every block itself and answers its own
/// questions over loopback.
///
/// WATTx is small enough for this to be reasonable on a handset — the whole
/// chain is tens of megabytes, so there is no pruning and no compromise.
class LocalNode {
  static const _channel = MethodChannel('app.wattxchange.wattx_wallet/node');

  /// False where no daemon ships for the device's ABI, so the UI can hide the
  /// option rather than offer something that cannot work.
  static Future<bool> supported() async {
    try {
      return await _channel.invokeMethod<bool>('supported') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isRunning') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Returns null on success, or a message explaining why the node did not
  /// start. The native side waits to see the process survive startup, so a
  /// daemon that exits immediately is reported rather than silently assumed up.
  static Future<String?> start() async {
    try {
      await _channel.invokeMethod('start');
      return null;
    } on PlatformException catch (e) {
      return e.message ?? 'The node could not be started.';
    }
  }

  static const _wantedKey = 'full_node_enabled';

  /// Whether the user turned full-node mode on. Persisted so the choice
  /// survives the app being locked, backgrounded or killed: the switch reflects
  /// what the user chose, and [ensureWanted] restores the node to match.
  static Future<bool> wanted() async =>
      (await SharedPreferences.getInstance()).getBool(_wantedKey) ?? false;

  static Future<void> setWanted(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(_wantedKey, on);

  /// Start the node if the user wants it and it is not running. Called when
  /// the app starts and whenever it returns to the foreground.
  static Future<void> ensureWanted() async {
    if (await wanted() && await supported() && !await isRunning()) {
      await start();
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException {
      // Nothing useful to do: the process is either already gone or will be
      // reaped with the app.
    }
  }

  /// Loopback URL and the credential generated on this device at first start.
  /// Null until the node has run at least once.
  static Future<({String url, String user, String password})?> rpcInfo() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('rpcInfo');
      if (m == null) return null;
      return (
        url: m['url'] as String,
        user: m['user'] as String,
        password: m['password'] as String,
      );
    } on PlatformException {
      return null;
    }
  }
}
