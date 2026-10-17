# Transversal · Arquitectura y testing

Cómo **organizar** un servicio para que siga siendo fácil de cambiar (estilos, capas, hexagonal, clean, DDD táctico, paquetes) y cómo **probarlo** con confianza (pirámide, TDD, BDD, dobles, integración, contrato, reglas de arquitectura). Ambas cosas van juntas: una buena arquitectura es la que deja probar el negocio sin levantar la infraestructura.

## 1. Qué es

**Analogía:** una casa con instalaciones accesibles: si las cañerías (infraestructura) pasan por un ducto registrable y no por dentro de las paredes maestras (dominio), puedes cambiarlas y revisarlas (probar) sin demoler nada.

```
 adaptadores (web, base, broker)  ──dependen de──►  aplicación (casos de uso)  ──►  dominio
 pruebas:  integración/contrato ─────────────────  unitarias con fakes/mocks ─────  unitarias puras
```

## 2. Contenido
| Archivo | Temas |
|---|---|
| [Arquitectura](arquitectura.md) | Monolito vs monolito modular vs microservicios (cuándo sí/no), capas, hexagonal con código, clean, DDD táctico, organización de paquetes |
| [Testing](testing.md) | Pirámide y panal, dobles de prueba, TDD paso a paso, Mockito, BDD con Cucumber en español, ArchUnit, integración con contenedores, contrato, mutación |

## 3. Decisiones rápidas
| Pregunta | Respuesta por defecto |
|---|---|
| ¿Monolito o microservicios? | Monolito modular hasta que un módulo necesite vida propia |
| ¿Capas o hexagonal? | Capas para CRUD; hexagonal cuando el dominio tiene reglas propias o varias entradas/salidas |
| ¿Paquetes por capa o por funcionalidad? | Por funcionalidad |
| ¿Qué pruebo primero? | El dominio y los casos de uso, con pruebas unitarias |
| ¿Cómo pruebo la base? | Integración contra la misma tecnología en contenedor |
| ¿Cómo evito romper a otros servicios? | Pruebas de contrato en CI |
| ¿TDD siempre? | En reglas de negocio sí; en código de pegamento, pruebas después está bien |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Puerto** | Interfaz que el núcleo define |
| **Adaptador** | Implementación tecnológica de un puerto |
| **Agregado** | Grupo de objetos que se cambia como unidad consistente |
| **Doble de prueba** | Sustituto de una dependencia en una prueba |
| **Rojo-verde-refactor** | El ciclo de TDD |

## 5. Cómo se usa
1. Lee [arquitectura](arquitectura.md) y reconoce en tu servicio qué es dominio, aplicación y adaptador.
2. Mueve reglas a clases sin frameworks y crea puertos para lo externo.
3. Escribe pruebas como en [testing](testing.md): unitarias del dominio, casos de uso con dobles, integración de adaptadores, contrato y reglas ArchUnit.

## 6. Seguridad
- Las reglas de autorización de negocio («solo el dueño cancela su pedido») viven en el dominio/aplicación y se prueban unitariamente.
- Pruebas negativas obligatorias: entradas inválidas, accesos sin permiso, límites.
- Datos de prueba sintéticos: nunca copias de producción con datos personales.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Dominio sin anotaciones de frameworks | Entidades JPA como modelo de dominio rico «por comodidad» en dominios complejos |
| Casos de uso pequeños y nombrados por intención | Servicios «Manager» de 3 000 líneas |
| Verificar dependencias con ArchUnit | Confiar en la disciplina |
| Pirámide con base ancha | Cono de helado (muchas E2E, pocas unitarias) |
| Pruebas que se leen como especificación | Pruebas acopladas a detalles internos |

## 8. Casos reales
| Historia | Qué pasó | Lección |
|---|---|---|
| Microservicios prematuros | Un equipo de 4 en ModaLima mantenía 14 servicios y pasaba más tiempo en despliegues que en producto | Monolito modular y extraer después |
| La regla duplicada | El descuento se calculaba distinto en web y en el consumidor de eventos | Un caso de uso, dos adaptadores de entrada |
| Pruebas de 40 minutos | Todo eran pruebas de punta a punta en Café Andino | Pirámide: mover reglas a unitarias |
| El módulo que importaba internos | `pagos` usaba clases internas de `pedidos` y nadie pudo separarlos | Visibilidad de paquete + ArchUnit |

**Siguiente:** [arquitectura](arquitectura.md) · [testing](testing.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md) · [índice transversal](../README.md)
