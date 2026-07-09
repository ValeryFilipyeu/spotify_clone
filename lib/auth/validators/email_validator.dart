final RegExp _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Returns a user-facing error message, or null if [email] is valid.
/// Pure and unit-testable with no widget involved -- reused by both a
/// screen's TextFormField.validator (instant feedback) and each Cubit's
/// isEmailValid getter (the authoritative check before submitting).
String? validateEmail(String email) {
  final trimmed = email.trim();
  if (trimmed.isEmpty) return 'Email is required.';
  if (!_emailRegExp.hasMatch(trimmed)) return 'Enter a valid email address.';
  return null;
}

bool isValidEmail(String email) => validateEmail(email) == null;
