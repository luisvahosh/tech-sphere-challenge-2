# Despliegue en VPS Hostinger (Docker + Nginx Proxy Manager)

Dominio: **https://postoperatorio.learnway.co**

```
Internet ─HTTPS─► Nginx Proxy Manager ──(red Docker de NPM)──┐
                   postoperatorio.learnway.co                 │
                     /llamada, /query, /webhook/post-call ──► ts2-postop-api:8000
                     /consola ──────────────────────────────► ts2-postop-console:8501
                                                                     │ red "interna"
                                                          volumen postop_data (chroma_db + llamadas.db)
```

- Proyecto compose `tech-sphere-2`: contenedores `ts2-postop-*` para no chocar con `tech-sphere-challenge` ni con otros proyectos.
- No se publican puertos en el host; NPM llega a los contenedores por su red Docker.

| URL | Uso |
|---|---|
| `https://postoperatorio.learnway.co/` | Redirige a `/llamada` |
| `https://postoperatorio.learnway.co/llamada` | Interfaz del paciente |
| `https://postoperatorio.learnway.co/consola` | Consola del equipo médico (pide `CONSOLE_PASSWORD`) |
| `https://postoperatorio.learnway.co/query` | Tool RAG de ElevenLabs |
| `https://postoperatorio.learnway.co/webhook/post-call` | Webhook post-llamada (firma HMAC) |
| `/documents`, `/llamadas`, `/docs` | Bloqueadas desde internet (404); la consola las usa por la red interna |

## 1. DNS (hPanel de Hostinger)

Dominios → `learnway.co` → DNS: registro **A** `postoperatorio` → IP del VPS.
Compruébalo con `ping postoperatorio.learnway.co`.

## 2. Clonar en el VPS

```bash
cd /opt
git clone https://github.com/luisvahosh/tech-sphere-challenge-2.git
cd tech-sphere-challenge-2
```

> El repo es privado: GitHub pide usuario y, como contraseña, un **token personal**
> (GitHub → Settings → Developer settings → Personal access tokens → fine-grained,
> permiso *Contents: Read-only* sobre este repo).

## 3. Variables de entorno

```bash
cp .env.example .env
nano .env
chmod 600 .env
```

Completa `NVIDIA_API_KEY`, `ELEVENLABS_AGENT_ID`, `ELEVENLABS_WEBHOOK_SECRET`, `CONSOLE_PASSWORD`
y `NPM_NETWORK`. Para saber la red de NPM:

```bash
docker ps --format '{{.Names}}' | grep -i proxy            # nombre del contenedor NPM
docker inspect <contenedor-npm> -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
```

## 4. Levantar

```bash
docker compose up -d --build
docker compose ps                          # ts2-postop-api "healthy", ts2-postop-console "running"
docker compose logs -f api
```

Prueba desde NPM que se ven (debe responder `{"status":"ok"}`):

```bash
docker exec <contenedor-npm> curl -s http://ts2-postop-api:8000/health
```

## 5. Proxy Host en Nginx Proxy Manager

**Hosts → Proxy Hosts → Add Proxy Host**

- **Details**
  - Domain Names: `postoperatorio.learnway.co`
  - Scheme: `http` · Forward Hostname: `ts2-postop-api` · Forward Port: `8000`
  - ✅ Block Common Exploits · ✅ Websockets Support
- **SSL**
  - Request a new SSL Certificate (Let's Encrypt) · ✅ Force SSL · ✅ HTTP/2
- **Advanced**
  - Pega el contenido de [`deploy/npm-advanced.conf`](./deploy/npm-advanced.conf)

No uses Access List en este host: bloquearía al paciente y al webhook de ElevenLabs.
La consola se protege con su propia clave.

> HTTPS es obligatorio: sin él el navegador no da acceso al micrófono en `/llamada`.

## 6. ElevenLabs

En el agente:

- Tool RAG: `POST https://postoperatorio.learnway.co/query`
- Webhook post-llamada: `POST https://postoperatorio.learnway.co/webhook/post-call`

## Actualizar

```bash
cd /opt/tech-sphere-challenge-2
git pull
docker compose up -d --build
docker image prune -f
```

Documentos e historial viven en el volumen `tech-sphere-2_postop_data` y sobreviven a redeploys.

## Backup

```bash
docker run --rm -v tech-sphere-2_postop_data:/data -v "$PWD":/backup alpine \
  tar czf /backup/postop-data-$(date +%F).tgz -C /data .
```
