import 'package:flutter/material.dart';

import '../screens/web_search_screen.dart';

/// Her barkodun yaninda kullanilan "Google'da Ara" butonu.
/// Uygulama ici tarayicida barkodu aratir.
class GoogleSearchButton extends StatelessWidget {
  final String query;
  final bool compact;

  const GoogleSearchButton({
    super.key,
    required this.query,
    this.compact = false,
  });

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebSearchScreen(query: query)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        icon: const Icon(Icons.search),
        tooltip: "Google'da Ara",
        onPressed: () => _open(context),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _open(context),
      icon: const Icon(Icons.search, size: 18),
      label: const Text("Google'da Ara"),
    );
  }
}
