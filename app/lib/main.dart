import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Make sure Firebase is initialized
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Goals Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const FirestoreListScreen(title: 'Daily Goals'),
    );
  }
}

class FirestoreListScreen extends StatelessWidget {
  const FirestoreListScreen({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final DocumentReference trackerDoc =
        FirebaseFirestore.instance.collection('habit').doc('tracker');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<DocumentSnapshot>(
        future: trackerDoc.get(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('No tracker data found.'));
          }

          final data = snapshot.data!.data();
          final text = data.toString(); // Convert entire document to string

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: SelectableText(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          );
        },
      ),
    );
  }
}
