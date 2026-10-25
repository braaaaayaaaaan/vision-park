import 'package:flutter/material.dart';

Future<bool> confirmAccountAction(
  BuildContext context, {
  required bool signOut,
}) async {
  final color = signOut
      ? Theme.of(context).colorScheme.error
      : Theme.of(context).colorScheme.primary;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          constraints: const BoxConstraints(maxWidth: 400),
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Icon(
            signOut ? Icons.logout_rounded : Icons.lock_outline_rounded,
            color: color,
            size: 24,
          ),
          title: Text(signOut ? 'Sign Out?' : 'Change Password?'),
          content: Text(
            signOut
                ? 'Are you sure you want to sign out of VisionPark?'
                : 'Are you sure you want to update your account password?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: () => Navigator.pop(context, true),
              child: Text(signOut ? 'Sign Out' : 'Confirm Change'),
            ),
          ],
        ),
      ) ??
      false;
}
