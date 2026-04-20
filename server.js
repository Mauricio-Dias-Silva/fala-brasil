const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;

// 1. SERVIDOR DE ARQUIVOS ESTÁTICOS (FRONTEND)
const server = http.createServer((req, res) => {
    let filePath = '.' + req.url;
    if (filePath === './') filePath = './index.html';

    const extname = String(path.extname(filePath)).toLowerCase();
    const mimeTypes = {
        '.html': 'text/html',
        '.js': 'text/javascript',
        '.css': 'text/css',
        '.json': 'application/json',
        '.png': 'image/png',
    };

    const contentType = mimeTypes[extname] || 'application/octet-stream';

    fs.readFile(filePath, (error, content) => {
        if (error) {
            res.writeHead(404);
            res.end('Arquivo não encontrado');
        } else {
            res.writeHead(200, { 'Content-Type': contentType });
            res.end(content, 'utf-8');
        }
    });
});

// 2. SERVIDOR WEBSOCKET (MENSAGERIA)
const wss = new WebSocketServer({ server });

wss.on('connection', (ws) => {
    console.log('Novo dispositivo conectado à Rede Aura');

    ws.on('message', (data) => {
        // Retransmitir a mensagem para todos os outros conectados (Broadcast)
        wss.clients.forEach((client) => {
            if (client.readyState === 1) {
                client.send(data.toString());
            }
        });
    });

    ws.on('close', () => console.log('Dispositivo desconectado'));
});

server.listen(PORT, () => {
    console.log(`FalaBrasil Cloud ativo na porta ${PORT}`);
});
