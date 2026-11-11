# Informe · Inventario y validación de `_docs`

> **Solo lectura:** este informe no modificó ningún documento. Fecha: 2026-11-10. Alcance de la revisión: los 27 archivos Markdown y los esquemas SQL de `_docs/`. Las decisiones sobre qué corregir quedan para la fase siguiente.

## 1 · Inventario

**Alcance:** *Ejercicio* = la versión de CU-02..CU-08, CU-10, CU-11 · *Proyecto* = el diseño completo (incluye sesión, administración y despliegue).
**Estado propuesto:** *Vigente* · *Referencia* (se consulta, no se edita en el ejercicio) · *Borrador* · *Por revisar*.

| Documento | Líneas | Categoría | Alcance | Estado | Observación |
|-----------|-------:|-----------|---------|--------|-------------|
| `00-context/vision-goals.md` | 231 | Contexto | Proyecto | Vigente | Trae el glosario (candidato a arc42 §12) |
| `00-context/deliverable01.md` | 547 | Entregable | Ejercicio | Vigente | Entrega académica; sección 6 tiene R1..R13 |
| `00-context/legal-considerations.md` | 48 | Contexto | Proyecto | Por revisar | `pending.md` (D21) dice que no menciona Habeas Data |
| `00-context/pending.md` | 119 | Gestión | Proyecto | Vigente | El ejercicio cita D7, D12, D16, D21 |
| `00-context/roadmap.md` | 67 | Gestión | Proyecto | Por revisar | No cubre la versión del ejercicio |
| `00-context/scope-1-questions.md` | 179 | Contexto | Proyecto | Por revisar | Estado «Sección B en curso (falta B6)» |
| `requirements/requirements.md` | 451 | Requisitos | Ejercicio | Vigente | Fuente de verdad de la versión |
| `requirements/original-requirements.md` | 316 | Requisitos | Proyecto | Referencia | Base de los IDs |
| `requirements/user-stories/CU-02.md` | 162 | Historias | Ejercicio | Borrador | 5 historias, 24 criterios, 8 preguntas abiertas |
| `architecture/architecture.md` | 150 | Arquitectura | Ejercicio | Vigente | Solapa con `general-architecture.md` |
| `architecture/general-architecture.md` | 489 | Arquitectura | Proyecto | Referencia | C4 niveles 1-3, despliegue, concerns |
| `architecture/scraping-flow.md` | 149 | Arquitectura | Proyecto | Referencia | Repite la cascada de extracción |
| `architecture/adr/0001-…` | 66 | ADR | Proyecto | Vigente | Aceptada |
| `architecture/adr/0003-…` | 49 | ADR | Proyecto | Referencia | Trata de `auth`, fuera del ejercicio |
| `data/data-model.md` | 662 | Datos | Proyecto | Referencia | La sección A (`auth`) está fuera del ejercicio |
| `data/db/**` (SQL y Mongo) | — | Datos | Proyecto | Referencia | Ver hallazgos H2 y H4 |
| `tools/tech-stack.md` | 192 | Herramientas | Proyecto | Por revisar | Desfasado frente a `origin/main` (H3) |
| `testing/strategy.md` | 30 | Pruebas | Ejercicio | Borrador | |
| `testing/test-cases/CU-02.md` | 293 | Pruebas | Ejercicio | Borrador | 24 casos, todos «Sin implementar» |
| `testing/traceability.md` | 41 | Pruebas | Ejercicio | Borrador | Solo CU-02 |
| `templates/*` (3) | 28-44 | Plantillas | — | Vigente | |
| `api/`, `guides/` | 3 c/u | Marcadores | — | Pendiente | Solo un README |

## 2 · Lo que está bien (verificado)

| Chequeo | Resultado |
|---------|-----------|
| IDs de `requirements.md`, entregable, arquitectura, historias y pruebas frente al original | **0 IDs inexistentes** |
| Los 12 endpoints en `architecture.md`, `requirements.md` y `deliverable01.md` | **Mismo conjunto de 12** en los tres |
| Criterios de CU-02 frente a casos de prueba | **24 criterios · 24 casos · 0 sin caso** |
| Requerimientos que entran, frente a su prioridad en el original | 22 son P0 y 21 son P1; **ninguno P2 ni P3** |
| Nombres de requerimientos citados en R1..R13 | 25 de 26 coinciden; el que falta es *Trazabilidad de la corrida* (INF-5), que vive en la tabla de transversales, no en una de caso de uso |
| Términos retirados («desplome», «WCAG») | No quedan |
| Enlaces relativos | 258 revisados; 5 sin resolver (4 ya rotos en el original, 1 es el ejemplo dentro de una plantilla) |
| Modelo de datos de `core` frente a su SQL | **Coincide** (única diferencia: `currency` está en el SQL y no en el diagrama; el texto del modelo la explica) |

## 3 · Hallazgos

### Altos

