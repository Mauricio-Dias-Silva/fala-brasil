// FALA BRASIL v3.5 - WHATSAPP SOBERANO EDITION
const HOST = window.location.origin.replace(/^http/, 'ws');
let socket;
let currentUser = localStorage.getItem('aura_user') || null;
let currentRoom = 'geral';
const SOVEREIGN_KEY = "AURA-BRASIL-SOBERANO-2026";

// DOM ELEMENTS
const chatListContainer = document.getElementById('chat-list');
const messagesContainer = document.getElementById('messages-container');
const messageInput = document.getElementById('message-input');
const sendBtn = document.getElementById('send-btn');
const chatView = document.getElementById('chat-view');

// CRYPTO UTILS
async function encryptMessage(text) {
    const encoder = new TextEncoder();
    const data = encoder.encode(text);
    const keyMaterial = await crypto.subtle.importKey("raw", encoder.encode(SOVEREIGN_KEY), { name: "PBKDF2" }, false, ["deriveKey"]);
    const key = await crypto.subtle.deriveKey({ name: "PBKDF2", salt: encoder.encode("aura-salt"), iterations: 1000, hash: "SHA-256" }, keyMaterial, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv: iv }, key, data);
    return { cipher: btoa(String.fromCharCode(...new Uint8Array(encrypted))), iv: btoa(String.fromCharCode(...iv)) };
}

async function decryptMessage(cipherB64, ivB64) {
    if (!cipherB64 || !ivB64) return "[MENSAGEM PROTEGIDA]";
    try {
        const encoder = new TextEncoder();
        const decoder = new TextDecoder();
        const keyMaterial = await crypto.subtle.importKey("raw", encoder.encode(SOVEREIGN_KEY), { name: "PBKDF2" }, false, ["deriveKey"]);
        const key = await crypto.subtle.deriveKey({ name: "PBKDF2", salt: encoder.encode("aura-salt"), iterations: 1000, hash: "SHA-256" }, keyMaterial, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
        const iv = Uint8Array.from(atob(ivB64), c => c.charCodeAt(0));
        const cipher = Uint8Array.from(atob(cipherB64), c => c.charCodeAt(0));
        const decrypted = await crypto.subtle.decrypt({ name: "AES-GCM", iv: iv }, key, cipher);
        return decoder.decode(decrypted);
    } catch (e) { return "[ERRO DE DESCRIPTOGRAFIA]"; }
}

// WEBSOCKET LOGIC
function connectToAura() {
    socket = new WebSocket(HOST);
    
    socket.onopen = () => {
        console.log("Conectado à Rede Aura");
        socket.send(JSON.stringify({ type: 'auth', name: currentUser, room: currentRoom }));
    };

    socket.onmessage = async (event) => {
        const data = JSON.parse(event.data);
        if (data.type === 'history') {
            messagesContainer.innerHTML = '';
            for (const msg of data.data) {
                if (msg.type === 'payment') {
                    renderPayment(msg.amount, msg.sender, msg.timestamp);
                } else {
                    const text = msg.isAI ? msg.text : await decryptMessage(msg.cipher, msg.iv);
                    renderBubble(text, msg.sender, msg.timestamp, msg.isAI);
                }
            }
        } else if (data.type === 'message') {
            const text = data.isAI ? data.text : await decryptMessage(data.cipher, data.iv);
            renderBubble(text, data.sender, data.timestamp, data.isAI);
        } else if (data.type === 'payment') {
            renderPayment(data.amount, data.sender, data.timestamp);
        }
    };

    socket.onclose = () => setTimeout(connectToAura, 3000);
}

// UI RENDERING
function renderBubble(text, sender, timestamp, isAI = false) {
    const isMe = sender === currentUser;
    const bubble = document.createElement('div');
    bubble.className = `bubble ${isMe ? 'sent' : 'received'}`;
    
    if (isAI) bubble.style.borderLeft = "4px solid var(--social-green)";

    const time = timestamp ? new Date(timestamp).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}) : '--:--';
    
    bubble.innerHTML = `
        <div style="font-size: 11px; font-weight: 700; color: ${isMe ? 'var(--social-green)' : 'var(--aura-blue)'}; margin-bottom: 2px;">
            ${isMe ? 'Você' : sender}
        </div>
        <div>${text}</div>
        <span class="time">${time} ${isMe ? '<i class="ph-fill ph-check-double" style="color: #53bdeb;"></i>' : ''}</span>
    `;

    messagesContainer.appendChild(bubble);
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
}

// EVENT LISTENERS
messageInput.addEventListener('input', () => {
    if (messageInput.value.trim() !== "") {
        sendBtn.className = "ph-fill ph-paper-plane-tilt icon-btn send-btn";
    } else {
        sendBtn.className = "ph-fill ph-microphone icon-btn";
    }
});

async function sendMessage() {
    const text = messageInput.value.trim();
    if (text !== "" && socket.readyState === WebSocket.OPEN) {
        const encrypted = await encryptMessage(text);
        socket.send(JSON.stringify({ 
            cipher: encrypted.cipher, 
            iv: encrypted.iv, 
            sender: currentUser, 
            room: currentRoom 
        }));
        messageInput.value = '';
        sendBtn.className = "ph-fill ph-microphone icon-btn";
    }
}

messageInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') sendMessage();
});

sendBtn.addEventListener('click', () => {
    if (sendBtn.classList.contains('ph-paper-plane-tilt')) {
        sendMessage();
    }
});

// INITIALIZATION
window.onload = () => {
    if (!currentUser) {
        currentUser = prompt("Digite seu Nome Soberano:") || "Cidadão";
        localStorage.setItem('aura_user', currentUser);
    }
    connectToAura();
};

// GLOBAL FUNCTIONS FOR MOBILE NAVIGATION
window.openChat = (name) => {
    currentRoom = name.toLowerCase().includes('presidencial') ? 'gabinete' : 'geral';
    document.getElementById('chat-name').innerText = name;
    document.getElementById('chat-avatar').style.backgroundImage = name.includes('Presidencial') 
        ? "url('https://i.pravatar.cc/150?u=presidencia')" 
        : "url('https://i.pravatar.cc/150?u=aura')";
    
    chatView.classList.add('active');
    
    // Solicitar histórico da nova sala
    if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ type: 'auth', name: currentUser, room: currentRoom }));
    }
};

window.closeChat = () => {
    chatView.classList.remove('active');
};

// CONTACTS & GROUPS
window.importContacts = async () => {
    if (window.NativeAura) {
        window.NativeAura.postMessage('getContacts');
    } else {
        const props = ['name', 'tel'];
        try {
            const contacts = await navigator.contacts.select(props, { multiple: true });
            alert(`${contacts.length} contatos selecionados.`);
        } catch (e) {
            alert("Acesso aos contatos negado ou não suportado.");
        }
    }
};

window.onNativeContactsReceived = (json) => {
    const contacts = JSON.parse(json);
    alert(`${contacts.length} contatos importados via Rede Soberana!`);
    console.log(contacts);
};

window.createNewGroup = () => {
    const name = prompt("Nome do Grupo Gigante:");
    if (name) {
        socket.send(JSON.stringify({ type: 'create_group', group_name: name }));
        alert(`Grupo "${name}" criado! Agora você pode adicionar até 1 milhão de pessoas.`);
    }
};

window.showTab = (tab) => {
    document.getElementById('tab-chats').classList.add('hidden');
    document.getElementById('tab-status').classList.add('hidden');
    document.getElementById('tab-groups').classList.add('hidden');
    
    document.getElementById('tab-' + tab).classList.remove('hidden');
    
    document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
    // Encontrar o item clicado é mais complexo aqui, mas a troca de abas funciona.
};

// JETPAY INTEGRATION
window.openJetPay = () => {
    const amount = prompt("Valor para transferência via JetPay (R$):");
    if (amount) {
        const confirmPay = confirm(`Confirmar envio de R$ ${amount} para ${document.getElementById('chat-name').innerText}?`);
        if (confirmPay) {
            socket.send(JSON.stringify({ 
                type: 'payment', 
                amount: amount, 
                sender: currentUser, 
                room: currentRoom 
            }));
        }
    }
};

function renderPayment(amount, sender, timestamp) {
    const isMe = sender === currentUser;
    const bubble = document.createElement('div');
    bubble.className = `bubble ${isMe ? 'sent' : 'received'}`;
    bubble.style.background = isMe ? "linear-gradient(135deg, #005c4b, #004d33)" : "var(--aura-bubble-in)";
    bubble.style.border = "1px solid var(--national-gold)";

    const time = timestamp ? new Date(timestamp).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}) : '--:--';
    
    bubble.innerHTML = `
        <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 8px;">
            <div style="background: var(--national-gold); color: black; padding: 5px; border-radius: 50%; display: flex;">
                <i class="ph-fill ph-currency-circle-dollar" style="font-size: 20px;"></i>
            </div>
            <div style="font-weight: 800; font-size: 16px; color: var(--national-gold);">JETPAY TRANSFER</div>
        </div>
        <div style="font-size: 28px; font-weight: 800; margin-bottom: 10px;">R$ ${amount}</div>
        
        ${!isMe ? `
            <div style="background: white; padding: 10px; border-radius: 8px; margin-bottom: 10px; text-align: center;">
                <img src="https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=jetpay-pix-mock-${amount}" style="width: 120px; height: 120px;">
                <div style="color: black; font-size: 10px; font-weight: bold; margin-top: 5px;">ESCANEIE PARA PAGAR</div>
            </div>
        ` : `
            <div style="font-size: 12px; opacity: 0.8; margin-bottom: 12px;">Comprovante de envio gerado com sucesso via rede Omni.</div>
        `}
        
        <button style="width: 100%; padding: 10px; border-radius: 8px; border: none; background: ${isMe ? 'rgba(255,255,255,0.2)' : 'var(--national-gold)'}; color: ${isMe ? 'white' : 'black'}; font-weight: 800; font-size: 12px; cursor: pointer;">
            ${isMe ? 'VER COMPROVANTE' : 'PAGAR COM PIX'}
        </button>
        <span class="time">${time}</span>
    `;

    messagesContainer.appendChild(bubble);
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
}
