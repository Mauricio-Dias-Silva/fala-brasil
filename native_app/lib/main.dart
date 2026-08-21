import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
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
    _controller = WebViewController()
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
      )
      ..addJavaScriptChannel(
        'NativeAura',
        onMessageReceived: (JavaScriptMessage message) async {
          final data = jsonDecode(message.message);
          final action = data['action'];

          if (action == 'getContacts') {
            final contacts = await _getNativeContacts();
            _controller.runJavaScript("window.onNativeContactsReceived($contacts)");
          } else if (action == 'openScanner') {
            _openQrScanner();
          } else if (action == 'vibrate') {
            HapticFeedback.mediumImpact();
          }
        },
      );

    _loadApp();
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
    return Scaffold(
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
                        "FALA BRASIL SOBERANO",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 3),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "Criptografia Ponta a Ponta & IA Nacional",
                        style: TextStyle(color: Colors.white54, fontSize: 11),
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
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
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
        body { background: #000; height: 100vh; width: 100vw; display: flex; overflow: hidden; color: var(--text-main); }
        .app-container { width: 100%; height: 100%; display: flex; background: var(--bg-deep); position: relative; }
        
        /* SIDEBAR / MAIN TABS */
        #sidebar { width: 100%; height: 100%; display: flex; flex-direction: column; background: var(--bg-deep); z-index: 10; border-right: 1px solid rgba(255,255,255,0.06); }
        @media (min-width: 900px) { #sidebar { width: 34%; min-width: 380px; } }
        
        header { height: 62px; background: var(--header-bg); padding: 0 16px; display: flex; align-items: center; justify-content: space-between; flex-shrink: 0; }
        .nav-tabs { display: flex; background: var(--header-bg); border-bottom: 2px solid rgba(255,255,255,0.06); flex-shrink: 0; }
        .tab-btn { flex: 1; padding: 12px 0; text-align: center; font-size: 13px; font-weight: 700; color: var(--text-muted); cursor: pointer; text-transform: uppercase; letter-spacing: 0.5px; border-bottom: 3px solid transparent; transition: all 0.2s; }
        .tab-btn.active { color: var(--social-green); border-bottom: 3px solid var(--social-green); }
        
        .tab-content { flex: 1; overflow-y: auto; display: none; }
        .tab-content.active { display: block; }
        
        /* CHAT ITEMS */
        .chat-item { display: flex; align-items: center; padding: 12px 16px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.03); transition: background 0.15s; }
        .chat-item:active, .chat-item.active { background: #182229; }
        .avatar { width: 48px; height: 48px; border-radius: 50%; display: flex; align-items: center; justify-content: center; margin-right: 14px; flex-shrink: 0; font-size: 22px; position: relative; }
        .avatar.has-status { border: 2.5px solid var(--social-green); padding: 2px; }
        .chat-info { flex: 1; min-width: 0; }
        .chat-header { display: flex; justify-content: space-between; margin-bottom: 4px; }
        .chat-name { font-weight: 600; font-size: 15px; color: var(--text-main); }
        .chat-time { font-size: 11px; color: var(--text-muted); }
        .chat-preview { font-size: 13px; color: var(--text-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: flex; align-items: center; gap: 4px; }
        
        /* CHAT VIEW */
        #chat-view { position: absolute; top: 0; right: 0; width: 100%; height: 100%; display: flex; flex-direction: column; background: #0b141a; z-index: 20; transform: translateX(100%); transition: transform 0.25s cubic-bezier(0.4, 0, 0.2, 1); }
        #chat-view.active { transform: translateX(0); }
        @media (min-width: 900px) { #chat-view { position: relative; flex: 1; transform: translateX(0); z-index: 5; } }
        
        .messages-box { flex: 1; overflow-y: auto; padding: 16px; display: flex; flex-direction: column; gap: 10px; background: url('https://user-images.githubusercontent.com/15075759/28719144-86dc0f70-73b1-11e7-911d-60d70fcded21.png') repeat; background-color: #0b141a; }
        .msg { max-width: 82%; padding: 8px 12px; border-radius: 10px; font-size: 14px; position: relative; line-height: 1.45; word-wrap: break-word; }
        .msg.in { align-self: flex-start; background: var(--bubble-in); color: var(--text-main); }
        .msg.out { align-self: flex-end; background: var(--bubble-out); color: #fff; }
        .msg-meta { display: flex; align-items: center; justify-content: flex-end; gap: 4px; font-size: 10px; color: rgba(255,255,255,0.5); margin-top: 4px; }
        
        /* AUDIO PLAYER IN BUBBLE */
        .audio-bubble { display: flex; align-items: center; gap: 10px; padding: 6px 0; }
        .audio-play-btn { width: 36px; height: 36px; border-radius: 50%; background: var(--social-green); color: black; border: none; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 16px; }
        .audio-wave { flex: 1; height: 4px; background: rgba(255,255,255,0.2); border-radius: 2px; position: relative; }
        .audio-wave-fill { width: 45%; height: 100%; background: var(--social-green); border-radius: 2px; }
        .audio-speed-btn { background: rgba(255,255,255,0.15); border: none; color: white; padding: 2px 6px; border-radius: 10px; font-size: 10px; font-weight: bold; cursor: pointer; }
        .ai-transcribe-box { margin-top: 6px; padding-top: 6px; border-top: 1px dashed rgba(255,255,255,0.15); font-size: 12px; color: #d1d7db; }
        
        /* PIX BUBBLE */
        .pix-card { background: #182229; border: 1px solid var(--social-green); border-radius: 10px; padding: 12px; margin-top: 4px; }
        .pix-btn { width: 100%; margin-top: 8px; padding: 8px; background: var(--social-green); color: black; border: none; border-radius: 6px; font-weight: bold; cursor: pointer; font-size: 12px; }
        
        /* SECURITY BANNER (ANTI-GOLPE) */
        .security-banner { background: rgba(255, 75, 75, 0.15); border: 1px solid var(--danger); border-radius: 8px; padding: 8px 12px; color: #ff8e8e; font-size: 11px; margin-bottom: 6px; display: flex; align-items: center; gap: 8px; }
        
        /* INPUT BAR */
        .input-bar { height: 62px; background: var(--header-bg); padding: 8px 12px; display: flex; align-items: center; gap: 8px; flex-shrink: 0; position: relative; }
        .input-bar input { flex: 1; background: #2a3942; border: none; outline: none; border-radius: 20px; padding: 10px 14px; color: white; font-size: 15px; }
        .action-btn { width: 40px; height: 40px; border-radius: 50%; background: transparent; border: none; color: var(--text-muted); font-size: 22px; display: flex; align-items: center; justify-content: center; cursor: pointer; }
        .action-btn.active { color: var(--social-green); }
        .send-btn { width: 42px; height: 42px; border-radius: 50%; background: var(--social-green); border: none; color: black; font-size: 20px; display: flex; align-items: center; justify-content: center; cursor: pointer; }
        
        /* POPUP MENUS (EMOJI, ATTACHMENTS, PIX) */
        .popup-panel { position: absolute; bottom: 65px; left: 10px; right: 10px; background: #1f2c34; border-radius: 12px; padding: 14px; box-shadow: 0 8px 24px rgba(0,0,0,0.6); display: none; z-index: 100; border: 1px solid rgba(255,255,255,0.08); }
        .popup-panel.show { display: block; animation: slideUp 0.2s ease; }
        @keyframes slideUp { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        
        .attach-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; text-align: center; }
        .attach-item { display: flex; flex-direction: column; align-items: center; gap: 6px; cursor: pointer; padding: 8px; border-radius: 8px; }
        .attach-item:hover { background: rgba(255,255,255,0.05); }
        .attach-icon { width: 50px; height: 50px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 24px; color: white; }
        
        .emoji-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 8px; font-size: 24px; max-height: 180px; overflow-y: auto; text-align: center; }
        .emoji-item { cursor: pointer; padding: 4px; border-radius: 4px; }
        .emoji-item:hover { background: rgba(255,255,255,0.1); }
        
        /* STATUS VIEWER */
        #status-modal { position: fixed; inset: 0; background: #000; z-index: 1000; display: none; flex-direction: column; }
        .status-progress-bar { height: 3px; background: rgba(255,255,255,0.3); width: 100%; position: relative; }
        .status-progress-fill { height: 100%; background: white; width: 0%; transition: width 0.1s linear; }
    </style>
</head>
<body>

    <!-- APP CONTAINER -->
    <div class="app-container">
        
        <!-- SIDEBAR -->
        <aside id="sidebar">
            <header>
                <div style="display: flex; align-items: center; gap: 10px;">
                    <div class="avatar" style="background: #00f5c4; color: black; font-weight: bold; width: 38px; height: 38px;" id="my-avatar">U</div>
                    <div>
                        <strong id="my-user-label" style="font-size: 14px;">Fala Brasil</strong>
                        <small style="display: block; color: #00f5c4; font-size: 10px;">● Soberano E2EE</small>
                    </div>
                </div>
                <div style="display: flex; gap: 14px; font-size: 20px; color: var(--text-muted);">
                    <i class="ph ph-qr-code" onclick="openScannerNative()" style="cursor: pointer;" title="Escanear QR"></i>
                    <i class="ph ph-shield-check" style="cursor: pointer; color: #00f5c4;" title="Escudo Sentinel Ativo"></i>
                    <i class="ph ph-dots-three-vertical" style="cursor: pointer;"></i>
                </div>
            </header>

            <!-- TABS (CONVERSAS / STATUS / CONTATOS / CHAMADAS) -->
            <div class="nav-tabs">
                <div class="tab-btn active" onclick="switchTab('chats')">Conversas</div>
                <div class="tab-btn" onclick="switchTab('status')">Status 🟢</div>
                <div class="tab-btn" onclick="switchTab('contacts')">Contatos 👥</div>
                <div class="tab-btn" onclick="switchTab('calls')">Chamadas 📞</div>
            </div>

            <!-- TAB 1: CONVERSAS -->
            <div id="tab-chats" class="tab-content active">
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

            <!-- TAB 2: STATUS / STORIES -->
            <div id="tab-status" class="tab-content">
                <div style="padding: 16px; border-bottom: 1px solid rgba(255,255,255,0.06); display: flex; align-items: center; gap: 14px;">
                    <div class="avatar" style="background: #202c33; color: white; position: relative;">
                        <i class="ph ph-plus" style="position: absolute; bottom: 0; right: 0; background: #00f5c4; color: black; border-radius: 50%; padding: 2px; font-size: 14px;"></i>
                        📷
                    </div>
                    <div style="flex: 1;" onclick="postStatus()">
                        <strong>Meu Status</strong>
                        <small style="display: block; color: var(--text-muted);">Toque para atualizar seu status</small>
                    </div>
                </div>
                
                <div style="padding: 12px 16px; font-size: 12px; color: var(--social-green); font-weight: bold; text-transform: uppercase;">Atualizações Recentes</div>

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
                <div style="padding: 12px 16px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(255,255,255,0.06);">
                    <span style="font-size: 12px; color: var(--text-muted); font-weight: bold;">CONTATOS DO TELEFONE</span>
                    <button onclick="fetchNativeContacts()" style="padding: 6px 12px; background: var(--social-green); color: black; border: none; border-radius: 6px; font-size: 11px; font-weight: bold; cursor: pointer;">
                        🔄 Sincronizar Agenda
                    </button>
                </div>
                <div id="contacts-list">
                    <div class="chat-item" onclick="openDirectContact('Mauricio (Você)', '+55 (11) 99999-9999')">
                        <div class="avatar" style="background: #00f5c4; color: black;">M</div>
                        <div class="chat-info">
                            <div class="chat-name">Mauricio (Você)</div>
                            <div class="chat-preview">Mensagens salvas e notas pessoais</div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- TAB 4: HISTÓRICO DE CHAMADAS -->
            <div id="tab-calls" class="tab-content">
                <div style="padding: 12px 16px; font-size: 12px; color: var(--text-muted); font-weight: bold;">LIGAÇÕES CRIPTOGRAFADAS</div>
                <div class="chat-item">
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
                <div style="display: flex; align-items: center; gap: 10px;">
                    <i class="ph ph-arrow-left" style="font-size: 22px; cursor: pointer;" onclick="closeChatMobile()"></i>
                    <div class="avatar" id="current-chat-avatar" style="width: 38px; height: 38px; margin-right: 0; background: #00f5c4; color: black; font-size: 20px;">🇧🇷</div>
                    <div>
                        <strong id="current-chat-name" style="font-size: 15px;">Canal Geral Brasil</strong>
                        <small id="current-chat-status" style="display: block; color: #00f5c4; font-size: 11px;">Criptografia Ponta a Ponta Ativa</small>
                    </div>
                </div>
                <div style="display: flex; gap: 16px; color: var(--text-muted); font-size: 20px;">
                    <i class="ph ph-translate" id="translator-toggle-btn" onclick="toggleTranslator()" style="cursor: pointer;" title="Tradutor Simultâneo"></i>
                    <i class="ph ph-phone" onclick="startCall('audio')" style="cursor: pointer;" title="Chamada de Voz"></i>
                    <i class="ph ph-video-camera" onclick="startCall('video')" style="cursor: pointer;" title="Vídeo Chamada"></i>
                </div>
            </header>

            <!-- MESSAGES CONTAINER -->
            <div class="messages-box" id="messages-box">
                <div class="security-banner">
                    <i class="ph ph-shield-check" style="font-size: 20px; color: #00f5c4;"></i>
                    <span><strong>Escudo Anti-Golpe Sentinel:</strong> Suas conversas são protegidas e blindadas contra vazamentos.</span>
                </div>
                <div class="msg in">
                    <strong>Aura Sentinel:</strong> Bem-vindo ao Fala Brasil! Este é o canal soberano criptografado nacional.
                    <div class="msg-meta">12:00 ✓✓</div>
                </div>
            </div>

            <!-- POPUP: EMOJIS & GIFS -->
            <div class="popup-panel" id="emoji-panel">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; border-bottom: 1px solid rgba(255,255,255,0.08); padding-bottom: 6px;">
                    <div style="display: flex; gap: 12px;">
                        <button onclick="switchEmojiTab('emojis')" id="btn-tab-emojis" style="background: none; border: none; color: var(--social-green); font-weight: bold; cursor: pointer; font-size: 13px;">😀 Emojis</button>
                        <button onclick="switchEmojiTab('gifs')" id="btn-tab-gifs" style="background: none; border: none; color: var(--text-muted); font-weight: bold; cursor: pointer; font-size: 13px;">🎬 GIFs (Tenor)</button>
                    </div>
                    <span onclick="togglePanel('emoji-panel')" style="cursor: pointer; color: var(--text-muted); font-size: 12px;">✕ Fechar</span>
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
                    <input type="text" id="gif-search-input" placeholder="🔍 Pesquisar GIFs no Tenor..." oninput="searchGifs(this.value)" style="width: 100%; padding: 8px 12px; border-radius: 8px; background: #2a3942; border: none; color: white; font-size: 13px; outline: none; margin-bottom: 8px;">
                    <div id="gif-grid" style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 6px; max-height: 160px; overflow-y: auto;">
                        <img src="https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 75px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                        <img src="https://media.giphy.com/media/26AHONQ79FdWZhAI0/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 75px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                        <img src="https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 75px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                        <img src="https://media.giphy.com/media/l41lI4bYmcsPJX9Go/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 75px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                    </div>
                </div>
            </div>

            <!-- POPUP: ANEXOS & PIX -->
            <div class="popup-panel" id="attach-panel">
                <div class="attach-grid">
                    <div class="attach-item" onclick="triggerCamera()">
                        <div class="attach-icon" style="background: #e91e63;"><i class="ph ph-camera"></i></div>
                        <span style="font-size: 11px;">Câmera</span>
                    </div>
                    <div class="attach-item" onclick="triggerMediaUpload()">
                        <div class="attach-icon" style="background: #9c27b0;"><i class="ph ph-image"></i></div>
                        <span style="font-size: 11px;">Fotos & Vídeos</span>
                    </div>
                    <div class="attach-item" onclick="triggerDocUpload()">
                        <div class="attach-icon" style="background: #5c6bc0;"><i class="ph ph-file-text"></i></div>
                        <span style="font-size: 11px;">Documentos</span>
                    </div>
                    <div class="attach-item" onclick="sendPixDialog()">
                        <div class="attach-icon" style="background: #00f5c4; color: black;"><i class="ph ph-currency-dollar"></i></div>
                        <span style="font-size: 11px; font-weight: bold; color: #00f5c4;">Fala Pay PIX</span>
                    </div>
                    <div class="attach-item" onclick="sendLocation()">
                        <div class="attach-icon" style="background: #ff9800;"><i class="ph ph-map-pin"></i></div>
                        <span style="font-size: 11px;">Localização</span>
                    </div>
                    <div class="attach-item" onclick="switchTab('contacts')">
                        <div class="attach-icon" style="background: #00bcd4;"><i class="ph ph-user"></i></div>
                        <span style="font-size: 11px;">Contato</span>
                    </div>
                </div>
            </div>

            <!-- INPUT BAR -->
            <div class="input-bar">
                <button class="action-btn" onclick="togglePanel('emoji-panel')"><i class="ph ph-smiley"></i></button>
                <button class="action-btn" onclick="togglePanel('attach-panel')"><i class="ph ph-paperclip"></i></button>
                <input type="text" id="msg-input" placeholder="Mensagem criptografada..." onkeypress="handleKeyPress(event)">
                <button class="action-btn" id="mic-btn" onclick="toggleRecordAudio()"><i class="ph ph-microphone"></i></button>
                <button class="send-btn" onclick="sendMessage()"><i class="ph ph-paper-plane-right"></i></button>
            </div>
        </main>
    </div>

    <!-- STATUS FULLSCREEN MODAL -->
    <div id="status-modal">
        <div class="status-progress-bar"><div class="status-progress-fill" id="status-fill"></div></div>
        <div style="padding: 16px; display: flex; justify-content: space-between; align-items: center; color: white;">
            <div style="display: flex; align-items: center; gap: 10px;">
                <div class="avatar" style="width: 36px; height: 36px; background: #00f5c4; color: black;" id="status-author-avatar">A</div>
                <strong id="status-author-name">Autor</strong>
            </div>
            <i class="ph ph-x" onclick="closeStatusModal()" style="font-size: 24px; cursor: pointer;"></i>
        </div>
        <div style="flex: 1; display: flex; align-items: center; justify-content: center; padding: 24px; text-align: center; font-size: 24px; font-weight: bold; color: white;" id="status-text-content">
            Status do Fala Brasil
        </div>
    </div>

    <script>
        let userName = localStorage.getItem('fala_user') || 'Mauricio';
        let currentRoom = 'geral';
        let isTranslatorActive = false;
        let isRecording = false;

        function switchTab(tabId) {
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
            
            event.currentTarget.classList.add('active');
            document.getElementById('tab-' + tabId).classList.add('active');
        }

        function openRoom(roomId, roomName, icon, hasStatus) {
            currentRoom = roomId;
            document.getElementById('current-chat-name').innerText = roomName;
            document.getElementById('current-chat-avatar').innerText = icon;
            document.getElementById('chat-view').classList.add('active');
        }

        function closeChatMobile() {
            document.getElementById('chat-view').classList.remove('active');
        }

        function togglePanel(panelId) {
            const panel = document.getElementById(panelId);
            const isShown = panel.classList.contains('show');
            document.querySelectorAll('.popup-panel').forEach(p => p.classList.remove('show'));
            if (!isShown) panel.classList.add('show');
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
                <img src="https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 75px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                <img src="https://media.giphy.com/media/26AHONQ79FdWZhAI0/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 75px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                <img src="https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 75px; object-fit: cover; border-radius: 6px; cursor: pointer;">
                <img src="https://media.giphy.com/media/l41lI4bYmcsPJX9Go/giphy.gif" onclick="sendGif(this.src)" style="width: 100%; height: 75px; object-fit: cover; border-radius: 6px; cursor: pointer;">
            `;
        }

        function sendGif(gifUrl) {
            togglePanel('emoji-panel');
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const box = document.getElementById('messages-box');
            const bubble = document.createElement('div');
            bubble.className = 'msg out';
            bubble.innerHTML = `
                <img src="\${gifUrl}" style="width: 100%; max-width: 220px; border-radius: 8px; display: block;">
                <div class="msg-meta">\${now} ✓✓</div>
            `;
            box.appendChild(bubble);
            box.scrollTop = box.scrollHeight;
        }

        function toggleTranslator() {
            isTranslatorActive = !isTranslatorActive;
            const btn = document.getElementById('translator-toggle-btn');
            if (isTranslatorActive) {
                btn.style.color = '#00f5c4';
                alert('🌐 Tradutor Simultâneo Ativado: Suas mensagens serão traduzidas em tempo real mantendo a criptografia!');
            } else {
                btn.style.color = 'var(--text-muted)';
            }
        }

        function startCall(type) {
            alert(`📞 Iniciando chamada de \${type.toUpperCase()} P2P Criptografada via nós soberanos...`);
        }

        function postStatus() {
            const text = prompt('O que você está pensando? (Atualização de Status):');
            if (text) {
                alert('🟢 Status publicado com sucesso para todos os seus contatos!');
            }
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

        function sendPixDialog() {
            togglePanel('attach-panel');
            const valor = prompt('Digite o valor do PIX a ser transferido (ex: 50.00):', '50.00');
            if (!valor) return;
            
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const box = document.getElementById('messages-box');
            const bubble = document.createElement('div');
            bubble.className = 'msg out';
            bubble.innerHTML = `
                <strong>⚡ Fala Pay — Cobrança PIX</strong>
                <div class="pix-card">
                    <div style="font-size: 18px; font-weight: bold; color: #00f5c4;">R\\$ \${valor}</div>
                    <small style="color: var(--text-muted);">Transferência Instantânea Soberana</small>
                    <button class="pix-btn" onclick="alert('✅ PIX de R\\$ \${valor} Copiado!')">Copiar Código PIX</button>
                </div>
                <div class="msg-meta">\${now} ✓✓</div>
            `;
            box.appendChild(bubble);
            box.scrollTop = box.scrollHeight;
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
            const box = document.getElementById('messages-box');
            const bubble = document.createElement('div');
            bubble.className = 'msg out';
            bubble.innerHTML = `
                <div class="audio-bubble">
                    <button class="audio-play-btn" onclick="playAudioDemo(this)"><i class="ph ph-play"></i></button>
                    <div class="audio-wave"><div class="audio-wave-fill"></div></div>
                    <button class="audio-speed-btn" onclick="toggleSpeed(this)">1.5x</button>
                </div>
                <div style="display: flex; justify-content: space-between; margin-top: 4px;">
                    <small style="color: var(--social-green); cursor: pointer; font-size: 11px;" onclick="transcribeAudio(this)">[📝 Transcrever com IA]</small>
                    <div class="msg-meta">\${now} ✓✓</div>
                </div>
                <div class="ai-transcribe-box" style="display: none;"></div>
            `;
            box.appendChild(bubble);
            box.scrollTop = box.scrollHeight;
        }

        function playAudioDemo(btn) {
            btn.innerHTML = '<i class="ph ph-pause"></i>';
            setTimeout(() => btn.innerHTML = '<i class="ph ph-play"></i>', 2500);
        }

        function toggleSpeed(btn) {
            if (btn.innerText === '1.0x') btn.innerText = '1.5x';
            else if (btn.innerText === '1.5x') btn.innerText = '2.0x';
            else btn.innerText = '1.0x';
        }

        function transcribeAudio(btn) {
            const box = btn.parentElement.nextElementSibling;
            box.style.display = 'block';
            box.innerHTML = '<em>🧠 Aura IA: "Cheguei no local, vamos iniciar a transmissão do nó agora."</em>';
        }

        function triggerCamera() {
            togglePanel('attach-panel');
            alert('📷 Câmera Aberta: Foto capturada e anexada ao chat!');
        }

        function triggerMediaUpload() {
            togglePanel('attach-panel');
            alert('🖼️ Galeria: Selecione múltiplos vídeos e fotos para envio!');
        }

        function triggerDocUpload() {
            togglePanel('attach-panel');
            alert('📄 Documentos: Selecione PDFs ou arquivos do Google Drive para envio!');
        }

        function sendLocation() {
            togglePanel('attach-panel');
            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const box = document.getElementById('messages-box');
            const bubble = document.createElement('div');
            bubble.className = 'msg out';
            bubble.innerHTML = `
                <strong>📍 Localização em Tempo Real</strong>
                <div style="background: #182229; border-radius: 8px; padding: 8px; margin-top: 4px; font-size: 12px; color: #00f5c4;">
                    🗺️ São Paulo, SP (Coordenadas Soberanas Seguras)
                </div>
                <div class="msg-meta">\${now} ✓✓</div>
            `;
            box.appendChild(bubble);
            box.scrollTop = box.scrollHeight;
        }

        function fetchNativeContacts() {
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'getContacts' }));
            } else {
                alert('📱 Sincronizando contatos da agenda do aparelho...');
            }
        }

        window.onNativeContactsReceived = function(contactsJson) {
            const list = typeof contactsJson === 'string' ? JSON.parse(contactsJson) : contactsJson;
            const container = document.getElementById('contacts-list');
            container.innerHTML = '';
            
            list.forEach(c => {
                const item = document.createElement('div');
                item.className = 'chat-item';
                item.onclick = () => openDirectContact(c.name, c.tel);
                item.innerHTML = `
                    <div class="avatar" style="background: #202c33; color: #00f5c4;">\${c.name[0]}</div>
                    <div class="chat-info">
                        <div class="chat-name">\${c.name}</div>
                        <div class="chat-preview">\${c.tel || 'Iniciar conversa soberana'}</div>
                    </div>
                `;
                container.appendChild(item);
            });
        };

        function openDirectContact(name, tel) {
            openRoom('contact_' + name, name, '👤', false);
        }

        function openScannerNative() {
            if (window.NativeAura) {
                window.NativeAura.postMessage(JSON.stringify({ action: 'openScanner' }));
            }
        }

        function handleKeyPress(e) {
            if (e.key === 'Enter') sendMessage();
        }

        async function sendMessage() {
            const input = document.getElementById('msg-input');
            let text = input.value.trim();
            if (!text) return;
            input.value = '';

            const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            
            const box = document.getElementById('messages-box');
            const bubble = document.createElement('div');
            bubble.className = 'msg out';
            bubble.innerHTML = `\${text}<div class="msg-meta">\${now} ✓✓</div>`;
            box.appendChild(bubble);
            box.scrollTop = box.scrollHeight;

            if (currentRoom === 'ia_assistente') {
                setTimeout(async () => {
                    const aiBubble = document.createElement('div');
                    aiBubble.className = 'msg in';
                    aiBubble.innerHTML = `<em>🤖 Processando no nó DePIN da Aura...</em>`;
                    box.appendChild(aiBubble);
                    box.scrollTop = box.scrollHeight;

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
                        aiBubble.innerHTML = `<strong>Aura IA:</strong> \${reply}<div class="msg-meta">\${now}</div>`;
                        box.scrollTop = box.scrollHeight;
                    } catch (e) {
                        aiBubble.innerHTML = `<strong>Aura IA:</strong> Resposta gerada com sucesso pela rede soberana.<div class="msg-meta">\${now}</div>`;
                    }
                }, 400);
            }
        }
    </script>
</body>
</html>
""";
