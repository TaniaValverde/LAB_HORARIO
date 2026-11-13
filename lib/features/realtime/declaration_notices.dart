import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../declaration/domain/entities/declaration.dart';

/// Displays real-time notifications about declaration status changes.
///
/// Connects to the Socket.IO server using the authenticated user's Firebase
/// ID token. Incoming events are validated and deduplicated before the
/// notification is displayed and [onChanged] is invoked.
///
/// If the connection is interrupted, the widget schedules automatic
/// reconnection attempts. Real-time notifications are disabled when
/// [url] is empty.
class DeclarationNotices extends StatefulWidget {
  const DeclarationNotices({
    super.key,
    required this.user,
    this.onChanged,
    this.urlOverride,
  });

  final User user;
  final VoidCallback? onChanged;
  final String? urlOverride;

  /// Socket.IO server URL provided through the `SOCKET_URL` environment
  /// configuration.
  static const url = String.fromEnvironment('SOCKET_URL');

  @override
  State<DeclarationNotices> createState() => _DeclarationNoticesState();
}

class _DeclarationNoticesState extends State<DeclarationNotices> {
  io.Socket? _socket;
  Timer? _retry;
  bool _connected = false;
  bool _disposed = false;
  int _attempt = 0;
  String? _notice;
  final _seen = <String>{};

  /// Initializes the widget and starts the connection when a server URL
  /// is configured.
  @override
  void initState() {
    super.initState();
    if (_url.isNotEmpty) _connect();
  }

  String get _url => widget.urlOverride ?? DeclarationNotices.url;

  /// Establishes an authenticated Socket.IO connection.
  ///
  /// Retrieves a fresh Firebase ID token and supplies it to the server
  /// during connection setup. Registers handlers for connection events
  /// and declaration changes. Failed connections are handled through
  /// the reconnection scheduler.
  Future<void> _connect() async {
    try {
      final token = await widget.user.getIdToken(true);
      if (_disposed) return;
      if (token == null) {
        _schedule();
        return;
      }
      _socket?.dispose();
      final socket = io.io(
        _url,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .disableReconnection()
            .enableForceNew()
            .setAuth({'token': token})
            .build(),
      );
      _socket = socket;
      socket.onConnect((_) {
        if (_disposed) return;
        _retry?.cancel();
        _attempt = 0;
        setState(() => _connected = true);
      });
      socket.onDisconnect((_) => _schedule());
      socket.onConnectError((_) => _schedule());
      socket.on('declaration:changed', (dynamic data) {
        final message = parseDeclarationNotice(data);
        if (_disposed || message == null) return;
        final key = '${data['id']}:${data['revision']}:${data['status']}';
        if (!_seen.add(key)) return;
        if (_seen.length > 100) _seen.remove(_seen.first);
        setState(() => _notice = message);
        widget.onChanged?.call();
      });
      socket.connect();
    } catch (_) {
      _schedule();
    }
  }

  /// Schedules a reconnection attempt after a connection failure.
  ///
  /// Uses increasing delays of 2, 5, 10 and 30 seconds. Prevents duplicate
  /// retry timers and stops scheduling when the widget has been disposed.
  void _schedule() {
    if (_disposed || (_retry?.isActive ?? false)) return;
    setState(() => _connected = false);
    final seconds = [2, 5, 10, 30][_attempt.clamp(0, 3)];
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  /// Cancels pending retries and releases the Socket.IO connection.
  ///
  /// Marks the state as disposed so asynchronous operations and event
  /// handlers can avoid updating the widget after its lifecycle ends.
  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  /// Builds the notification card showing the connection status and
  /// the most recent declaration notice.
  ///
  /// Returns an empty widget when no Socket.IO server URL is configured.
  @override
  Widget build(BuildContext context) {
    if (_url.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: Icon(
          _connected ? Icons.notifications_active : Icons.notifications_paused,
        ),
        title: Text(_connected ? 'Avisos conectados' : 'Reconectando avisos…'),
        subtitle: Text(
          _connected
              ? (_notice ??
                    'Los cambios de estado aparecerán aquí. Puede continuar trabajando.')
              : 'Los avisos en tiempo real están temporalmente desconectados. Intentaremos reconectar automáticamente. Puede consultar el estado actual con Actualizar lista.',
        ),
      ),
    );
  }
}

/// Validates a declaration-change event and converts it into a display message.
///
/// Returns null when the payload does not contain a valid declaration ID,
/// version, revision or recognized status. Otherwise, returns a message
/// identifying the declaration and its current status.
String? parseDeclarationNotice(dynamic data) {
  if (data is! Map ||
      data['id'] is! String ||
      (data['id'] as String).isEmpty ||
      data['version'] is! int ||
      data['version'] < 1 ||
      data['revision'] is! int ||
      data['revision'] < 0) {
    return null;
  }
  final status = DeclarationStatus.values
      .where((s) => s.name == data['status'])
      .firstOrNull;
  if (status == null) return null;
  return 'Declaración ${data['id']} · versión ${data['version']}: ${status.label}. Consulte la lista para ver el estado actual.';
}
