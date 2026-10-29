package app.wattxchange.wattx_wallet

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity, not FlutterActivity: local_auth shows its prompt
// through a FragmentActivity and fails instantly ("no_fragment_activity")
// on a plain FlutterActivity, so the biometric unlock never appeared.
class MainActivity : FlutterFragmentActivity() {

    private val channel = "app.wattxchange.wattx_wallet/node"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Reported honestly: a device with no bundled binary must
                    // see the option hidden rather than offered and broken.
                    "supported" -> result.success(FullNode.supported(applicationContext))

                    "isRunning" -> result.success(FullNode.isRunning)

                    "start" -> {
                        // Start here first so a node that cannot run is reported
                        // to the user, then hand it to the foreground service,
                        // which keeps it alive while the phone is locked.
                        val err = FullNode.start(applicationContext)
                        if (err == null) {
                            FullNodeService.start(applicationContext)
                            result.success(true)
                        } else {
                            result.error("start_failed", err, null)
                        }
                    }

                    "stop" -> {
                        FullNodeService.stop(applicationContext)
                        FullNode.stop()
                        result.success(true)
                    }

                    // The RPC credential is generated on the device at first
                    // start and never leaves it; Dart needs it to talk to the
                    // loopback endpoint.
                    "rpcInfo" -> {
                        val creds = FullNode.credentials()
                        if (creds == null) result.success(null)
                        else result.success(
                            mapOf(
                                "url" to "http://127.0.0.1:${FullNode.RPC_PORT}/",
                                "user" to creds.first,
                                "password" to creds.second,
                            )
                        )
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // No onDestroy() stop: Android destroys this activity routinely in the
    // background, and stopping the node there is what switched full-node mode
    // off whenever the phone locked. FullNodeService owns the node's lifetime
    // and stops it only when the user turns full-node mode off.
}
