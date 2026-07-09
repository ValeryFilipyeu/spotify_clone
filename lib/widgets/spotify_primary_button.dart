import 'package:flutter/material.dart';

/// A full-width green pill button standardizing the loading-spinner swap
/// used by every submit button in the auth flow.
class SpotifyPrimaryButton extends StatelessWidget {
  const SpotifyPrimaryButton({super.key, required this.label, required this.onPressed, this.isLoading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
            )
          : Text(label),
    );
  }
}
