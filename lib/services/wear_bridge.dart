import 'dart:async';

import 'package:flutter/services.dart';

/// Thin Dart wrapper around the native [WearBridgePlugin] which provides access
/// to the Google Wearable Data Layer API (MessageClient, DataClient, etc.).
///
/// All methods are no-ops / return safe defaults on non-Android platforms.
class WearBridge {
  WearBridge._();
  static final WearBridge instance = WearBridge._();

  static const _method = MethodChannel('com.jhelum.gyawun/wear_bridge');
  static const _events = EventChannel('com.jhelum.gyawun/wear_bridge_events');

  Stream<Map<String, dynamic>>? _eventStream;

  /// A broadcast stream of events from the Wearable Data Layer.
  ///
  /// Each event is a `Map` with a `"type"` key (`"message"` or `"data"`) and
  /// associated fields:
  /// - **message**: `path`, `sourceNodeId`, `data` (UTF-8 string)
  /// - **data**: `path`, `data` (JSON string from DataMap)
  Stream<Map<String, dynamic>> get events {
    _eventStream ??= _events
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .asBroadcastStream();
    return _eventStream!;
  }

  /// Send a message to a specific node (or broadcast to all if [targetNodeId]
  /// is null).
  Future<bool> sendMessage(
    String path, {
    String data = '',
    String? targetNodeId,
  }) async {
    final result = await _method.invokeMethod<bool>('sendMessage', {
      'path': path,
      'data': data,
      'targetNodeId': targetNodeId,
    });
    return result ?? false;
  }

  /// Sync data via DataClient (persistent, survives disconnections).
  Future<bool> syncData(
    String path, {
    required String json,
    bool urgent = false,
  }) async {
    final result = await _method.invokeMethod<bool>('syncData', {
      'path': path,
      'json': json,
      'urgent': urgent,
    });
    return result ?? false;
  }

  /// Get all connected Wear OS nodes.
  /// Returns a list of `{id: String, name: String}`.
  Future<List<Map<String, String>>> getConnectedNodes() async {
    final result = await _method.invokeMethod<List>('getConnectedNodes');
    if (result == null) return [];
    return result
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  /// Find nodes that advertise the given [capability].
  Future<List<Map<String, String>>> findCapableNodes(String capability) async {
    final result = await _method.invokeMethod<List>('findCapableNodes', {
      'capability': capability,
    });
    if (result == null) return [];
    return result
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  /// Check if the Gyawun Wear app is installed on any connected watch.
  Future<bool> isWearAppInstalled() async {
    final result = await _method.invokeMethod<bool>('isWearAppInstalled');
    return result ?? false;
  }

  /// Open the Play Store on the watch for this app.
  Future<bool> openPlayStoreOnWatch() async {
    final result = await _method.invokeMethod<bool>('openPlayStoreOnWatch');
    return result ?? false;
  }

  /// Open the Wear OS / Galaxy Wearable companion app on this phone.
  Future<bool> openWearOsCompanion() async {
    final result = await _method.invokeMethod<bool>('openWearOsCompanion');
    return result ?? false;
  }
}
