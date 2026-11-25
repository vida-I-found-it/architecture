# Semana 15 · Interfaz e integración del corte vertical

> Guía original: [`guia_ArqSisI_Sem15_2026_2.pdf`](../guia_ArqSisI_Sem15_2026_2.pdf) · Arquitectura de Sistemas I · Prof. Elias Buitrago Bolivar · Octubre de 2026.
> Respuestas del equipo: [`university/docs/semana-15`](../../docs/semana-15/README.md).

## Propósito

Integrar los **dos RF priorizados** en una interfaz mínima, demostrar su recorrido completo con datos reales y consolidar las evidencias de sus RNF asociados a ISO/IEC 25010. Es la tercera y última semana del prototipo.

**Recorrido que se debe demostrar:** interfaz → API → servicio → repositorio → base de datos. La consulta del segundo RF debe llegar a la API y recuperar el registro persistido; repetir en pantalla lo que devolvió la creación no lo demuestra.

## Qué pide la guía

1. **Antes de construir la interfaz.** Probar los endpoints con el cliente HTTP de la semana 14, recuperar los contratos reales, revisar datos iniciales, URL, puertos y CORS, y abrir la matriz RF–RNF.
2. **Actividad 1 · Diseñar la interacción.** Por RF: campos, acción, resultado visible y corrección ante errores. Etiquetas visibles, uso con teclado, mensajes que no dependan solo del color y entradas que se conservan tras un rechazo.
3. **Actividad 2 · Conectar cada acción con su contrato.** Estados inicial, en curso, resultado y error. Confirmar éxito solo con la respuesta esperada. Distinguir un rechazo de negocio de un fallo de comunicación. Si se pierde la respuesta de una escritura, no afirmar que no se guardó ni repetirla automáticamente.
4. **Actividad 3 · Probar la integración.** Escenarios desde la pantalla: válido, rechazo, ausencia, entrada inválida y backend detenido. Registrar por escenario RF, estado inicial, entrada, esperado, obtenido y evidencia.
5. **Actividad 4 · Cerrar la verificación de los RNF.** Misma matriz, sin RNF nuevos por haber hecho la interfaz. Estado cumple, no cumple o no verificado, con medida y motivo. Las pruebas de carga solo si un RNF las exige.

## Entrega final

- Código integrado, scripts o migraciones, datos de prueba, contratos vigentes, pruebas, matriz RF–RNF y README.
- **README mínimo:** integrantes, dos RF y prioridades, RNF asociados, requisitos y versiones, configuración de ejemplo sin credenciales, comandos de arranque, puertos y URL, datos iniciales, pasos de repetición, contratos, evidencias y limitaciones.
- **Guion de demostración:** presentar los RF y su orden; ejecutar el primero desde la pantalla y comprobar el registro; recargar y ejecutar el segundo con el ID real; mostrar rechazo o ausencia; localizar pantalla, endpoint, servicio y repositorio en el código; explicar un resultado de calidad con su RNF, meta, medida y evidencia.

## Checklist final

- Ambos RF conservan alcance, prioridad e identificadores.
- La interfaz ejecuta ambos RF mediante sus API reales.
- Los contratos coinciden con las solicitudes y respuestas observadas.
- Se prueban éxito, rechazo o ausencia de ambos RF.
- Se demuestra persistencia y no se confirman resultados simulados.
- Se manejan errores de entrada y de comunicación de forma comprensible.
- Las reglas quedan en negocio y el acceso a datos en persistencia.
- La matriz conserva la trazabilidad RF–RNF–prueba–evidencia.
- Los resultados de calidad se comparan con las metas acordadas.
- Se identifican incumplimientos, no verificados y limitaciones.
- Otra persona puede repetir la demostración con el README.

## Referencias

- ISO/IEC 25010:2023, *Product quality model*: https://www.iso.org/standard/78176.html
- Fowler, M. (2002). *Patterns of Enterprise Application Architecture*. Addison-Wesley.
