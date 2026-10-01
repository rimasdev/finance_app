import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final store = context.read<FolioStore>();
    setState(() => _busy = true);
    try {
      await store.login(_email.text, _password.text);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    final store = context.read<FolioStore>();
    setState(() => _busy = true);
    try {
      await store.signInWithGoogle();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apple() async {
    final store = context.read<FolioStore>();
    setState(() => _busy = true);
    try {
      await store.signInWithApple();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showApple = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
          children: [
            const SizedBox(height: 24),
            const Text(
              'TAKINGS',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 3, color: FolioColors.green),
            ),
            const SizedBox(height: 36),
            const Text(
              'Welcome',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in to continue',
              textAlign: TextAlign.center,
              style: TextStyle(color: FolioColors.muted, fontSize: 15),
            ),
            const SizedBox(height: 36),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Email'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_busy) _submit();
              },
              decoration: InputDecoration(
                hintText: 'Password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: FolioColors.muted,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            PrimaryButton(label: 'Sign in', busy: _busy, onPressed: _submit),
            const SizedBox(height: 22),
            const _OrDivider(),
            const SizedBox(height: 22),
            _SocialButton(
              label: 'Continue with Google',
              icon: const _GoogleMark(),
              onPressed: _busy ? null : _google,
            ),
            if (showApple) ...[
              const SizedBox(height: 12),
              _SocialButton(
                label: 'Continue with Apple',
                icon: const Icon(Icons.apple, color: FolioColors.green, size: 22),
                onPressed: _busy ? null : _apple,
              ),
            ],
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const RegisterScreen()),
                        );
                      },
                child: const Text(
                  'Register',
                  style: TextStyle(color: FolioColors.green, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final store = context.read<FolioStore>();
    setState(() => _busy = true);
    try {
      await store.register(_name.text, _email.text, _password.text);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    final store = context.read<FolioStore>();
    setState(() => _busy = true);
    try {
      await store.signInWithGoogle();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apple() async {
    final store = context.read<FolioStore>();
    setState(() => _busy = true);
    try {
      await store.signInWithApple();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showApple = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FolioColors.bg,
        leading: IconButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
          children: [
            const Text(
              'Create account',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign up to track your money',
              textAlign: TextAlign.center,
              style: TextStyle(color: FolioColors.muted, fontSize: 15),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_busy) _submit();
              },
              decoration: InputDecoration(
                hintText: 'Password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: FolioColors.muted,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Register', busy: _busy, onPressed: _submit),
            const SizedBox(height: 22),
            const _OrDivider(),
            const SizedBox(height: 22),
            _SocialButton(
              label: 'Continue with Google',
              icon: const _GoogleMark(),
              onPressed: _busy ? null : _google,
            ),
            if (showApple) ...[
              const SizedBox(height: 10),
              _SocialButton(
                label: 'Continue with Apple',
                icon: const Icon(Icons.apple, color: FolioColors.text, size: 22),
                onPressed: _busy ? null : _apple,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: FolioColors.line, height: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: FolioColors.muted, fontSize: 13)),
        ),
        Expanded(child: Divider(color: FolioColors.line, height: 1)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.label, required this.icon, required this.onPressed});

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: FolioColors.text,
          backgroundColor: FolioColors.card,
          side: const BorderSide(color: FolioColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.18
      ..strokeCap = StrokeCap.butt;
    final rect = Rect.fromLTWH(
      stroke.strokeWidth / 2,
      stroke.strokeWidth / 2,
      size.width - stroke.strokeWidth,
      size.height - stroke.strokeWidth,
    );
    canvas.drawArc(rect, -0.4, 1.9, false, stroke..color = const Color(0xFF4285F4));
    canvas.drawArc(rect, 1.5, 1.15, false, stroke..color = const Color(0xFF34A853));
    canvas.drawArc(rect, 2.65, 1.05, false, stroke..color = const Color(0xFFFBBC05));
    canvas.drawArc(rect, 3.7, 1.15, false, stroke..color = const Color(0xFFEA4335));
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.48, size.height * 0.42, size.width * 0.42, size.width * 0.16),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
