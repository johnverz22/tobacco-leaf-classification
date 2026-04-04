import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF111111),
            foregroundColor: Colors.white,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: const Text(
                'How to Use',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1B3A1B), Color(0xFF111111)],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _SectionCard(
                  icon: Icons.play_circle_outline_rounded,
                  iconColor: const Color(0xFF4CAF50),
                  title: 'Getting Started',
                  child: const _BodyText(
                    'Point your camera at a tobacco leaf lying flat on a dark surface. '
                    'The app detects and grades it automatically — no button to press.',
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.tips_and_updates_outlined,
                  iconColor: const Color(0xFFFFC107),
                  title: 'For Best Results',
                  child: Column(
                    children: const [
                      _Tip(
                        icon: Icons.contrast,
                        label: 'Dark background is required',
                        body:
                            'Place the leaf on a black or very dark surface before scanning. '
                            'The app uses contrast to find the leaf. On light surfaces it will not trigger.',
                      ),
                      _Tip(
                        icon: Icons.crop_free_rounded,
                        label: 'Fill the guide',
                        body:
                            'Hold the camera close enough so the leaf fills most of the '
                            'leaf-shaped guide on screen. A leaf that is too small or too far away will be ignored.',
                      ),
                      _Tip(
                        icon: Icons.wb_sunny_outlined,
                        label: 'Good lighting',
                        body:
                            'Use natural daylight or bright indoor light aimed at the leaf. '
                            'Avoid harsh shadows across the surface. Low light causes blurry images and lower confidence.',
                      ),
                      _Tip(
                        icon: Icons.horizontal_rule_rounded,
                        label: 'Lay it flat',
                        body:
                            'Curled or folded leaves affect shape detection. '
                            'Lay the leaf as flat as possible before scanning.',
                      ),
                      _Tip(
                        icon: Icons.filter_1_outlined,
                        label: 'One leaf at a time',
                        body:
                            'Place a single leaf in frame. Multiple overlapping leaves confuse the shape filter.',
                        isLast: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.grade_outlined,
                  iconColor: const Color(0xFF64B5F6),
                  title: 'Understanding the Grade',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BodyText(
                        'A confidence score below 80% will not be recorded. '
                        'Reposition the leaf and try again.',
                      ),
                      const SizedBox(height: 14),
                      _GradeTable(),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.location_on_outlined,
                  iconColor: const Color(0xFFEF9A9A),
                  title: 'Setting Your Location',
                  child: const _BodyText(
                    'Open Settings and enter your town and province before you start classifying. '
                    'This location is attached to every record in your analytics export — '
                    'important for traceability when sharing data.',
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.share_outlined,
                  iconColor: const Color(0xFFCE93D8),
                  title: 'Sharing Your Data',
                  child: const _BodyText(
                    'After classifying a batch of leaves, go to Settings and tap '
                    '"Share analytics JSON". This exports a full record of every '
                    'classification — label, confidence, timestamp, and location.\n\n'
                    'You can also tap "Copy analytics JSON" to paste it into an email '
                    'or messaging app manually.',
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  icon: Icons.restart_alt_rounded,
                  iconColor: const Color(0xFFFF8A65),
                  title: 'Resetting Counts',
                  child: const _BodyText(
                    '"Reset analytics" in Settings clears all counters and records from '
                    'this device. Do this at the start of a new grading session if you '
                    'want clean per-session data. This cannot be undone.',
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable components ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  final String text;
  const _BodyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFB0B0B0),
        fontSize: 14,
        height: 1.55,
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String body;
  final bool isLast;

  const _Tip({
    required this.icon,
    required this.label,
    required this.body,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 15),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Text(
            body,
            style: const TextStyle(
              color: Color(0xFFB0B0B0),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
        if (!isLast) ...[
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _GradeTable extends StatelessWidget {
  final _rows = const [
    ('AX', 'Fine quality', 'Grade A'),
    ('BX', 'Good quality', 'Grade B'),
    ('CX', 'Good quality', 'Grade C'),
    ('DX', 'Fair quality', 'Grade D'),
    ('K3', 'Good quality', 'Grade C'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: const [
                SizedBox(
                  width: 36,
                  child: Text(
                    'Label',
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Description',
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'NTA',
                  style: TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF2A2A2A), height: 1),
          ..._rows.asMap().entries.map((e) {
            final isLast = e.key == _rows.length - 1;
            final (label, desc, nta) = e.value;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withValues(
                              alpha: 0.18,
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Color(0xFF4CAF50),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          desc,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        nta,
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast) const Divider(color: Color(0xFF2A2A2A), height: 1),
              ],
            );
          }),
        ],
      ),
    );
  }
}
