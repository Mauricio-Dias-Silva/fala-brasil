const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const crypto = require('crypto');
const sqlite3 = require('sqlite3').verbose();
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const PORT = process.env.PORT || 8080;
const JWT_SECRET = "AURA-BRASIL-JWT-SUPER-SECRET-2026"; // In prod, use .env

// Configurando Banco de Dados SQLite
const dbPath = path.join(__dirname, 'fala_brasil.db');
const db = new sqlite3.Database(dbPath);

db.serialize(() => {
    db.run(`CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password_hash TEXT,
        public_key TEXT
    )`);
    db.run(`CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT,
        room TEXT,
        cipher TEXT,
        iv TEXT,
        text TEXT,
        is_ai BOOLEAN,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
    )`);
});

const server = http.createServer((req, res) => {
    let filePath = '.' + req.url;
    if (filePath === './') filePath = './index.html';
    
    // Rota de Health Check para o App Nativo saber se o servidor está vivo
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ status: 'ok', message: 'Rede Aura Sincronizada' }));
    }

    const extname = String(path.extname(filePath)).toLowerCase();
    const mimeTypes = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };
    const contentType = mimeTypes[extname] || 'application/octet-stream';

    fs.readFile(filePath, (error, content) => {
        if (error) { res.writeHead(404); res.end('404'); }
        else { res.writeHead(200, { 'Content-Type': contentType }); res.end(content, 'utf-8'); }
    });
});

const wss = new WebSocketServer({ server });
const clients = new Map(); // ws -> { name, room }
const pendingWebSessions = new Map(); // session_id -> ws

wss.on('connection', (ws) => {
    console.log('Nova conexão na Rede Aura');

    ws.on('message', async (data) => {
        try {
            const msg = JSON.parse(data.toString());
            
            if (msg.type === 'request_web_session') {
                const sessionId = crypto.randomUUID();
                pendingWebSessions.set(sessionId, ws);
                ws.send(JSON.stringify({ type: 'web_session_created', session_id: sessionId }));
                return;
            }

            if (msg.type === 'authorize_web_session') {
                const { session_id, token } = msg;
                if (!token || !session_id) return ws.send(JSON.stringify({ type: 'error', message: 'Dados inválidos' }));
                
                try {
                    const decoded = jwt.verify(token, JWT_SECRET);
                    const name = decoded.name;
                    
                    const webWs = pendingWebSessions.get(session_id);
                    if (webWs && webWs.readyState === 1) {
                        // Autoriza a sessão web
                        const newToken = jwt.sign({ name }, JWT_SECRET, { expiresIn: '7d' });
                        webWs.send(JSON.stringify({ type: 'auth_success', token: newToken, name }));
                        finishAuth(webWs, name, 'geral');
                        pendingWebSessions.delete(session_id);
                        
                        ws.send(JSON.stringify({ type: 'auth_success', message: 'Sessão Web autorizada' }));
                    } else {
                        ws.send(JSON.stringify({ type: 'error', message: 'Sessão web não encontrada' }));
                    }
                } catch (err) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Token inválido/expirado.' }));
                }
                return;
            }

            if (msg.type === 'auth') {
                const { name, password, publicKey, token, room } = msg;
                const targetRoom = room || 'geral';

                // Se já tem token, valida direto
                if (token) {
                    try {
                        const decoded = jwt.verify(token, JWT_SECRET);
                        finishAuth(ws, decoded.name, targetRoom);
                    } catch (err) {
                        ws.send(JSON.stringify({ type: 'error', message: 'Token inválido/expirado.' }));
                        ws.close();
                    }
                    return;
                }

                if (!name || !password) {
                    ws.send(JSON.stringify({ type: 'error', message: 'Nome e Senha são obrigatórios.' }));
                    return;
                }

                // Fluxo Login / Registro
                db.get("SELECT * FROM users WHERE username = ?", [name], (err, user) => {
                    if (err) return ws.send(JSON.stringify({ type: 'error', message: 'Erro no BD' }));
                    
                    if (!user) {
                        // Registra novo usuário
                        const hash = bcrypt.hashSync(password, 10);
                        db.run("INSERT INTO users (username, password_hash, public_key) VALUES (?, ?, ?)", [name, hash, publicKey], function(err) {
                            if (err) return ws.send(JSON.stringify({ type: 'error', message: 'Erro ao criar usuário' }));
                            const newToken = jwt.sign({ name }, JWT_SECRET, { expiresIn: '7d' });
                            ws.send(JSON.stringify({ type: 'auth_success', token: newToken, name }));
                            finishAuth(ws, name, targetRoom);
                        });
                    } else {
                        // Valida Login
                        if (bcrypt.compareSync(password, user.password_hash)) {
                            // Atualiza chave publica se houver uma nova
                            if (publicKey && publicKey !== user.public_key) {
                                db.run("UPDATE users SET public_key = ? WHERE username = ?", [publicKey, name]);
                            }
                            const newToken = jwt.sign({ name }, JWT_SECRET, { expiresIn: '7d' });
                            ws.send(JSON.stringify({ type: 'auth_success', token: newToken, name }));
                            finishAuth(ws, name, targetRoom);
                        } else {
                            ws.send(JSON.stringify({ type: 'error', message: 'Senha incorreta!' }));
                        }
                    }
                });
                return;
            }

            // Exigir autenticação para outros comandos
            if (!clients.has(ws)) return;
            const senderInfo = clients.get(ws);

            if (msg.type === 'get_public_keys') {
                // Retorna chaves publicas de todos na sala
                db.all("SELECT username, public_key FROM users", [], (err, rows) => {
                    if (!err && rows) {
                        ws.send(JSON.stringify({ type: 'public_keys', keys: rows }));
                    }
                });
                return;
            }

            if (msg.type === 'create_group') {
                console.log(`Novo grupo soberano criado: ${msg.group_name}`);
                ws.send(JSON.stringify({ type: 'group_created', name: msg.group_name }));
                return;
            }

            // Chat Normal
            msg.timestamp = new Date().toISOString();
            msg.room = msg.room || 'geral';
            msg.sender = senderInfo.name;

            // Salva no SQLite
            db.run("INSERT INTO messages (sender, room, cipher, iv, text, is_ai, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?)", 
                [msg.sender, msg.room, msg.cipher || null, msg.iv || null, msg.text || null, msg.isAI ? 1 : 0, msg.timestamp]
            );

            // Transmite
            const output = JSON.stringify({ type: 'message', ...msg });
            wss.clients.forEach((client) => {
                const clientData = clients.get(client);
                if (client.readyState === 1 && clientData && clientData.room === msg.room) {
                    client.send(output);
                }
            });

            // Tratamento Aura AI (Para simplificar, permitimos invocar por texto limpo no payload ou msg cifrada legado)
            let aiQuery = msg.text; 
            if (aiQuery && aiQuery.includes('@Aura') && msg.sender !== 'Aura AI') {
                handleAuraAI(aiQuery, msg.room);
            }

        } catch (e) { console.error('Erro de parse/WS:', e); }
    });

    ws.on('close', () => clients.delete(ws));
});

