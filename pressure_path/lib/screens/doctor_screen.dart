import 'package:flutter/material.dart';
import '../i18n/strings.dart';
import '../theme/app_theme.dart';

class DoctorScreen extends StatefulWidget {
  const DoctorScreen({super.key});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  int _difficulty = 1;
  String _stressLevel = 'none';
  String _pathType = 'wave';
  bool _dailyTask = false;

  final _patients = [
    _Patient(id: 'ahmed', name: 'Ahmed', nameAr: 'أحمد', color: const Color(0xFF6366F1)),
    _Patient(id: 'sara', name: 'Sara', nameAr: 'سارة', color: const Color(0xFFF472B6)),
    _Patient(id: 'youssef', name: 'Youssef', nameAr: 'يوسف', color: const Color(0xFF38BDF8)),
  ];
  String _selectedPatientId = 'ahmed';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(I18n.t('doctorPanel'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  _LangButton(),
                ],
              ),
            ),

            // Body
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Patients section
                  _Section(
                    title: I18n.t('patients'),
                    child: Column(
                      children: _patients.map((p) {
                        final selected = p.id == _selectedPatientId;
                        final displayName = I18n.isArabic ? p.nameAr : p.name;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedPatientId = p.id),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.card : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: p.color.withValues(alpha: 0.13),
                                  foregroundColor: p.color,
                                  child: Text(displayName[0],
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(displayName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600, fontSize: 15)),
                                      Text('0 ${I18n.t('sessionsToday')}',
                                          style: const TextStyle(
                                              fontSize: 12, color: AppColors.muted)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Settings section
                  _Section(
                    title: I18n.t('settings'),
                    child: Column(
                      children: [
                        _SettingRow(
                          label: I18n.t('difficulty'),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: Slider(
                                  value: _difficulty.toDouble(),
                                  min: 1,
                                  max: 5,
                                  divisions: 4,
                                  onChanged: (v) => setState(() => _difficulty = v.round()),
                                ),
                              ),
                              Text('$_difficulty',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        _SettingRow(
                          label: I18n.t('stressLevel'),
                          child: DropdownButton<String>(
                            value: _stressLevel,
                            dropdownColor: AppColors.bg,
                            underline: const SizedBox(),
                            items: ['none', 'low', 'medium', 'high']
                                .map((v) => DropdownMenuItem(
                                    value: v, child: Text(I18n.t('stress${v[0].toUpperCase()}${v.substring(1)}'))))
                                .toList(),
                            onChanged: (v) => setState(() => _stressLevel = v!),
                          ),
                        ),
                        _SettingRow(
                          label: I18n.t('pathType'),
                          child: DropdownButton<String>(
                            value: _pathType,
                            dropdownColor: AppColors.bg,
                            underline: const SizedBox(),
                            items: ['wave', 'zigzag', 'spiral']
                                .map((v) => DropdownMenuItem(value: v, child: Text(I18n.t(v))))
                                .toList(),
                            onChanged: (v) => setState(() => _pathType = v!),
                          ),
                        ),
                        _SettingRow(
                          label: I18n.t('dailyTask'),
                          child: Switch(
                            value: _dailyTask,
                            activeTrackColor: AppColors.accent,
                            onChanged: (v) => setState(() => _dailyTask = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(I18n.t('assigned')),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          },
                          child: Text(I18n.t('assignTask')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(I18n.t('previewTrail')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Patient {
  final String id, name, nameAr;
  final Color color;
  const _Patient({required this.id, required this.name, required this.nameAr, required this.color});
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.accent)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _SettingRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: const TextStyle(fontSize: 14))),
          child,
        ],
      ),
    );
  }
}

class _LangButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          I18n.toggle();
          (context as Element).markNeedsBuild();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Text(I18n.currentLang == 'en' ? 'EN' : 'AR',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
