import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const FalaBrasilNative());
}

class FalaBrasilNative extends StatelessWidget {
  const FalaBrasilNative({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fala Brasil',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF030308),
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setDomStorageEnabled(true)
      ..setBackgroundColor(const Color(0xFF030308))
      ..setUserAgent("AuraSovereignApp/1.0")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint("Erro WebView: ${error.description}");
          },
        ),
      )
      ..addJavaScriptChannel(
        'NativeAura',
        onMessageReceived: (JavaScriptMessage message) async {
          if (message.message == 'getContacts') {
            final contacts = await _getNativeContacts();
            _controller.runJavaScript("window.onNativeContactsReceived('$contacts')");
          }
        },
      )
      ..loadRequest(Uri.parse('https://site-269-relnbcvmoq-ue.a.run.app/'));
  }

  Future<String> _getNativeContacts() async {
    if (await Permission.contacts.request().isGranted) {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      final List<Map<String, String>> contactList = contacts.map((c) => {
        'name': c.displayName,
        'tel': c.phones.isNotEmpty ? c.phones.first.number : '',
      }).toList();
      return jsonEncode(contactList);
    }
    return '[]';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              Container(
                color: const Color(0xFF030308),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo Premium Fala Brasil
                      const Icon(Icons.security, size: 80, color: Color(0xFF00f5c4)),
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(color: Color(0xFF00f5c4)),
                      const SizedBox(height: 10),
                      const Text(
                        "CONECTANDO REDE SOBERANA",
                        style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 2),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
