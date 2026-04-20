// CONFIGURAÇÃO DE REDE AURA (WEBSOCKETS)
const HOST = window.location.origin.replace(/^http/, 'ws');
let socket;

function connectToAuraCloud() {
    socket = new WebSocket(HOST);

    socket.onopen = () => {
        console.log("Conectado ao Aura Cloud Hub");
        document.querySelector('.zero-rating-banner span').innerText = "Zero-Rating Ativo (Cloud)";
    };

    socket.onmessage = (event) => {
        const data = JSON.parse(event.data);
        displayMessage(data.text, data.sender);
    };

    socket.onclose = () => {
        console.log("Conexão perdida. Tentando reconectar...");
        setTimeout(connectToAuraCloud, 3000);
    };
}

function displayMessage(text, sender) {
    const chatArea = document.querySelector('.mobile-frame');
    const msgDiv = document.createElement('div');
    const isMe = sender === 'Eu';
    
    msgDiv.style.cssText = `
        padding: 10px 15px; 
        background: ${isMe ? '#e6faff' : '#f0f0f0'}; 
        border-radius: 12px; 
        margin: 8px 20px; 
        align-self: ${isMe ? 'flex-end' : 'flex-start'};
        max-width: 80%;
        font-size: 14px;
        border: ${isMe ? '1px solid var(--aura-blue)' : '1px solid #ddd'};
    `;
    
    msgDiv.innerHTML = `
        <div style="font-size: 10px; color: #888; margin-bottom: 2px;">${sender}</div>
        <div>${text}</div>
    `;
    
    chatArea.insertBefore(msgDiv, document.getElementById('chat-input-area'));
    // Auto-scroll para o fim
    msgDiv.scrollIntoView({ behavior: 'smooth' });
}

// Lógica de Pix Social
const pixModal = document.getElementById('pix-modal');
const btnPix = document.getElementById('btn-pix');
const closePix = document.getElementById('close-modal');
const confirmPix = document.getElementById('confirm-pix');

// Abrir Chat e Mostrar Barra de Entrada
document.querySelectorAll('.chat-item').forEach(item => {
    item.addEventListener('click', () => {
        document.getElementById('chat-list').style.display = 'none';
        document.getElementById('chat-input-area').style.display = 'block';
    });
});

// Enviar Mensagem Real
document.querySelector('#chat-input-area input').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
        const text = e.target.value;
        if (text && socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify({ text, sender: 'Eu' }));
            e.target.value = '';
        }
    }
});

btnPix.addEventListener('click', () => pixModal.style.display = 'flex');
closePix.addEventListener('click', () => pixModal.style.display = 'none');

confirmPix.addEventListener('click', () => {
    const amount = document.getElementById('pix-amount').value || "0,00";
    if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ 
            text: `💸 Pix Enviado: R$ ${amount}`, 
            sender: 'Aura Bank' 
        }));
    }
    pixModal.style.display = 'none';
});

// TROCA DE TELA PARA EDUFUTURO (SIMULAÇÃO)
document.getElementById('btn-edufuturo').addEventListener('click', function() {
    const main = document.querySelector('main');
    main.innerHTML = `
        <div style="padding: 20px; text-align: center;">
            <i class="ph ph-graduation-cap" style="font-size: 80px; color: var(--aura-blue);"></i>
            <h2 style="margin-top: 20px; color: var(--aura-dark);">Cursos EduFuturo</h2>
            <p style="color: #666; font-size: 14px; margin-top: 10px;">Educação sem Consumo de Dados</p>
        </div>
    `;
    document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
    this.classList.add('active');
});

// INICIALIZAÇÃO
window.onload = () => {
    connectToAuraCloud();
};
