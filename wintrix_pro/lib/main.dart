import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'register_screen.dart'; // अगर आपकी फ़ाइल का नाम अलग है, तो यहाँ बदल लेना

void main() async {
  // यह लाइन सबसे ज़रूरी है, यह फ्लटर के विजेट्स को बाइंड करती है ताकि हम runApp से पहले async काम कर सकें
  WidgetsFlutterBinding.ensureInitialized();
  
  // यहाँ आपका फायरबेस इनिशियलाइज़ होगा (कोटलिन का FirebaseApp.initializeApp)
  await Firebase.initializeApp();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wintrix',
      debugShowCheckedModeBanner: false, // वो कोने में आने वाला लाल 'Debug' बैनर हटाने के लिए
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // ऐप खुलते ही सबसे पहले कौन सी स्क्रीन दिखेगी
      initialRoute: '/',
      routes: {
        '/': (context) => const RegisterScreen(),
        '/home': (context) => const DummyHomeScreen(), // जब तक होम स्क्रीन का कोड नहीं बदलेंगे, तब तक ये दिखेगी
      },
    );
  }
}

// भाई, यह एक टेम्परेरी होम स्क्रीन है ताकि जब यूजर रजिस्टर करके नेविगेट करे, तो ऐप क्रैश न हो।
class DummyHomeScreen extends StatelessWidget {
  const DummyHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Home Screen")),
      body: const Center(
        child: Text(
          "Welcome to Wintrix!\nयहाँ आपका होम स्क्रीन का लॉजिक आएगा।",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
