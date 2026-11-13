package cr.ac.ucr.declarahorario

import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "declara_horario/platform")
            .setMethodCallHandler { call, result ->
                if (call.method == "isAndroidEmulator") {
                    result.success(
                        Build.FINGERPRINT.startsWith("generic") ||
                            Build.FINGERPRINT.lowercase().contains("emulator") ||
                            Build.MODEL.contains("Emulator") ||
                            Build.HARDWARE.contains("goldfish") ||
                            Build.HARDWARE.contains("ranchu")
                    )
                } else {
                    result.notImplemented()
                }
            }
    }
}
