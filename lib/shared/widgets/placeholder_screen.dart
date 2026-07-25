import 'package:flutter/material.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, required this.icon, super.key});
  final String title;
  final String icon;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Icon(icon == 'search' ? Icons.search : icon == 'favorite' ? Icons.favorite_outline : Icons.person_outline, size: 72, color: Theme.of(context).colorScheme.primary),
        ),
      );
}
