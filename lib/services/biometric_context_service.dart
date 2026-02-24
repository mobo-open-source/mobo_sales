class BiometricContextService {
  static final BiometricContextService _instance =
      BiometricContextService._internal();
  factory BiometricContextService() => _instance;
  BiometricContextService._internal();

  bool _isAccountOperation = false;
  DateTime? _lastAccountOperationTime;
  static const Duration _accountOperationGracePeriod = Duration(seconds: 3);

  bool get isAccountOperation => _isAccountOperation;

  bool get shouldSkipBiometric {
    if (_isAccountOperation) {
      return true;
    }

    if (_lastAccountOperationTime != null) {
      final timeSinceOperation = DateTime.now().difference(
        _lastAccountOperationTime!,
      );
      if (timeSinceOperation < _accountOperationGracePeriod) {
        return true;
      }
    }

    return false;
  }

  void startAccountOperation(String operation) {
    _isAccountOperation = true;
    _lastAccountOperationTime = DateTime.now();
  }

  void endAccountOperation(String operation) {
    _isAccountOperation = false;
    _lastAccountOperationTime = DateTime.now();
  }

  void reset() {
    _isAccountOperation = false;
    _lastAccountOperationTime = null;
  }
}
