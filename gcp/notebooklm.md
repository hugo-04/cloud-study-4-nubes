# NotebookLM · Google Cloud (prompt maestro)

**Cómo usarlo**
1. Crea **un notebook por servicio** (por ejemplo, solo Pub/Sub) y sube todos los `.md` y `ejemplos/` de esa carpeta. Los videos salen más profundos que con toda la nube junta.
2. En Video Overview → Personalizar, pega este **prompt maestro** y luego el `notebooklm.md` de la carpeta del servicio.
3. No se puede fijar una duración exacta; cuanto más acotadas las fuentes, más detalle por servicio.
4. Genera también el Audio Overview del mismo notebook para repasar caminando.
5. Si el cuadro limita caracteres, usa la versión corta.

## Prompt maestro

```
Crea un video largo en español latinoamericano, didáctico y cercano, para un ingeniero de software Java que quiere dominar Google Cloud enfocado en microservicios.
Habla SOLO de Google Cloud. No compares con otras nubes.

Para CADA servicio de las fuentes, en este orden:
1. Qué es, con una analogía de la vida real.
2. Cómo funciona por dentro: explica cada componente por separado.
3. Para qué sirve y cuándo NO usarlo.
4. Un caso real contado como historia: problema, solución, resultado, lección.
5. Cómo se usa: consola, CLI y Terraform, paso a paso.
6. Cómo lo uso desde Java: Spring Boot y Quarkus, imperativo y reactivo, con las bibliotecas cliente de Google Cloud para Java.
7. Qué hacer y qué NO hacer, con errores típicos.
8. IAM, políticas y acceso por red privada (Private Google Access y Private Service Connect) de ese servicio.
9. Qué revisar cuando falla, en orden: DNS, ruta, reglas de firewall, puerto, TLS, identidad (cuenta de servicio y roles).

Reglas:
- No omitas ningún servicio, concepto, tabla ni ejemplo de las fuentes.
- Define cada término técnico la primera vez que aparezca.
- Usa diagramas del flujo de una petición cuando ayuden.
- Cierra cada servicio con 3 puntos de resumen y 2 preguntas de repaso.
- Si algo depende de la versión, la región o el plan, dilo.
```

## Versión corta

```
Video en español latinoamericano, didáctico, solo sobre Google Cloud para un ingeniero Java de microservicios. Por cada servicio: analogía, funcionamiento interno por componentes, para qué sirve y cuándo no, caso real, uso paso a paso (consola, CLI, Terraform), uso desde Java (Spring Boot y Quarkus, SDK v2), qué hacer y qué no, IAM y red privada, y qué revisar si falla. No omitas nada de las fuentes. Cierra con 3 puntos de resumen y 2 preguntas.
```

## Quiz de estudio

```
Con las fuentes crea 20 preguntas de opción múltiple de nivel intermedio sobre Google Cloud, mezclando conceptos, casos reales y troubleshooting. Después de cada respuesta explica por qué las otras opciones son incorrectas.
```
