/// Small formatting helpers shared across screens so date/time formatting
/// isn't duplicated per-widget (the original repeated these inline).
class Formatters {
  const Formatters._();

  static String time(DateTime dt) =>
      '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';

  static String date(DateTime dt) =>
      '${dt.year}-${_two(dt.month)}-${_two(dt.day)}';

  static String dateTime(DateTime dt) => '${date(dt)} ${time(dt)}';

  static String duration(Duration d) {
    if (d.isNegative) return 'expired';
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
