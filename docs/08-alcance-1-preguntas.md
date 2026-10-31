# 08 · Preguntas para definir el Alcance 1 (MVP)

> Objetivo: acotar qué construimos **primero** para tener algo funcional de punta a punta. Responde lo que puedas; donde no, usamos la recomendación (💡) como default.

> **Estado:** ✅ Sección A decidida · 🔄 Sección B en curso (falta B6). Ver "Decisiones" al pie de cada bloque.

## Tabla de contenido

- [A. Alcance funcional — ¿qué entra en la Fase 1?](#a-alcance-funcional--qué-entra-en-la-fase-1)
- [B. Scraping inteligente (el corazón técnico)](#b-scraping-inteligente-el-corazón-técnico)
- [C. Descubrimiento con IA (Modo B)](#c-descubrimiento-con-ia-modo-b)
- [D. Autenticación y usuarios](#d-autenticación-y-usuarios)
- [E. Datos y precios](#e-datos-y-precios)
- [F. Notificaciones por email](#f-notificaciones-por-email)
- [G. Frontend (React PWA)](#g-frontend-react-pwa)
- [H. Infraestructura y despliegue](#h-infraestructura-y-despliegue)
- [I. No funcionales / límites](#i-no-funcionales--límites)
- [🎯 Alcance 1 — cerrado](#alcance-1--cerrado)
- [Alcance de la Fase 1 (revisado y confirmado)](#alcance-de-la-fase-1-revisado-y-confirmado)
  - [Correcciones aplicadas sobre la propuesta original](#correcciones-aplicadas-sobre-la-propuesta-original)

## A. Alcance funcional — ¿qué entra en la Fase 1?

1. ¿El MVP incluye **los dos modos** (URL directa **y** tema con IA), o arrancamos solo con **URL directa** y el modo IA entra en Fase 2?
   💡 *Recomiendo empezar con URL directa (más simple y determinista) y sumar IA enseguida después.*
2. De los módulos, ¿cuáles son **imprescindibles** en Fase 1? Marca:
   - [ ] Crear alerta · [ ] Consultar alerta · [ ] Suscribirse · [ ] Comparar precios en el tiempo · [ ] Estadísticas · [ ] Editar perfil · [ ] Gestionar usuarios (admin)
   💡 *Mínimo viable: Crear alerta + Consultar + Suscribirse + Gestionar usuarios + login.*
3. ¿La ejecución diaria puede ser **manual/semiautomática** en Fase 1 (un botón "correr ahora") y dejamos el scheduler 100% automático para después?

> **✅ Decisiones sección A:**
> - **A1** → Solo **URL directa** en Fase 1; modo IA en Fase 2.
> - **A2** → Módulos MVP: Crear alerta · Consultar · Suscribirse · Gestionar usuarios · Login.
> - **A3** → Ejecución **automática, al menos 2 veces al día** (necesita scheduler real en Fase 1, no solo botón manual). Se puede sumar un "correr ahora" como extra.

## B. Scraping inteligente (el corazón técnico)

4. Para el scraping **genérico sin importar el producto**, ¿aceptamos que en Fase 1 use **heurísticas + datos estructurados** (JSON-LD / schema.org `Product/Offer`, meta `og:price`) y caigamos a IA solo cuando falle?
   💡 *Muchísimos e-commerce exponen precio en JSON-LD; esto da un extractor genérico robusto sin scrapers por sitio.*
5. ¿Cuántos **sitios/URLs por alerta** debemos soportar en Fase 1? (1, hasta 5, hasta 10…)
6. ¿Qué hacemos si una página necesita **navegador headless** (JS)? ¿Lo incluimos en Fase 1 (Playwright) o solo HTTP simple primero?

> **🔄 Decisiones sección B:**
> - **B4** → ✅ Scraping genérico vía **JSON-LD/schema.org + og:price**, fallback a IA.
> - **B5** → ✅ Soportar **>10 sitios por alerta** (empezar por los más representativos). Refuerza usar HTTP-first por costo.
> - **B6** → ✅ **HTTP-first + Playwright como fallback** (instalado pero no por defecto).
> - **Nota transversal** → El scraping son **procesos en background**, que pueden **escalonarse a horas distintas** para no sobrecargar la máquina. Arquitectura **modular** con **revisión de opciones y costos** como requisito de diseño.

## C. Descubrimiento con IA (Modo B)

7. ¿Prefieres una **API gratuita alojada** (OpenRouter/Groq con modelos free) o un enfoque **búsqueda web + LLM** (más control, más piezas)?
8. El descubrimiento, ¿corre **una vez al crear el tema** y luego se **re-descubre cada N días**, o **cada día**?
   💡 *Descubrir al alta + refrescar cada 7 días equilibra costo y frescura.*
9. ¿Cuántos **links** debe devolver como máximo por tema? (ej. top 5–10)

> **✅ Decisiones sección C:**
> - **C7** → Proveedor de IA: **Google Gemini** (free tier). Para links reales, combinar con búsqueda/grounding para evitar URLs alucinadas.
> - **C8** → ⏳ Recomendado **Opción B**: descubrir al crear la alerta + **refrescar cada 7 días**. El scraping de precios sigue siendo diario/2×día sobre los links ya conocidos.
> - **C9** → **10–15 links** iniciales por producto/tema/servicio.

## D. Autenticación y usuarios

10. ¿El **administrador** se crea por **seed inicial** (config/migración) en Fase 1? (No hay quién lo registre si no.)
11. ¿Qué datos mínimos guarda un **usuario**? (nombre, email, contraseña…) ¿Algo más?
12. ¿"Recuperar contraseña" en Fase 1 debe ser **real** (email con enlace) o basta con reseteo por el admin?
13. ¿Sesión con **JWT** o cookie de sesión? 💡 *JWT encaja bien con React PWA + API.*

> **✅ Decisiones sección D:**
> - **D10** → **Admin sembrado** por seed inicial.
> - **D11** → Datos de usuario: **Nombres, Apellidos, Fecha de nacimiento, Género, Correo electrónico, Teléfono (opcional)** + contraseña (hash).
> - **D12** → **Recuperar contraseña real por email**, con **código de 6 dígitos**. Reglas del flujo:
>   - Se envía notificación al correo con el código de 6 dígitos.
>   - Si se pide otro reset y **no han pasado 15 min** desde el anterior, el sistema responde que debe **esperar hasta cierta hora** (throttling anti-abuso).
>   - **FU-3 ✅** El código de 6 dígitos **expira a los 15 min**.
> - **D13** → **JWT**.

## E. Datos y precios

14. Multi-moneda COP/USD: ¿guardamos el precio **tal cual** con su moneda (sin convertir), o necesitamos **conversión** a una moneda base para comparar? 💡 *Guardar tal cual en Fase 1; conversión después.*
15. ¿Qué campos mínimos capturamos por snapshot? (precio, precio_lista, stock, título, moneda, timestamp) ¿Falta alguno clave (envío, vendedor)?
16. ¿Cuánto **historial** queremos conservar? (afecta retención; para "mes y año" bastaría 12+ meses).

> **✅ Decisiones sección E:**
> - **E14** → Guardar el precio en su **moneda original**. Si el sitio **no** está en COP (ej. USD), guardar **también** el valor **convertido a COP** (dos valores).
>   - **FU-1 ✅** Fuente de tasa de cambio vía **API externa**, consultada ~1×/día. Guardar la **tasa usada + su fecha** junto al snapshot (histórico reproducible). El proveedor debe estar **parametrizado/desacoplado** para cambiarlo fácilmente mañana por otro.
> - **E15** → Campos por captura: **precio, stock, moneda, título** + **descripción útil** si está disponible (ej. envío, vendedor, condición).
> - **E16** → Conservar **~12–18 meses**; más allá, la info pierde valor. Política de retención/purga a revisar en otra fase.

## F. Notificaciones por email

17. ¿Cómo enviamos email en Fase 1: **SMTP propio** (Gmail app-password), o un servicio (Resend/SendGrid free tier)? 💡 *Resend/SendGrid free simplifica entregabilidad.*
18. ¿Frecuencia del email: **inmediato** al detectar novedad, **resumen diario**, o ambos configurables?
19. ¿Una plantilla única, o distinta por tipo de novedad (bajada / mínimo histórico / vuelve a stock)?

> **✅ Decisiones sección F:**
> - **F17** → **SMTP propio** en Fase 1 para bajar costos. Resend/SendGrid a explorar después.
> - **F18** → El email se envía cuando el sistema, tras el scraping, **detecta un bajón de precio que amerita comprar**. La decisión la toma una **tarea background** que analiza los datos scrapeados.
>   - **FU-2 ✅ Estrategia "mejor precio móvil" (running minimum):**
>     - Se mantiene por producto un **"mejor precio"** = mínimo observado desde que se sigue.
>     - **Día 1:** el precio inicial es la referencia (best), **sin notificar**.
>     - **Cada día siguiente:** si `precio_hoy < best` → **notificar** y `best = precio_hoy`. Si `precio_hoy ≥ best` → **no notificar**.
>     - Así sucesivamente: solo se notifica cuando se rompe el mínimo, y ese nuevo mínimo pasa a ser el punto de comparación.
>     - **Diseño abierto (patrón Strategy):** el algoritmo debe ser **reemplazable** por uno más óptimo en fases futuras sin tocar el resto del sistema.
> - **F19** → **Plantilla única** de novedades; solo cambia la info del producto (imágenes, links, precio, etc.).

## G. Frontend (React PWA)

20. ¿Confirmas **React + Vite + TypeScript**? ¿Librería de componentes preferida (shadcn/ui, MUI, Mantine)? 💡 *Vite + TS + shadcn/ui = moderno, ligero y rápido.*
21. ¿PWA "instalable" (offline básico, ícono) **desde Fase 1** o lo dejamos listo pero lo pulimos después?
22. ¿Idioma de la interfaz: **español** únicamente en Fase 1?

> **✅ Decisiones sección G:**
> - **G20** → **React + Vite + TypeScript + shadcn/ui**.
> - **G21** → **PWA instalable de forma progresiva** en próximas fases (no bloqueante en Fase 1).
> - **G22** → **Español** en Fase 1, pero **dejar el andamiaje i18n listo** para inglés en fases futuras.

## H. Infraestructura y despliegue

23. ¿Dónde va a correr? (tu máquina/local con Docker, un VPS, o algún free tier cloud). 💡 *Docker Compose local para Fase 1.*
24. ¿Base de datos **PostgreSQL** confirmada?
25. ¿Necesitamos que el scheduler diario funcione **sin que tu PC esté encendida** desde Fase 1? (define si hace falta un servidor ya).

> **✅ Decisiones sección H:**
> - **H23** → **Docker local** para desarrollar, pero **todo debe ser portable a la nube** (Oracle Cloud o GCP). Sin lock-in: contenedores + config por entorno (12-factor).
> - **H24** → **PostgreSQL** confirmado — se aprovecha **JSONB** para trabajar objetos JSON de forma profesional.
> - **H25** → Debe correr **sin la PC encendida** y **sin costo** → **free tier** (Oracle Cloud como principal candidato, GCP alterno).

## I. No funcionales / límites

26. ¿Volumen esperado en Fase 1? (nº de alertas, nº de suscriptores, nº de sitios) — ya estimamos 10–50 alertas.
27. ¿Algún requisito de **privacidad** de los emails de suscriptores a tener en cuenta?
28. Rate limiting / respeto a robots.txt: ¿confirmamos la política conservadora del [doc 07](07-consideraciones-legales.md)?

> **✅ Decisiones sección I:**
> - **I26** → Se espera **crecimiento (potencialmente exponencial)** del volumen. Diseñar para escalar con **costo nulo o mínimo**: cola de trabajos + workers escalonados, batching, caché, aprovechar free tiers. Evaluar límites en cada fase.
> - **I27** → El **contenido del email es privado por suscriptor**. Guardar el **log de notificaciones enviadas en una base NoSQL** (seguimiento). Futuro: **módulo "notificaciones enviadas al suscriptor X"** (próxima fase). No exponer emails en UI pública; permitir baja.
> - **I28** → ✅ Se confirma la **política conservadora** de robots.txt + rate limiting del [doc 07](07-consideraciones-legales.md).

---

## 🎯 Alcance 1 — cerrado

Todas las secciones (A–I) y follow-ups quedaron decididos. Implicaciones de arquitectura que se derivan y que hay que reflejar en los docs 02–07:

- **Cola de trabajos + workers background escalonados** (no scraping dentro del request web).
- **Persistencia políglota:** PostgreSQL (relacional + JSONB) **+** NoSQL (log de notificaciones).
- **Módulos desacoplados y reemplazables:** proveedor de tasa de cambio, estrategia de "mejor precio", proveedor de IA — todos detrás de una interfaz.
- **Contenedores portables a la nube** (Oracle/GCP free tier), config por entorno.
- **Extractor genérico** (JSON-LD/schema.org) con fallback HTTP→Playwright→IA.

---

## Alcance de la Fase 1 (revisado y confirmado)

> Un "vertical slice" funcional de punta a punta. El desglose accionable está en **[requerimientos.md](deliverables/requerimientos.md)**.

- **Auth:**
  - Login con JWT.
  - **Admin sembrado** (seed inicial): cuenta de administrador creada al instalar, con credenciales desde variables de entorno. Resuelve el "quién crea al primer admin".
  - **Módulo de gestión de usuarios accesible SOLO por el admin** (registro y administración de cuentas se hace desde un módulo con formularios en el sistema).
  - **Reset de contraseña por email con código de 6 dígitos** (en Fase 1, no diferido): código válido 15 min + throttle de 15 min.
- **Alertas modo URL directa** (IA en Fase 2).
- **Scraping genérico** vía JSON-LD/schema.org + `og:price`; **HTTP-first, Playwright como fallback**.
- **Ejecución 100% background, SIN botón manual.**
  - **Modelo de datos de programación por alerta**: define cuándo debe lanzarse el schedule de cada alerta.
  - **Editable por el admin** desde el sistema mediante **formularios / wizard**.
- **Suscripción** a alertas + **email de novedad** cuando se rompe el "mejor precio móvil" (SMTP propio; plantilla única).
- **Consultar alertas** (todas, lectura; editar solo las propias) e **histórico de precios** básico (línea de tiempo por sitio) + conversión USD→COP.
- **Frontend React + Vite + TS + shadcn/ui**, en español, con **andamiaje i18n** (PWA instalable → progresiva en fases futuras).
- **PostgreSQL (+ JSONB) + NoSQL (log de notif.) + Docker Compose** local, portable a la nube.

### Correcciones aplicadas sobre la propuesta original
| Antes | Ahora |
|-------|-------|
| Reset de contraseña por admin (email en Fase 2) | **Reset por email + código de 6 dígitos en Fase 1** |
| Registro "por admin" (implícito) | **Módulo dedicado de gestión de usuarios, solo-admin, con formularios** |
| Scheduler + **botón "correr ahora"** | **100% background, sin botón**; programación por alerta editable por admin (wizard) |
| Email vía SMTP **o Resend** | **SMTP propio** en Fase 1 |
| PWA instalable básica en Fase 1 | PWA **progresiva** en fases futuras |
