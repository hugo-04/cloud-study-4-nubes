# Azure · Caso integrado · Clickstream · Casos reales

Historias de ModaLima (ficticia).

## 1. La partición que ardía
**Qué pasó:** en una campaña, una partición recibía el 70 % del tráfico y su lector iba 40 minutos atrasado; las otras 7 estaban casi vacías.
**Causa:** la clave era la **página** y la portada concentraba casi todo.
**Solución:** clave = cubeta de la sesión; se verificó el reparto con el detector de sesgo.
**Lección:** la clave de partición es la decisión de diseño más cara de corregir.

## 2. 429 en plena campaña
**Qué pasó:** el colector devolvió 429 y se perdieron clics durante 12 minutos.
**Causa:** capacidad fija en 2 unidades; sin auto-inflate.
**Solución:** planificador con margen ×1,5, auto-inflate con tope 6 y alerta por limitaciones; reintentos con espera en el cliente.
**Lección:** dimensiona con el pico, no con el promedio; y pon una alarma antes del tope.

## 3. El bot de las 3 a.m.
**Qué pasó:** una sesión generó 2 millones de eventos y distorsionó todos los tableros.
**Solución:** límite por sesión en el colector (APIM), detección de sesgo y exclusión de sesiones sospechosas en el agregador.
**Lección:** el tráfico no humano también es tráfico.

## 4. El reinicio que «perdió» minutos
**Qué pasó:** tras un despliegue, los números de la hora anterior quedaron bajos en el tablero.
**Causa:** el agregador mantiene ventanas en memoria; al reiniciarse, la ventana abierta se reconstruyó solo desde el último punto de control.
**Solución:** aceptar que el camino en línea es aproximado, y recalcular el día completo desde el lago cada noche; el resumen se guarda con UPSERT.
**Lección:** define qué es «en vivo» y qué es «oficial».

## 5. Datos personales en el lago
**Qué pasó:** se descubrió el identificador real de los clientes en los archivos de Capture.
**Solución:** seudonimizar con HMAC en el colector (sal en Key Vault), borrar el histórico y revisar con políticas de datos.
**Lección:** lo que entra al flujo se queda en el lago; filtra en la puerta.

## 6. Dos aplicaciones, un solo grupo
**Qué pasó:** el equipo de recomendaciones leyó con el mismo grupo que el agregador; ambos veían la mitad de los eventos.
**Causa:** los consumidores del mismo grupo **se reparten** las particiones.
**Solución:** un grupo por aplicación.
**Lección:** un grupo es una «vista»; compartirlo es repartir.

## 7. Resumen sumado dos veces
**Qué pasó:** tras un reintento, las visitas de un minuto se duplicaron.
**Solución:** UPSERT con el valor completo de la ventana en lugar de sumar.
**Lección:** en mensajería «al menos una vez», el destino debe ser idempotente.

| Problema | Solución |
|---|---|
| Hot key | Clave por sesión/cubeta |
| Limitaciones | Planificador, auto-inflate con tope, alertas |
| Bots | Límite en el borde + detección de sesgo |
| Reinicios | Lago como fuente de verdad |
| Privacidad | Seudónimos desde el colector |
| Duplicados | UPSERT idempotente |
