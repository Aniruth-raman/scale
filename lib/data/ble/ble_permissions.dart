import 'dart:io';

import 'package:flutter/services.dart';

/// Runtime permission boundary for BLE. Android needs SCAN/CONNECT on 12+ and
/// fine location on older releases; iOS prompts through CoreBluetooth.
abstract class BlePermissionRequester {
  Future<bool> request();
}

/// Small platform bridge for system Bluetooth UI. It never enables Bluetooth
/// silently; Android shows its own prompt and the user decides.
abstract class BleSystemActions {
  Future<void> requestEnableBluetooth();
}

class MethodChannelBleSystemActions implements BleSystemActions {
  const MethodChannelBleSystemActions();

  static const _channel = MethodChannel('com.aniruth/ble_permissions');

  @override
  Future<void> requestEnableBluetooth() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('enableBluetooth');
    } on PlatformException {
      // The button is a convenience; the user can still use system settings.
    } on MissingPluginException {
      // Nothing to open on this platform.
    }
  }
}

class MethodChannelBlePermissionRequester implements BlePermissionRequester {
  const MethodChannelBlePermissionRequester();

  static const _channel = MethodChannel('com.aniruth/ble_permissions');

  @override
  Future<bool> request() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('request') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
