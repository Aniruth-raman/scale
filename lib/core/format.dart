String _pad(int value) => value.toString().padLeft(2, '0');

String formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_pad(local.month)}-${_pad(local.day)} '
      '${_pad(local.hour)}:${_pad(local.minute)}';
}

String formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_pad(local.month)}-${_pad(local.day)}';
}

String formatTime(DateTime value) {
  final local = value.toLocal();
  return '${_pad(local.hour)}:${_pad(local.minute)}:${_pad(local.second)}';
}

String formatShortDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day}/${local.month}';
}

String statusLabel(bool complete) => complete ? 'Complete' : 'Manual';
