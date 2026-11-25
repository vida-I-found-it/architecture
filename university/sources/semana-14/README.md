# Semana 14 · Lógica de negocio y API del corte vertical

> Guía original: [`guia_ArqSisI_Sem14_2026_2.pdf`](../guia_ArqSisI_Sem14_2026_2.pdf) · Arquitectura de Sistemas I · Prof. Elias Buitrago Bolivar · Octubre de 2026.
> Respuestas del equipo: [`university/docs/semana-14`](../../docs/semana-14/README.md).

## Propósito

Implementar los **dos RF priorizados** mediante servicios y API, verificar sus reglas y los RNF previstos, y dejar contratos y evidencias listos para la integración de la semana 15. Es la segunda semana del prototipo.

**Flujo del backend:** API → servicio de aplicación → repositorio → base de datos. Las reglas van en el servicio o el dominio; las consultas, en persistencia. El servicio debe poder probarse sin la pantalla ni detalles HTTP.

## Qué pide la guía

1. **Antes de programar.** Abrir la matriz de la semana 13, repetir la prueba de lectura y escritura con una base conocida, identificar los métodos que necesita cada RF y acordar quién implementa, prueba y revisa.
2. **Actividad 1 · Implementar los servicios.** Por cada RF: servicio, entrada, reglas o condiciones, métodos de repositorio, resultado válido y rechazo esperado. Documentar quién administra la transacción y cómo se liberan conexiones. Una respuesta de creación exitosa se envía después de confirmar la escritura. Un conflicto de unicidad se traduce a un rechazo controlado.
3. **Actividad 2 · Documentar y exponer ambos contratos.** Por endpoint: RF, método, ruta, entrada, respuesta exitosa, errores y servicio invocado. Los errores esperados deben distinguirse de un fallo interno, que se registra en el servidor sin exponer detalles.
4. **Actividad 3 · Probar los dos RF.** Por RF, un resultado válido y un rechazo, ausencia o condición límite. Registrar estado inicial y resultado esperado. La consulta debe atravesar API, servicio y repositorio.
5. **Actividad 4 · Verificar los RNF previstos.** Mantener la trazabilidad RF → RNF → característica ISO → prueba → resultado → evidencia, con estado verificado, no cumple o pendiente. No rebajar un umbral para declarar éxito.

## Entregables

| Elemento | Contenido mínimo |
|---|---|
| Dos RF | Identificadores, prioridad, servicios y reglas o condiciones |
| Contratos | Método, ruta, entrada, éxito y errores por endpoint, con ejemplos que coincidan con el backend |
| Pruebas funcionales | Estado inicial, pasos, resultado esperado y obtenido para ambos RF |
| RNF y evidencias | Atributo ISO, escenario, medida, umbral, resultado y enlace a la prueba |
| Ejecución | Requisitos, comandos, variables de ejemplo, URL base, puertos y reinicio de datos |
| Relevo a interfaz | Contratos, datos disponibles, RNF pendientes y origen local para CORS |

## Checklist

- Los dos RF mantienen la prioridad y el alcance de la semana 13.
- Ambos RF tienen servicios y endpoints identificables.
- Los contratos describen éxito, entrada inválida y errores pertinentes.
- Hay resultado válido y rechazo o ausencia probado para cada RF.
- Se verifica persistencia real y ausencia de escrituras indebidas.
- El SQL queda en persistencia y las reglas en servicio o dominio.
- Cada RF se vincula con sus RNF y atributos ISO/IEC 25010.
- Los RNF previstos tienen medidas observadas y evidencias.
- Se distinguen incumplimientos y pendientes de la semana 15.
- El README permite ejecutar y repetir las pruebas.

## Referencias

- ISO/IEC 25010:2023, *Product quality model*: https://www.iso.org/standard/78176.html
- Fowler, M. (2002). *Patterns of Enterprise Application Architecture*. Addison-Wesley.
