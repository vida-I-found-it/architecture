# Semana 15 · Interfaz e integración

> Enunciado: [guía de la semana 15](../../sources/semana-15/README.md) · Continúa la [semana 13](../semana-13/README.md) y la [semana 14](../semana-14/README.md): mismos RF, prioridades, contratos y RNF.

**Integrantes:** _por completar por el equipo._

---

## Antes de construir la interfaz

### ¿Funcionan los endpoints sin la pantalla?

Sí. `POST /api/alerts` (RF-01) y `GET /api/alerts/{alert_id}` (RF-02) responden según su contrato.

### ¿Cuáles son los contratos que usa la pantalla?

Los de la [semana 14](../semana-14/README.md#actividad-2--contratos-de-la-api), sin cambios.

### ¿Cómo se arranca todo?

| Pieza | Dirección |
|---|---|
| API (`core`) | `http://127.0.0.1:8000` |
| Pantalla (`foundit-web-app`) | `http://127.0.0.1:5173` |

La API acepta peticiones desde la dirección de la pantalla (CORS).

### ¿Qué estaba verificado y qué faltaba?

- **Verificado:** RF-01 y su seguridad.
- **Faltaba:** la prueba de RF-02 desde la pantalla y la medición de velocidad de RF-01.

---

## Actividad 1 · Diseñar la interacción

### ¿Qué hace el usuario en cada RF y qué ve?

| RF | Qué hace el usuario | Qué ve |
|---|---|---|
| RF-01 · Registrar | Elige «URL directa», pega las páginas, escribe los correos y pulsa **Guardar alerta**. Antes de crear, confirma en una ventana | «Alerta creada», con su número, las páginas y el correo oculto (`u***@example.com`). Ve también un aviso: la primera revisión de precios se hace en segundo plano |
| RF-02 · Consultar ([US-07-06](../../../docs/requirements/user-stories/CU-07.md#us-07-06--consultar-una-alerta-por-su-número-prototipo-universitario)) | Pulsa **Ver alerta** al crear, o entra a «Alertas» y escribe el número | Los datos de la alerta (estado, páginas y correos ocultos), o el aviso de que no existe |

### ¿Es fácil de usar?

- Todos los campos tienen etiqueta visible.
- Se puede usar solo con el teclado.
- Los errores se explican con texto, no solo con color.
- Lo escrito no se borra cuando hay un error.

---

## Actividad 2 · Conectar cada acción con su contrato

### ¿Qué muestra la pantalla según la respuesta?

| Respuesta | RF-01 · Registrar | RF-02 · Consultar |
|---|---|---|
| Éxito | 201: el número y el estado reales | 200: los datos recuperados |
| Rechazo | 422: marca el campo o la fila exacta, por ejemplo «Esta dirección apunta a una red no permitida» | 404: «La alerta no existe.» · 422: «El número no es válido…»; no quedan datos de la consulta anterior |
| Sin conexión | «No pudimos conectar», y se conserva lo escrito | Aviso y botón «Reintentar» |

### ¿Cómo se evitan los errores de comunicación?

- Mientras se envía, el botón queda deshabilitado: aunque se haga doble clic, sale **una sola** petición.
- «Creada» se muestra **solo** cuando la API responde que sí.
- Si se pierde la respuesta, **no se reintenta solo**, porque podría crear la alerta dos veces. Se avisa que el resultado no está confirmado.
- La pantalla no consulta el estado una y otra vez (sin *polling*). Una prueba automática lo comprueba.

---

## Actividad 3 · Probar la integración

### ¿Qué se probó desde la pantalla?

**Fecha:** 24 de noviembre de 2026, en el navegador. **Estado inicial:** base vacía con el script oficial, más la API y la pantalla corriendo en local.

| Prueba | Acción en la pantalla | Esperado | Resultado |
|---|---|---|---|
| RF-01 válido | Crear una alerta con `https://example.com/producto/1` | «Alerta creada» y la alerta guardada en la base | ✅ Número 1; en la base hay 1 alerta, 1 página y 1 correo |
| RF-01 rechazo | Página 2 = `http://localhost/x` | Error solo en la fila 2 y nada guardado | ✅ |
| RF-01 vacío | Pulsar **Guardar** sin datos | Pide al menos una página y un correo | ✅ |
| RF-01 repetida | La misma página escrita de dos formas | Avisa «repite la página 1» y guarda una sola | ✅ |
| Privacidad | Buscar el correo completo | No aparece en la pantalla ni en los registros | ✅ |
| Sin conexión | Apagar la API y enviar | Aviso, sin falso «creada» | ✅ En pruebas automáticas · ⏳ en el navegador |
| RF-02 | «Ver alerta» tras crear la 1001; recargar; luego cambiar a 999999, `abc` y 500 sin recargar | Datos de la API, «no existe», «no es válido» y otra alerta, siempre con un solo formulario | ✅ El 25/11. La primera prueba encontró un formulario repetido al cambiar de número; se corrigió y se agregó una prueba automática |

**Pruebas automáticas de la pantalla:** 49 de 49 pasan.

**Un tropiezo, y fue nuestro.** El primer intento falló porque cargamos la base con el usuario equivocado. Se corrigió siguiendo el script oficial y funcionó. No era un fallo del código.

---

## Actividad 4 · Cerrar la verificación de los RNF

### ¿Cómo quedó la calidad frente a las metas?

| RF / RNF | Calidad (ISO/IEC 25010:2023) | Resultado frente a la meta | Estado |
|---|---|---|---|
| RF-01 / RNF-SEC-01 | Seguridad / integridad: rechazar las direcciones peligrosas | 100 % rechazadas, también desde la pantalla | ✅ Cumple |
| RF-01, RF-02 / RNF-SEC-02 | Seguridad / confidencialidad: correo nunca completo | 0 apariciones en pantalla, API y registros | ✅ Cumple en RF-01 y RF-02 |
| RF-01 / RNF-PERF-01 | Eficiencia / tiempo: crear en ≤ 1 s | Sin medir | ❔ No verificado. Riesgo: si el servicio de programación está caído, unos 19 s |
| RF-02 / RNF-PERF-02 | Eficiencia / tiempo: consultar en ≤ 0,5 s | 20 consultas HTTP con 1.000 alertas: de 3,7 a 7,3 ms | ✅ Cumple (20 de 20) |
| RF-01, RF-02 / RNF-MANT-01 | Mantenibilidad / capacidad para ser probado | Lógica probada sin la base real | ✅ Cumple en RF-01 y RF-02 |

No bajamos ninguna meta para mostrar un éxito: lo que falta queda señalado.

---

## Entrega final y demostración

### ¿Cómo se repite la demostración?

1. **Base.** Levantar PostgreSQL 16 desechable y cargar los dos scripts oficiales, en este orden:
   - `provision-roles.sql`
   - `core/schema.sql`, con el usuario `CORE_SERVICE`.
2. **API.** Levantarla con:

   ```bash
   cd core-service && uv run uvicorn core_service.main:create_app --factory --host 127.0.0.1 --port 8000
   ```

3. **Pantalla.** Levantarla apuntando a la API:

   ```bash
   cd foundit-web-app && VITE_API_BASE_URL=http://127.0.0.1:8000 pnpm exec vite --host 127.0.0.1 --port 5173
   ```

4. **Recorrido.** Abrir `http://127.0.0.1:5173`, pulsar **Ir al board** y seguir las pruebas de la actividad 3.

### Guion de demostración

1. **El orden de los RF:** RF-01 va primero porque RF-02 necesita una alerta creada.
2. **Crear una alerta** desde la pantalla y comprobar en la base que quedó guardada.
3. **Mostrar un rechazo:** una página que apunta a `localhost`.
4. **Mostrar cada capa en el código:**

   | Capa | Archivo |
   |---|---|
   | Pantalla | `create-alert-page.tsx` |
   | Endpoint | `api/routes.py` |
   | Servicio | `service.py` |
   | Repositorio | `adapters/sql_repository.py` |

5. **Explicar un resultado de calidad:** el correo nunca aparece completo (RNF-SEC-02), con su evidencia.

### Limitaciones

- La velocidad de crear una alerta (RNF-PERF-01) sigue sin medir.
- No se midió la velocidad de ninguno de los dos RF.
- No hay pruebas automáticas de punta a punta en el navegador: la herramienta está por definir.
- La pantalla no se probó con un lector de pantalla.

---

## Checklist final

| Criterio | Cumple |
|---|---|
| Ambos RF conservan alcance, prioridad e identificadores | ✅ |
| La interfaz ejecuta ambos RF con la API real | ✅ |
| Los contratos coinciden con lo observado | ✅ RF-01 |
| Éxito, rechazo o ausencia de ambos RF | ✅ |
| Persistencia real, sin resultados simulados | ✅ |
| Errores de entrada y de conexión comprensibles | ✅ |
| Reglas en el servicio y datos en el repositorio | ✅ |
| Trazabilidad RF–RNF–prueba–evidencia | ✅ |
| Calidad comparada con las metas | ⚠️ Todo menos RNF-PERF-01 |
| Incumplimientos y limitaciones identificados | ✅ |
| Otra persona puede repetir la demostración | ✅ |

## Cierre

Los dos RF recorren todas las capas desde la pantalla y dejan resultados que se pueden comprobar en la base. Su seguridad, la velocidad de la consulta y la facilidad de prueba están verificadas. Para cerrar el prototipo solo falta medir la velocidad de crear una alerta (RNF-PERF-01).
