import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/units.dart';
import '../../domain/measurement.dart';
import '../../domain/metric_report.dart';
import '../../domain/profile.dart';

/// Opens a preview of the shareable image and sends it through the system share
/// sheet. The app never uploads anything itself.
Future<void> showSharePreview(BuildContext context, Measurement measurement) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SharePreviewDialog(measurement: measurement),
  );
}

class _SharePreviewDialog extends ConsumerStatefulWidget {
  const _SharePreviewDialog({required this.measurement});

  final Measurement measurement;

  @override
  ConsumerState<_SharePreviewDialog> createState() =>
      _SharePreviewDialogState();
}

class _SharePreviewDialogState extends ConsumerState<_SharePreviewDialog> {
  final _boundary = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final measurement = widget.measurement;
    final profiles =
        ref.watch(profilesProvider).value?.all ?? const <Profile>[];
    final matches = profiles.where((p) => p.id == measurement.profileId);
    final profile = matches.isEmpty
        ? ref.watch(activeProfileProvider)
        : matches.first;
    final unit = ref.watch(displayUnitProvider);
    final report = buildMetricReport(
      weightKg: measurement.weightKg,
      values: measurement.bodyComposition,
      unit: unit,
      sex: profile?.sex,
      age: profile?.age,
      heightCm: profile?.heightCm,
      impedanceOhm: measurement.impedanceOhm,
    );
    final width = (MediaQuery.sizeOf(context).width - 72).clamp(280.0, 380.0);
    final weightText = formatWeight(measurement.weightKg, unit);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 660),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: _boundary,
                  child: ShareCard(
                    width: width,
                    profileName: profile?.name ?? 'Measurement',
                    weightText: weightText,
                    dateText: formatDateTime(measurement.measuredAt),
                    deviceLabel: measurement.sourceDeviceLabel,
                    estimated: measurement.bodyCompositionEstimated,
                    metrics: report.metrics
                        .where((m) => m.key != 'impedanceOhm')
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _sharing
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _sharing
                        ? null
                        : () => _share(
                            profileName: profile?.name ?? 'Measurement',
                            weightText: weightText,
                          ),
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: Text(_sharing ? 'Preparing…' : 'Share image'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share({
    required String profileName,
    required String weightText,
  }) async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _boundary.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Card is not rendered');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Could not encode the image');
      final slug = profileName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final date = widget.measurement.measuredAt.toLocal();
      final name =
          'ailink-${slug.isEmpty ? 'measurement' : slug}-'
          '${date.year}${date.month.toString().padLeft(2, '0')}'
          '${date.day.toString().padLeft(2, '0')}.png';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              data.buffer.asUint8List(),
              mimeType: 'image/png',
              name: name,
            ),
          ],
          text:
              '$profileName · $weightText · '
              '${formatDateTime(widget.measurement.measuredAt)}',
          subject: 'Scale measurement',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not share: $error')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.width,
    required this.profileName,
    required this.weightText,
    required this.dateText,
    required this.metrics,
    required this.estimated,
    this.deviceLabel,
  });

  final double width;
  final String profileName;
  final String weightText;
  final String dateText;
  final List<MetricDisplay> metrics;
  final bool estimated;
  final String? deviceLabel;

  @override
  Widget build(BuildContext context) {
    final tileWidth = (width - 50) / 2;
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B3B32), Color(0xFF0E7C66)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_weight_outlined, color: Colors.white70),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Scale',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                dateText,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            profileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Body weight',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            weightText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: tileWidth,
                  child: _ShareTile(metric: metric),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            [
              if (deviceLabel != null) 'Scale: $deviceLabel',
              if (estimated)
                'Body composition estimated from weight + impedance.',
              'Generated on this device. No cloud, no account.',
            ].join('\n'),
            style: const TextStyle(color: Colors.white54, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  const _ShareTile({required this.metric});

  final MetricDisplay metric;

  @override
  Widget build(BuildContext context) {
    final tone = metric.status?.tone ?? MetricTone.neutral;
    final color = _onDark(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 3),
          Text(
            metric.value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (metric.status != null) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    metric.status!.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Color _onDark(MetricTone tone) {
  return switch (tone) {
    MetricTone.good => const Color(0xFF8FE3C8),
    MetricTone.warn => const Color(0xFFFFD08A),
    MetricTone.bad => const Color(0xFFFFB4AB),
    MetricTone.neutral => const Color(0xFFD6E4E0),
  };
}
