import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF030308))
      ..setUserAgent("AuraSovereignApp/1.0")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint("Erro WebView: ${error.description}");
            setState(() => _isLoading = false);
            // Mostrar aviso de falha de SSL ou Conexão
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Falha ao carregar o servidor. Verifique a URL e tente novamente."),
                backgroundColor: Colors.redAccent,
              )
            );
            // Voltar para a tela de configuração
            _showConfigDialog();
          },
        ),
      )
      ..addJavaScriptChannel(
        'NativeAura',
        onMessageReceived: (JavaScriptMessage message) async {
          if (message.message == 'getContacts') {
            final contacts = await _getNativeContacts();
            _controller.runJavaScript("window.onNativeContactsReceived('\$contacts')");
          }
        },
      );
    
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    String? url = prefs.getString('server_url');
    if (url == null || url.isEmpty) {
      url = 'https://falabrasil.auracloud.com.br';
      await prefs.setString('server_url', url);
    }
    setState(() => _currentUrl = url!);
    _controller.loadRequest(Uri.parse(url));
  }

  Future<void> _showConfigDialog() async {
    String tempUrl = _currentUrl;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161b22),
          title: const Text('Configurar Servidor Web', style: TextStyle(color: Colors.white)),
          content: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'https://seu-servidor...',
              hintStyle: TextStyle(color: Colors.white54),
            ),
            onChanged: (val) => tempUrl = val,
            controller: TextEditingController(text: tempUrl),
          ),
          actions: [
            TextButton(
              child: const Text('SALVAR', style: TextStyle(color: Color(0xFF00f5c4))),
              onPressed: () async {
                String finalUrl = tempUrl.trim();
                if (finalUrl.isNotEmpty) {
                  // FORÇAR HTTPS: A WebCrypto API (usada no app.js) falha se não for https://
                  if (!finalUrl.startsWith('https://') && !finalUrl.startsWith('http://localhost')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("ATENÇÃO: O Servidor deve iniciar com https:// para garantir a criptografia."),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 4),
                      )
                    );
                    finalUrl = finalUrl.replaceFirst('http://', 'https://');
                    if (!finalUrl.startsWith('https://')) {
                      finalUrl = 'https://' + finalUrl;
                    }
                  }

                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('server_url', finalUrl);
                  setState(() {
                    _currentUrl = finalUrl;
                    _isLoading = true;
                  });
                  _controller.loadRequest(Uri.parse(finalUrl));
                  Navigator.pop(context);
                }
              },
            )
          ],
        );
      }
    );
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

  void _openQrScanner() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const QRScannerScreen())).then((result) {
      if (result != null && result is String) {
        try {
          final data = jsonDecode(result);
          if (data['action'] == 'login' && data['session_id'] != null) {
            // Send the auth_web command through the WebView using JavaScript
            final token = ''; // We can read aura_token from local storage of webview, but let's just dispatch to JS
            final sessionId = data['session_id'];
            
            // Invoke the authorize web session via Javascript in the WebView
            _controller.runJavaScript("""
              const authTokenStr = localStorage.getItem('aura_token');
              if (socket && socket.readyState === WebSocket.OPEN && authTokenStr) {
                  socket.send(JSON.stringify({ 
                      type: 'authorize_web_session', 
                      session_id: '\$sessionId', 
                      token: authTokenStr 
                  }));
                  alert('Sessão Web Autorizada!');
              } else {
                  alert('Erro: Você precisa estar logado no celular primeiro.');
              }
            """);
          }
        } catch (e) {
          debugPrint("Invalid QR Code: \$e");
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (_currentUrl.isNotEmpty) WebViewWidget(controller: _controller),
            if (_isLoading)
              Container(
                color: const Color(0xFF030308),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'config_btn',
            mini: true,
            backgroundColor: Colors.white24,
            child: const Icon(Icons.settings, color: Colors.white),
            onPressed: _showConfigDialog,
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'qr_btn',
            backgroundColor: const Color(0xFF00f5c4),
            child: const Icon(Icons.qr_code_scanner, color: Colors.black),
            onPressed: _openQrScanner,
          ),
        ],
      ),
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear WhatsApp Web'),
        backgroundColor: Colors.black,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final String? code = barcodes.first.rawValue;
            if (code != null) {
              Navigator.pop(context, code);
            }
          }
        },
      ),
    );
  }
}
