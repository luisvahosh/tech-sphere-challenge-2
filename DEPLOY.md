# Despliegue en VPS (Hostinger) con Docker + Nginx

Arquitectura en el servidor:

```
Internet ──HTTPS──► Nginx (VPS, puertos 80/443)
                      ├─ api.tu-dominio.com      ─► 127.0.0.1:8000  contenedor merian-api
                      └─ consola.tu-dominio.com  ─► 127.0.0.1:8501  contenedor merian-console
                                                         │  (red interna Docker: http://api:8000)
                                                   volumen merian_data  (chroma_db + llamadas.db)
```

Los contenedores solo escuchan en `127.0.0.1`; lo único expuesto a internet es Nginx.

## 0. Requisitos en el VPS

- Docker + plugin compose (`docker compose version`). En Hostinger la plantilla "Ubuntu + Docker" ya lo trae.
- Dos registros DNS tipo **A** apuntando a la IP del VPS: `api.tu-dominio.com` y `consola.tu-dominio.com` (hPanel → Dominios → DNS).
- Puertos 80 y 443 abiertos (hPanel → VPS → Firewall, y `ufw` si lo usas).

## 1. Clonar el proyecto

```bash
cd /opt
git clone https://github.com/emanuelvahos/tech-sphere-challenge-2.git merian
cd merian
```

> Si el repo es privado, usa un token personal de GitHub o una deploy key SSH.

## 2. Variables de entorno

```bash
cp .env.example .env
nano .env        # NVIDIA_API_KEY, ELEVENLABS_AGENT_ID, ELEVENLABS_WEBHOOK_SECRET...
chmod 600 .env
```

Si los puertos 8000/8501 ya los usa otro contenedor del servidor, agrega al `.env`
`API_PORT=` y `CONSOLE_PORT=` con otros valores (y ajústalos en la config de Nginx).

## 3. Construir y levantar

```bash
docker compose up -d --build
docker compose ps                     # ambos "healthy"/"running"
curl http://127.0.0.1:8000/health     # {"status":"ok"}
docker compose logs -f api            # ver logs
```

## 4. Proxy inverso (Nginx + HTTPS)

```bash
sudo apt install -y nginx certbot python3-certbot-nginx apache2-utils

sudo cp deploy/nginx/merian.conf /etc/nginx/sites-available/merian.conf
sudo nano /etc/nginx/sites-available/merian.conf     # cambia tu-dominio.com
sudo ln -s /etc/nginx/sites-available/merian.conf /etc/nginx/sites-enabled/

# Usuario/clave para la consola del equipo médico
sudo htpasswd -c /etc/nginx/.htpasswd-merian medico

sudo nginx -t && sudo systemctl reload nginx

# Certificados SSL (Let's Encrypt); certbot edita el conf y agrega el 443
sudo certbot --nginx -d api.tu-dominio.com -d consola.tu-dominio.com
```

> Si en el servidor ya tienes otro proxy (Traefik, Nginx Proxy Manager, Caddy),
> no instales Nginx: apunta ese proxy a `127.0.0.1:8000` y `127.0.0.1:8501`,
> activa WebSocket para la consola y replica el filtro de rutas de la API.

## 5. Conectar ElevenLabs

En el dashboard del agente:

- **Tool RAG**: `POST https://api.tu-dominio.com/query`
- **Webhook post-llamada**: `POST https://api.tu-dominio.com/webhook/post-call`

Interfaz del paciente: `https://api.tu-dominio.com/llamada`
Consola: `https://consola.tu-dominio.com`

## Qué queda público y qué no

| Ruta | Público | Motivo |
|---|---|---|
| `/llamada`, `/llamada/static/*` | ✅ | Interfaz del paciente |
| `/query` | ✅ | Tool RAG que invoca ElevenLabs |
| `/webhook/post-call` | ✅ | Protegido por firma HMAC |
| `/health` | ✅ | Monitoreo |
| `/documents`, `/llamadas`, `/docs` | ❌ 404 | Gestión RAG y datos de pacientes: solo vía consola |

## Actualizar a una nueva versión

```bash
cd /opt/merian
git pull
docker compose up -d --build
docker image prune -f
```

Los documentos cargados y el historial de llamadas viven en el volumen `merian_data` y sobreviven a reinicios y redeploys.

## Backup del volumen

```bash
docker run --rm -v merian_merian_data:/data -v "$PWD":/backup alpine \
  tar czf /backup/merian-data-$(date +%F).tgz -C /data .
```
