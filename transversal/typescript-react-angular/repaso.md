# Transversal · TypeScript, React y Angular · Repaso

## Preguntas
1. ¿Por qué tratar las respuestas de la API como `unknown`?
2. ¿Qué es una unión discriminada y para qué sirve en la UI?
3. ¿Cómo comprueba TypeScript que cubriste todos los casos de un `switch`?
4. ¿Por qué abortar el `fetch` en la limpieza de `useEffect`?
5. ¿Cuándo `useReducer` en vez de `useState`?
6. ¿Qué hace `switchMap` en una búsqueda?
7. ¿Para qué sirven `computed` y `effect` en signals?
8. ¿Qué gana el frontend con un BFF?
9. ¿Dónde guardar los tokens?
10. ¿Por qué un *guard* no es seguridad?

## Respuestas
1. Porque pueden no cumplir el contrato; se validan antes de usarlas.
2. Un tipo con una etiqueta común (`fase`, `tipo`) que separa los casos; modela cargando/listo/error sin contradicciones.
3. Asignando el valor restante a `never` en el `default`.
4. Para que una respuesta vieja no pise el estado nuevo ni se actualice un componente desmontado.
5. Cuando el estado tiene muchas transiciones relacionadas (carrito).
6. Cancela la petición anterior cuando llega un texto nuevo.
7. Derivar valores de otros signals / ejecutar efectos cuando cambian.
8. Respuestas a la medida, menos llamadas y manejo seguro de la sesión.
9. En una cookie `HttpOnly` gestionada por el BFF, o solo en memoria.
10. Corre en el navegador del usuario; la autorización real está en el backend.

## Ejercicios
1. Agrega a `pedirJson` reintentos solo para `GET` con backoff.
2. Escribe un hook `useBusqueda` en React con *debounce* y cancelación.
3. Convierte el buscador de Angular para paginar por cursor.
