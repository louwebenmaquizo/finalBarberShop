import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/api_config.dart';
import '../services/password_generator.dart';
import '../services/supabase_service_helpers.dart';

/// Lets an admin or manager give a customer who forgot their password a new
/// temporary one. The app has no password-reset email, so this replaces it.
void showResetCustomerPasswordDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const _ResetCustomerPasswordDialog(),
  );
}

class _ResetCustomerPasswordDialog extends StatefulWidget {
  const _ResetCustomerPasswordDialog();

  @override
  State<_ResetCustomerPasswordDialog> createState() =>
      _ResetCustomerPasswordDialogState();
}

class _ResetCustomerPasswordDialogState
    extends State<_ResetCustomerPasswordDialog> {
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;
  String? _newPassword;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter the email address the customer signs in with.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final password = generateTempPassword();
    try {
      final result = SupabaseServiceHelpers.asMap(
        await SupabaseConfig.client.rpc(
          'admin_reset_customer_password',
          params: {'p_email': email, 'p_new_password': password},
        ),
      );
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() => _newPassword = password);
      } else {
        setState(() => _error = result['message']?.toString() ?? 'Could not reset the password.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = SupabaseServiceHelpers.errorMessage(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _newPassword != null;
    return AlertDialog(
      title: Text(
        done ? 'Password reset' : "Reset a customer's password",
        style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: done
              ? [
                  Text(
                    'Give this temporary password to the customer. They can change it in '
                    'Settings > Change Password after logging in.',
                    style: GoogleFonts.manrope(),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    _newPassword!,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ]
              : [
                  Text(
                    'For customers who forgot their password. Staff passwords are changed '
                    'in the Employee screen.',
                    style: GoogleFonts.manrope(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: "Customer's email",
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _isSubmitting ? null : _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
        ),
      ),
      actions: done
          ? [
              TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: _newPassword!)),
                child: const Text('Copy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Reset password'),
              ),
            ],
    );
  }
}
