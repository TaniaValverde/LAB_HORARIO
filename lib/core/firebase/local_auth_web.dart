import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// firebase_auth_web 6.3.0 restores this setting before awaiting Auth's
/// persisted session. Setting it only after Firebase.initializeApp can be too
/// late: a cached session may already have started a production token request.
void prepareLocalAuth(bool useEmulators) {
  const key = '[DEFAULT]-firebaseEmulatorOrigin';
  if (useEmulators && kDebugMode && web.window.location.hostname == 'localhost') {
    web.window.sessionStorage.setItem(key, 'http://127.0.0.1:9099');
  } else {
    web.window.sessionStorage.removeItem(key);
  }
}
