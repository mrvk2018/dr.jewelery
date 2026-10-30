package com.jewelrysunlight.jewelry_sunlight_store

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRINTER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "printRawData" -> {
                        val payload = call.argument<String>("payload")
                        if (payload == null) {
                            result.error("INVALID_ARGS", "payload is required", null)
                            return@setMethodCallHandler
                        }
                        dispatchRawPrintPayload(payload)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Заглушка транспорта: Flutter уже сформировал TSPL/ZPL; здесь — доставка на принтер.
     *
     * TODO (Bluetooth): paired device + RFCOMM / SPP UUID, OutputStream.write(payload bytes).
     * TODO (Network RAW): TCP Socket(printerHost, 9100), flush, close — стандарт ESC/POS & label printers.
     */
    private fun dispatchRawPrintPayload(payload: String) {
        Log.d(TAG, "printRawData received, length=${payload.length}")
        Log.d(TAG, payload)
    }

    companion object {
        private const val TAG = "DrJewelryPrinter"
        private const val PRINTER_CHANNEL = "com.drjewelry.pos/printer"
    }
}
