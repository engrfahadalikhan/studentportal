// Simple bundled profanity / abuse filter for AUST Connect submissions.
// English + common Roman-Urdu terms. Matches whole words (with light leet
// substitution) so ordinary text like "class" or "assessment" is NOT rejected.
class ProfanityFilter {
  ProfanityFilter._();

  static const _words = <String>[
    // English
    'fuck', 'fuk', 'fck', 'shit', 'bitch', 'bastard', 'asshole', 'dick',
    'pussy', 'slut', 'whore', 'cunt', 'motherfucker', 'nigga', 'nigger',
    'rape', 'retard', 'faggot',
    // Roman-Urdu / regional
    'gandu', 'gaandu', 'chutiya', 'chutiye', 'chutya', 'madarchod',
    'madarchood', 'bhenchod', 'behenchod', 'bhosdi', 'bhosdike', 'harami',
    'haramzada', 'haraami', 'kutta', 'kutti', 'kutte', 'lund', 'lauda',
    'lawda', 'randi', 'gashti', 'kanjar', 'kameena', 'kamina', 'zaleel',
    'ullu', 'jahil', 'besharam', 'badtameez',
  ];

  static final RegExp _leet = RegExp(r'[\s\.\-_*@0-9]+');

  /// Returns the first banned word found, or null when the text is clean.
  static String? firstMatch(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll('@', 'a')
        .replaceAll('\$', 's')
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('3', 'e');
    // collapse separators so "f u c k" / "f.u.c.k" are caught
    final collapsed = normalized.replaceAll(_leet, '');
    for (final w in _words) {
      final b = RegExp('\\b$w\\b');
      if (b.hasMatch(normalized) || collapsed.contains(w)) return w;
    }
    return null;
  }

  static bool isClean(String text) => firstMatch(text) == null;
}
