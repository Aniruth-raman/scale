package com.aniruth.scale

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.aniruth/ble_permissions",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "request" -> requestBlePermissions(result)
                "enableBluetooth" -> requestEnableBluetooth(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requestEnableBluetooth(result: MethodChannel.Result) {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = manager?.adapter
        if (adapter == null) {
            result.success(false)
            return
        }
        if (adapter.isEnabled) {
            result.success(true)
            return
        }
        try {
            startActivityForResult(
                Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE),
                REQUEST_ENABLE_BLUETOOTH,
            )
            result.success(true)
        } catch (error: SecurityException) {
            openBluetoothSettings(result)
        } catch (error: Exception) {
            openBluetoothSettings(result)
        }
    }

    private fun openBluetoothSettings(result: MethodChannel.Result) {
        try {
            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            result.success(true)
        } catch (error: Exception) {
            result.success(false)
        }
    }

    private fun requiredPermissions(): Array<String> {
        // minSdk is 31; the legacy location path is intentionally absent.
        return arrayOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
        )
    }

    private fun requestBlePermissions(result: MethodChannel.Result) {
        val missing = requiredPermissions().filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }
        pendingPermissionResult = result
        requestPermissions(missing.toTypedArray(), REQUEST_BLE_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_BLE_PERMISSIONS) return
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    companion object {
        private const val REQUEST_BLE_PERMISSIONS = 4127
        private const val REQUEST_ENABLE_BLUETOOTH = 4128
    }
}
