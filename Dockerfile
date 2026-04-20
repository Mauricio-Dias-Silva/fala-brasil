# Usa uma imagem estável de Node.js
FROM node:20-slim

# Define o diretório de trabalho
WORKDIR /app

# Copia os arquivos de dependência
COPY package*.json ./

# Instala as dependências (apenas produção)
RUN npm install --only=production

# Copia o restante do código (Frontend + Backend)
COPY . .

# Expõe a porta padrão do Cloud Run
ENV PORT=8080
EXPOSE 8080

# Inicia o servidor
CMD ["node", "server.js"]
