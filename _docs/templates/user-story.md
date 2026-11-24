# Plantilla · Historia de usuario

> Copiar a `requirements/user-stories/CU-NN.md` (un archivo por caso de uso) y repetir el bloque «Historia» por cada una. IDs según el [README](../README.md#cadena-de-trazabilidad).

```markdown
# CU-NN · Nombre del caso de uso

**Descripción:** una frase, tomada de [`requirements.md`](../requirements.md).
**Actor:** quién la ejecuta (usuario, sistema, pieza).
**Requerimientos cubiertos:** IDs.  **Reglas:** Rn.

## US-NN-MM · Título corto

**Como** <actor>, **quiero** <acción>, **para** <beneficio>.

| Campo | Valor |
|-------|-------|
| Requerimientos | ALE-2, … |
| Reglas | R3, … |
| Capa | 🖥️ backend · 🎨 frontend |
| Endpoint | `POST /api/…` o — |

### Criterios de aceptación

| ID | Dado | Cuando | Entonces |
|----|------|--------|----------|
| US-NN-MM-AC1 | contexto inicial | acción | resultado verificable |

### Casos borde
- vacío, duplicado, unicode, valores enormes, errores de red (los que apliquen).

### Fuera de alcance
- lo que **no** cubre esta historia.

### Preguntas abiertas
- lo que el documento no define; **no se inventa**, se pregunta.
```

## Reglas de redacción

- Un criterio = **una** verificación, con valores concretos (números, códigos, rutas), no adjetivos («rápido», «seguro»).
- Cada criterio tendrá **un** caso de prueba (`TC-NN-MM`) que lo cubre.
- Si el requerimiento no define un dato (umbral, formato, código), va a **Preguntas abiertas**, no al criterio.
- Los criterios no contradicen las reglas Rn; si lo hacen, se señala.
