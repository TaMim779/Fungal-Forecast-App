import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/state/app_state.dart';
import '../../l10n/app_localizations.dart';

const _countries = {
  'BD': 'Bangladesh',
  'IN': 'India',
  'PK': 'Pakistan',
  'NP': 'Nepal',
  'KE': 'Kenya',
  'NG': 'Nigeria',
  'TZ': 'Tanzania',
  'UG': 'Uganda',
  'ID': 'Indonesia',
  'VN': 'Vietnam',
  'PH': 'Philippines',
};

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String _country = 'BD';
  String _crop = 'rice';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    try {
      if (_register) {
        await app.register(
          name: _name.text,
          phone: _phone.text,
          password: _password.text,
          country: _country,
          crop: _crop,
          fieldSizeHa: 1,
        );
      } else {
        await app.login(phone: _phone.text, password: _password.text);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final app = context.watch<AppState>();
    final t = Theme.of(context);
    final crops = app.catalog.crops;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
              children: [
                Icon(Icons.eco, size: 48, color: t.colorScheme.primary),
                const SizedBox(height: 12),
                Text(l.appTitle, style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  _register ? l.registerSubtitle : l.loginSubtitle,
                  style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(l.loginTitle), icon: const Icon(Icons.login)),
                    ButtonSegment(value: true, label: Text(l.registerTitle), icon: const Icon(Icons.person_add_alt_1)),
                  ],
                  selected: {_register},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() {
                            _register = s.first;
                            _error = null;
                          }),
                ),
                const SizedBox(height: 20),
                Form(
                  key: _form,
                  child: Column(children: [
                    if (_register) ...[
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(labelText: l.name, prefixIcon: const Icon(Icons.badge_outlined)),
                        validator: (v) => (v == null || v.trim().isEmpty) ? l.requiredField : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: l.phone, prefixIcon: const Icon(Icons.phone_outlined)),
                      validator: (v) => (v == null || v.trim().length < 6) ? l.requiredField : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: l.password,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 4) ? l.passwordTooShort : null,
                    ),
                    if (_register) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirm,
                        obscureText: _obscure,
                        decoration: InputDecoration(labelText: l.confirmPassword, prefixIcon: const Icon(Icons.lock_outline)),
                        validator: (v) => v == _password.text ? null : l.passwordMismatch,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _country,
                        decoration: InputDecoration(labelText: l.country, prefixIcon: const Icon(Icons.flag_outlined)),
                        items: [for (final e in _countries.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                        onChanged: (v) => setState(() => _country = v ?? _country),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: crops.any((c) => c.id == _crop) ? _crop : crops.firstOrNull?.id,
                        decoration: InputDecoration(labelText: l.crop, prefixIcon: const Icon(Icons.grass)),
                        items: [for (final c in crops) DropdownMenuItem(value: c.id, child: Text(c.name))],
                        onChanged: (v) => setState(() => _crop = v ?? _crop),
                      ),
                    ],
                  ]),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: t.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_register ? l.registerAction : l.loginAction),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _register = !_register;
                            _error = null;
                          }),
                  child: Text(_register ? l.switchToLogin : l.switchToRegister),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'en', label: Text('English')),
                    ButtonSegment(value: 'bn', label: Text('বাংলা')),
                    ButtonSegment(value: 'hi', label: Text('हिन्दी')),
                  ],
                  selected: {app.language},
                  onSelectionChanged: (s) => app.setLanguage(s.first),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
