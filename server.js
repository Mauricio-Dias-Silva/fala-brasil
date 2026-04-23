const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;
const HISTORY_FILE = path.join(__dirname, 'messages.json');

if (!fs.existsSync(HISTORY_FILE)) {
    fs.writeFileSync(HISTORY_FILE, JSON.stringify([]));
}

const server = http.createServer((req, res) => {
    let filePath = '.' + req.url;
    if (filePath === './') filePath = './index.html';
    const extname = String(path.extname(filePath)).toLowerCase();
    const mimeTypes = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };
    const contentType = mimeTypes[extname] || 'application/octet-stream';

    fs.readFile(filePath, (error, content) => {
        if (error) { res.writeHead(404); res.end('404'); }
        else { res.writeHead(200, { 'Content-Type': contentType }); res.end(content, 'utf-8'); }
    });
});

const wss = new WebSocketServer({ server });

// Mapeamento de usuários e salas
const clients = new Map(); // ws -> { name, room }

wss.on('connection', (ws) => {
    console.log('Nova conexão na Rede Aura');

    ws.on('message', async (data) => {
        try {
            const msg = JSON.parse(data.toString());
            
            if (msg.type === 'auth') {
                clients.set(ws, { name: msg.name, room: msg.room || 'geral' });
                // Enviar histórico da sala específica
                const history = JSON.parse(fs.readFileSync(HISTORY_FILE, 'utf-8'));
                const roomHistory = history.filter(m => m.room === (msg.room || 'geral')).slice(-100);
                ws.send(JSON.stringify({ type: 'history', data: roomHistory }));
                return;
            }

            if (msg.type === 'create_group') {
                console.log(`Novo grupo soberano criado: ${msg.group_name}`);
                // Notificar criador
                ws.send(JSON.stringify({ type: 'group_created', name: msg.group_name }));
                return;
            }

            // Mensagem normal de chat
            msg.timestamp = new Date().toISOString();
            msg.room = msg.room || 'geral';

            // Salvar no histórico
            const history = JSON.parse(fs.readFileSync(HISTORY_FILE, 'utf-8'));
            history.push(msg);
            fs.writeFileSync(HISTORY_FILE, JSON.stringify(history.slice(-2000)));

            // Transmitir apenas para quem está na mesma sala
            const output = JSON.stringify({ type: 'message', ...msg });
            wss.clients.forEach((client) => {
                const clientData = clients.get(client);
                if (client.readyState === 1 && clientData && clientData.room === msg.room) {
                    client.send(output);
                }
            });

            // --- INTEGRAÇÃO COM IA AURA ---
            // Se mencionar @Aura e não for a própria Aura respondendo
            if (msg.text && msg.text.includes('@Aura') && msg.sender !== 'Aura AI') {
                handleAuraAI(msg.text, msg.room);
            }

        } catch (e) { console.error('Erro:', e); }
    });

    ws.on('close', () => clients.delete(ws));
});

// Função para simular a resposta da IA (Pode ser integrada com a API da Aura Cloud)
async function handleAuraAI(query, room) {
    const responseText = `Olá! Sou a Aura. Recebi seu comando: "${query.replace('@Aura', '').trim()}". Estou processando via Rede Soberana...`;
    
    // Simular delay de pensamento
    setTimeout(() => {
        const auraMsg = {
            type: 'message',
            sender: 'Aura AI',
            text: responseText,
            room: room,
            timestamp: new Date().toISOString(),
            isAI: true
        };
        
        // Criptografia seria aplicada no cliente, mas para o log do servidor salvamos o aviso
        const history = JSON.parse(fs.readFileSync(HISTORY_FILE, 'utf-8'));
        history.push(auraMsg);
        fs.writeFileSync(HISTORY_FILE, JSON.stringify(history.slice(-2000)));

        wss.clients.forEach((client) => {
            const clientData = clients.get(client);
            if (client.readyState === 1 && clientData && clientData.room === room) {
                client.send(JSON.stringify(auraMsg));
            }
        });
    }, 1500);
}

server.listen(PORT, () => console.log(`FalaBrasil v3 ativo na porta ${PORT}`));
