#!/bin/bash
# Script de Deploy do Fala Brasil na Nuvem (GCP)
# Executar como ROOT ou com sudo: sudo ./deploy_falabrasil_cloud.sh <SEU-DOMINIO>
# Exemplo: sudo ./deploy_falabrasil_cloud.sh falabrasil.auracloud.com.br

DOMAIN=$1

if [ -z "$DOMAIN" ]; then
    echo "ERRO: Você precisa informar o domínio!"
    echo "Uso: sudo ./deploy_falabrasil_cloud.sh <SEU-DOMINIO>"
    exit 1
fi

echo "Iniciando Deploy Seguro do Fala Brasil para $DOMAIN..."

# 1. Instalar dependências (Node.js, Nginx, Certbot)
echo "=> Instalando dependências..."
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs
npm install -g pm2

# 2. Configurar o Projeto Node.js
echo "=> Configurando o Backend..."
cd /var/www/auracloud/fala-brasil || {
    echo "ERRO: Pasta do projeto não encontrada em /var/www/auracloud/fala-brasil"
    exit 1
}
npm install
pm2 stop falabrasil || true
pm2 start server.js --name falabrasil
pm2 save
pm2 startup

# 3. Configurar o NGINX
echo "=> Configurando NGINX..."
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

# 4. Gerar Certificado SSL (Let's Encrypt)
echo "=> Solicitando Certificado SSL Seguro..."
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@auracloud.com.br

echo "========================================================="
echo "DEPLOY FINALIZADO COM SUCESSO!"
echo "Acesse o app: https://$DOMAIN"
echo "URL do WebSocket: wss://$DOMAIN"
echo "O aplicativo Fala Brasil no celular agora pode conectar de forma Segura!"
echo "========================================================="
