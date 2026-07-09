final RegExp _digitRegExp = RegExp(r'\d');

/// Demo-grade UX validation (not RFC-5322/password-strength-meter-grade) --
/// intentionally simple so "validation lives outside the widget" is easy to
/// see and test, rather than the validator itself becoming the focus.
String? validatePassword(String password) {
  if (password.isEmpty) return 'Password is required.';
  if (password.length < 8) return 'Password must be at least 8 characters.';
  if (!_digitRegExp.hasMatch(password)) return 'Password must contain at least one number.';
  return null;
}

bool isValidPassword(String password) => validatePassword(password) == null;
