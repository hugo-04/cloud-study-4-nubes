# Transversal · Patrones de diseño (los 23 del GoF)

Un **patrón de diseño** es una solución probada y con nombre para un problema de diseño que se repite. Los 23 del libro *Design Patterns* (Gamma, Helm, Johnson, Vlissides, «Gang of Four», 1994) siguen siendo el vocabulario común del diseño orientado a objetos; en Java 21 muchos se escriben más cortos gracias a lambdas, records, `sealed` y `switch` con patrones. Aquí cada patrón trae problema, solución, código que compila y cuándo usarlo (y cuándo no), con ejemplos de ModaLima.

## 1. Qué es

**Analogía:** las jugadas ensayadas de un equipo de fútbol: no son el partido, pero cuando aparece la situación (córner, contraataque) todos saben qué hacer y cómo se llama.

```
 Creacionales (5)  → cómo se crean los objetos
 Estructurales (7) → cómo se componen
 Comportamiento (11) → cómo colaboran y se reparten responsabilidades
```

## 2. El catálogo

| Patrón | Tipo | En una frase | Ejemplo de ModaLima |
|---|---|---|---|
| [Factory Method](creacionales.md#1-factory-method) | Creacional | Delegar qué clase concreta se crea | Pasarela de pago según medio |
| [Abstract Factory](creacionales.md#2-abstract-factory) | Creacional | Crear familias coherentes | Cliente + etiqueta por courier |
| [Builder](creacionales.md#3-builder) | Creacional | Armar paso a paso un objeto complejo | Pedido con opcionales |
| [Prototype](creacionales.md#4-prototype) | Creacional | Copiar un objeto ya configurado | Plantilla de campaña |
| [Singleton](creacionales.md#5-singleton) | Creacional | Una sola instancia | Cliente costoso (mejor: el contenedor) |
| [Adapter](estructurales.md#1-adapter) | Estructural | Traducir una interfaz ajena | Stock del ERP legado |
| [Bridge](estructurales.md#2-bridge) | Estructural | Separar dos dimensiones | Tipo de aviso × canal |
| [Composite](estructurales.md#3-composite) | Estructural | Tratar igual uno y muchos | Producto y *pack* |
| [Decorator](estructurales.md#4-decorator) | Estructural | Agregar comportamiento apilable | Catálogo con caché y métricas |
| [Facade](estructurales.md#5-facade) | Estructural | Simplificar un subsistema | Compra = stock + pago + envío |
| [Flyweight](estructurales.md#6-flyweight) | Estructural | Compartir datos repetidos | Fichas en millones de clics |
| [Proxy](estructurales.md#7-proxy) | Estructural | Controlar el acceso | Reportes con permiso y carga perezosa |
| [Chain of Responsibility](comportamiento.md#1-chain-of-responsibility) | Comportamiento | Cadena de manejadores | Reglas antifraude |
| [Command](comportamiento.md#2-command) | Comportamiento | Acción como objeto | Reserva con compensación |
| [Interpreter](comportamiento.md#3-interpreter) | Comportamiento | Evaluar un mini-lenguaje | Reglas de promoción |
| [Iterator](comportamiento.md#4-iterator) | Comportamiento | Recorrer sin exponer | API paginada |
| [Mediator](comportamiento.md#5-mediator) | Comportamiento | Coordinador central | Carrito, cupones y totales |
| [Memento](comportamiento.md#6-memento) | Comportamiento | Guardar y restaurar estado | Borrador de pedido |
| [Observer](comportamiento.md#7-observer) | Comportamiento | Avisar a interesados | Pedido pagado → correo, puntos |
| [State](comportamiento.md#8-state) | Comportamiento | Comportamiento según estado | Ciclo de vida del pedido |
| [Strategy](comportamiento.md#9-strategy) | Comportamiento | Algoritmos intercambiables | Cálculo de envío |
| [Template Method](comportamiento.md#10-template-method) | Comportamiento | Esqueleto fijo con huecos | Importadores de catálogo |
| [Visitor](comportamiento.md#11-visitor) | Comportamiento | Operaciones nuevas sobre una jerarquía | IVA y exportación de líneas |

## 3. Para qué sirven y cuándo NO
| Situación | Decisión |
|---|---|
| El mismo problema aparece en varios lugares | Aplica el patrón y nómbralo en el código |
| Comunicar diseño en una revisión | Usa el nombre del patrón |
| «Por si acaso» o para lucirse | No: complejidad sin beneficio (YAGNI) |
| El lenguaje ya lo resuelve (lambda en vez de Strategy con clases) | Usa la forma simple |

## 4. Conceptos clave
| Principio | En simple | Patrones que lo aplican |
|---|---|---|
| Programar contra interfaces | Depender de abstracciones | Casi todos |
| Composición sobre herencia | Armar con piezas en vez de heredar | Decorator, Strategy, Bridge |
| Abierto/cerrado | Extender sin modificar | Factory, Strategy, Visitor |
| Responsabilidad única | Una razón para cambiar | Facade, Command |
| Inversión de dependencias | El dominio define la interfaz; la infraestructura la implementa | Adapter (hexagonal) |

## 5. Cómo se usa
Lee los tres archivos en orden: [creacionales](creacionales.md), [estructurales](estructurales.md) y [de comportamiento](comportamiento.md). Para cada patrón: identifica la **señal** (tabla de resumen al final de cada archivo), compara con la alternativa simple y nómbralo en el código (`...Factory`, `...Strategy`, `...Adapter`).

## 6. Patrones en los frameworks que ya usas
| Patrón | Dónde lo ves |
|---|---|
| Singleton | Beans por defecto de Spring, `@ApplicationScoped` |
| Factory | `@Bean`, `@Produces` |
| Proxy / Decorator | `@Transactional`, `@Cacheable`, `@Retry` (AOP e interceptores) |
| Template Method | `JdbcTemplate`, `KafkaTemplate` |
| Chain of Responsibility | Filtros HTTP y de seguridad |
| Observer | `@EventListener`, `@Observes` |
| Builder | `RestClient.builder()`, *builders* de SDK |
| Adapter | Repositorios y clientes que implementan puertos |
| Iterator | `iterateAll()` de los SDK paginados |

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Empezar simple y refactorizar al patrón cuando aparezca la señal | Diseñar con 8 patrones desde el día uno |
| Preferir composición | Herencias profundas |
| Usar `sealed` + `switch` en vez de Visitor clásico | Visitors con 2 tipos |
| Dejar el Singleton al contenedor | Singletons con estado mutable global |
| Nombrar el patrón en el código | Patrones «escondidos» que nadie reconoce |

## 8. Casos reales
| Historia | Qué pasó | Lección |
|---|---|---|
| El `switch` de pasarelas | Cada medio de pago nuevo de ModaLima tocaba 7 archivos | Factory + Strategy: un registro y una clase nueva |
| El singleton con estado | Un contador «global» de Café Andino daba números distintos por réplica | Un singleton es por proceso; el estado compartido va a una base |
| El decorador mal ordenado | La caché envolvía a las métricas y ocultaba la carga real | El orden de los decoradores importa |
| La máquina de estados de `if` | Se podía «entregar» un pedido cancelado | State con transiciones explícitas |

**Siguiente:** [creacionales](creacionales.md) · [estructurales](estructurales.md) · [de comportamiento](comportamiento.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md) · [índice transversal](../README.md)
