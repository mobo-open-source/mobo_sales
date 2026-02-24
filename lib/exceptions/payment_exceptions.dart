abstract class PaymentException implements Exception {
  final String message;
  final String? code;
  final Map<String, dynamic>? details;

  const PaymentException(this.message, {this.code, this.details});

  @override
  String toString() => 'PaymentException: $message';
}

class NetworkException extends PaymentException {
  final NetworkErrorType type;

  const NetworkException(super.message, this.type, {super.code, super.details});

  @override
  String toString() =>
      'NetworkException(${type.toString().split('.').last}): $message';
}

enum NetworkErrorType {
  connectionTimeout,
  serverUnavailable,
  noConnection,
  authenticationFailed,
  rateLimited,
  unknown,
}

class ValidationException extends PaymentException {
  final String? field;
  final String userMessage;

  const ValidationException(
    super.message,
    this.userMessage, {
    this.field,
    super.code,
    super.details,
  });

  @override
  String toString() =>
      'ValidationException${field != null ? '($field)' : ''}: $userMessage';
}

class SyncException extends PaymentException {
  final SyncErrorType type;

  const SyncException(super.message, this.type, {super.code, super.details});

  @override
  String toString() =>
      'SyncException(${type.toString().split('.').last}): $message';
}

enum SyncErrorType {
  statusConflict,
  concurrentModification,
  dataInconsistency,
  versionMismatch,
  unknown,
}

class ReconciliationException extends PaymentException {
  final ReconciliationErrorType type;

  const ReconciliationException(
    super.message,
    this.type, {
    super.code,
    super.details,
  });

  @override
  String toString() =>
      'ReconciliationException(${type.toString().split('.').last}): $message';
}

enum ReconciliationErrorType {
  autoReconcileFailed,
  missingReconciliationData,
  accountConfigurationError,
  insufficientPermissions,
  unknown,
}

class OdooApiException extends PaymentException {
  final int statusCode;
  final String? endpoint;

  const OdooApiException(
    super.message,
    this.statusCode, {
    this.endpoint,
    super.code,
    super.details,
  });

  @override
  String toString() =>
      'OdooApiException($statusCode${endpoint != null ? ' - $endpoint' : ''}): $message';
}

class BusinessRuleException extends PaymentException {
  final String rule;

  const BusinessRuleException(
    super.message,
    this.rule, {
    super.code,
    super.details,
  });

  @override
  String toString() => 'BusinessRuleException($rule): $message';
}

class PaymentProcessingException extends PaymentException {
  final PaymentProcessingErrorType type;

  const PaymentProcessingException(
    super.message,
    this.type, {
    super.code,
    super.details,
  });

  @override
  String toString() =>
      'PaymentProcessingException(${type.toString().split('.').last}): $message';
}

enum PaymentProcessingErrorType {
  insufficientFunds,
  paymentMethodUnavailable,
  amountExceedsLimit,
  currencyMismatch,
  paymentDeclined,
  unknown,
}

class PaymentConfigurationException extends PaymentException {
  final String configKey;

  const PaymentConfigurationException(
    super.message,
    this.configKey, {
    super.code,
    super.details,
  });

  @override
  String toString() => 'PaymentConfigurationException($configKey): $message';
}

class PaymentSecurityException extends PaymentException {
  final SecurityViolationType violationType;

  const PaymentSecurityException(
    super.message,
    this.violationType, {
    super.code,
    super.details,
  });

  @override
  String toString() =>
      'PaymentSecurityException(${violationType.toString().split('.').last}): $message';
}

enum SecurityViolationType {
  insufficientPermissions,
  sessionExpired,
  invalidToken,
  suspiciousActivity,
  unknown,
}
