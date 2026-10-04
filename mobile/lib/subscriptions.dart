import 'package:flutter/material.dart';

const subscriptionCatalog = <String, List<String>>{
  'Streaming': [
    'Netflix',
    'Spotify',
    'YouTube Premium',
    'YouTube Music',
    'Disney+',
    'Amazon Prime',
    'Apple TV+',
    'Apple Music',
    'Apple One',
    'ViU',
    'Peo TV',
    'Dialog TV',
    'Zee5',
    'Sony LIV',
    'Hoichoi',
    'Crunchyroll',
  ],
  'Phone and internet': [
    'Dialog',
    'Mobitel',
    'Hutch',
    'Airtel',
    'SLT Fibre',
    'Lanka Bell',
    'Starlink',
  ],
  'AI and software': [
    'ChatGPT',
    'Claude',
    'Gemini',
    'Cursor',
    'GitHub',
    'Microsoft 365',
    'Google One',
    'iCloud+',
    'Adobe',
    'Canva',
    'Notion',
    'Figma',
    'Dropbox',
    'Zoom',
    'Slack',
    'LinkedIn Premium',
    'Grammarly',
    'Duolingo',
    '1Password',
    'NordVPN',
  ],
  'News': [
    'Sunday Times',
    'Daily FT',
    'Daily Mirror',
    'Ada Derana',
    'EconomyNext',
  ],
  'Games': [
    'PlayStation Plus',
    'Xbox Game Pass',
    'Nintendo Switch Online',
  ],
};

List<String> matchingSubscriptions(String query) {
  final needle = query.trim().toLowerCase();
  final names = [for (final group in subscriptionCatalog.values) ...group];
  if (needle.isEmpty) return names;
  return [for (final name in names) if (name.toLowerCase().contains(needle)) name];
}

const _subscriptionLogos = <String, String>{
  'netflix': 'images/subscriptions/netflix.png',
  'spotify': 'images/subscriptions/spotify.png',
  'youtube': 'images/subscriptions/youtube-premium.png',
  'youtubepremium': 'images/subscriptions/youtube-premium.png',
  'youtubemusic': 'images/subscriptions/youtube-music.png',
  'disney': 'images/subscriptions/disney-plus.png',
  'disneyplus': 'images/subscriptions/disney-plus.png',
  'amazonprime': 'images/subscriptions/amazon-prime.png',
  'primevideo': 'images/subscriptions/amazon-prime.png',
  'appletv': 'images/subscriptions/apple-tv.png',
  'applemusic': 'images/subscriptions/apple-music.png',
  'appleone': 'images/subscriptions/apple-one.png',
  'apple': 'images/subscriptions/apple-one.png',
  'viu': 'images/subscriptions/viu.png',
  'peotv': 'images/subscriptions/peo-tv.png',
  'dialogtv': 'images/subscriptions/dialog-tv.png',
  'zee5': 'images/subscriptions/zee5.png',
  'sonyliv': 'images/subscriptions/sony-liv.png',
  'hoichoi': 'images/subscriptions/hoichoi.png',
  'crunchyroll': 'images/subscriptions/crunchyroll.png',
  'dialog': 'images/subscriptions/dialog.png',
  'hutch': 'images/subscriptions/hutch.png',
  'airtel': 'images/subscriptions/airtel.png',
  'sltfibre': 'images/subscriptions/slt-fibre.png',
  'slt': 'images/subscriptions/slt-fibre.png',
  'starlink': 'images/subscriptions/starlink.png',
  'chatgpt': 'images/subscriptions/chatgpt.png',
  'openai': 'images/subscriptions/chatgpt.png',
  'claude': 'images/subscriptions/claude.png',
  'gemini': 'images/subscriptions/gemini.png',
  'cursor': 'images/subscriptions/cursor.png',
  'github': 'images/subscriptions/github.png',
  'microsoft365': 'images/subscriptions/microsoft-365.png',
  'microsoft': 'images/subscriptions/microsoft-365.png',
  'googleone': 'images/subscriptions/google-one.png',
  'icloud': 'images/subscriptions/icloud.png',
  'adobe': 'images/subscriptions/adobe.png',
  'canva': 'images/subscriptions/canva.png',
  'notion': 'images/subscriptions/notion.png',
  'figma': 'images/subscriptions/figma.png',
  'dropbox': 'images/subscriptions/dropbox.png',
  'zoom': 'images/subscriptions/zoom.png',
  'slack': 'images/subscriptions/slack.png',
  'linkedin': 'images/subscriptions/linkedin-premium.png',
  'linkedinpremium': 'images/subscriptions/linkedin-premium.png',
  'grammarly': 'images/subscriptions/grammarly.png',
  'duolingo': 'images/subscriptions/duolingo.png',
  '1password': 'images/subscriptions/1password.png',
  'nordvpn': 'images/subscriptions/nordvpn.png',
  'dailyft': 'images/subscriptions/daily-ft.png',
  'dailymirror': 'images/subscriptions/daily-mirror.png',
  'adaderana': 'images/subscriptions/ada-derana.png',
  'playstation': 'images/subscriptions/playstation-plus.png',
  'playstationplus': 'images/subscriptions/playstation-plus.png',
  'xbox': 'images/subscriptions/xbox-game-pass.png',
  'xboxgamepass': 'images/subscriptions/xbox-game-pass.png',
  'nintendo': 'images/subscriptions/nintendo-switch-online.png',
  'nintendoswitchonline': 'images/subscriptions/nintendo-switch-online.png',
};

String _compact(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String? subscriptionLogo(String name) {
  final key = _compact(name);
  if (key.isEmpty) return null;
  final exact = _subscriptionLogos[key];
  if (exact != null) return exact;
  String? contained;
  var containedLength = 0;
  for (final brand in _subscriptionLogos.keys) {
    if (key.contains(brand) && brand.length > containedLength) {
      contained = _subscriptionLogos[brand];
      containedLength = brand.length;
    }
  }
  if (contained != null) return contained;
  String? near;
  var nearDistance = 3;
  for (final brand in _subscriptionLogos.keys) {
    if (brand.length < 5 || (key.length - brand.length).abs() > 2) continue;
    final distance = _edits(key, brand);
    if (distance < nearDistance || (distance == nearDistance && brand.length > containedLength)) {
      near = _subscriptionLogos[brand];
      nearDistance = distance;
      containedLength = brand.length;
    }
  }
  return nearDistance <= 2 ? near : null;
}

int _edits(String a, String b) {
  final rows = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    rows[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    rows[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final insert = rows[i][j - 1] + 1;
      final remove = rows[i - 1][j] + 1;
      final replace = rows[i - 1][j - 1] + cost;
      rows[i][j] = insert < remove
          ? (insert < replace ? insert : replace)
          : (remove < replace ? remove : replace);
    }
  }
  return rows[a.length][b.length];
}

class SubscriptionMark extends StatelessWidget {
  const SubscriptionMark({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = subscriptionLogo(name);
    if (logo == null) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: Color(0xFF2A2A30), shape: BoxShape.circle),
        child: Icon(Icons.subscriptions_outlined, color: const Color(0xFFB7A6F5), size: size * 0.5),
      );
    }
    return ClipOval(
      child: Image.asset(logo, width: size, height: size, fit: BoxFit.cover),
    );
  }
}
