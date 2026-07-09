import 'package:flutter/material.dart';

/// A thin TextFormField wrapper pre-wired to the app theme's
/// InputDecorationTheme -- screens just pass an errorText, never construct
/// decoration inline.
class SpotifyTextField extends StatefulWidget {
  const SpotifyTextField({
    super.key,
    required this.labelText,
    required this.onChanged,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.enabled = true,
    this.helperText,
  });

  final String labelText;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool enabled;
  final String? helperText;

  @override
  State<SpotifyTextField> createState() => _SpotifyTextFieldState();
}

class _SpotifyTextFieldState extends State<SpotifyTextField> {
  bool _obscured = true;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: widget.onChanged,
      obscureText: _obscured,
      keyboardType: widget.keyboardType,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: widget.labelText,
        errorText: widget.errorText,
        helperText: widget.errorText == null ? widget.helperText : null,
        suffixIcon: widget.obscureText
            ? IconButton(
                icon: Icon(_obscured ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
      ),
    );
  }
}
