# Infraestructura local · I Found It

Levanta en tu equipo todas las piezas que existen hoy, conectadas entre sí: `frontend`, `core`, `schedule` (API + worker), `scraper`, PostgreSQL 16 y MongoDB 8.0.

Qué hace cada pieza, sus redes, el orden de arranque y las limitaciones están en la guía [`docs/guides/local-environment.md`](../../docs/guides/local-environment.md). Aquí solo van los comandos.

## Antes de empezar

- Docker con Compose v2, encendido.
- Los repos de servicios clonados **en la misma carpeta que `architecture`**: `core-service`, `schedule-service`, `scraper-service` y `foundit-web-app`. Si están en otro lugar, define `IFI_REPOS_DIR` en `.env`.
- Todos los comandos se corren **desde esta carpeta** (`infra/local/`).

## Levantar

1. **Solo la primera vez:** genera el `.env` con contraseñas de prueba aleatorias. No muestra los valores y no sobrescribe un `.env` que ya exista.

   ```bash
   ./gen-env.sh
   ```

2. Construye las imágenes y levanta todo, esperando a que cada pieza quede sana:

   ```bash
   docker compose up -d --build --wait
   ```

   Si las imágenes ya están construidas y no cambió el código, puedes omitir `--build`.

3. Abre la aplicación:
   - Interfaz: <http://127.0.0.1:5173>
   - API de `core`: <http://127.0.0.1:8000/api/health>

## Ver el estado

```bash
docker compose ps
```

```bash
docker compose logs -f core schedule worker scraper
```

## Detener

Detener sin borrar los contenedores. **Las bases se reinician vacías** al volver a arrancar, porque viven en `tmpfs`:

```bash
docker compose stop
```

Detener y eliminar los contenedores y las redes. **Borra todos los datos**:

```bash
docker compose down
```

Volver a levantar después de un `stop` o un `down`:

```bash
docker compose up -d --wait
```

## Problemas comunes

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `required variable ... is missing` / `run ./gen-env.sh` | No existe `.env` | `./gen-env.sh` |
| `.env already exists` | `gen-env.sh` no sobrescribe | Bórralo tú si quieres valores nuevos (perderás los datos al reiniciar igual) |
| `port is already allocated` en 5173 u 8000 | Otro compose de un servicio sigue arriba | Detén ese compose (`docker compose down` en su repo) |
| `unable to prepare context` | Falta un repo hermano o la rama con su `Dockerfile` | Clónalo junto a `architecture` o ajusta `IFI_REPOS_DIR` |
| Una pieza queda `unhealthy` | Ver sus logs | `docker compose logs <servicio>` |

## Archivos

| Archivo | Para qué |
|---|---|
| [`compose.yaml`](compose.yaml) | Las piezas, sus redes y su orden de arranque |
| [`gen-env.sh`](gen-env.sh) | Crea `.env` con valores de prueba (permisos `600`, ignorado por git) |
| [`.env.example`](.env.example) | Nombres de las variables, sin valores |
| [`docker/postgres-init/`](docker/postgres-init/) | Crea los roles y aplica los esquemas de `core` y `schedule` al primer arranque |
