import 'package:equatable/equatable.dart';

/// A signed-in user. There is no real backend, so this intentionally carries
/// only what the UI needs (the email shown on Home) rather than inventing
/// fields like a fake `uid` that nothing in this app reads.
class AppUser extends Equatable {
  const AppUser(this.email);

  final String email;

  @override
  List<Object?> get props => [email];
}