| # | Hallazgo | Evidencia | Propuesta |
|---|----------|-----------|-----------|
| H1 | **Dos numeraciones de «decisión» que se confunden.** `requirements.md` numera sus decisiones 1..23 y cita además `D7`, `D12`, `D16`, `D21` de `pending.md`. «Decisión 12» y «D12», o «decisión 13» y «D13», nombran cosas distintas | `requirements.md` §5; `pending.md` líneas 64-78 | Prefijo propio para las decisiones del ejercicio (p. ej. `DEC-12`) y mantener `D*` solo para `pending.md` |
| H2 | **`auth/schema.sql` no refleja el modelo.** Faltan las tablas `user_system_role` y `anonymization_event`, y columnas como `system_code`, `parent_id` y `must_change_password`; sobran `role_id`, `gender` e `is_revoked` | Comparación del diagrama de la sección A con el SQL | Fuera del ejercicio (sin login), pero es referencia. Decidir si se actualiza el SQL o se marca como obsoleto |
| H3 | **`origin/main` tiene cambios que `_docs` no tiene.** El PR #2 añade 162 líneas a `04-stack-tecnologico.md`, agentes nuevos y cambios en `CLAUDE.md`. `tools/tech-stack.md` es la versión anterior | `git log HEAD..origin/main` | Integrar `origin/main` antes de seguir (sigue pendiente tu decisión) y volver a copiar ese documento |

### Medios

| # | Hallazgo | Evidencia | Propuesta |
|---|----------|-----------|-----------|
| H4 | **Desfase modelo ↔ SQL en `schedule` y `notify`.** El diagrama pone `created_at`/`updated_at` en `execution_type`, `channel` y `template`, y `updated_at` en `notification`; el SQL no los tiene. El principio de timestamps dice que los catálogos inmutables no los llevan, pero `channel` tiene `is_active` (mutable) | Comparación diagrama ↔ SQL; `data-model.md` línea 42 | Decidir qué es correcto y alinear el otro |
| H5 | **Numeración «doc NN» obsoleta.** Unas 120 menciones («doc 02», «doc 09»…) y los títulos conservan el prefijo (`# 02 · Arquitectura`), pero los archivos ya no se llaman así | `pending.md` (22), `original-requirements.md` (27), `general-architecture.md` (17)… | Quitar el número de los títulos o dejar una tabla de equivalencias en el README |
| H6 | **Solapamiento y alcances sin etiquetar.** `architecture.md` y `general-architecture.md` repiten «Comunicación entre piezas»; `scraping-flow.md` repite la cascada. Ningún documento declara su alcance | Estructura de secciones | Cabecera con alcance y estado (fase 5) y enlazar en vez de repetir |
| H7 | **Texto visible con ruta antigua.** `requirements.md` línea 3 muestra `docs/deliverables/requerimientos.md` aunque el enlace ya apunta bien | `requirements.md:3` | Cambiar el texto visible |
| H8 | **Falta el ADR 0002.** Hay 0001 y 0003, sin 0002 | `architecture/adr/` | Confirmar si existió y se descartó, o dejar una nota |
| H9 | **Estados posiblemente obsoletos.** `scope-1-questions.md` dice «Sección B en curso (falta B6)»; `legal-considerations.md` no cubre Habeas Data (RNF-7, D21) | Cabeceras de ambos | Revisarlos contigo y archivar o actualizar |

### Bajos (ya conocidos)

- **Rango «SCH-4..9»** en la sección 4 de `requirements.md`: incluye SCH-6 y SCH-7, que sí entran.
- **IDs sin mención** en `requirements.md`: INF-6, RNF-2, RNF-3, RNF-5 y SCH-10.
- **SCH-3** marcado «Funcionalidad» aunque podría ser regla; R2 no lo cita.
- **4 enlaces rotos** en `data-model.md` a `seed-default.sql` y `register-system.sql`, que no existen.
- **8 preguntas abiertas** de CU-02 (largos máximos, normalización de URL, formato del enmascarado, respuesta de `POST /api/alerts`…).

## 4 · Lo que no se revisó

- Los diagramas ER de la sección 8 del entregable frente a los SQL.
- El texto de cada requerimiento de la versión frente al texto del original (solo se verificaron IDs, nombres y prioridades).
- Los mockups y los diagramas Mermaid (que rendericen).
- Los esquemas de MongoDB (`mongo-setup.js`) frente al modelo.

## 5 · Decisiones que necesito de ti

1. **H3:** ¿integramos `origin/main` ahora (merge, con tu aprobación del commit)?
2. **H1:** ¿adoptamos el prefijo `DEC-` para las decisiones del ejercicio?
3. **H5:** ¿quitamos los números de los títulos o dejamos la tabla de equivalencias?
4. **H2 y H4:** ¿corregimos los SQL, el modelo, o solo los marcamos como desfasados?
5. **H6 y H9:** ¿qué documentos del proyecto se archivan o se dejan solo como referencia?
