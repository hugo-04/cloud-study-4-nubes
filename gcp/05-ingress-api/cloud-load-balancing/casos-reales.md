# Google Cloud · Ingress y API · Cloud Load Balancing · Casos reales

## 1. El certificado que vencía cada trimestre
**Qué pasó:** cada tres meses la tienda de ModaLima mostraba «conexión no segura».
**Causa:** certificados subidos a mano.
**Arreglo:** certificados administrados (Certificate Manager) con autorización DNS.
**Lección:** automatiza la renovación.

## 2. La ruta que iba al servicio equivocado
**Qué pasó:** `/api/v2/pedidos` llegaba al servicio viejo.
**Causa:** regla `/api/*` evaluada para ese path y nadie probó el URL map.
**Arreglo:** regla específica `/api/v2/*` y pruebas del URL map en el pipeline.
**Lección:** el enrutamiento también se prueba.

## 3. Backends «no sanos» tras un cambio de firewall
**Qué pasó:** todos los backends quedaron no sanos y la tienda devolvió 502.
**Causa:** se borró la regla que permitía los rangos de chequeo de salud.
**Arreglo:** regla gestionada en Terraform junto al balanceador.
**Lección:** los chequeos vienen de rangos de Google que hay que permitir.

## 4. Exportaciones cortadas a los 30 segundos
**Qué pasó:** las descargas de reportes de Café Andino se cortaban.
**Causa:** timeout del backend service por defecto.
**Arreglo:** timeout mayor en ese backend o generación asíncrona con URL firmada.
**Lección:** cada backend tiene su timeout.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Certificado vencido | Manual | Administrado |
| 2 | Ruta errónea | Reglas sin pruebas | Pruebas del URL map |
| 3 | 502 masivo | Firewall de chequeos | Regla gestionada |
| 4 | Cortes | Timeout | Ajustar o asíncrono |
