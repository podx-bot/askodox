import 'package:flutter/material.dart';

void main() {
  runApp(const PodxLiveTestApp());
}

class PodxLiveTestApp extends StatelessWidget {
  const PodxLiveTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PODX Live Test',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const PodxLiveTestHome(),
    );
  }
}

class PodxLiveTestHome extends StatelessWidget {
  const PodxLiveTestHome({super.key});

  @override
  Widget build(BuildContext context) {
    const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    return Scaffold(
      appBar: AppBar(title: const Text('PODX Live Test')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.verified_outlined, size: 72),
                const SizedBox(height: 20),
                Text(
                  'Android build is installed and running.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'This validation build isolates APK generation from the legacy Flutter compile blockers.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Backend configuration'),
                  subtitle: Text(apiBaseUrl.isEmpty ? 'API_BASE_URL not injected' : apiBaseUrl),
                ),
                const ListTile(
                  leading: Icon(Icons.build_circle_outlined),
                  title: Text('Build channel'),
                  subtitle: Text('GitHub Actions debug APK'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
