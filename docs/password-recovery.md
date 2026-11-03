# Password recovery and administrator password changes

The mobile app supports `visionpark://auth/reset-password`. Android intent filters and the native callback channel already handle this destination. Opening an email on a laptop or a different phone cannot open an app running inside an emulator.

## Supabase configuration to verify

In **Authentication → URL Configuration → Redirect URLs**, allow the exact destinations in use:

- `visionpark://auth/reset-password`
- `http://localhost:3000/reset-password` for local administrator development
- `https://<your-admin-host>/reset-password` for the deployed administrator application

Keep existing confirmation redirects. Do not replace the shared Site URL with the mobile scheme. The reset email should use Supabase's `{{ .ConfirmationURL }}`; a custom template that hardcodes the Site URL can discard the requested destination. Do not add broad production wildcards. These project settings and email templates have **not** been inspected or changed by this implementation.

Official references: [Supabase password recovery](https://supabase.com/docs/guides/auth/passwords), [redirect configuration](https://supabase.com/docs/guides/auth/redirect-urls), [native deep links](https://supabase.com/docs/guides/auth/native-mobile-deep-linking).

## Test on an emulator

1. Run the updated mobile app and request a fresh reset email from **Forgot Password**.
2. Either open that email inside the emulator, or copy the reset button's original link address from the email on your laptop. Copy it **before clicking it**; links are single use.
3. In the requesting emulator, paste it into **Reset Link**, then select **Continue with Reset Link**. The normal emulator clipboard paste is sufficient. Never paste a real reset link into logs, terminals, screenshots or chat.
4. Verify the existing authenticator when prompted, choose a new password, then sign in again. MFA remains enrolled.

The pasted-link fallback accepts only the configured Supabase Auth verification URL with recovery purpose and the mobile destination. It follows no HTTP redirect chain: it reads Auth's redirect and exchanges its code using the requesting app's stored PKCE verifier. Foreign hosts, signup links, duplicate parameters and foreign redirect destinations are rejected. A copied native callback URL is also accepted. Email tracking wrappers are deliberately unsupported; use the original Supabase link.

If a link has already been clicked elsewhere or expired, explicitly start over after the cooldown and request a fresh link. Reinstalling the app or clearing its storage removes its verifier, so request another link. Mail delivery restrictions and provider rate limits can still prevent a message from arriving.

## Administrator screens

- **Forgot Password?** on Sign In opens `/forgot-password`. Request and open the email in the same browser/profile; PKCE binds the reset to that browser.
- `/reset-password` exchanges the email code into separate, short-lived HTTP-only recovery cookies. It requires a current approved, active administrator profile and Supabase's signed recovery authentication method. Existing verified MFA must be completed before the password update. Recovery cannot enroll/remove an authenticator or open administrator pages.
- **Administrator account menu → Change Password** opens `/change-password`. It requires the normal administrator `aal2` session and the current password. A temporary password check never replaces the browser's application cookies; the native update uses the original `aal2` token and `current_password`.
- Recovery completion clears/revokes its isolated session and returns to Sign In. Role, approval, application records and MFA factors are not edited.

No account-existence or upstream email-delivery errors are exposed. Passwords, callback codes and session tokens are not returned in JSON or stored in browser local storage. Requests have origin/body checks, coordinated browser mutations and no automatic password-write retries. A lost update response is reported as unconfirmed.

## Verification and remaining manual checks

Automated tests use offline Auth HTTP fixtures, not a real Supabase deployment. Run:

```powershell
cd web-app
npm.cmd run lint
node --test tests/mfa.test.mjs tests/password.test.mjs
cd ../mobile
flutter test --no-pub test/mfa_flow_test.dart
dart analyze lib test
```

Coverage includes native PKCE and MFA contracts; untrusted/duplicate/foreign links; missing verifier; recovery session isolation; wrong/expired authenticator codes; recovery session substitution; approval/role rejection; current-password checks; password policy; origin rejection; cooldown/restart behavior; expired sessions/outages; and the mobile paste-link screen.

Before declaring the feature operational, manually check:

1. Fresh email delivery and redirect for mobile, emulator paste, and web using the actual project configuration. Test warm/cold app launch, application restart while awaiting email, and browser reload on the reset page.
2. Used/expired links, another browser/device without the verifier, existing signed-in accounts, incorrect TOTP, lost authenticators and interrupted recovery. None should disable MFA or overwrite a signed-in application's identity. Operators must use the established identity-verified recovery procedure for lost authenticators.
3. Both enrolled and not-yet-enrolled existing accounts. After reset, old passwords fail; new passwords sign in; existing MFA/approval requirements still apply. Check any configured secure-password-change reauthentication and single-session settings; their live behavior has not been verified.
4. Change Password with wrong/current/same/weak passwords, network interruption, an expired session, multiple tabs and sign-out in another tab. Confirm any successful update with a fresh sign-in; do not automatically repeat an ambiguous write.
5. Regression: email confirmation → administrator approval → driver login/MFA → vehicle approval → camera/service ANPR entry → allocation/navigation → exit → payment/receipt → completed session/history. Check administrator overview, approvals, tenants, vehicles, parking configuration, sessions and payments, plus refresh/restoration/logout on both applications.

There are no database/RLS, ANPR, allocation, navigation or payment changes in this password work. Compilation and fixture tests do not establish live email delivery, live MFA enforcement or the full parking workflow. Browser screenshots/manual visual review also remain unverified if computer-use tooling is unavailable.
