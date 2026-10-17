# Transversal · Patrones de diseño · Repaso

## Preguntas
1. ¿Cuáles son las tres familias del GoF y cuántos patrones tiene cada una?
2. ¿Diferencia entre Factory Method y Abstract Factory?
3. ¿Cuándo un Builder y cuándo un record?
4. ¿Por qué dejar el Singleton al contenedor?
5. ¿Diferencia entre Decorator y Proxy?
6. ¿Qué patrón es el «adaptador» de la arquitectura hexagonal?
7. ¿Diferencia entre Strategy y State?
8. ¿Qué reemplaza al Visitor en Java 21?
9. ¿Qué patrón encapsula una acción con su compensación?
10. ¿Qué patrón usan los filtros HTTP?

## Respuestas
1. Creacionales (5), estructurales (7) y de comportamiento (11).
2. Uno crea un producto; el otro, familias de productos coherentes.
3. Builder con muchos opcionales y validación; record con pocos campos obligatorios.
4. Gestiona el ciclo de vida, la concurrencia y facilita pruebas.
5. Decorator agrega comportamiento; Proxy controla el acceso.
6. Adapter.
7. La estrategia la elige el cliente; el estado cambia por transiciones internas.
8. `sealed` + `switch` con patrones.
9. Command (con `deshacer`).
10. Chain of Responsibility.

## Ejercicios
1. Agrega el medio «billetera» a la fábrica de pasarelas sin tocar a los clientes.
2. Agrega el estado `Devuelto` al ciclo del pedido y sus transiciones.
3. Escribe un decorador de reintentos para `Catalogo` y decide su orden respecto de la caché.
