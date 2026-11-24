# Plantilla · Caso de prueba

> Copiar a `testing/test-cases/CU-NN.md` (un archivo por caso de uso). **Un caso de prueba por criterio de aceptación.**

```markdown
### TC-NN-MM · Título

| Campo | Valor |
|-------|-------|
| Criterio | US-NN-MM-ACk |
| Nivel | unitaria · integración · E2E |
| Dónde | pieza o pantalla (`core`, `frontend`, …) |
| Estado | Sin implementar · Escrito · Automatizado · Verde |

**Precondiciones:** estado inicial (datos sembrados, configuración).
**Datos de prueba:** entradas concretas.
**Pasos:**
1. …
**Resultado esperado:** salida y efectos verificables (respuesta, filas, logs).
**Notas:** bordes, entorno (contenedor desechable), fixtures.
```

## Reglas

- Pruebas contra bases de datos, SMTP o navegadores: **contenedores desechables** con la misma versión que el entorno objetivo (ver [estrategia](../testing/strategy.md)).
- Sin red real: **fixtures** locales; ningún scraping a sitios de terceros.
- Credenciales y correos **de prueba**, nunca reales.
- Un test en rojo no se arregla cambiando el test para que coincida con el bug.
