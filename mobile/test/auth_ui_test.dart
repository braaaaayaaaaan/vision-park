import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpark_mobile/app/vision_park_app.dart';
import 'package:visionpark_mobile/features/auth/login_screen.dart';
import 'package:visionpark_mobile/features/auth/registration_screen.dart';
import 'package:visionpark_mobile/data/repositories/auth_repository.dart';

import 'support/auth_fakes.dart';

Finder field(String label) => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
  matching: find.byType(TextFormField),
);

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late FakeAuthRepository repo;
  setUp(() => repo = FakeAuthRepository());
  tearDown(() => repo.events.close());
  testWidgets(
    'login and registration navigate both ways without entering driver tabs',
    (tester) async {
      await tester.pumpWidget(
        VisionParkApp(repository: repo, initialRoute: '/login'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tapVisible(tester, find.text('Create an Account'));
      expect(find.byType(RegistrationScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tapVisible(tester, find.text('Create an Account'));
      await tapVisible(tester, find.text('Back to Login'));
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('direct registration preview returns to login', (tester) async {
    await tester.pumpWidget(
      VisionParkApp(repository: repo, initialRoute: '/register'),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Back to Login'));
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets(
    'login validates fields, toggles password and opens approved dashboard',
    (tester) async {
      await tester.pumpWidget(
        VisionParkApp(repository: repo, initialRoute: '/login'),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Login'));
      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      await tester.enterText(field('Email'), 'invalid');
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tester.enterText(field('Email'), 'driver@example.com');
      await tester.enterText(field('Password'), 'example-password');
      final editable = find.descendant(
        of: field('Password'),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).obscureText, isTrue);
      await tapVisible(tester, find.byTooltip('Show Password'));
      expect(tester.widget<EditableText>(editable).obscureText, isFalse);
      await tapVisible(tester, find.byTooltip('Hide Password'));
      expect(tester.widget<EditableText>(editable).obscureText, isTrue);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Login'));
      expect(repo.signedInEmail, 'driver@example.com');
      expect(repo.profileCalls, 1);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Account'),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Sign Out'));
      expect(repo.signOutCalls, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets(
    'registration validates inputs, sends company ID and asks user to confirm email',
    (tester) async {
      await tester.pumpWidget(
        VisionParkApp(repository: repo, initialRoute: '/register'),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Register'));
      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(find.text('Confirm your password.'), findsOneWidget);
      expect(find.text('Select a company.'), findsOneWidget);
      await tester.enterText(field('Full Name'), '   ');
      await tester.enterText(field('Email'), 'bad-address');
      await tester.enterText(field('Password'), 'short');
      await tester.enterText(field('Confirm Password'), 'different');
      await tester.pump();
      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Passwords must match.'), findsOneWidget);
      expect(find.text('Use 12 to 128 characters.'), findsNWidgets(2));
      await tester.enterText(field('Full Name'), 'Example Driver');
      await tester.enterText(field('Email'), 'driver@example.com');
      await tester.enterText(field('Password'), 'example-password');
      await tester.enterText(field('Confirm Password'), 'example-password');
      await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.text('Second Company').last);
      await tester.pumpAndSettle();
      repo.registrationFailure = const AuthFailure(
        'Registration service unavailable.',
      );
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Register'));
      expect(find.text('Registration service unavailable.'), findsOneWidget);
      expect(find.byType(RegistrationScreen), findsOneWidget);
      expect(repo.registration, isNull);
      repo.registrationFailure = null;
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Register'));
      expect(repo.registration?['tenant_id'], 'company-2');
      expect(repo.registration?['full_name'], 'Example Driver');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.textContaining('Check your email and confirm it'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  for (final (profile, message) in [
    (
      const AuthProfile(
        id: 'driver-id',
        role: 'driver',
        approvalStatus: 'pending',
        isActive: false,
      ),
      'awaiting administrator approval',
    ),
    (
      const AuthProfile(
        id: 'driver-id',
        role: 'driver',
        approvalStatus: 'rejected',
        isActive: false,
      ),
      'registration was rejected',
    ),
    (
      const AuthProfile(
        id: 'driver-id',
        role: 'driver',
        approvalStatus: 'approved',
        isActive: false,
      ),
      'account is inactive',
    ),
    (
      const AuthProfile(
        id: 'driver-id',
        role: 'admin',
        approvalStatus: 'approved',
        isActive: true,
      ),
      'Administrator accounts cannot',
    ),
  ]) {
    testWidgets(
      'restored ${profile.role}/${profile.approvalStatus} is blocked',
      (tester) async {
        repo.hasSession = true;
        repo.currentProfile = profile;
        await tester.pumpWidget(VisionParkApp(repository: repo));
        await tester.pumpAndSettle();
        expect(find.textContaining(message), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
      },
    );
  }

  testWidgets(
    'verified identity without profile completes registration and stays pending',
    (tester) async {
      repo.hasSession = true;
      repo.profileFailure = const AuthFailure(
        'Complete your driver registration.',
        missingProfile: true,
      );
      await tester.pumpWidget(VisionParkApp(repository: repo));
      await tester.pumpAndSettle();
      expect(field('Password'), findsNothing);
      expect(field('Email'), findsNothing);
      await tester.enterText(field('Full Name'), 'Verified Driver');
      await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.text('Company From Backend').last);
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Complete Registration'),
      );
      expect(repo.completion, {
        'full_name': 'Verified Driver',
        'tenant_id': 'company-id',
      });
      expect(
        find.textContaining('awaiting administrator approval'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('failed login stays on login; failed company load can retry', (
    tester,
  ) async {
    repo.loginFailure = const AuthFailure('Check your email and password.');
    await tester.pumpWidget(VisionParkApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.enterText(field('Email'), 'driver@example.com');
    await tester.enterText(field('Password'), 'wrong-password');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Login'));
    expect(find.text('Check your email and password.'), findsOneWidget);
    repo.companiesFailure = const AuthFailure('Company service unavailable.');
    await tapVisible(tester, find.text('Create an Account'));
    expect(find.text('Company service unavailable.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    repo.companiesFailure = null;
    await tapVisible(tester, find.text('Retry Companies'));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('missing configuration never exposes driver dashboard', (
    tester,
  ) async {
    await tester.pumpWidget(const VisionParkApp(initialRoute: '/driver'));
    await tester.pumpAndSettle();
    expect(find.text('Authentication Unavailable'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  for (final route in ['/login', '/register']) {
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(900, 600),
    ]) {
      testWidgets('$route fits $size with large text and keyboard', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          VisionParkApp(repository: repo, initialRoute: route),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(field('Email'));
        await tester.tap(field('Email'));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.byType(FilledButton));
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        expect(find.text('Enter your email.'), findsOneWidget);
      });
    }
  }
}
