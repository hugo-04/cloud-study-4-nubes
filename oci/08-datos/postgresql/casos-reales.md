# Oracle OCI · Datos · PostgreSQL · Casos reales

## 1. El pedido que «desaparecía»
**Qué pasó:** tras pagar, el cliente de ModaLima veía «no tienes pedidos» durante un instante.
**Causa:** la pantalla de confirmación leía del endpoint de lectura.
**Arreglo:** ventana de 5 segundos tras una escritura en la que ese usuario lee del primario.
**Lección:** las réplicas son eventualmente consistentes.

## 2. Mil conexiones dormidas
**Qué pasó:** la base usaba mucha memoria y respondía lento aunque había poco tráfico.
**Causa:** pools de 50 en 20 réplicas: mil conexiones casi siempre inactivas.
**Arreglo:** pools de 10 y tiempos de inactividad cortos.
**Lección:** en PostgreSQL cada conexión cuesta memoria.

## 3. La migración que bloqueó la tabla
**Qué pasó:** un `ALTER TABLE` con valor por defecto bloqueó el checkout 3 minutos.
**Causa:** migración pesada en horario de tráfico.
**Arreglo:** migraciones en dos pasos (agregar columna nula, completar por lotes, luego restricción) y ventana definida.
**Lección:** las migraciones son despliegues.

## 4. La extensión que no estaba
**Qué pasó:** Café Andino planeó usar una extensión que el servicio no soportaba.
**Causa:** no se revisó la lista de extensiones.
**Arreglo:** validar la lista antes de diseñar; alternativa en la aplicación.
**Lección:** administrado significa también «lista cerrada».

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Dato ausente al instante | Lectura en réplica | Primario tras escribir |
| 2 | Lentitud con poco tráfico | Demasiadas conexiones | Pools pequeños |
| 3 | Bloqueo | Migración pesada | Migraciones por pasos |
| 4 | Diseño inviable | Extensión no soportada | Verificar antes |
