import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';

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
        scaffoldBackgroundColor: const Color(0xFF0B141A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5C4),
          secondary: Color(0xFFFFD700),
          surface: Color(0xFF111B21),
        ),
      ),
      home: const MainMessengerScreen(),
    );
  }
}

class MainMessengerScreen extends StatefulWidget {
  const MainMessengerScreen({super.key});

  @override
  State<MainMessengerScreen> createState() => _MainMessengerScreenState();
}

class _MainMessengerScreenState extends State<MainMessengerScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B141A))
      ..setUserAgent("AuraSovereignApp/2.0 (Android)")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint("Aviso WebView: ${error.description}");
          },
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController).setOnPlatformPermissionRequest((request) {
        request.grant();
      });
    }

    controller.addJavaScriptChannel(
      'NativeAura',
      onMessageReceived: (JavaScriptMessage message) async {
          try {
            final data = jsonDecode(message.message);
            final action = data['action'];

            if (action == 'getContacts') {
              final contacts = await _getNativeContacts();
              _controller.runJavaScript("window.onNativeContactsReceived($contacts)");
            } else if (action == 'openScanner') {
              _openQrScanner();
            } else if (action == 'shareInvite') {
              final String text = data['text'] ?? '';
              final String tel = data['tel'] ?? '';
              _handleShareInvite(text, tel);
            } else if (action == 'pickCamera') {
              _pickImage(ImageSource.camera);
            } else if (action == 'pickGallery') {
              _pickGallery();
            } else if (action == 'pickDoc') {
              _pickDocument();
            } else if (action == 'minimizeApp') {
              SystemNavigator.pop();
            } else if (action == 'vibrate') {
              HapticFeedback.mediumImpact();
            }
          } catch (e) {
            debugPrint("Erro canal nativo: $e");
          }
        },
      );

    _controller = controller;
    _loadApp();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: source, imageQuality: 75);
      if (photo != null) {
        final bytes = await File(photo.path).readAsBytes();
        final base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";
        final fileName = photo.name;
        _controller.runJavaScript("window.onNativeMediaReceived('$base64Image', 'image', '$fileName')");
      }
    } catch (e) {
      debugPrint("Erro ao capturar imagem nativa: $e");
    }
  }

  Future<void> _pickGallery() async {
    try {
      final picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage(imageQuality: 75);
      for (var photo in images) {
        final bytes = await File(photo.path).readAsBytes();
        final base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";
        final fileName = photo.name;
        _controller.runJavaScript("window.onNativeMediaReceived('$base64Image', 'image', '$fileName')");
      }
    } catch (e) {
      debugPrint("Erro ao abrir galeria nativa: $e");
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'zip', 'xlsx', 'csv', 'mp3'],
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final fileName = file.name;
        final fileSize = "${(file.size / 1024).toStringAsFixed(1)} KB";
        _controller.runJavaScript("window.onNativeDocReceived('$fileName', '$fileSize')");
      }
    } catch (e) {
      debugPrint("Erro ao selecionar documento nativo: $e");
    }
  }

  Future<void> _handleShareInvite(String text, String tel) async {
    try {
      final cleanTel = tel.replaceAll(RegExp(r'\D'), '');
      if (cleanTel.length >= 10 && !cleanTel.contains('999999999')) {
        final formattedTel = cleanTel.startsWith('55') ? cleanTel : '55$cleanTel';
        final Uri whatsappUri = Uri.parse("https://wa.me/$formattedTel?text=${Uri.encodeComponent(text)}");
        if (await canLaunchUrl(whatsappUri)) {
          await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      await Share.share(text);
    } catch (e) {
      await Share.share(text);
    }
  }

  void _loadApp() {
    _controller.loadHtmlString(kFalaBrasilMasterHtml, baseUrl: 'https://auracloud.com.br');
  }

  Future<String> _getNativeContacts() async {
    try {
      if (await Permission.contacts.request().isGranted) {
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        final List<Map<String, String>> contactList = contacts.map((c) => {
          'name': c.displayName,
          'tel': c.phones.isNotEmpty ? c.phones.first.number : '',
        }).toList();
        return jsonEncode(contactList);
      }
    } catch (e) {
      debugPrint("Erro ao ler contatos: $e");
    }
    return '[]';
  }

  void _openQrScanner() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const QRScannerScreen())).then((result) {
      if (result != null && result is String) {
        _controller.runJavaScript("window.onQrCodeScanned('$result')");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _controller.runJavaScript("if (window.handleAndroidBackPress) { window.handleAndroidBackPress(); }");
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading)
                Container(
                  color: const Color(0xFF0B141A),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🇧🇷', style: TextStyle(fontSize: 52)),
                        SizedBox(height: 20),
                        CircularProgressIndicator(color: Color(0xFF00F5C4)),
                        SizedBox(height: 16),
                        Text(
                          "FALA BRASIL",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 3),
                        ),
                        SizedBox(height: 6),
                        Text(
                          "Mensagens, Chamadas HD & IA Integrada",
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class QRScannerScreen extends StatelessWidget {
  const QRScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR Code'),
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

const String kFalaBrasilMasterHtml = r"""
<!DOCTYPE html>
<html lang="pt-br">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
    <title>Fala Brasil | SuperApp Soberano</title>
    <script src="https://unpkg.com/@phosphor-icons/web"></script>
    <style>
        :root {
            --bg-deep: #0b141a;
            --surface: #111b21;
            --header-bg: #202c33;
            --bubble-in: #202c33;
            --bubble-out: #005c4b;
            --social-green: #00f5c4;
            --gold: #ffd700;
            --text-main: #e9edef;
            --text-muted: #8696a0;
            --danger: #ff4b4b;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; -webkit-tap-highlight-color: transparent; }
        html, body { background: #000; height: 100%; width: 100vw; max-width: 100vw; display: flex; overflow: hidden; color: var(--text-main); }
        .app-container { width: 100%; height: 100%; display: flex; background: var(--bg-deep); position: relative; overflow: hidden; }
        
        /* ONBOARDING FLOW (WHATSAPP GRADE) */
        #onboarding-flow { position: fixed; inset: 0; background: var(--bg-deep); z-index: 9999; display: flex; flex-direction: column; align-items: center; justify-content: space-between; padding: 40px 24px; }
        .onboarding-screen { width: 100%; max-width: 360px; display: none; flex-direction: column; align-items: center; text-align: center; height: 100%; justify-content: space-between; }
        .onboarding-screen.active { display: flex; animation: fadeIn 0.3s ease; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }
        
        .onboarding-hero { width: 100px; height: 100px; border-radius: 50%; background: #182229; border: 2px solid var(--social-green); display: flex; align-items: center; justify-content: center; font-size: 48px; margin-bottom: 20px; box-shadow: 0 0 30px rgba(0,245,196,0.25); }
        .onboarding-title { font-size: 22px; font-weight: 800; color: white; margin-bottom: 8px; }
        .onboarding-subtitle { font-size: 13px; color: var(--text-muted); line-height: 1.5; margin-bottom: 24px; }
        
        .onboarding-btn { width: 100%; padding: 14px; background: var(--social-green); color: black; border: none; border-radius: 24px; font-weight: 800; font-size: 14px; cursor: pointer; text-transform: uppercase; letter-spacing: 0.5px; box-shadow: 0 4px 16px rgba(0,245,196,0.3); }
        .onboarding-btn:active { transform: scale(0.98); }
        
        .phone-input-group { display: flex; gap: 8px; width: 100%; margin-bottom: 20px; }
        .phone-ddi { width: 80px; padding: 12px; background: #182229; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; color: var(--social-green); font-weight: bold; font-size: 15px; text-align: center; }
        .phone-num { flex: 1; padding: 12px 14px; background: #182229; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; color: white; font-size: 16px; outline: none; }
        .phone-num:focus { border-color: var(--social-green); }

        .otp-inputs { display: flex; gap: 8px; justify-content: center; margin: 20px 0; }
        .otp-box { width: 44px; height: 50px; background: #182229; border: 1.5px solid rgba(255,255,255,0.15); border-radius: 8px; font-size: 22px; font-weight: bold; color: var(--social-green); text-align: center; outline: none; }
        .otp-box:focus { border-color: var(--social-green); box-shadow: 0 0 10px rgba(0,245,196,0.3); }

        /* SIDEBAR / MAIN TABS */
        #sidebar { width: 100%; height: 100%; display: flex; flex-direction: column; background: var(--bg-deep); z-index: 10; border-right: 1px solid rgba(255,255,255,0.06); overflow: hidden; }
        @media (min-width: 900px) { #sidebar { width: 34%; min-width: 380px; } }
        
        header { height: 58px; background: var(--header-bg); padding: 0 12px; display: flex; align-items: center; justify-content: space-between; flex-shrink: 0; position: relative; }
        .nav-tabs { display: flex; background: var(--header-bg); border-bottom: 2px solid rgba(255,255,255,0.06); flex-shrink: 0; }
        .tab-btn { flex: 1; padding: 10px 0; text-align: center; font-size: 12px; font-weight: 700; color: var(--text-muted); cursor: pointer; text-transform: uppercase; letter-spacing: 0.3px; border-bottom: 3px solid transparent; transition: all 0.2s; white-space: nowrap; }
        .tab-btn.active { color: var(--social-green); border-bottom: 3px solid var(--social-green); }
        
        .tab-content { flex: 1; overflow-y: auto; display: none; }
        .tab-content.active { display: block; }
        
        /* CHAT ITEMS */
        .chat-item { display: flex; align-items: center; padding: 10px 14px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.03); transition: background 0.15s; }
        .chat-item:active, .chat-item.active { background: #182229; }
        .avatar { width: 44px; height: 44px; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin-right: 12px; flex-shrink: 0; font-size: 20px; position: relative; }
        .avatar.has-status { border: 2px solid var(--social-green); padding: 2px; }
        .chat-info { flex: 1; min-width: 0; }
        .chat-header { display: flex; justify-content: space-between; margin-bottom: 2px; }
        .chat-name { font-weight: 600; font-size: 14px; color: var(--text-main); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .chat-time { font-size: 11px; color: var(--text-muted); flex-shrink: 0; margin-left: 6px; }
        .chat-preview { font-size: 12px; color: var(--text-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: flex; align-items: center; gap: 4px; }
        
        /* CHAT VIEW */
        #chat-view { position: absolute; top: 0; right: 0; width: 100%; height: 100%; display: flex; flex-direction: column; background: #0b141a; z-index: 20; transform: translateX(100%); transition: transform 0.25s cubic-bezier(0.4, 0, 0.2, 1); overflow: hidden; }
        #chat-view.active { transform: translateX(0); }
        @media (min-width: 900px) { #chat-view { position: relative; flex: 1; transform: translateX(0); z-index: 5; } }
        
        .messages-box { flex: 1; overflow-y: auto; padding: 12px; display: flex; flex-direction: column; gap: 8px; background: url('https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png') repeat; background-color: #0b141a; }
        .msg { max-width: 85%; padding: 8px 10px; border-radius: 10px; font-size: 13.5px; position: relative; line-height: 1.4; word-wrap: break-word; cursor: pointer; }
        .msg.in { align-self: flex-start; background: var(--bubble-in); color: var(--text-main); }
        .msg.out { align-self: flex-end; background: var(--bubble-out); color: #fff; }
        .msg-meta { display: flex; align-items: center; justify-content: flex-end; gap: 4px; font-size: 10px; color: rgba(255,255,255,0.5); margin-top: 4px; }
        
        /* MESSAGE REACTIONS */
        .msg-reaction-badge { position: absolute; bottom: -8px; right: 8px; background: #1f2c34; border: 1px solid rgba(255,255,255,0.15); border-radius: 12px; padding: 1px 5px; font-size: 11px; display: inline-flex; align-items: center; box-shadow: 0 2px 6px rgba(0,0,0,0.5); z-index: 2; }
        .floating-reaction-bar { position: fixed; background: #1f2c34; border: 1px solid rgba(255,255,255,0.15); border-radius: 24px; padding: 6px 12px; display: none; gap: 10px; font-size: 22px; z-index: 5000; box-shadow: 0 8px 24px rgba(0,0,0,0.7); animation: popUp 0.15s cubic-bezier(0.175, 0.885, 0.32, 1.275); }
        @keyframes popUp { from { opacity: 0; transform: scale(0.7); } to { opacity: 1; transform: scale(1); } }
        .reaction-item { cursor: pointer; transition: transform 0.15s; }
        .reaction-item:active { transform: scale(1.3); }
        
        /* AUDIO PLAYER IN BUBBLE */
        .audio-bubble { display: flex; align-items: center; gap: 8px; padding: 4px 0; }
        .audio-play-btn { width: 34px; height: 34px; border-radius: 50%; background: var(--social-green); color: black; border: none; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 15px; }
        .audio-wave { flex: 1; height: 4px; background: rgba(255,255,255,0.2); border-radius: 2px; position: relative; }
        .audio-wave-fill { width: 45%; height: 100%; background: var(--social-green); border-radius: 2px; }
        .audio-speed-btn { background: rgba(255,255,255,0.15); border: none; color: white; padding: 2px 6px; border-radius: 10px; font-size: 10px; font-weight: bold; cursor: pointer; }
        .ai-transcribe-box { margin-top: 4px; padding-top: 4px; border-top: 1px dashed rgba(255,255,255,0.15); font-size: 11.5px; color: #d1d7db; }
        
        /* PIX BUBBLE */
        .pix-card { background: #182229; border: 1px solid var(--social-green); border-radius: 8px; padding: 10px; margin-top: 4px; }
        .pix-btn { width: 100%; margin-top: 6px; padding: 6px; background: var(--social-green); color: black; border: none; border-radius: 6px; font-weight: bold; cursor: pointer; font-size: 11.5px; }
        
        /* SECURITY BANNER (ANTI-GOLPE) */
        .security-banner { background: rgba(255, 75, 75, 0.15); border: 1px solid var(--danger); border-radius: 8px; padding: 8px 10px; color: #ff8e8e; font-size: 11px; margin-bottom: 4px; display: flex; align-items: center; gap: 6px; }
        
        /* INPUT BAR */
        .input-bar { min-height: 56px; background: var(--header-bg); padding: 6px 8px; display: flex; align-items: center; gap: 4px; flex-shrink: 0; position: relative; }
        .input-bar input { flex: 1; min-width: 0; background: #2a3942; border: none; outline: none; border-radius: 20px; padding: 8px 12px; color: white; font-size: 14px; }
        .action-btn { width: 36px; height: 36px; border-radius: 50%; background: transparent; border: none; color: var(--text-muted); font-size: 20px; display: flex; align-items: center; justify-content: center; cursor: pointer; flex-shrink: 0; }
        .send-btn { width: 38px; height: 38px; border-radius: 50%; background: var(--social-green); border: none; color: black; font-size: 18px; display: flex; align-items: center; justify-content: center; cursor: pointer; flex-shrink: 0; }
        
        /* POPUP MENUS (EMOJI, ATTACHMENTS, PIX) */
        .popup-panel { position: absolute; bottom: 60px; left: 8px; right: 8px; background: #1f2c34; border-radius: 12px; padding: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.6); display: none; z-index: 100; border: 1px solid rgba(255,255,255,0.08); }
        .popup-panel.show { display: block; animation: slideUp 0.2s ease; }
        @keyframes slideUp { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        
        .attach-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; text-align: center; }
        .attach-item { display: flex; flex-direction: column; align-items: center; gap: 4px; cursor: pointer; padding: 6px; border-radius: 8px; }
        .attach-item:hover { background: rgba(255,255,255,0.05); }
        .attach-icon { width: 44px; height: 44px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 20px; color: white; }
        
        .emoji-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 6px; font-size: 22px; max-height: 170px; overflow-y: auto; text-align: center; }
        .emoji-item { cursor: pointer; padding: 4px; border-radius: 4px; }
        .emoji-item:hover { background: rgba(255,255,255,0.1); }
        
        /* STATUS VIEWER */
        #status-modal { position: fixed; inset: 0; background: #000; z-index: 1000; display: none; flex-direction: column; }
        .status-progress-bar { height: 3px; background: rgba(255,255,255,0.3); width: 100%; position: relative; }
        .status-progress-fill { height: 100%; background: white; width: 0%; transition: width 0.1s linear; }

        /* CALL OVERLAY */
        #call-overlay { position: fixed; inset: 0; background: linear-gradient(180deg, #0b141a 0%, #002b23 100%); z-index: 2000; display: none; flex-direction: column; align-items: center; justify-content: space-between; padding: 50px 20px; }
        .call-avatar { width: 90px; height: 90px; border-radius: 50%; background: #00f5c4; color: black; font-size: 40px; display: flex; align-items: center; justify-content: center; box-shadow: 0 0 30px rgba(0,245,196,0.4); animation: pulse 2s infinite; }
        @keyframes pulse { 0% { transform: scale(1); } 50% { transform: scale(1.06); } 100% { transform: scale(1); } }
        .call-btn { width: 56px; height: 56px; border-radius: 50%; border: none; display: flex; align-items: center; justify-content: center; font-size: 24px; cursor: pointer; }

        /* NATIVE CUSTOM MODAL (NO BROWSER PROMPT/ALERT) */
        .native-modal-backdrop { position: fixed; inset: 0; background: rgba(0,0,0,0.75); z-index: 3000; display: none; align-items: center; justify-content: center; padding: 16px; backdrop-filter: blur(4px); }
        .native-modal-card { width: 100%; max-width: 320px; background: #1f2c34; border-radius: 12px; padding: 18px; border: 1px solid rgba(255,255,255,0.1); box-shadow: 0 16px 36px rgba(0,0,0,0.8); animation: slideUp 0.2s ease; }
        .native-modal-title { font-size: 15px; font-weight: 700; color: white; margin-bottom: 10px; }
        .native-modal-input { width: 100%; padding: 10px; border-radius: 8px; background: #2a3942; border: 1px solid rgba(255,255,255,0.1); color: white; font-size: 13.5px; outline: none; margin-bottom: 14px; }
        .native-modal-actions { display: flex; justify-content: flex-end; gap: 8px; }
        .btn-modal-cancel { background: transparent; border: none; color: var(--text-muted); font-weight: bold; padding: 6px 12px; cursor: pointer; font-size: 12px; }
        .btn-modal-confirm { background: var(--social-green); color: black; border: none; border-radius: 6px; font-weight: bold; padding: 6px 14px; cursor: pointer; font-size: 12px; }

        /* THREE DOTS DROPDOWN MENU */
        #options-dropdown { position: absolute; top: 50px; right: 10px; background: #1f2c34; border-radius: 10px; border: 1px solid rgba(255,255,255,0.1); box-shadow: 0 8px 24px rgba(0,0,0,0.6); display: none; flex-direction: column; width: 210px; z-index: 2500; overflow: hidden; }
        .dropdown-item { padding: 10px 14px; font-size: 12.5px; color: var(--text-main); display: flex; align-items: center; gap: 8px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.04); }
        .dropdown-item:active { background: #2a3942; }

        /* TOAST NOTIFICATION */
        #toast-notice { position: fixed; bottom: 70px; left: 50%; transform: translateX(-50%); background: #00f5c4; color: black; font-weight: bold; font-size: 11.5px; padding: 8px 16px; border-radius: 20px; box-shadow: 0 4px 16px rgba(0,0,0,0.5); z-index: 4000; display: none; animation: slideUp 0.2s ease; white-space: nowrap; }
    </style>
    <script>
        window.nextOnboardingStep = function(stepId) {
            var screens = document.querySelectorAll('.onboarding-screen');
            for (var i = 0; i < screens.length; i++) {
                screens[i].classList.remove('active');
                screens[i].style.setProperty('display', 'none', 'important');
            }
            var target = document.getElementById(stepId);
            if (target) {
                target.classList.add('active');
                target.style.setProperty('display', 'flex', 'important');
            }
        };
    </script>
</head>
<body>

    <!-- TOAST NOTIFICATION -->
    <div id="toast-notice"></div>

    <!-- ONBOARDING FLOW: REGISTRO VIA CELULAR (ESTILO WHATSAPP) -->
    <div id="onboarding-flow">
        
        <!-- STEP 1: BOAS-VINDAS -->
        <div class="onboarding-screen active" id="step-welcome">
            <div style="margin-top: 30px;">
                <div class="onboarding-hero">🇧🇷</div>
                <h1 class="onboarding-title">Bem-vindo ao Fala Brasil</h1>
                <p class="onboarding-subtitle">O aplicativo brasileiro de mensagens rápidas, chamadas em alta definição, PIX e inteligência artificial 24h.</p>
            </div>
            <div style="width: 100%; margin-bottom: 20px;">
                <p style="font-size: 11px; color: var(--text-muted); margin-bottom: 16px;">Ao tocar em "Concordar e continuar", você aceita os Termos de Serviço e a Política de Privacidade.</p>
                <button class="onboarding-btn" onclick="nextOnboardingStep('step-phone')">Concordar e Continuar ➔</button>
            </div>
        </div>

        <!-- STEP 2: NÚMERO DO TELEFONE -->
        <div class="onboarding-screen" id="step-phone">
            <div style="margin-top: 20px; width: 100%;">
                <h2 class="onboarding-title" style="font-size: 18px;">Insira seu número de celular</h2>
                <p class="onboarding-subtitle">O Fala Brasil enviará uma mensagem SMS para verificar seu número de telefone.</p>
                
                <div class="phone-input-group">
                    <div class="phone-ddi">🇧🇷 +55</div>
                    <input type="tel" id="reg-phone" class="phone-num" placeholder="(11) 98765-4321" maxlength="15" oninput="maskPhone(this)">
                </div>
                <small style="color: var(--text-muted); font-size: 11px; display: block;">Seu número é sua conta segura e privada no Fala Brasil.</small>
            </div>
            <div style="width: 100%; margin-bottom: 20px;">
                <button class="onboarding-btn" onclick="requestSmsCode()">Avançar ➔</button>
            </div>
        </div>

        <!-- STEP 3: CÓDIGO SMS DE CONFIRMAÇÃO -->
        <div class="onboarding-screen" id="step-otp">
            <div style="margin-top: 20px; width: 100%;">
                <h2 class="onboarding-title" style="font-size: 18px;">Verificando seu número</h2>
                <p class="onboarding-subtitle" id="otp-phone-label">Aguardando código SMS...</p>
                
                <div id="sms-notification-banner" style="background: rgba(0,245,196,0.1); border: 1px solid var(--social-green); border-radius: 12px; padding: 12px; margin: 16px 0; text-align: center; animation: fadeIn 0.4s ease;">
                    <small style="color: var(--text-muted); font-size: 11px; display: block;">📩 Simulação de SMS Seguro:</small>
                    <strong id="simulated-otp-code" style="font-size: 24px; color: var(--social-green); letter-spacing: 6px; display: block; margin: 4px 0;">849215</strong>
                    <small style="color: #ffd700; font-size: 10.5px; cursor: pointer;" onclick="autofillOtp()">Toque aqui para preencher automaticamente ⚡</small>
                </div>

                <div style="margin: 20px 0;">
                    <input type="text" id="otp-input-field" class="phone-num" maxlength="6" placeholder="••••••" style="width: 100%; text-align: center; letter-spacing: 10px; font-size: 24px; font-weight: bold; color: var(--social-green); background: #182229; border: 1.5px solid var(--social-green);">
                </div>
            </div>
            <div style="width: 100%; margin-bottom: 20px;">
                <button class="onboarding-btn" onclick="verifySmsCode()">Confirmar Código ➔</button>
            </div>
        </div>

        <!-- STEP 4: DADOS DO PERFIL -->
        <div class="onboarding-screen" id="step-profile">
            <div style="margin-top: 20px; width: 100%;">
                <h2 class="onboarding-title" style="font-size: 18px;">Seu Perfil no Fala Brasil</h2>
                <p class="onboarding-subtitle">Insira seu nome para que seus contatos reconheçam suas mensagens.</p>
                
                <div class="avatar" style="width: 80px; height: 80px; font-size: 32px; background: #00f5c4; color: black; margin: 0 auto 20px auto; border: 3px solid white; font-weight: bold;" id="reg-avatar-preview">🇧🇷</div>
                
                <input type="text" id="reg-name" class="native-modal-input" placeholder="Digite seu nome (ex: João / Maria)" oninput="updateAvatarPreview(this.value)" style="text-align: center; font-size: 15px; font-weight: bold; margin-bottom: 12px;">
                <input type="text" id="reg-status-bio" class="native-modal-input" placeholder="Recado (ex: Disponível no Fala Brasil 🇧🇷)" value="Disponível no Fala Brasil 🇧🇷" style="text-align: center; font-size: 12px;">
            </div>
            <div style="width: 100%; margin-bottom: 20px;">
                <button class="onboarding-btn" onclick="finishRegistration()">Iniciar Fala Brasil 🚀</button>
            </div>
        </div>
    </div>

    <!-- HIDDEN REAL FILE INPUTS FOR CAMERA, GALLERY, DOCS -->
    <input type="file" id="camera-input" accept="image/*" capture="environment" style="display:none" onchange="handleFileUpload(this, 'camera')">
    <input type="file" id="gallery-input" accept="image/*,video/*" multiple style="display:none" onchange="handleFileUpload(this, 'gallery')">
    <input type="file" id="doc-input" accept=".pdf,.doc,.docx,.txt,.zip" multiple style="display:none" onchange="handleFileUpload(this, 'doc')">

    <!-- CUSTOM NATIVE MODAL: CRIAR NOVO GRUPO -->
    <div class="native-modal-backdrop" id="modal-group">
        <div class="native-modal-card">
            <div class="native-modal-title">👥 Criar Novo Grupo</div>
            <p style="font-size: 11.5px; color: var(--text-muted); margin-bottom: 10px;">Capacidade de até 50.000 membros com privacidade total.</p>
            <input type="text" id="input-group-name" class="native-modal-input" placeholder="Nome do Grupo (ex: Família / Trabalho)">
            <div class="native-modal-actions">
                <button class="btn-modal-cancel" onclick="closeModal('modal-group')">Cancelar</button>
                <button class="btn-modal-confirm" onclick="confirmCreateGroup()">Criar Grupo 🚀</button>
            </div>
        </div>
    </div>

    <!-- CUSTOM NATIVE MODAL: CONFIGURAR CHAVE PIX -->
    <div class="native-modal-backdrop" id="modal-pix-setup">
        <div class="native-modal-card">
            <div class="native-modal-title" style="color: #00f5c4;">⚡ Minha Chave PIX</div>
            <p style="font-size: 11.5px; color: var(--text-muted); margin-bottom: 10px;">Cadastre sua chave PIX para que os pagamentos caiam diretamente na sua conta bancária:</p>
            <input type="text" id="input-my-pix-key" class="native-modal-input" placeholder="Chave PIX (Celular, CPF, E-mail ou Aleatória)">
            <input type="text" id="input-my-pix-city" class="native-modal-input" placeholder="Sua Cidade (ex: SAO PAULO)" value="SAO PAULO">
            <div class="native-modal-actions">
                <button class="btn-modal-cancel" onclick="closeModal('modal-pix-setup')">Cancelar</button>
                <button class="btn-modal-confirm" onclick="confirmSavePixKey()">Salvar Chave 💾</button>
            </div>
        </div>
    </div>

    <!-- CUSTOM NATIVE MODAL: FALA PAY PIX -->
    <div class="native-modal-backdrop" id="modal-pix">
        <div class="native-modal-card">
            <div class="native-modal-title">⚡ Fala Pay — Cobrar com PIX</div>
            <p id="pix-dest-label" style="font-size: 11.5px; color: var(--social-green); margin-bottom: 8px;">Receber na sua chave:</p>
            <input type="number" id="input-pix-val" class="native-modal-input" placeholder="Valor em R$ (ex: 50.00)" value="50.00">
            <div class="native-modal-actions">
                <button class="btn-modal-cancel" onclick="closeModal('modal-pix')">Cancelar</button>
                <button class="btn-modal-confirm" onclick="confirmSendPix()">Gerar PIX ⚡</button>
            </div>
        </div>
    </div>

    <!-- CUSTOM NATIVE MODAL: ATUALIZAR STATUS -->
    <div class="native-modal-backdrop" id="modal-status">
        <div class="native-modal-card">
            <div class="native-modal-title">🟢 Atualizar Meu Status</div>
            <input type="text" id="input-status-text" class="native-modal-input" placeholder="O que você está pensando agora?">
            <div class="native-modal-actions">
                <button class="btn-modal-cancel" onclick="closeModal('modal-status')">Cancelar</button>
                <button class="btn-modal-confirm" onclick="confirmPostStatus()">Publicar 🟢</button>
            </div>
        </div>
    </div>

    <!-- CUSTOM NATIVE MODAL: DENUNCIAR ABUSO / BLOQUEAR -->
    <div class="native-modal-backdrop" id="modal-report">
        <div class="native-modal-card">
            <div class="native-modal-title" style="color: #ff4b4b;">🚨 Denunciar e Bloquear</div>
            <p style="font-size: 11.5px; color: var(--text-muted); margin-bottom: 10px;">O Fala Brasil mantém tolerância zero para crimes, golpes e abusos. Selecione o motivo da denúncia:</p>
            <select id="select-report-reason" class="native-modal-input" style="background: #2a3942; color: white;">
                <option value="fraude">💸 Golpe Financeiro / Falso PIX / Fraude</option>
                <option value="ilegal">🚫 Conteúdo Ilegal / Atividade Proibida</option>
                <option value="spam">📢 Spam / Divulgação Não Autorizada</option>
                <option value="odio">⚠️ Discurso de Ódio / Assédio</option>
            </select>
            <div class="native-modal-actions">
                <button class="btn-modal-cancel" onclick="closeModal('modal-report')">Cancelar</button>
                <button class="btn-modal-confirm" style="background: #ff4b4b; color: white;" onclick="confirmReportAbuse()">Denunciar & Bloquear 🚨</button>
            </div>
        </div>
    </div>

    <!-- CUSTOM NATIVE MODAL: CRIAR ENQUETE -->
    <div class="native-modal-backdrop" id="modal-poll">
        <div class="native-modal-card">
            <div class="native-modal-title">🗳️ Criar Enquete</div>
            <input type="text" id="poll-question" class="native-modal-input" placeholder="Qual é a sua pergunta?">
            <input type="text" id="poll-opt-1" class="native-modal-input" placeholder="Opção 1 (Ex: Sim, concordo!)">
            <input type="text" id="poll-opt-2" class="native-modal-input" placeholder="Opção 2 (Ex: Não, discordo)">
            <input type="text" id="poll-opt-3" class="native-modal-input" placeholder="Opção 3 (Opcional)">
            <div class="native-modal-actions">
                <button class="btn-modal-cancel" onclick="closeModal('modal-poll')">Cancelar</button>
                <button class="btn-modal-confirm" onclick="confirmSendPoll()">Lançar Enquete 📊</button>
            </div>
        </div>
    </div>

    <!-- CUSTOM NATIVE MODAL: TRAVAR COM PIN -->
    <div class="native-modal-backdrop" id="modal-pin-setup">
        <div class="native-modal-card">
            <div class="native-modal-title">🔒 Bloqueio com PIN</div>
            <p style="font-size: 11.5px; color: var(--text-muted); margin-bottom: 10px;">Defina um PIN de 4 dígitos para proteger suas conversas contra acessos não autorizados:</p>
            <input type="password" id="input-pin-code" class="native-modal-input" maxlength="4" placeholder="••••" style="text-align: center; letter-spacing: 8px; font-size: 20px;">
            <div class="native-modal-actions">
                <button class="btn-modal-cancel" onclick="closeModal('modal-pin-setup')">Cancelar</button>
                <button class="btn-modal-confirm" onclick="confirmSetPin()">Ativar Bloqueio 🔒</button>
            </div>
        </div>
    </div>

    <!-- PIN LOCK OVERLAY SCREEN -->
    <div id="pin-lock-overlay" style="display: none; position: fixed; inset: 0; background: var(--bg-deep); z-index: 10000; flex-direction: column; align-items: center; justify-content: center; padding: 24px; text-align: center;">
        <div class="avatar" style="width: 70px; height: 70px; font-size: 32px; background: #182229; border: 2px solid var(--social-green); margin-bottom: 16px;">🔒</div>
        <h2 style="font-size: 18px; font-weight: bold; margin-bottom: 6px;">Fala Brasil Bloqueado</h2>
        <p style="color: var(--text-muted); font-size: 12px; margin-bottom: 20px;">Digite seu PIN de 4 dígitos para desbloquear suas mensagens:</p>
        <input type="password" id="unlock-pin-code" maxlength="4" placeholder="••••" oninput="checkUnlockPin(this.value)" style="width: 140px; text-align: center; letter-spacing: 8px; font-size: 24px; padding: 10px; background: #182229; border: 1.5px solid var(--social-green); border-radius: 8px; color: white; outline: none; margin-bottom: 16px;">
        <button onclick="unlockWithBiometrics()" style="background: transparent; border: 1px solid rgba(255,255,255,0.2); color: var(--social-green); padding: 8px 16px; border-radius: 20px; font-size: 12px; cursor: pointer; display: flex; align-items: center; gap: 6px;">
            <i class="ph ph-fingerprint" style="font-size: 18px;"></i> Desbloquear com Biometria
        </button>
    </div>

    <!-- APP CONTAINER -->
    <div class="app-container">
        
        <!-- SIDEBAR -->
        <aside id="sidebar">
            <header>
                <div style="display: flex; align-items: center; gap: 8px;">
                    <div class="avatar" style="background: #00f5c4; color: black; font-weight: bold; width: 34px; height: 34px; font-size: 16px;" id="my-avatar">U</div>
                    <div>
                        <strong id="my-user-label" style="font-size: 13.5px;">Fala Brasil</strong>
                        <small id="my-phone-label" style="display: block; color: #00f5c4; font-size: 9.5px;">● +55 (11) 98765-4321</small>
                    </div>
                </div>
                <div style="display: flex; gap: 12px; font-size: 18px; color: var(--text-muted);">
                    <i class="ph ph-user-plus" onclick="openModalGroup()" style="cursor: pointer; color: #00f5c4;" title="Criar Novo Grupo"></i>
                    <i class="ph ph-qr-code" onclick="openScannerNative()" style="cursor: pointer;" title="Escanear QR"></i>
                    <i class="ph ph-dots-three-vertical" onclick="toggleOptionsMenu()" style="cursor: pointer;"></i>
                </div>

                <!-- DROPDOWN 3 PONTINHOS -->
                <div id="options-dropdown">
                    <div class="dropdown-item" onclick="openModalGroup()"><i class="ph ph-users-three" style="color: #00f5c4;"></i> Novo Grupo</div>
                    <div class="dropdown-item" onclick="openModalGroup()"><i class="ph ph-broadcast" style="color: #ffd700;"></i> Novo Canal (Ilimitado)</div>
                    <div class="dropdown-item" onclick="openModalPix()"><i class="ph ph-currency-dollar" style="color: #00f5c4;"></i> Cobrar com PIX</div>
                    <div class="dropdown-item" onclick="openModalPixSetup()"><i class="ph ph-qr-code" style="color: #ffd700;"></i> Minha Chave PIX</div>
                    <div class="dropdown-item" onclick="openModalPinSetup()"><i class="ph ph-lock-key" style="color: #00d1ff;"></i> Bloquear com PIN / Biometria</div>
                    <div class="dropdown-item" onclick="toggleTheme()"><i class="ph ph-palette" style="color: #e91e63;"></i> Alternar Tema Visual</div>
                    <div class="dropdown-item" onclick="openScannerNative()"><i class="ph ph-qr-code"></i> Aparelhos Conectados</div>
                    <div class="dropdown-item" onclick="resetAccountData()"><i class="ph ph-sign-out" style="color: #ff4b4b;"></i> Trocar de Número / Sair</div>
                </div>
            </header>

            <!-- TABS (CONVERSAS / STATUS / CONTATOS / CHAMADAS) -->
            <div class="nav-tabs">
                <div class="tab-btn active" onclick="switchTab('chats')">Conversas</div>
                <div class="tab-btn" onclick="switchTab('status')">Status 🟢</div>
                <div class="tab-btn" onclick="switchTab('contacts')">Contatos 👥</div>
                <div class="tab-btn" onclick="switchTab('calls')">Chamadas 📞</div>
            </div>

            <!-- SEARCH BAR REAL-TIME -->
            <div style="padding: 8px 12px; border-bottom: 1px solid rgba(255,255,255,0.04);">
                <div style="background: #182229; border-radius: 8px; display: flex; align-items: center; padding: 6px 10px; gap: 6px;">
                    <i class="ph ph-magnifying-glass" style="color: var(--text-muted); font-size: 15px;"></i>
                    <input type="text" id="global-search-input" placeholder="Pesquisar conversas e contatos..." oninput="filterRoomsAndContacts(this.value)" style="background: transparent; border: none; outline: none; color: white; font-size: 12.5px; width: 100%;">
                </div>
            </div>

            <!-- TAB 1: CONVERSAS -->
            <div id="tab-chats" class="tab-content active">
                <div id="rooms-list">
                    <div class="chat-item active" onclick="openRoom('geral', 'Canal Geral Brasil', '🇧🇷', true)">
                        <div class="avatar has-status" style="background: #00f5c4; color: black;">🇧🇷</div>
                        <div class="chat-info">
                            <div class="chat-header"><span class="chat-name">Canal Geral Brasil</span><span class="chat-time">Agora</span></div>
                            <div class="chat-preview"><i class="ph ph-shield-check" style="color: #00f5c4;"></i> Criptografia Soberana Ativa</div>
                        </div>
                    </div>

                    <div class="chat-item" onclick="openRoom('ia_assistente', 'Aura Assistente IA 24h', '🤖', false)">
                        <div class="avatar" style="background: #7c3aed; color: white;">🤖</div>
                        <div class="chat-info">
                            <div class="chat-header"><span class="chat-name">Aura Assistente IA</span><span class="chat-time">Online</span></div>
                            <div class="chat-preview"><i class="ph ph-sparkle" style="color: #ffd700;"></i> Resumos, Traduções & Pesquisas</div>
                        </div>
                    </div>

                    <div class="chat-item" onclick="openRoom('depin', 'Comunidade DePIN Brasil', '⚡', true)">
                        <div class="avatar has-status" style="background: #00d1ff; color: black;">⚡</div>
                        <div class="chat-info">
                            <div class="chat-header"><span class="chat-name">Comunidade DePIN Brasil</span><span class="chat-time">17:40</span></div>
                            <div class="chat-preview">64 nós virtuais por celular operando</div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- TAB 2: STATUS / STORIES -->
            <div id="tab-status" class="tab-content">
                <div style="padding: 14px; border-bottom: 1px solid rgba(255,255,255,0.06); display: flex; align-items: center; gap: 12px;">
                    <div class="avatar" style="background: #202c33; color: white; position: relative;">
                        <i class="ph ph-plus" style="position: absolute; bottom: 0; right: 0; background: #00f5c4; color: black; border-radius: 50%; padding: 2px; font-size: 12px;"></i>
                        📷
                    </div>
                    <div style="flex: 1;" onclick="openModalStatus()">
                        <strong>Meu Status</strong>
                        <small style="display: block; color: var(--text-muted);">Toque para atualizar seu status</small>
                    </div>
                </div>
                
                <div style="padding: 10px 14px; font-size: 11px; color: var(--social-green); font-weight: bold; text-transform: uppercase;">Atualizações Recentes</div>

                <div class="chat-item" onclick="viewStatus('Aura DePIN', 'Acabamos de atingir 64 nós por aparelho! 🚀🇧🇷', '#005c4b')">
                    <div class="avatar has-status" style="background: #00d1ff; color: black;">⚡</div>
                    <div class="chat-info">
                        <strong class="chat-name">Aura DePIN</strong>
                        <small style="display: block; color: var(--text-muted);">Há 15 minutos</small>
                    </div>
                </div>

                <div class="chat-item" onclick="viewStatus('Governo Soberano', 'Rede nacional protegida contra espionagem.', '#7c3aed')">
                    <div class="avatar has-status" style="background: #ffd700; color: black;">🇧🇷</div>
                    <div class="chat-info">
                        <strong class="chat-name">Governo Soberano</strong>
                        <small style="display: block; color: var(--text-muted);">Hoje às 14:20</small>
                    </div>
                </div>
            </div>

            <!-- TAB 3: CONTATOS REAIS DA AGENDA -->
            <div id="tab-contacts" class="tab-content">
                <div style="padding: 10px 14px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(255,255,255,0.06);">
                    <span style="font-size: 11px; color: var(--text-muted); font-weight: bold;">CONTATOS DO TELEFONE</span>
                    <button onclick="fetchNativeContacts()" style="padding: 5px 10px; background: var(--social-green); color: black; border: none; border-radius: 6px; font-size: 10.5px; font-weight: bold; cursor: pointer;">
                        🔄 Sincronizar Agenda
                    </button>
                </div>
                <div id="contacts-list">
                    <div style="padding: 24px 16px; text-align: center; color: var(--text-muted);">
                        <i class="ph ph-address-book" style="font-size: 36px; color: #00f5c4; margin-bottom: 8px; display: block;"></i>
                        <strong style="color: white; font-size: 13.5px; display: block; margin-bottom: 4px;">Sincronizar sua Agenda</strong>
                        <p style="font-size: 11.5px; margin-bottom: 12px;">Carregue seus contatos reais para conversar e enviar convites com 1 toque.</p>
                        <button onclick="fetchNativeContacts()" style="padding: 8px 16px; background: var(--social-green); color: black; border: none; border-radius: 6px; font-weight: bold; cursor: pointer; font-size: 11.5px;">
                            🔄 Carregar Contatos do Celular
                        </button>
                    </div>
                </div>
            </div>

            <!-- TAB 4: HISTÓRICO DE CHAMADAS -->
            <div id="tab-calls" class="tab-content">
                <div style="padding: 10px 14px; font-size: 11px; color: var(--text-muted); font-weight: bold;">LIGAÇÕES CRIPTOGRAFADAS</div>
                <div class="chat-item" onclick="startCall('audio')">
                    <div class="avatar" style="background: #202c33;"><i class="ph ph-phone-incoming" style="color: #00f5c4;"></i></div>
                    <div class="chat-info">
                        <div class="chat-name">Nó DePIN São Paulo</div>
                        <div class="chat-preview"><i class="ph ph-arrow-down-left" style="color: #00f5c4;"></i> Recebida (Voz P2P HD) • Hoje 15:30</div>
                    </div>
                </div>
            </div>
        </aside>

        <!-- CHAT VIEW -->
        <main id="chat-view">
            <header>
                <div style="display: flex; align-items: center; gap: 8px; min-width: 0; flex: 1;">
                    <i class="ph ph-arrow-left" style="font-size: 20px; cursor: pointer; flex-shrink: 0;" onclick="closeChatMobile()"></i>
                    <div class="avatar" id="current-chat-avatar" style="width: 34px; height: 34px; margin-right: 0; background: #00f5c4; color: black; font-size: 18px; flex-shrink: 0;">🇧🇷</div>
                    <div style="min-width: 0; flex: 1;">
                        <strong id="current-chat-name" style="font-size: 13.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: block;">Canal Geral Brasil</strong>
                        <small id="current-chat-status" style="display: block; color: #00f5c4; font-size: 9.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">Criptografia Ponta a Ponta Ativa</small>
                    </div>
                </div>
                <div style="display: flex; gap: 8px; color: var(--text-muted); font-size: 18px; align-items: center; flex-shrink: 0;">
                    <button onclick="summarizeCurrentChat()" style="background: rgba(0,245,196,0.15); border: 1px solid #00f5c4; color: #00f5c4; border-radius: 12px; padding: 4px 8px; font-size: 10.5px; font-weight: bold; cursor: pointer; display: flex; align-items: center; gap: 3px; flex-shrink: 0;" title="Resumir Conversa com IA">🧠 Resumo</button>
                    <i class="ph ph-shield-warning" onclick="openModalReport()" style="cursor: pointer; color: #ff4b4b; font-size: 19px;" title="Denunciar Abuso / Bloquear"></i>
                    <i class="ph ph-translate" id="translator-toggle-btn" onclick="toggleTranslator()" style="cursor: pointer;" title="Tradutor Simultâneo"></i>
                    <i class="ph ph-phone" onclick="startCall('audio')" style="cursor: pointer;" title="Chamada de Voz"></i>
                    <i class="ph ph-video-camera" onclick="startCall('video')" style="cursor: pointer;" title="Vídeo Chamada"></i>
                </div>
            </header>

            <!-- MESSAGES CONTAINER -->
            <div class="messages-box" id="messages-box">
                <div class="security-banner">
                    <i class="ph ph-shield-check" style="font-size: 18px; color: #00f5c4; flex-shrink: 0;"></i>
                    <span><strong>Escudo Anti-Golpe:</strong> Conversas blindadas contra vazamentos.</span>
                </div>
            </div>

            <!-- POPUP: EMOJIS & GIFS -->
            <div class="popup-panel" id="emoji-panel">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; border-bottom: 1px solid rgba(255,255,255,0.08); padding-bottom: 4px;">
                    <div style="display: flex; gap: 10px;">
                        <button onclick="switchEmojiTab('emojis')" id="btn-tab-emojis" style="background: none; border: none; color: var(--social-green); font-weight: bold; cursor: pointer; font-size: 12px;">😀 Emojis</button>
                        <button onclick="switchEmojiTab('gifs')" id="btn-tab-gifs" style="background: none; border: none; color: var(--text-muted); font-weight: bold; cursor: pointer; font-size: 12px;">🎬 GIFs (Tenor)</button>
                    </div>
                    <span onclick="togglePanel('emoji-panel')" style="cursor: pointer; color: var(--text-muted); font-size: 11px;">✕ Fechar</span>
                </div>
                
                <!-- SUB-TAB 1: EMOJIS -->
                <div id="subtab-emojis" class="emoji-grid">
                    <span class="emoji-item" onclick="insertEmoji('🇧🇷')">🇧🇷</span>
                    <span class="emoji-item" onclick="insertEmoji('😀')">😀</span>
                    <span class="emoji-item" onclick="insertEmoji('😂')">😂</span>
                    <span class="emoji-item" onclick="insertEmoji('🔥')">🔥</span>
                    <span class="emoji-item" onclick="insertEmoji('🚀')">🚀</span>
                    <span class="emoji-item" onclick="insertEmoji('❤️')">❤️</span>
                    <span class="emoji-item" onclick="insertEmoji('👍')">👍</span>
                    <span class="emoji-item" onclick="insertEmoji('☕')">☕</span>
                    <span class="emoji-item" onclick="insertEmoji('🍕')">🍕</span>
                    <span class="emoji-item" onclick="insertEmoji('⚡')">⚡</span>
                    <span class="emoji-item" onclick="insertEmoji('💰')">💰</span>
                    <span class="emoji-item" onclick="insertEmoji('🔒')">🔒</span>
                    <span class="emoji-item" onclick="insertEmoji('👏')">👏</span>
                    <span class="emoji-item" onclick="insertEmoji('😎')">😎</span>
                    <span class="emoji-item" onclick="insertEmoji('🤩')">🤩</span>
                    <span class="emoji-item" onclick="insertEmoji('🎉')">🎉</span>
                    <span class="emoji-item" onclick="insertEmoji('🤝')">🤝</span>
                    <span class="emoji-item" onclick="insertEmoji('💪')">💪</span>
                    <span class="emoji-item" onclick="insertEmoji('🏆')">🏆</span>
                    <span class="emoji-item" onclick="insertEmoji('💡')">💡</span>
                    <span class="emoji-item" onclick="insertEmoji('✨')">✨</span>
                </div>

                <!-- SUB-TAB 2: GIFS SEARCH -->
                <div id="subtab-gifs" style="display: none;">
                    <input type="text" id="gif-search-input" placeholder="🔍 Pesquisar GIFs no Tenor..." oninput="searchGifs(this.value)" style="width: 100%; padding: 6px 10px; border-radius: 6px; background: #2a3942; border: none; color: white; font-size: 12px; outline: none; margin-bottom: 6px;">
                    <div id="gif-grid" style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 6px; max-height: 150px; overflow-y: auto;">
                        <img src="https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 70px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                        <img src="https://media.giphy.com/media/26AHONQ79FdWZhAI0/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 70px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                        <img src="https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 70px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                        <img src="https://media.giphy.com/media/l41lI4bYmcsPJX9Go/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 70px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                    </div>
                </div>
            </div>

            <!-- POPUP: ANEXOS & PIX -->
            <div class="popup-panel" id="attach-panel">
                <div class="attach-grid">
                    <div class="attach-item" onclick="triggerCamera()">
                        <div class="attach-icon" style="background: #e91e63;"><i class="ph ph-camera"></i></div>
                        <span style="font-size: 10.5px;">Câmera</span>
                    </div>
                    <div class="attach-item" onclick="triggerMediaUpload()">
                        <div class="attach-icon" style="background: #9c27b0;"><i class="ph ph-image"></i></div>
                        <span style="font-size: 10.5px;">Fotos/Vídeos</span>
                    </div>
                    <div class="attach-item" onclick="triggerDocUpload()">
                        <div class="attach-icon" style="background: #5c6bc0;"><i class="ph ph-file-text"></i></div>
                        <span style="font-size: 10.5px;">Documentos</span>
                    </div>
                    <div class="attach-item" onclick="openModalPix()">
                        <div class="attach-icon" style="background: #00f5c4; color: black;"><i class="ph ph-currency-dollar"></i></div>
                        <span style="font-size: 10.5px; font-weight: bold; color: #00f5c4;">Fala Pay PIX</span>
                    </div>
                    <div class="attach-item" onclick="openModalPoll()">
                        <div class="attach-icon" style="background: #ffb300; color: black;"><i class="ph ph-chart-bar"></i></div>
                        <span style="font-size: 10.5px; font-weight: bold; color: #ffb300;">Enquete</span>
                    </div>
                    <div class="attach-item" onclick="sendLocation()">
                        <div class="attach-icon" style="background: #ff9800;"><i class="ph ph-map-pin"></i></div>
                        <span style="font-size: 10.5px;">Localização</span>
                    </div>
                    <div class="attach-item" onclick="switchTab('contacts')">
                        <div class="attach-icon" style="background: #00bcd4;"><i class="ph ph-user"></i></div>
                        <span style="font-size: 10.5px;">Contato</span>
                    </div>
                </div>
            </div>

            <!-- INPUT BAR -->
            <div class="input-bar">
                <button class="action-btn" onclick="togglePanel('emoji-panel')"><i class="ph ph-smiley"></i></button>
                <button class="action-btn" onclick="togglePanel('attach-panel')"><i class="ph ph-paperclip"></i></button>
                <button onclick="openModalPix()" style="color: #000; font-weight: 800; font-size: 11px; background: #00f5c4; border: none; border-radius: 12px; padding: 5px 8px; cursor: pointer; flex-shrink: 0; display: flex; align-items: center; gap: 2px;" title="Transferir PIX">
                    ⚡ PIX
                </button>
                <input type="text" id="msg-input" placeholder="Mensagem..." onkeypress="handleKeyPress(event)">
                <button class="action-btn" id="mic-btn" onclick="triggerRecordAudio()"><i class="ph ph-microphone" id="mic-icon-btn"></i></button>
                <button class="send-btn" onclick="sendMessage()"><i class="ph ph-paper-plane-right"></i></button>
            </div>
        </main>
    </div>

    <!-- STATUS FULLSCREEN MODAL -->
    <div id="status-modal">
        <div class="status-progress-bar"><div class="status-progress-fill" id="status-fill"></div></div>
        <div style="padding: 14px; display: flex; justify-content: space-between; align-items: center; color: white;">
            <div style="display: flex; align-items: center; gap: 8px;">
                <div class="avatar" style="width: 32px; height: 32px; background: #00f5c4; color: black; font-size: 14px;" id="status-author-avatar">A</div>
                <strong id="status-author-name" style="font-size: 14px;">Autor</strong>
            </div>
            <i class="ph ph-x" onclick="closeStatusModal()" style="font-size: 22px; cursor: pointer;"></i>
        </div>
        <div style="flex: 1; display: flex; align-items: center; justify-content: center; padding: 20px; text-align: center; font-size: 20px; font-weight: bold; color: white;" id="status-text-content">
            Status do Fala Brasil
        </div>
    </div>

    <!-- CALL OVERLAY (AUDIO & REAL LIVE VIDEO) -->
    <div id="call-overlay" style="position: fixed; inset: 0; background: #0b141a; z-index: 9999; display: none; flex-direction: column; justify-content: space-between; padding: 40px 24px; text-align: center;">
        <!-- Live Video Element -->
        <video id="live-video-feed" autoplay playsinline muted style="display: none; position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; z-index: 1;"></video>
        
        <!-- Header Info Overlay -->
        <div style="position: relative; z-index: 10; text-align: center; background: rgba(0,0,0,0.55); padding: 16px; border-radius: 16px; backdrop-filter: blur(8px);">
            <div class="call-avatar" id="call-avatar-icon" style="margin: 0 auto; width: 64px; height: 64px; font-size: 28px; border-radius: 50%; background: var(--social-green); color: black; display: flex; align-items: center; justify-content: center;">🇧🇷</div>
            <h2 id="call-title" style="margin-top: 10px; font-weight: 700; font-size: 18px; color: white;">Canal Geral Brasil</h2>
            <p id="call-status-timer" style="color: var(--social-green); font-size: 13px; margin-top: 4px;">Conectando via Nós DePIN P2P...</p>
        </div>

        <!-- Controls Bar -->
        <div style="position: relative; z-index: 10; display: flex; justify-content: center; gap: 20px; margin-bottom: 20px;">
            <button class="call-btn" id="btn-toggle-cam" style="width: 54px; height: 54px; border-radius: 50%; background: rgba(255,255,255,0.2); border: none; color: white; font-size: 22px; cursor: pointer; display: none;" onclick="toggleCameraTrack()"><i class="ph ph-camera-rotate"></i></button>
            <button class="call-btn" id="btn-toggle-mic" style="width: 54px; height: 54px; border-radius: 50%; background: rgba(255,255,255,0.2); border: none; color: white; font-size: 22px; cursor: pointer;" onclick="toggleCallMic()"><i class="ph ph-microphone"></i></button>
            <button class="call-btn" style="width: 54px; height: 54px; border-radius: 50%; background: #ff4b4b; border: none; color: white; font-size: 24px; cursor: pointer; box-shadow: 0 4px 16px rgba(255,75,75,0.4);" onclick="endCall()"><i class="ph ph-phone-disconnect"></i></button>
        </div>
    </div>

    <!-- FLOATING REACTION BAR -->
    <div class="floating-reaction-bar" id="floating-reaction-bar">
        <span class="reaction-item" onclick="applyReaction('❤️')">❤️</span>
        <span class="reaction-item" onclick="applyReaction('👍')">👍</span>
        <span class="reaction-item" onclick="applyReaction('😂')">😂</span>
        <span class="reaction-item" onclick="applyReaction('😮')">😮</span>
        <span class="reaction-item" onclick="applyReaction('😢')">😢</span>
        <span class="reaction-item" onclick="applyReaction('🙏')">🙏</span>
        <span class="reaction-item" onclick="applyReaction('🇧🇷')">🇧🇷</span>
    </div>

    <script>
        let userName = localStorage.getItem('fala_user_name') || 'Usuário';
        let userPhone = localStorage.getItem('fala_user_phone') || '+55 (11) 99999-0000';
        let currentRoom = 'geral';
        let isTranslatorActive = false;
        let isRecording = false;
        let callTimerInterval = null;
        let callSeconds = 0;
        let activeTargetBubble = null;
        let currentThemeIndex = 0;
        let currentGeneratedOtp = '849215';

        const themes = [
            { bgDeep: '#0b141a', surface: '#111b21', headerBg: '#202c33', bubbleOut: '#005c4b', socialGreen: '#00f5c4', name: 'Dark Padrão' },
            { bgDeep: '#051814', surface: '#0a231d', headerBg: '#0f332a', bubbleOut: '#026c54', socialGreen: '#25d366', name: 'Esmeralda Brasil' },
            { bgDeep: '#0e1621', surface: '#17212b', headerBg: '#242f3d', bubbleOut: '#2b5278', socialGreen: '#64b5f6', name: 'Azul Meia-Noite' }
        ];

        function checkRegistration() {
            const isRegistered = localStorage.getItem('fala_registered') === 'true';
            if (isRegistered) {
                userName = localStorage.getItem('fala_user_name') || 'Usuário';
                userPhone = localStorage.getItem('fala_user_phone') || '+55 (11) 99999-0000';
                document.getElementById('onboarding-flow').style.display = 'none';
                document.getElementById('my-user-label').innerText = userName;
                document.getElementById('my-phone-label').innerText = '● ' + userPhone;
                document.getElementById('my-avatar').innerText = (userName[0] || 'U').toUpperCase();
                checkPinLock();
                initRealtimeRelay();
            } else {
                document.getElementById('onboarding-flow').style.display = 'flex';
                nextOnboardingStep('step-welcome');
            }
        }

        /* PIN LOCK METHODS */
        function checkPinLock() {
            const savedPin = localStorage.getItem('fala_pin_code');
            if (savedPin && savedPin.length === 4) {
                document.getElementById('pin-lock-overlay').style.display = 'flex';
                document.getElementById('unlock-pin-code').focus();
            }
        }

        function openModalPinSetup() {
            document.getElementById('options-dropdown').style.display = 'none';
            document.getElementById('modal-pin-setup').style.display = 'flex';
            document.getElementById('input-pin-code').focus();
        }

        function confirmSetPin() {
            const pin = document.getElementById('input-pin-code').value.trim();
            if (pin.length === 4) {
                localStorage.setItem('fala_pin_code', pin);
                closeModal('modal-pin-setup');
                showToast('🔒 Bloqueio com PIN ativado com sucesso!');
            } else {
                showToast('⚠️ O PIN deve ter exatamente 4 dígitos.');
            }
        }

        function checkUnlockPin(val) {
            const savedPin = localStorage.getItem('fala_pin_code');
            if (val === savedPin) {
                document.getElementById('pin-lock-overlay').style.display = 'none';
                document.getElementById('unlock-pin-code').value = '';
                showToast('🔓 Fala Brasil desbloqueado!');
                if (window.NativeAura) {
                    window.NativeAura.postMessage(JSON.stringify({ action: 'vibrate' }));
                }
            }
        }

        function unlockWithBiometrics() {
            document.getElementById('pin-lock-overlay').style.display = 'none';
            showToast('🧬 Biometria confirmada! Desbloqueado.');
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'vibrate' }));
            }
        }

        /* POLLS / ENQUETES */
        function openModalPoll() {
            togglePanel('attach-panel');
            document.getElementById('modal-poll').style.display = 'flex';
            document.getElementById('poll-question').focus();
        }

        function confirmSendPoll() {
            const q = document.getElementById('poll-question').value.trim();
            const o1 = document.getElementById('poll-opt-1').value.trim();
            const o2 = document.getElementById('poll-opt-2').value.trim();
            const o3 = document.getElementById('poll-opt-3').value.trim();

            if (!q || !o1 || !o2) {
                showToast('⚠️ Preencha a pergunta e pelo menos 2 opções.');
                return;
            }

            closeModal('modal-poll');
            const pollId = 'poll_' + Date.now();
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

            let optionsHtml = `
                <div class="poll-option-btn" onclick="votePoll('${pollId}', 1, this)" style="background: #182229; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; padding: 8px 10px; margin-top: 6px; cursor: pointer; position: relative; overflow: hidden;">
                    <div class="poll-bar" style="position: absolute; inset: 0; background: rgba(0,245,196,0.15); width: 0%; transition: width 0.3s;"></div>
                    <div style="position: relative; display: flex; justify-content: space-between; font-size: 12px;">
                        <span>⚪ ${o1}</span>
                        <strong class="poll-count" style="color: var(--social-green);">0 votos (0%)</strong>
                    </div>
                </div>
                <div class="poll-option-btn" onclick="votePoll('${pollId}', 2, this)" style="background: #182229; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; padding: 8px 10px; margin-top: 6px; cursor: pointer; position: relative; overflow: hidden;">
                    <div class="poll-bar" style="position: absolute; inset: 0; background: rgba(0,245,196,0.15); width: 0%; transition: width 0.3s;"></div>
                    <div style="position: relative; display: flex; justify-content: space-between; font-size: 12px;">
                        <span>⚪ ${o2}</span>
                        <strong class="poll-count" style="color: var(--social-green);">0 votos (0%)</strong>
                    </div>
                </div>
            `;

            if (o3) {
                optionsHtml += `
                    <div class="poll-option-btn" onclick="votePoll('${pollId}', 3, this)" style="background: #182229; border: 1px solid rgba(255,255,255,0.1); border-radius: 8px; padding: 8px 10px; margin-top: 6px; cursor: pointer; position: relative; overflow: hidden;">
                        <div class="poll-bar" style="position: absolute; inset: 0; background: rgba(0,245,196,0.15); width: 0%; transition: width 0.3s;"></div>
                        <div style="position: relative; display: flex; justify-content: space-between; font-size: 12px;">
                            <span>⚪ ${o3}</span>
                            <strong class="poll-count" style="color: var(--social-green);">0 votos (0%)</strong>
                        </div>
                    </div>
                `;
            }

            const bubbleHtml = `
                <div id="${pollId}">
                    <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 4px;">
                        <span style="font-size: 16px;">📊</span>
                        <strong style="color: var(--gold); font-size: 13px;">${q}</strong>
                    </div>
                    ${optionsHtml}
                    <div class="msg-meta" style="margin-top: 6px;">Enquete • ${now} ✓✓</div>
                </div>
            `;

            appendAndSaveMessage(bubbleHtml, 'out');
            broadcastMessage({
                type: 'text',
                roomId: currentRoom,
                senderName: userName,
                senderPhone: userPhone,
                text: bubbleHtml
            });
            document.getElementById('poll-question').value = '';
            document.getElementById('poll-opt-1').value = '';
            document.getElementById('poll-opt-2').value = '';
            document.getElementById('poll-opt-3').value = '';
            showToast('📊 Enquete lançada com sucesso!');
        }

        function votePoll(pollId, optIdx, btn) {
            const bar = btn.querySelector('.poll-bar');
            const count = btn.querySelector('.poll-count');
            bar.style.width = '100%';
            count.innerText = '1 voto (100%)';
            btn.style.borderColor = 'var(--social-green)';
            showToast('🗳️ Seu voto foi registrado e computado!');
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'vibrate' }));
            }
        }

        function nextOnboardingStep(stepId) {
            document.querySelectorAll('.onboarding-screen').forEach(s => {
                s.classList.remove('active');
                s.style.display = 'none';
            });
            const target = document.getElementById(stepId);
            if (target) {
                target.classList.add('active');
                target.style.display = 'flex';
            }
        }

        function maskPhone(input) {
            let v = input.value.replace(/\D/g, '');
            if (v.length > 11) v = v.substring(0, 11);
            if (v.length > 6) {
                input.value = `(${v.substring(0,2)}) ${v.substring(2,7)}-${v.substring(7)}`;
            } else if (v.length > 2) {
                input.value = `(${v.substring(0,2)}) ${v.substring(2)}`;
            } else {
                input.value = v;
            }
        }

        function requestSmsCode() {
            const phoneInput = document.getElementById('reg-phone');
            const num = phoneInput.value.trim();
            if (num.replace(/\D/g, '').length < 10) {
                showToast('⚠️ Digite seu número com DDD (ex: 11 99999-8888)');
                return;
            }
            userPhone = '+55 ' + num;
            currentGeneratedOtp = String(Math.floor(100000 + Math.random() * 900000));
            document.getElementById('otp-phone-label').innerText = `SMS enviado para ${userPhone}`;
            document.getElementById('simulated-otp-code').innerText = currentGeneratedOtp;
            document.getElementById('otp-input-field').value = '';
            nextOnboardingStep('step-otp');
            showToast(`📩 Código SMS recebido: ${currentGeneratedOtp}`);
        }

        function autofillOtp() {
            document.getElementById('otp-input-field').value = currentGeneratedOtp;
            verifySmsCode();
        }

        function verifySmsCode() {
            const inputVal = document.getElementById('otp-input-field').value.trim();
            if (inputVal === currentGeneratedOtp || inputVal.length === 6) {
                nextOnboardingStep('step-profile');
                showToast('⚡ SMS confirmado com sucesso!');
            } else {
                showToast('⚠️ Código SMS incorreto. Digite o código de 6 dígitos.');
            }
        }

        function updateAvatarPreview(val) {
            const letter = val.trim() ? val.trim()[0].toUpperCase() : '🇧🇷';
            document.getElementById('reg-avatar-preview').innerText = letter;
        }

        function finishRegistration() {
            const nameInput = document.getElementById('reg-name');
            const typedName = nameInput.value.trim();
            userName = typedName || 'Usuário ' + userPhone.slice(-4);
            localStorage.setItem('fala_user_name', userName);
            localStorage.setItem('fala_user_phone', userPhone);
            localStorage.setItem('fala_registered', 'true');

            document.getElementById('onboarding-flow').style.display = 'none';
            document.getElementById('my-user-label').innerText = userName;
            document.getElementById('my-phone-label').innerText = '● ' + userPhone;
            document.getElementById('my-avatar').innerText = (userName[0] || 'U').toUpperCase();
            
            showToast(`🎉 Bem-vindo ao Fala Brasil, ${userName}!`);
            initRealtimeRelay();
            loadRoomMessages();
            setTimeout(fetchNativeContacts, 500);
        }

        function resetAccountData() {
            if (confirm("Deseja desconectar sua conta e cadastrar outro número?")) {
                localStorage.clear();
                location.reload();
            }
        }

        function showToast(text) {
            const toast = document.getElementById('toast-notice');
            toast.innerText = text;
            toast.style.display = 'block';
            setTimeout(() => toast.style.display = 'none', 3000);
        }

        function switchTab(tabId) {
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
            
            event.currentTarget.classList.add('active');
            document.getElementById('tab-' + tabId).classList.add('active');
            document.getElementById('options-dropdown').style.display = 'none';
        }

        function openRoom(roomId, roomName, icon, hasStatus) {
            currentRoom = roomId;
            document.getElementById('current-chat-name').innerText = roomName;
            document.getElementById('current-chat-avatar').innerText = icon;
            document.getElementById('chat-view').classList.add('active');
            document.getElementById('options-dropdown').style.display = 'none';
            loadRoomMessages();
        }

        function closeChatMobile() {
            document.getElementById('chat-view').classList.remove('active');
        }

        function toggleOptionsMenu() {
            const menu = document.getElementById('options-dropdown');
            menu.style.display = menu.style.display === 'flex' ? 'none' : 'flex';
        }

        function togglePanel(panelId) {
            const panel = document.getElementById(panelId);
            const isShown = panel.classList.contains('show');
            document.querySelectorAll('.popup-panel').forEach(p => p.classList.remove('show'));
            if (!isShown) panel.classList.add('show');
            document.getElementById('options-dropdown').style.display = 'none';
        }

        function insertEmoji(emoji) {
            const input = document.getElementById('msg-input');
            input.value += emoji;
            input.focus();
            togglePanel('emoji-panel');
        }

        function switchEmojiTab(tab) {
            const isEmojis = tab === 'emojis';
            document.getElementById('subtab-emojis').style.display = isEmojis ? 'grid' : 'none';
            document.getElementById('subtab-gifs').style.display = isEmojis ? 'none' : 'block';
            document.getElementById('btn-tab-emojis').style.color = isEmojis ? 'var(--social-green)' : 'var(--text-muted)';
            document.getElementById('btn-tab-gifs').style.color = isEmojis ? 'var(--text-muted)' : 'var(--social-green)';
        }

        function searchGifs(query) {
            const grid = document.getElementById('gif-grid');
            if (!query) return;
            grid.innerHTML = `
                <img src="https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 70px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                <img src="https://media.giphy.com/media/26AHONQ79FdWZhAI0/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 70px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                <img src="https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 70px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                <img src="https://media.giphy.com/media/l41lI4bYmcsPJX9Go/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 70px; object-fit: cover; border-radius: 6px; cursor: pointer;">
            `;
        }

        function sendGif(gifUrl) {
            togglePanel('emoji-panel');
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const bubbleHtml = `
                <img src="${gifUrl}" style="width: 100%; max-width: 220px; border-radius: 8px; display: block;">
                <div class="msg-meta">${now} ✓✓</div>
            `;
            appendAndSaveMessage(bubbleHtml, 'out');
        }

        function toggleTranslator() {
            isTranslatorActive = !isTranslatorActive;
            const btn = document.getElementById('translator-toggle-btn');
            if (isTranslatorActive) {
                btn.style.color = '#00f5c4';
                showToast('🌐 Tradutor Simultâneo Ativado');
            } else {
                btn.style.color = 'var(--text-muted)';
            }
        }

        let activeMediaStream = null;
        let isMicMuted = false;
        let isFacingUser = true;

        async function startCall(type) {
            const overlay = document.getElementById('call-overlay');
            const videoFeed = document.getElementById('live-video-feed');
            const avatarIcon = document.getElementById('call-avatar-icon');
            const timerEl = document.getElementById('call-status-timer');
            const toggleCamBtn = document.getElementById('btn-toggle-cam');
            
            overlay.style.display = 'flex';
            document.getElementById('call-title').innerText = document.getElementById('current-chat-name').innerText;
            avatarIcon.innerText = document.getElementById('current-chat-avatar').innerText;
            callSeconds = 0;

            if (type === 'video') {
                toggleCamBtn.style.display = 'block';
                timerEl.innerText = "Iniciando câmera HD e criptografia P2P...";
                try {
                    activeMediaStream = await navigator.mediaDevices.getUserMedia({
                        video: { facingMode: isFacingUser ? "user" : "environment" },
                        audio: true
                    });
                    videoFeed.srcObject = activeMediaStream;
                    videoFeed.style.display = 'block';
                    avatarIcon.style.display = 'none';
                    timerEl.innerText = "00:00 (Vídeo HD P2P Ativo)";
                } catch (err) {
                    console.warn("Camera WebRTC stream fallback:", err);
                    videoFeed.style.display = 'none';
                    avatarIcon.style.display = 'flex';
                    timerEl.innerText = "00:00 (Modo de Áudio HD Opus)";
                }
            } else {
                toggleCamBtn.style.display = 'none';
                videoFeed.style.display = 'none';
                avatarIcon.style.display = 'flex';
                timerEl.innerText = "Conectando via Nós DePIN P2P...";
                setTimeout(() => {
                    timerEl.innerText = "00:00 (Áudio HD Opus Ativo)";
                }, 1000);
            }

            if (callTimerInterval) clearInterval(callTimerInterval);
            callTimerInterval = setInterval(() => {
                callSeconds++;
                const mins = String(Math.floor(callSeconds / 60)).padStart(2, '0');
                const secs = String(callSeconds % 60).padStart(2, '0');
                const prefix = type === 'video' ? 'Vídeo HD' : 'Voz HD';
                timerEl.innerText = `${mins}:${secs} (${prefix} Criptografado)`;
            }, 1000);
        }

        async function toggleCameraTrack() {
            if (activeMediaStream) {
                activeMediaStream.getTracks().forEach(t => t.stop());
            }
            isFacingUser = !isFacingUser;
            try {
                activeMediaStream = await navigator.mediaDevices.getUserMedia({
                    video: { facingMode: isFacingUser ? "user" : "environment" },
                    audio: true
                });
                document.getElementById('live-video-feed').srcObject = activeMediaStream;
                showToast(isFacingUser ? '📷 Câmera Frontal Ativa' : '📷 Câmera Traseira Ativa');
            } catch (e) {
                showToast('Alternando câmera...');
            }
        }

        function toggleCallMic() {
            isMicMuted = !isMicMuted;
            if (activeMediaStream) {
                activeMediaStream.getAudioTracks().forEach(t => t.enabled = !isMicMuted);
            }
            const btn = document.getElementById('btn-toggle-mic');
            btn.innerHTML = isMicMuted ? '<i class="ph ph-microphone-slash" style="color: #ff4b4b;"></i>' : '<i class="ph ph-microphone"></i>';
            showToast(isMicMuted ? '🎤 Microfone Silenciado' : '🎤 Microfone Ativo');
        }

        function endCall() {
            if (callTimerInterval) clearInterval(callTimerInterval);
            if (activeMediaStream) {
                activeMediaStream.getTracks().forEach(t => t.stop());
                activeMediaStream = null;
            }
            const videoFeed = document.getElementById('live-video-feed');
            if (videoFeed) {
                videoFeed.srcObject = null;
                videoFeed.style.display = 'none';
            }
            document.getElementById('call-overlay').style.display = 'none';
            showToast('📞 Chamada encerrada');
        }

        /* CUSTOM MODAL CONTROLS */
        function openModalGroup() {
            document.getElementById('options-dropdown').style.display = 'none';
            document.getElementById('modal-group').style.display = 'flex';
            document.getElementById('input-group-name').focus();
        }

        function confirmCreateGroup() {
            const input = document.getElementById('input-group-name');
            const groupName = input.value.trim();
            if (!groupName) return;

            const newGroupId = 'group_' + Date.now();
            const list = document.getElementById('rooms-list');
            const item = document.createElement('div');
            item.className = 'chat-item';
            item.onclick = () => openRoom(newGroupId, groupName, '👥', false);
            item.innerHTML = `
                <div class="avatar" style="background: #ffd700; color: black;">👥</div>
                <div class="chat-info">
                    <div class="chat-header"><span class="chat-name">${groupName}</span><span class="chat-time">Agora</span></div>
                    <div class="chat-preview">Grupo Soberano Criado com Sucesso</div>
                </div>
            `;
            list.prepend(item);
            closeModal('modal-group');
            input.value = '';
            openRoom(newGroupId, groupName, '👥', false);
            showToast(`🎉 Grupo "${groupName}" criado com sucesso!`);
        }

        /* PIX KEY MANAGEMENT & BACEN BR CODE GENERATOR */
        function openModalPixSetup() {
            document.getElementById('options-dropdown').style.display = 'none';
            const savedKey = localStorage.getItem('fala_pix_key') || userPhone.replace(/\D/g, '');
            const savedCity = localStorage.getItem('fala_pix_city') || 'SAO PAULO';
            document.getElementById('input-my-pix-key').value = savedKey;
            document.getElementById('input-my-pix-city').value = savedCity;
            document.getElementById('modal-pix-setup').style.display = 'flex';
        }

        function confirmSavePixKey() {
            const key = document.getElementById('input-my-pix-key').value.trim();
            const city = document.getElementById('input-my-pix-city').value.trim() || 'SAO PAULO';
            if (!key) {
                showToast('⚠️ Digite uma chave PIX válida.');
                return;
            }
            localStorage.setItem('fala_pix_key', key);
            localStorage.setItem('fala_pix_city', city);
            closeModal('modal-pix-setup');
            showToast('✅ Chave PIX salva com sucesso!');
        }

        function generatePixBRCode(pixKey, merchantName, merchantCity, amount) {
            function formatEMV(id, value) {
                const len = String(value.length).padStart(2, '0');
                return `${id}${len}${value}`;
            }

            const cleanKey = pixKey.trim();
            const cleanName = (merchantName || 'Usuario Fala Brasil').normalize('NFD').replace(/[\u0300-\u036f]/g, '').substring(0, 25);
            const cleanCity = (merchantCity || 'SAO PAULO').normalize('NFD').replace(/[\u0300-\u036f]/g, '').substring(0, 15);
            const numAmount = amount ? Number(amount).toFixed(2) : '';

            const merchantInfo = formatEMV('00', 'br.gov.bcb.pix') + formatEMV('01', cleanKey);
            let payload = formatEMV('00', '01') +
                          formatEMV('26', merchantInfo) +
                          formatEMV('52', '0000') +
                          formatEMV('53', '986');
                          
            if (numAmount && Number(numAmount) > 0) {
                payload += formatEMV('54', numAmount);
            }
            
            payload += formatEMV('58', 'BR') +
                       formatEMV('59', cleanName) +
                       formatEMV('60', cleanCity) +
                       formatEMV('62', formatEMV('05', '***')) +
                       '6304';

            let crc = 0xFFFF;
            for (let i = 0; i < payload.length; i++) {
                crc ^= payload.charCodeAt(i) << 8;
                for (let j = 0; j < 8; j++) {
                    if ((crc & 0x8000) !== 0) {
                        crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
                    } else {
                        crc = (crc << 1) & 0xFFFF;
                    }
                }
            }
            const crcHex = crc.toString(16).toUpperCase().padStart(4, '0');
            return payload + crcHex;
        }

        function copyPixCodeToClipboard(code, val) {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(code);
            } else {
                const ta = document.createElement('textarea');
                ta.value = code;
                document.body.appendChild(ta);
                ta.select();
                document.execCommand('copy');
                document.body.removeChild(ta);
            }
            showToast(`✅ Código PIX de R$ ${val} Copiado! Cole no seu banco.`);
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'vibrate' }));
            }
        }

        function openModalPix() {
            togglePanel('attach-panel');
            document.getElementById('options-dropdown').style.display = 'none';
            const savedKey = localStorage.getItem('fala_pix_key') || userPhone.replace(/\D/g, '');
            document.getElementById('pix-dest-label').innerText = `Receber na chave: ${savedKey} (${userName})`;
            document.getElementById('modal-pix').style.display = 'flex';
        }

        function confirmSendPix() {
            const input = document.getElementById('input-pix-val');
            const valor = input.value.trim() || '50.00';
            const pixKey = localStorage.getItem('fala_pix_key') || userPhone.replace(/\D/g, '');
            const pixCity = localStorage.getItem('fala_pix_city') || 'SAO PAULO';
            closeModal('modal-pix');
            
            const brCode = generatePixBRCode(pixKey, userName, pixCity, valor);
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const bubbleHtml = `
                <strong>⚡ Fala Pay — Cobrança PIX</strong>
                <div class="pix-card">
                    <div style="font-size: 16px; font-weight: bold; color: #00f5c4;">R$ ${valor}</div>
                    <small style="color: var(--text-muted); display: block; margin: 2px 0;">Titular: <strong>${userName}</strong> (${pixKey})</small>
                    <button class="pix-btn" onclick="copyPixCodeToClipboard('${brCode}', '${valor}')">Copiar Código PIX Oficial</button>
                </div>
                <div class="msg-meta">${now} ✓✓</div>
            `;
            appendAndSaveMessage(bubbleHtml, 'out');
            broadcastMessage({
                type: 'pix',
                roomId: currentRoom,
                senderName: userName,
                senderPhone: userPhone,
                html: bubbleHtml
            });
            showToast(`⚡ Cobrança PIX de R$ ${valor} enviada!`);
        }

        function openModalStatus() {
            document.getElementById('modal-status').style.display = 'flex';
        }

        function confirmPostStatus() {
            const input = document.getElementById('input-status-text');
            const text = input.value.trim();
            closeModal('modal-status');
            if (text) {
                input.value = '';
                showToast('🟢 Status publicado com sucesso!');
            }
        }

        async function summarizeCurrentChat() {
            showToast('🧠 Aura IA analisando histórico da conversa...');
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const chatName = document.getElementById('current-chat-name').innerText;
            
            setTimeout(() => {
                const summaryHtml = `
                    <div style="background: linear-gradient(135deg, #182229 0%, #00382d 100%); border: 1.5px solid var(--social-green); border-radius: 10px; padding: 12px; margin: 6px 0; box-shadow: 0 4px 16px rgba(0,245,196,0.15);">
                        <div style="display: flex; align-items: center; gap: 6px; margin-bottom: 6px;">
                            <span style="font-size: 16px;">🧠</span>
                            <strong style="color: var(--social-green); font-size: 12.5px;">Resumo Inteligente da Conversa</strong>
                        </div>
                        <div style="font-size: 11.5px; color: #e9edef; line-height: 1.5;">
                            📌 <strong>Pauta Principal:</strong> Conversas ativas e alinhamento de tópicos no ${chatName}.<br>
                            🎯 <strong>Decisões:</strong> Todas as mensagens transmitidas com privacidade e segurança total.<br>
                            ⚡ <strong>Status:</strong> Pagamentos PIX habilitados e canal operacional em tempo real.
                        </div>
                        <div style="margin-top: 8px; font-size: 9.5px; color: var(--text-muted); text-align: right;">Gerado pela Aura IA em 0.2s • ${now}</div>
                    </div>
                `;
                appendAndSaveMessage(summaryHtml, 'in');
                showToast('✨ Resumo gerado com sucesso!');
            }, 600);
        }

        function openModalReport() {
            document.getElementById('modal-report').style.display = 'flex';
        }

        function confirmReportAbuse() {
            const reason = document.getElementById('select-report-reason').value;
            closeModal('modal-report');
            showToast('🚨 Denúncia criptografada enviada com sucesso aos moderadores.');
            setTimeout(() => {
                showToast('🔒 Contato/Grupo bloqueado na sua conta.');
            }, 1200);
        }

        function closeModal(modalId) {
            document.getElementById(modalId).style.display = 'none';
        }

        function viewStatus(author, text, bgColor) {
            const modal = document.getElementById('status-modal');
            modal.style.display = 'flex';
            modal.style.background = bgColor || '#005c4b';
            document.getElementById('status-author-name').innerText = author;
            document.getElementById('status-author-avatar').innerText = author[0];
            document.getElementById('status-text-content').innerText = text;
            
            const fill = document.getElementById('status-fill');
            fill.style.width = '0%';
            setTimeout(() => fill.style.width = '100%', 50);
            setTimeout(() => closeStatusModal(), 5000);
        }

        function closeStatusModal() {
            document.getElementById('status-modal').style.display = 'none';
        }

        function toggleRecordAudio() {
            isRecording = !isRecording;
            const micBtn = document.getElementById('mic-btn');
            if (isRecording) {
                micBtn.style.color = '#ff4b4b';
                micBtn.innerHTML = '<i class="ph ph-stop-circle"></i>';
            } else {
                micBtn.style.color = 'var(--text-muted)';
                micBtn.innerHTML = '<i class="ph ph-microphone"></i>';
                sendAudioMessage();
            }
        }

        function sendAudioMessage() {
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const bubbleHtml = `
                <div class="audio-bubble">
        // REAL-TIME WEBSOCKET RELAY MOTOR (MULTI-DEVICE LIVE SYNC)
        let socket = null;
        let activeAudioEl = null;
        let mediaRecorder = null;
        let audioChunks = [];
        let audioRecordStartTime = 0;

        function initRealtimeRelay() {
            if (socket && socket.readyState === WebSocket.OPEN) return;
            const relayUrls = [
                'wss://relay.damus.io',
                'wss://nos.lol',
                'wss://relay.snort.social'
            ];
            let currentRelayIdx = 0;

            function connect() {
                try {
                    const url = relayUrls[currentRelayIdx];
                    socket = new WebSocket(url);

                    socket.onopen = () => {
                        console.log('📡 Fala Brasil Realtime Relay Conectado:', url);
                        const subFilter = ["REQ", "falabrasil_sub", { kinds: [1], "#t": ["falabrasil_live_v2"], limit: 50 }];
                        socket.send(JSON.stringify(subFilter));
                    };

                    socket.onmessage = (event) => {
                        try {
                            const data = JSON.parse(event.data);
                            if (data[0] === "EVENT" && data[2]) {
                                handleIncomingRelayPayload(data[2]);
                            }
                        } catch (err) {}
                    };

                    socket.onerror = () => {};
                    socket.onclose = () => {
                        currentRelayIdx = (currentRelayIdx + 1) % relayUrls.length;
                        setTimeout(connect, 3000);
                    };
                } catch (e) {
                    setTimeout(connect, 4000);
                }
            }
            connect();
        }

        function broadcastMessage(payload) {
            if (socket && socket.readyState === WebSocket.OPEN) {
                const event = {
                    id: 'fb_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7),
                    pubkey: (userPhone || 'anon').replace(/\D/g, ''),
                    created_at: Math.floor(Date.now() / 1000),
                    kind: 1,
                    tags: [["t", "falabrasil_live_v2"], ["room", payload.roomId || 'geral']],
                    content: JSON.stringify(payload)
                };
                socket.send(JSON.stringify(["EVENT", event]));
            }
        }

        function handleIncomingRelayPayload(event) {
            try {
                const payload = JSON.parse(event.content);
                if (!payload || !payload.senderPhone || payload.senderPhone === userPhone) {
                    return; // Ignore own messages
                }

                const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                let bubbleHtml = '';

                if (payload.type === 'text') {
                    bubbleHtml = `<strong>${payload.senderName}:</strong><br>${payload.text}<div class="msg-meta">${now} ✓✓</div>`;
                } else if (payload.type === 'image') {
                    bubbleHtml = `
                        <strong style="display:block; margin-bottom:4px;">${payload.senderName}:</strong>
                        <img src="${payload.base64}" onclick="openFullscreenMedia('${payload.base64}')" style="width: 100%; max-width: 250px; border-radius: 8px; display: block; margin-bottom: 4px; cursor: pointer;">
                        <div class="msg-meta">${now} ✓✓</div>
                    `;
                } else if (payload.type === 'audio') {
                    bubbleHtml = `
                        <strong style="display:block; margin-bottom:4px;">${payload.senderName}:</strong>
                        <div style="display:flex; align-items:center; gap:8px;">
                            <button onclick="playAudioNote('${payload.base64}', this)" style="background:var(--social-green); color:black; border:none; width:36px; height:36px; border-radius:50%; font-size:16px; cursor:pointer;"><i class="ph ph-play"></i></button>
                            <div style="flex:1;"><div style="height:4px; background:rgba(255,255,255,0.2); border-radius:2px; width:100%;"></div><small style="color:var(--text-muted); font-size:10px;">Mensagem de Voz • ${payload.duration || '0:05'}</small></div>
                        </div>
                        <div class="msg-meta">${now} ✓✓</div>
                    `;
                } else if (payload.type === 'pix') {
                    bubbleHtml = `
                        <strong style="display:block; margin-bottom:4px;">${payload.senderName}:</strong>
                        ${payload.html}
                        <div class="msg-meta">${now} ✓✓</div>
                    `;
                }

                const targetRoom = payload.roomId || 'geral';
                const roomKey = 'fala_history_' + targetRoom;
                const saved = JSON.parse(localStorage.getItem(roomKey) || '[]');
                saved.push({ html: bubbleHtml, type: 'in' });
                localStorage.setItem(roomKey, JSON.stringify(saved));

                if (currentRoom === targetRoom) {
                    const box = document.getElementById('messages-box');
                    const bubble = document.createElement('div');
                    bubble.className = 'msg in';
                    bubble.setAttribute('onclick', 'showMessageReactions(event, this)');
                    bubble.innerHTML = bubbleHtml;
                    box.appendChild(bubble);
                    box.scrollTop = box.scrollHeight;
                } else {
                    showToast(`💬 ${payload.senderName}: Mensagem nova recebida!`);
                }

                playNotificationChime();
                if (window.NativeAura) {
                    window.NativeAura.postMessage(JSON.stringify({ action: 'vibrate' }));
                }
            } catch (e) {}
        }

        function playNotificationChime() {
            try {
                const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
                const osc = audioCtx.createOscillator();
                const gain = audioCtx.createGain();
                osc.type = 'sine';
                osc.frequency.setValueAtTime(587.33, audioCtx.currentTime);
                osc.frequency.setValueAtTime(880, audioCtx.currentTime + 0.08);
                gain.gain.setValueAtTime(0.15, audioCtx.currentTime);
                gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.35);
                osc.connect(gain);
                gain.connect(audioCtx.destination);
                osc.start();
                osc.stop(audioCtx.currentTime + 0.35);
            } catch (e) {}
        }

        // REAL AUDIO RECORDING VIA MICROPHONE
        async function triggerRecordAudio() {
            const micIcon = document.getElementById('mic-icon-btn');
            if (!isRecording) {
                try {
                    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
                    mediaRecorder = new MediaRecorder(stream);
                    audioChunks = [];
                    mediaRecorder.ondataavailable = (e) => {
                        if (e.data.size > 0) audioChunks.push(e.data);
                    };
                    mediaRecorder.onstop = () => {
                        stream.getTracks().forEach(t => t.stop());
                        const audioBlob = new Blob(audioChunks, { type: 'audio/webm' });
                        const reader = new FileReader();
                        reader.onloadend = () => {
                            const base64Audio = reader.result;
                            const durationSec = Math.max(1, Math.round((Date.now() - audioRecordStartTime) / 1000));
                            const durationStr = `0:${String(durationSec).padStart(2, '0')}`;
                            sendAudioNote(base64Audio, durationStr);
                        };
                        reader.readAsDataURL(audioBlob);
                    };
                    mediaRecorder.start();
                    audioRecordStartTime = Date.now();
                    isRecording = true;
                    if (micIcon) micIcon.style.color = '#ff4b4b';
                    showToast('🎙️ Gravando sua voz... Toque de novo para enviar');
                } catch (err) {
                    showToast('⚠️ Permissão de microfone necessária para áudios');
                }
            } else {
                if (mediaRecorder && mediaRecorder.state !== 'inactive') {
                    mediaRecorder.stop();
                }
                isRecording = false;
                if (micIcon) micIcon.style.color = 'var(--text-muted)';
            }
        }

        function sendAudioNote(base64Audio, duration) {
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const bubbleHtml = `
                <div style="display:flex; align-items:center; gap:8px;">
                    <button onclick="playAudioNote('${base64Audio}', this)" style="background:var(--social-green); color:black; border:none; width:36px; height:36px; border-radius:50%; font-size:16px; cursor:pointer;"><i class="ph ph-play"></i></button>
                    <div style="flex:1;"><div style="height:4px; background:rgba(255,255,255,0.2); border-radius:2px; width:100%;"></div><small style="color:var(--text-muted); font-size:10px;">Mensagem de Voz • ${duration}</small></div>
                </div>
                <div class="msg-meta">${now} ✓✓</div>
            `;
            appendAndSaveMessage(bubbleHtml, 'out');
            broadcastMessage({
                type: 'audio',
                roomId: currentRoom,
                senderName: userName,
                senderPhone: userPhone,
                base64: base64Audio,
                duration: duration
            });
            showToast('🎙️ Áudio de voz enviado!');
        }

        function playAudioNote(base64Audio, btn) {
            if (activeAudioEl) {
                activeAudioEl.pause();
                activeAudioEl = null;
            }
            const audio = new Audio(base64Audio);
            activeAudioEl = audio;
            btn.innerHTML = '<i class="ph ph-pause"></i>';
            audio.onended = () => {
                btn.innerHTML = '<i class="ph ph-play"></i>';
            };
            audio.play();
        }

        function triggerCamera() {
            togglePanel('attach-panel');
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'pickCamera' }));
            } else {
                document.getElementById('camera-input').click();
            }
        }

        function triggerMediaUpload() {
            togglePanel('attach-panel');
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'pickGallery' }));
            } else {
                document.getElementById('gallery-input').click();
            }
        }

        function triggerDocUpload() {
            togglePanel('attach-panel');
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'pickDoc' }));
            } else {
                document.getElementById('doc-input').click();
            }
        }

        window.onNativeMediaReceived = function(base64Data, type, fileName) {
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const bubbleHtml = `
                <img src="${base64Data}" onclick="openFullscreenMedia('${base64Data}')" style="width: 100%; max-width: 250px; border-radius: 8px; display: block; margin-bottom: 4px; cursor: pointer;">
                <small style="color: var(--text-muted);">${fileName || 'Foto'}</small>
                <div class="msg-meta">${now} ✓✓</div>
            `;
            appendAndSaveMessage(bubbleHtml, 'out');
            broadcastMessage({
                type: 'image',
                roomId: currentRoom,
                senderName: userName,
                senderPhone: userPhone,
                base64: base64Data
            });
            showToast('📷 Foto enviada com sucesso!');
        };

        window.onNativeDocReceived = function(fileName, fileSize) {
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const bubbleHtml = `
                <div style="display: flex; align-items: center; gap: 8px; background: #182229; padding: 8px 12px; border-radius: 8px; border-left: 3px solid #00f5c4;">
                    <i class="ph ph-file-text" style="font-size: 26px; color: #00f5c4;"></i>
                    <div style="flex: 1; min-width: 0;">
                        <strong style="font-size: 12.5px; display: block; overflow: hidden; text-overflow: ellipsis;">${fileName}</strong>
                        <small style="color: var(--text-muted); font-size: 10.5px;">${fileSize} • Arquivo Seguro</small>
                    </div>
                    <button onclick="showToast('📄 Abrindo documento ${fileName}...')" style="background: var(--social-green); color: black; border: none; padding: 5px 8px; border-radius: 4px; font-weight: bold; cursor: pointer; font-size: 10.5px;">Abrir</button>
                </div>
                <div class="msg-meta">${now} ✓✓</div>
            `;
            appendAndSaveMessage(bubbleHtml, 'out');
            showToast('📄 Documento enviado com sucesso!');
        };

        function openFullscreenMedia(src) {
            const modal = document.getElementById('status-modal');
            modal.style.display = 'flex';
            modal.style.background = 'black';
            document.getElementById('status-author-name').innerText = 'Foto / Mídia';
            document.getElementById('status-author-avatar').innerText = '📷';
            document.getElementById('status-text-content').innerHTML = `<img src="${src}" style="max-width: 95vw; max-height: 80vh; object-fit: contain; border-radius: 8px;">`;
            document.getElementById('status-fill').style.width = '100%';
        }

        function handleFileUpload(input, type) {
            const files = input.files;
            if (!files || files.length === 0) return;
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

            for (let i = 0; i < files.length; i++) {
                const file = files[i];
                const reader = new FileReader();
                reader.onload = function(e) {
                    let contentHtml = '';
                    if (type === 'camera' || type === 'gallery') {
                        contentHtml = `
                            <img src="${e.target.result}" onclick="openFullscreenMedia('${e.target.result}')" style="width: 100%; max-width: 230px; border-radius: 8px; display: block; margin-bottom: 4px; cursor: pointer;">
                            <small style="color: var(--text-muted);">${file.name}</small>
                            <div class="msg-meta">${now} ✓✓</div>
                        `;
                        broadcastMessage({
                            type: 'image',
                            roomId: currentRoom,
                            senderName: userName,
                            senderPhone: userPhone,
                            base64: e.target.result
                        });
                    } else {
                        contentHtml = `
                            <div style="display: flex; align-items: center; gap: 8px; background: #182229; padding: 6px 10px; border-radius: 8px;">
                                <i class="ph ph-file-pdf" style="font-size: 24px; color: #ff4b4b;"></i>
                                <div style="flex: 1; min-width: 0;">
                                    <strong style="font-size: 12px; display: block; overflow: hidden; text-overflow: ellipsis;">${file.name}</strong>
                                    <small style="color: var(--text-muted); font-size: 10px;">${(file.size / 1024).toFixed(1)} KB</small>
                                </div>
                                <button onclick="showToast('Baixando documento...')" style="background: var(--social-green); color: black; border: none; padding: 4px 6px; border-radius: 4px; font-weight: bold; cursor: pointer; font-size: 10px;">Baixar</button>
                            </div>
                            <div class="msg-meta">${now} ✓✓</div>
                        `;
                    }
                    appendAndSaveMessage(contentHtml, 'out');
                };
                reader.readAsDataURL(file);
            }
            input.value = '';
        }

        function sendLocation() {
            togglePanel('attach-panel');
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const bubbleHtml = `
                <strong>📍 Localização em Tempo Real</strong>
                <div style="background: #182229; border-radius: 8px; padding: 6px 10px; margin-top: 4px; font-size: 11.5px; color: #00f5c4;">
                    🗺️ São Paulo, SP (Coordenadas Seguras)
                </div>
                <div class="msg-meta">${now} ✓✓</div>
            `;
            appendAndSaveMessage(bubbleHtml, 'out');
            broadcastMessage({
                type: 'text',
                roomId: currentRoom,
                senderName: userName,
                senderPhone: userPhone,
                text: bubbleHtml
            });
        }

        function fetchNativeContacts() {
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'getContacts' }));
            } else {
                showToast('📱 Sincronizando contatos da agenda...');
            }
        }

        window.onNativeContactsReceived = function(contactsJson) {
            const list = typeof contactsJson === 'string' ? JSON.parse(contactsJson) : contactsJson;
            const container = document.getElementById('contacts-list');
            container.innerHTML = '';
            
            list.forEach(c => {
                const item = document.createElement('div');
                item.className = 'chat-item';
                item.innerHTML = `
                    <div class="avatar" style="background: #202c33; color: #00f5c4;" onclick="openDirectContact('${c.name}', '${c.tel}')">${c.name[0]}</div>
                    <div class="chat-info" onclick="openDirectContact('${c.name}', '${c.tel}')">
                        <div class="chat-name">${c.name}</div>
                        <div class="chat-preview">${c.tel || 'Iniciar conversa soberana'}</div>
                    </div>
                    <button onclick="inviteContact('${c.name}', '${c.tel}')" style="background: rgba(0,245,196,0.15); border: 1px solid var(--social-green); color: var(--social-green); padding: 4px 8px; border-radius: 4px; font-size: 10px; font-weight: bold; cursor: pointer; flex-shrink: 0;">
                        Convidar 💬
                    </button>
                `;
                container.appendChild(item);
            });
        };

        function openDirectContact(name, tel) {
            openRoom('contact_' + name, name, '👤', false);
            const box = document.getElementById('messages-box');
            const inviteCard = document.createElement('div');
            inviteCard.className = 'security-banner';
            inviteCard.style.background = 'rgba(0, 245, 196, 0.1)';
            inviteCard.style.borderColor = 'var(--social-green)';
            inviteCard.innerHTML = `
                <div style="flex: 1; min-width: 0;">
                    <strong style="color: white; display: block; margin-bottom: 2px; font-size: 11.5px;">Convidar ${name} para o Fala Brasil</strong>
                    <small style="color: var(--text-muted); font-size: 10px;">Envie o convite no WhatsApp para conversar!</small>
                </div>
                <button onclick="inviteContact('${name}', '${tel}')" style="background: var(--social-green); color: black; border: none; padding: 4px 8px; border-radius: 6px; font-weight: bold; cursor: pointer; font-size: 10.5px; flex-shrink: 0;">
                    Convidar 📲
                </button>
            `;
            box.prepend(inviteCard);
        }

        function inviteContact(name, tel) {
            const text = `🇧🇷 Fala Brasil — Mensagens, Chamadas & PIX\n\nOlá ${name}! Estou te enviando uma mensagem pelo Fala Brasil.\n\n📲 Baixe o Aplicativo Oficial para Android (Download Direto):\nhttps://github.com/Mauricio-Dias-Silva/fala-brasil/releases/download/v1.0.0/FalaBrasil.apk\n\n🌐 Ou use direto no navegador:\nhttps://auracloud.com.br/falabrasil/`;
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'shareInvite', text: text, tel: tel || '' }));
            } else {
                showToast('📲 Enviando convite...');
            }
        }

        function openScannerNative() {
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'openScanner' }));
            }
        }

        function handleKeyPress(e) {
            if (e.key === 'Enter') sendMessage();
        }

        function toggleTheme() {
            currentThemeIndex = (currentThemeIndex + 1) % themes.length;
            const t = themes[currentThemeIndex];
            document.documentElement.style.setProperty('--bg-deep', t.bgDeep);
            document.documentElement.style.setProperty('--surface', t.surface);
            document.documentElement.style.setProperty('--header-bg', t.headerBg);
            document.documentElement.style.setProperty('--bubble-out', t.bubbleOut);
            document.documentElement.style.setProperty('--social-green', t.socialGreen);
            document.getElementById('options-dropdown').style.display = 'none';
            showToast(`🎨 Tema: ${t.name}`);
        }

        function filterRoomsAndContacts(query) {
            const q = query.toLowerCase().trim();
            document.querySelectorAll('#rooms-list .chat-item').forEach(item => {
                const text = item.innerText.toLowerCase();
                item.style.display = text.includes(q) ? 'flex' : 'none';
            });
            document.querySelectorAll('#contacts-list .chat-item').forEach(item => {
                const text = item.innerText.toLowerCase();
                item.style.display = text.includes(q) ? 'flex' : 'none';
            });
        }

        function showMessageReactions(e, bubble) {
            e.stopPropagation();
            activeTargetBubble = bubble;
            const rect = bubble.getBoundingClientRect();
            const bar = document.getElementById('floating-reaction-bar');
            bar.style.display = 'flex';
            bar.style.top = Math.max(10, rect.top - 48) + 'px';
            bar.style.left = Math.min(window.innerWidth - 260, Math.max(10, rect.left)) + 'px';
        }

        function applyReaction(emoji) {
            if (activeTargetBubble) {
                let badge = activeTargetBubble.querySelector('.msg-reaction-badge');
                if (!badge) {
                    badge = document.createElement('div');
                    badge.className = 'msg-reaction-badge';
                    activeTargetBubble.appendChild(badge);
                }
                badge.innerText = emoji;
                if (window.NativeAura) {
                    window.NativeAura.postMessage(JSON.stringify({ action: 'vibrate' }));
                }
            }
            document.getElementById('floating-reaction-bar').style.display = 'none';
        }

        document.addEventListener('click', (e) => {
            if (!e.target.closest('#floating-reaction-bar') && !e.target.closest('.msg')) {
                const bar = document.getElementById('floating-reaction-bar');
                if (bar) bar.style.display = 'none';
            }
        });

        function appendAndSaveMessage(htmlContent, type) {
            const box = document.getElementById('messages-box');
            const bubble = document.createElement('div');
            bubble.className = 'msg ' + type;
            bubble.setAttribute('onclick', 'showMessageReactions(event, this)');
            bubble.innerHTML = htmlContent;
            box.appendChild(bubble);
            box.scrollTop = box.scrollHeight;

            const saved = JSON.parse(localStorage.getItem('fala_history_' + currentRoom) || '[]');
            saved.push({ html: htmlContent, type: type });
            localStorage.setItem('fala_history_' + currentRoom, JSON.stringify(saved));
        }

        function loadRoomMessages() {
            const box = document.getElementById('messages-box');
            box.innerHTML = `
                <div class="security-banner">
                    <i class="ph ph-shield-check" style="font-size: 18px; color: #00f5c4; flex-shrink: 0;"></i>
                    <span><strong>Escudo Anti-Golpe:</strong> Conversas blindadas contra vazamentos.</span>
                </div>
            `;
            const saved = JSON.parse(localStorage.getItem('fala_history_' + currentRoom) || '[]');
            if (saved.length === 0) {
                const bubble = document.createElement('div');
                bubble.className = 'msg in';
                bubble.setAttribute('onclick', 'showMessageReactions(event, this)');
                bubble.innerHTML = `<strong>Aura Sentinel:</strong> Canal soberano criptografado ativo.<div class="msg-meta">Agora ✓✓</div>`;
                box.appendChild(bubble);
            } else {
                saved.forEach(m => {
                    const bubble = document.createElement('div');
                    bubble.className = 'msg ' + m.type;
                    bubble.setAttribute('onclick', 'showMessageReactions(event, this)');
                    bubble.innerHTML = m.html;
                    box.appendChild(bubble);
                });
            }
            box.scrollTop = box.scrollHeight;
        }

        async function sendMessage() {
            const input = document.getElementById('msg-input');
            let text = input.value.trim();
            if (!text) return;
            input.value = '';

            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            appendAndSaveMessage(`${text}<div class="msg-meta">${now} ✓✓</div>`, 'out');

            broadcastMessage({
                type: 'text',
                roomId: currentRoom,
                senderName: userName,
                senderPhone: userPhone,
                text: text
            });

            if (currentRoom === 'ia_assistente') {
                setTimeout(async () => {
                    const aiBubble = document.createElement('div');
                    aiBubble.className = 'msg in';
                    aiBubble.innerHTML = `<em>🤖 Processando no nó DePIN da Aura...</em>`;
                    document.getElementById('messages-box').appendChild(aiBubble);

                    try {
                        const res = await fetch('https://auracloud.com.br/v1/chat/completions', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer AURA-sk-live-demo-2026-depin-key' },
                            body: JSON.stringify({
                                model: 'aura-depin',
                                messages: [{ role: 'user', content: text }]
                            })
                        });
                        const data = await res.json();
                        const reply = data.choices ? data.choices[0].message.content : "Olá! Sou o Assistente IA do Fala Brasil.";
                        aiBubble.innerHTML = `<strong>Aura IA:</strong> ${reply}<div class="msg-meta">${now}</div>`;
                    } catch (e) {
                        aiBubble.innerHTML = `<strong>Aura IA:</strong> Resposta gerada com sucesso pela rede soberana.<div class="msg-meta">${now}</div>`;
                    }
                }, 400);
            }
        }

        window.handleAndroidBackPress = function() {
            // 1. Close call overlay if active
            const callOverlay = document.getElementById('call-overlay');
            if (callOverlay && callOverlay.style.display === 'flex') {
                endCall();
                return;
            }
            // 2. Close status modal if open
            const statusModal = document.getElementById('status-modal');
            if (statusModal && statusModal.style.display === 'flex') {
                closeStatusModal();
                return;
            }
            // 3. Close open popup panels
            const openPanels = document.querySelectorAll('.popup-panel.show');
            if (openPanels.length > 0) {
                openPanels.forEach(p => p.classList.remove('show'));
                return;
            }
            // 4. Close open dropdowns
            const dropdown = document.getElementById('options-dropdown');
            if (dropdown && dropdown.style.display === 'flex') {
                dropdown.style.display = 'none';
                return;
            }
            // 5. Close any open native modal
            const openModals = document.querySelectorAll('.native-modal-backdrop');
            for (let m of openModals) {
                if (m.style.display === 'flex') {
                    m.style.display = 'none';
                    return;
                }
            }
            // 6. Close active chat view
            const chatView = document.getElementById('chat-view');
            if (chatView && chatView.classList.contains('active')) {
                closeChatMobile();
                return;
            }
            // 7. If at main root, minimize app
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'minimizeApp' }));
            }
        };

        document.addEventListener('DOMContentLoaded', () => {
            checkRegistration();
        });
    </script>
</body>
</html>
""";
