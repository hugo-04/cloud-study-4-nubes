import os
def tnb(ruta, titulo, analogia, temas, practica, extra=""):
    """notebooklm.md de un módulo transversal (sin proveedores de nube)."""
    texto = f"""# NotebookLM · Transversal · {titulo}

**Fuentes a subir:** todos los `.md` de esta carpeta (y de `ejemplos/` si existe).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, sobre {titulo}, para un ingeniero Java de microservicios. Es un tema independiente de cualquier proveedor de nube: no menciones proveedores concretos.

Estructura obligatoria:
1. Qué es y por qué importa, con la analogía de {analogia}.
2. Recorrido por los temas, uno por uno, con ejemplos simples: {temas}.
3. Cuándo usarlo y cuándo NO (tabla).
4. Práctica: {practica}. Explica el código paso a paso.{(' ' + extra) if extra else ''}
5. Errores comunes y casos reales de ModaLima y Café Andino.
6. Buenas prácticas en tabla «hacer / no hacer».

Reglas: no omitas tablas ni ejemplos; define cada término al usarlo; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
"""
    os.makedirs(ruta, exist_ok=True)
    open(os.path.join(ruta, 'notebooklm.md'), 'w', encoding='utf-8').write(texto)
