import 'package:meta/meta.dart';

import '../../core/units.dart';

sealed class ScaleEvent {
  const ScaleEvent();
}

class ScaleReadingEvent extends ScaleEvent {
  const ScaleReadingEvent(this.reading);

  final WeightReading reading;
}

class ScaleCompletionEvent extends ScaleEvent {
  const ScaleCompletionEvent({required this.requiresStable});

  final bool requiresStable;
}

class ScaleBodyCompositionEvent extends ScaleEvent {
  const ScaleBodyCompositionEvent(this.metrics);

  final Map<String, double> metrics;
}

class ScaleInfoEvent extends ScaleEvent {
  const ScaleInfoEvent(this.message);

  final String message;
}

class ScaleErrorEvent extends ScaleEvent {
  const ScaleErrorEvent(this.message);

  final String message;
}

@immutable
class DecodeResult {
  const DecodeResult({this.events = const [], this.rawSummary});

  final List<ScaleEvent> events;
  final String? rawSummary;
}
