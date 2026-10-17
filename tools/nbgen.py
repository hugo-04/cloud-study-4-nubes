import os
def nb(ruta, titulo, nube, analogia, internos, conceptos, java, extra=""):
    """Escribe notebooklm.md de un servicio. ruta = carpeta del servicio."""
    corto = ruta.rstrip('/').split('/')
    ctx = " · ".join(p for p in corto[-3:])
    texto = f"""# NotebookLM · {nube} · {titulo}

**Fuentes a subir:** todos los `.md` de esta carpeta y de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre {titulo} en {nube}, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de {analogia} y un diagrama de sus piezas.
2. Cómo funciona por dentro, componente por componente: {internos}.
3. Para qué sirve y cuándo NO usarlo.
4. Conceptos clave explicados en palabras simples: {conceptos}.
5. Seguridad: tabla de identidad, plano de control y plano de datos, y acceso por red privada.
6. Qué hacer y qué NO hacer, límites y costos (con «verifica» en lo que cambia).
7. Los casos reales y el uso desde Java: {java}; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.{(' ' + extra) if extra else ''}
8. Troubleshooting en orden y repaso con 3 preguntas.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
"""
    os.makedirs(ruta, exist_ok=True)
    open(os.path.join(ruta, 'notebooklm.md'), 'w', encoding='utf-8').write(texto)

def cap_nb(ruta, titulo, nube, servicios):
    texto = f"""# NotebookLM · {nube} · {titulo}

**Fuentes a subir:** el `README.md` de este capítulo y los de cada servicio. Para un video por servicio usa el `notebooklm.md` de cada subcarpeta.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, sobre el capítulo "{titulo}" de {nube}, para un ingeniero Java de microservicios. Habla solo de {nube}; no compares con otras nubes.

Estructura obligatoria:
1. La pregunta que responde cada servicio del capítulo ({servicios}), con una analogía por servicio.
2. El árbol de decisión «quiero…» y la comparativa en tabla.
3. La receta de ModaLima: cómo se combinan en una tienda real.
4. Orden recomendado de adopción y reglas transversales.
5. Qué construye cada `uso-en-java.md` y el patrón común (núcleo puro, adaptador del SDK, Spring MVC/WebFlux, Quarkus imperativo/Mutiny).
6. Errores comunes entre servicios del capítulo.

Reglas: no omitas tablas; define cada término al usarlo; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
"""
    os.makedirs(ruta, exist_ok=True)
    open(os.path.join(ruta, 'notebooklm.md'), 'w', encoding='utf-8').write(texto)
