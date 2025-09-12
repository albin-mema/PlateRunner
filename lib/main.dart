// PlateRunner main entrypoint - simple two-button counter demo.
import 'package:flutter/material.dart';

void main() {
  runApp(const PlateRunnerApp());
}

class PlateRunnerApp extends StatelessWidget {
  const PlateRunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlateRunner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const CounterPage(),
    );
  }
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _count = 0;

  void _increment() {
    setState(() => _count++);
  }

  void _decrement() {
    setState(() {
      if (_count > 0) _count--;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Read compile-time environment (passed via --dart-define=APP_ENV=dev)
    const String env = String.fromEnvironment('APP_ENV', defaultValue: 'prod');
    final bool isDev = env.toLowerCase() == 'dev';

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('PlateRunner Counter'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Counter value:',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '$_count',
              key: const Key('counter_value'),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 16,
              children: [
                ElevatedButton.icon(
                  key: const Key('increment_button'),
                  onPressed: _increment,
                  icon: const Icon(Icons.add),
                  label: const Text('Increment'),
                ),
                ElevatedButton.icon(
                  key: const Key('decrement_button'),
                  onPressed: _decrement,
                  icon: const Icon(Icons.remove),
                  label: const Text('Decrement'),
                ),
              ],
            ),
          ],
        ),
      ),
// FABs removed: using only elevated buttons
    );

    return isDev
        ? Banner(
            location: BannerLocation.topStart,
            message: 'DEV',
            color: Colors.deepOrange.withValues(alpha: 0.85),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
            child: scaffold,
          )
        : scaffold;
  }
}