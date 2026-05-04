import 'package:flutter/material.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import 'game_screen.dart';
import 'doctor_screen.dart';
import 'image_capture_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _breatheCtrl1;
  late final AnimationController _breatheCtrl2;
  late final AnimationController _breatheCtrl3;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _breatheCtrl1 = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat(reverse: true);
    _breatheCtrl2 = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..forward(from: 0.33)
      ..repeat(reverse: true);
    _breatheCtrl3 = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..forward(from: 0.66)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breatheCtrl1.dispose();
    _breatheCtrl2.dispose();
    _breatheCtrl3.dispose();
    super.dispose();
  }

  void _showPinDialog() {
    final controllers = List.generate(4, (_) => TextEditingController());
    final focusNodes = List.generate(4, (_) => FocusNode());
    String? error;

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          void checkPin() {
            final pin = controllers.map((c) => c.text).join();
            if (pin == '1234') {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DoctorScreen()));
            } else if (pin.length == 4) {
              setDialogState(() => error = I18n.t('pinWrong'));
              for (final c in controllers) {
                c.clear();
              }
              focusNodes[0].requestFocus();
            }
          }

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(I18n.t('enterPin'), textAlign: TextAlign.center),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    return Container(
                      width: 48,
                      height: 56,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      child: TextField(
                        controller: controllers[i],
                        focusNode: focusNodes[i],
                        maxLength: 1,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.card, width: 2),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.accent, width: 2),
                          ),
                          filled: true,
                          fillColor: AppColors.bg,
                        ),
                        onChanged: (val) {
                          if (val.isNotEmpty && i < 3) {
                            focusNodes[i + 1].requestFocus();
                          }
                          if (i == 3 && val.isNotEmpty) {
                            checkPin();
                          }
                        },
                      ),
                    );
                  }),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(I18n.t('cancel')),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Breathing circles background
          _BreathingCircle(
            controller: _breatheCtrl1,
            size: 300,
            top: MediaQuery.of(context).size.height * 0.1,
            left: MediaQuery.of(context).size.width * 0.1,
          ),
          _BreathingCircle(
            controller: _breatheCtrl2,
            size: 400,
            bottom: MediaQuery.of(context).size.height * 0.05,
            right: -MediaQuery.of(context).size.width * 0.1,
          ),
          _BreathingCircle(
            controller: _breatheCtrl3,
            size: 200,
            top: MediaQuery.of(context).size.height * 0.5,
            left: MediaQuery.of(context).size.width * 0.5,
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _IconBtn(
                      label: I18n.currentLang == 'en' ? 'EN' : 'AR',
                      onTap: () => setState(() => I18n.toggle()),
                    ),
                    const SizedBox(width: 8),
                    _IconBtn(
                      icon: _muted ? Icons.volume_off : Icons.volume_up,
                      onTap: () => setState(() => _muted = !_muted),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Center content
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [AppColors.accent, Color(0xFFA78BFA), AppColors.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: Text(
                      I18n.t('appName'),
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width < 360 ? 32 : 48,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    I18n.t('appTagline'),
                    style: const TextStyle(color: AppColors.muted, fontSize: 15),
                  ),
                  const SizedBox(height: 32),

                  // Buttons
                  SizedBox(
                    width: 300,
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const GameScreen()),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 8,
                              shadowColor: AppColors.accent.withValues(alpha: 0.3),
                            ),
                            child: Text(I18n.t('playNow'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ImageCaptureScreen()),
                              );
                            },
                            icon: const Icon(Icons.camera_alt_rounded, size: 20),
                            label: Text(I18n.t('createFromPhoto')),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.text,
                              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _showPinDialog,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.text,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(I18n.t('doctorMode')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreathingCircle extends AnimatedWidget {
  final double size;
  final double? top, bottom, left, right;

  const _BreathingCircle({
    required AnimationController controller,
    required this.size,
    this.top,
    this.bottom,
    this.left,
    this.right,
  }) : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final anim = listenable as AnimationController;
    final scale = 0.8 + 0.35 * anim.value;
    final opacity = 0.4 + 0.4 * anim.value;

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.7],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  const _IconBtn({this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: label != null
              ? Text(label!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))
              : Icon(icon, size: 22, color: AppColors.text),
        ),
      ),
    );
  }
}
