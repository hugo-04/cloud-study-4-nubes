# Google Cloud · Datos · Bigtable · Repaso

## Preguntas
1. ¿Qué modelo usa Bigtable?
2. ¿Cuál es su único índice?
3. ¿Por qué invertir el timestamp?
4. ¿Qué es una familia de columnas?
5. ¿Qué atomicidad ofrece?
6. ¿Qué es un perfil de aplicación?
7. ¿Qué rol necesita la app?
8. ¿Cómo se escala?
9. ¿Cuándo no usar Bigtable?
10. ¿Qué herramienta muestra hotspots?

## Respuestas
1. Columnas anchas con filas ordenadas por clave.
2. La clave de fila.
3. Para que lo más reciente quede primero.
4. Grupo de columnas con su política de GC.
5. Atómica por fila.
6. La política de enrutado de un cliente.
7. `roles/bigtable.user`.
8. Sumando nodos o con autoescalado.
9. Con pocos datos, transacciones entre filas o consultas ad hoc.
10. Key Visualizer.

## Ejercicios
1. Diseña la clave para «últimas 100 lecturas de una máquina».
2. Define GC para 30 días o 3 versiones.
3. Separa cargas batch y paneles con perfiles.
