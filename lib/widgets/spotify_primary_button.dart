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
          ? SizedBox(
              height: 20,
              width: 20,
              // Without a semanticsLabel the spinner emits no node at all, and
              // since it replaces the only Text, a submitting button would be
              // announced as an unnamed disabled button. Keep the name, add the
              // state.
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.black,
                semanticsLabel: '$label, in progress',
              ),
            )
          : Text(label),
    );
  }
}
