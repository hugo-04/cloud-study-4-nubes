# NotebookLM · Oracle OCI · OCI Cache (compatible con Redis/Valkey)

**Fuentes a subir:** todos los `.md` de esta carpeta y de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre OCI Cache (compatible con Redis/Valkey) en Oracle OCI, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de el mostrador de cafés listos junto a la caja y un diagrama de sus piezas.
2. Cómo funciona por dentro, componente por componente: clúster con primario y réplicas o sharded, endpoints primario/réplicas/descubrimiento, config sets y políticas de expulsión, usuarios ACL, TLS.
3. Para qué sirve y cuándo NO usarlo.
4. Conceptos clave explicados en palabras simples: cache-aside, TTL con jitter, estampida, versión en la clave, expulsión.
5. Seguridad: tabla de identidad, plano de control y plano de datos, y acceso por red privada.
6. Qué hacer y qué NO hacer, límites y costos (con «verifica» en lo que cambia).
7. Los casos reales y el uso desde Java: cache-aside con anti-estampida y degradación, y el descubrimiento de endpoints con RedisClusterClient; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Troubleshooting en orden y repaso con 3 preguntas.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
