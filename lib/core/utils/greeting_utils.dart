class GreetingUtils {
  const GreetingUtils._();

  static DateTime indiaNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  }

  static String greetingForIndiaTime() {
    final int hour = indiaNow().hour;
    if (hour < 12) {
      return 'Good morning ☀️';
    }
    if (hour < 17) {
      return 'Good afternoon 🌤️';
    }
    return 'Good evening 🌙';
  }
}
