import 'package:cloud_functions/cloud_functions.dart';

/// Small boundary that keeps callable operations testable without Firebase.
abstract interface class CallableFunctionClient {
  Future<Object?> call(String name, Map<String, Object?> data);
}

class FirebaseCallableFunctionClient implements CallableFunctionClient {
  FirebaseCallableFunctionClient({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(String name, Map<String, Object?> data) async {
    final result = await _functions.httpsCallable(name).call(data);
    return result.data;
  }
}
