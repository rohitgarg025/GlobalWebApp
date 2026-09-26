import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi_web;

/// Web: the official Google Identity Services button. Sign-ins land in
/// AuthService via GoogleSignIn.onCurrentUserChanged.
Widget buildGoogleSignInButton() {
  return gsi_web.renderButton(
    configuration: gsi_web.GSIButtonConfiguration(
      theme: gsi_web.GSIButtonTheme.outline,
      size: gsi_web.GSIButtonSize.large,
      shape: gsi_web.GSIButtonShape.pill,
    ),
  );
}
