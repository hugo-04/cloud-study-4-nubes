# Transversal · Arquitectura y testing · Repaso

## Preguntas
1. ¿Cuándo elegir un monolito modular?
2. ¿Qué es un puerto y quién lo define?
3. ¿Hacia dónde apuntan las dependencias en hexagonal/clean?
4. ¿Qué diferencia a un value object de una entidad?
5. ¿Qué protege un agregado?
6. ¿Por qué paquetes por funcionalidad?
7. ¿Diferencia entre stub, fake y mock?
8. ¿Cuáles son los pasos de TDD?
9. ¿Para qué sirve BDD?
10. ¿Qué detecta una prueba de mutación que la cobertura no?

## Respuestas
1. Con un equipo pequeño o un dominio que aún cambia, sin necesidad de escalar partes por separado.
2. Una interfaz hacia lo externo; la define el núcleo (dominio/aplicación).
3. Hacia adentro: la infraestructura depende del dominio, nunca al revés.
4. El value object se compara por valor y es inmutable; la entidad tiene identidad propia.
5. Sus invariantes: solo se modifica por su raíz.
6. Cohesión, visibilidad de paquete y módulos fáciles de extraer.
7. Stub responde fijo; fake es una implementación simple real; mock verifica interacciones.
8. Rojo (prueba que falla), verde (código mínimo), refactor.
9. Acordar reglas con negocio en lenguaje común y automatizarlas.
10. Pruebas que ejecutan código pero no verifican su resultado.

## Ejercicios
1. Agrega el puerto `PublicadorEventos` a `CrearPedido` y un fake para probarlo.
2. Aplica TDD para una regla nueva: envío gratis desde 150 000 céntimos.
3. Escribe una regla ArchUnit que impida a `pagos` usar `pedidos.adaptadores`.
