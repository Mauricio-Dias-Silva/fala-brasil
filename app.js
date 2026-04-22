// CONFIGURAÇÃO DE REDE AURA E CRIPTOGRAFIA v3.0
const HOST = window.location.origin.replace(/^http/, 'ws');
let socket;
let currentUser = localStorage.getItem('aura_user') || null;
let currentRoom = 'geral';
const SOVEREIGN_KEY = "AURA-BRASIL-SOBERANO-2026";

// FUNÇÕES DE CRIPTOGRAFIA
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
    if (!cipherB64 || !ivB64) return "[ERRO DE CIFRA]";
    try {
        const encoder = new TextEncoder();
        const decoder = new TextDecoder();
        const keyMaterial = await crypto.subtle.importKey("raw", encoder.encode(SOVEREIGN_KEY), { name: "PBKDF2" }, false, ["deriveKey"]);
        const key = await crypto.subtle.deriveKey({ name: "PBKDF2", salt: encoder.encode("aura-salt"), iterations: 1000, hash: "SHA-256" }, keyMaterial, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
        const iv = Uint8Array.from(atob(ivB64), c => c.charCodeAt(0));
        const cipher = Uint8Array.from(atob(cipherB64), c => c.charCodeAt(0));
        const decrypted = await crypto.subtle.decrypt({ name: "AES-GCM", iv: iv }, key, cipher);
        return decoder.decode(decrypted);
    } catch (e) { return "[MENSAGEM PROTEGIDA]"; }
}

// ELEMENTOS DOM
const chatList = document.getElementById('chat-list');
const chatInputArea = document.getElementById('chat-input-area');
const inputField = document.querySelector('#chat-input-area input');
const mobileFrame = document.querySelector('.mobile-frame');

function connectToAuraCloud() {
    socket = new WebSocket(HOST);

    socket.onopen = () => {
        document.querySelector('.zero-rating-banner span').innerText = "Soberania Ativa: " + currentRoom.toUpperCase();
        // Autenticação na sala
        socket.send(JSON.stringify({ type: 'auth', name: currentUser, room: currentRoom }));
    };

    socket.onmessage = async (event) => {
        const data = JSON.parse(event.data);
        if (data.type === 'history') {
            document.getElementById('messages-container')?.remove();
            for (const msg of data.data) {
                const text = msg.isAI ? msg.text : await decryptMessage(msg.cipher, msg.iv);
                displayMessage(text, msg.sender, msg.timestamp, msg.isAI);
            }
        } else if (data.type === 'message') {
            const text = data.isAI ? data.text : await decryptMessage(data.cipher, data.iv);
            displayMessage(text, data.sender, data.timestamp, data.isAI);
        }
    };

    socket.onclose = () => setTimeout(connectToAuraCloud, 3000);
}

function displayMessage(text, sender, timestamp, isAI = false) {
    let container = document.getElementById('messages-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'messages-container';
        container.style.cssText = "flex: 1; overflow-y: auto; padding: 20px; display: flex; flex-direction: column; gap: 12px; padding-bottom: 120px;";
        mobileFrame.insertBefore(container, chatInputArea);
    }

    const isMe = sender === currentUser;
    const msgDiv = document.createElement('div');
    msgDiv.style.cssText = `
        max-width: 85%; padding: 12px 16px; border-radius: ${isMe ? '20px 20px 4px 20px' : '20px 20px 20px 4px'};
        background: ${isAI ? 'rgba(0,245,196,0.1)' : (isMe ? 'linear-gradient(135deg, var(--aura-blue), #7d5fff)' : 'rgba(255,255,255,0.08)')};
        color: white; align-self: ${isMe ? 'flex-end' : 'flex-start'};
        box-shadow: 0 4px 15px rgba(0,0,0,0.2); border: 1px solid ${isAI ? 'var(--social-green)' : 'rgba(255,255,255,0.05)'};
        backdrop-filter: blur(5px);
    `;

    const time = timestamp ? new Date(timestamp).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}) : '--:--';
    msgDiv.innerHTML = `
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px; gap: 10px;">
            <span style="font-size: 10px; font-weight: 800; color: ${isAI ? 'var(--national-gold)' : 'var(--social-green)'}; text-transform: uppercase;">${sender}</span>
            <i class="ph ${isAI ? 'ph-sparkle' : 'ph-lock-key'}" style="font-size: 10px; color: rgba(255,255,255,0.2);"></i>
        </div>
        <div style="font-size: 14px; line-height: 1.4;">${text}</div>
        <div style="font-size: 9px; color: rgba(255,255,255,0.4); text-align: right; margin-top: 4px;">${time}</div>
    `;

    container.appendChild(msgDiv);
    container.scrollTop = container.scrollHeight;
}

// --- FUNÇÃO DE CONTATOS (SALA SOBERANA) ---
async function importContacts() {
    const props = ['name', 'tel'];
    const opts = { multiple: true };

    try {
        const contacts = await navigator.contacts.select(props, opts);
        if (contacts.length > 0) {
            alert(`${contacts.length} contatos importados para sua Rede Soberana!`);
            // Aqui poderíamos salvar no servidor ou localStorage
            console.log(contacts);
        }
    } catch (ex) {
        alert("Acesso aos contatos negado ou não suportado neste navegador.");
    }
}

// SWITCH DE SALAS
document.querySelectorAll('.chat-item').forEach(item => {
    item.addEventListener('click', () => {
        const name = item.querySelector('.name').innerText;
        currentRoom = name.toLowerCase().includes('presidencial') ? 'gabinete' : 'geral';
        chatList.style.display = 'none';
        chatInputArea.style.display = 'block';
        if (socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify({ type: 'auth', name: currentUser, room: currentRoom }));
        }
    });
});

inputField.addEventListener('keypress', async (e) => {
    if (e.key === 'Enter' && inputField.value.trim() !== "") {
        const text = inputField.value;
        if (socket.readyState === WebSocket.OPEN) {
            const encrypted = await encryptMessage(text);
            socket.send(JSON.stringify({ cipher: encrypted.cipher, iv: encrypted.iv, sender: currentUser, room: currentRoom }));
            inputField.value = '';
        }
    }
});

// Adicionar listener para o botão de contatos (se existisse no nav)
document.querySelector('.fab').addEventListener('click', importContacts);

window.onload = () => {
    if (!currentUser) {
        currentUser = prompt("Digite seu Nome Soberano:") || "Usuário";
        localStorage.setItem('aura_user', currentUser);
    }
    connectToAuraCloud();
};
