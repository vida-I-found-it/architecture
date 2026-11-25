# Semana 13 · Base de datos y persistencia del corte vertical

> Guía original: [`guia_ArqSisI_Sem13_2026-2.pdf`](../guia_ArqSisI_Sem13_2026-2.pdf) · Arquitectura de Sistemas I · Prof. Elias Buitrago Bolivar · Octubre de 2026.
> Respuestas del equipo: [`university/docs/semana-13`](../../docs/semana-13/README.md).

## Propósito

Priorizar **dos requerimientos funcionales (RF)**, vincular sus requerimientos de calidad (**RNF**) con **ISO/IEC 25010:2023** y preparar los datos y la persistencia que permitirán implementarlos. Es la primera de tres semanas del prototipo:

| Semana del prototipo | Semana del curso | Trabajo | Evidencia |
|---|---|---|---|
| 1 | 13 | Priorización, calidad, datos y persistencia | Matriz RF–RNF, base mínima, datos y prueba de lectura y escritura |
| 2 | 14 | Negocio y API de los dos RF | Servicios, reglas, contratos y pruebas |
| 3 | 15 | Interfaz e integración de los dos RF | Flujo completo y evidencias funcionales y de calidad |

## Qué pide la guía

1. **Actividad 1 · Confirmar y priorizar los dos RF.** Para cada RF: identificador, actor, acción y resultado observable. Prioridad 1 y 2 justificadas con valor para el actor, relevancia arquitectónica, esfuerzo, riesgo y dependencias. Declarar en una frase qué queda fuera.
2. **Actividad 2 · Vincular RNF y calidad verificable.** Cada RF con al menos un RNF. Cada RNF con: identificador y RF asociado, característica y subcaracterística ISO/IEC 25010:2023, condición de prueba, resultado medible, umbral y evidencia. Si ya existe un escenario de calidad, referenciarlo en lugar de duplicarlo. Una regla de negocio no se convierte en RNF solo por llamarla «seguridad».
3. **Actividad 3 · Preparar y probar la persistencia.**
   - Datos mínimos: entidades, claves, relaciones y campos obligatorios para los dos RF.
   - Base reproducible: esquema o migraciones y una carga de prueba con estado inicial conocido.
   - Acceso separado: repositorio, DAO o equivalente, con entradas y resultados definidos.
   - Prueba real: guardar y recuperar desde otra conexión, probar un identificador inexistente y una restricción de integridad.
   - Separación: el repositorio consulta y guarda; las reglas van en el servicio; la pantalla y los endpoints no contienen SQL. Definir quién confirma o revierte la transacción y cómo se liberan las conexiones.

## Entregables

- Matriz breve RF–RNF.
- Código de persistencia.
- Scripts o migraciones con datos de prueba.
- README que permita repetir la verificación: comandos, versiones, configuración de ejemplo sin credenciales reales, estado inicial, resultados esperados y ubicación de las evidencias.

## Criterios de revisión

- Hay dos RF identificados, priorizados y justificados.
- Cada RF se vincula con sus RNF e ISO/IEC 25010.
- Los RNF incluyen condición, medida, umbral y verificación.
- Los datos y operaciones cubren ambos RF.
- La base y los datos de prueba pueden recrearse.
- Se demuestra lectura, escritura y persistencia real.
- El README indica requisitos y pasos exactos de prueba.
- Se distingue lo probado de lo pendiente para las semanas 2 y 3.

## Referencia

ISO/IEC 25010:2023, *Product quality model*: https://www.iso.org/standard/78176.html