function finishAuth(ws, name, room) {
    clients.set(ws, { name, room });
    console.log(`Usuário autenticado: ${name} na sala ${room}`);
    
    db.all("SELECT * FROM messages WHERE room = ? ORDER BY timestamp DESC LIMIT 100", [room], (err, rows) => {
        if (!err && rows) {
            const history = rows.reverse().map(r => ({
                ...r,
                isAI: r.is_ai === 1
            }));
            ws.send(JSON.stringify({ type: 'history', data: history }));
        }
    });
}

// Bot Aura AI
function handleAuraAI(query, room) {
    let responseText = `Olá! Sou a Aura. Recebi seu comando: "${query.replace('@Aura', '').trim()}". Estou processando via Rede Soberana...`;
    
    // (Aura logic from before)
    setTimeout(() => {
        const auraMsg = {
            type: 'message',
            sender: 'Aura AI',
            text: responseText, // Texto legivel para a AI
            room: room,
            timestamp: new Date().toISOString(),
            isAI: true
        };
        
        db.run("INSERT INTO messages (sender, room, text, is_ai, timestamp) VALUES (?, ?, ?, ?, ?)", 
            [auraMsg.sender, auraMsg.room, auraMsg.text, 1, auraMsg.timestamp]
        );

        wss.clients.forEach((client) => {
            const clientData = clients.get(client);
            if (client.readyState === 1 && clientData && clientData.room === room) {
                client.send(JSON.stringify(auraMsg));
            }
        });
    }, 1500);
}

server.listen(PORT, () => console.log(`FalaBrasil v4 (Secure Node) ativo na porta ${PORT}`));
