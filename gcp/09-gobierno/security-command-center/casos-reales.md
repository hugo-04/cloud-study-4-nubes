# Google Cloud · Gobierno · Security Command Center · Casos reales

## 1. El bucket público del lunes
**Qué pasó:** SCC marcó `PUBLIC_BUCKET_ACL` en un bucket de pruebas de ModaLima con datos reales.
**Causa:** `allUsers` para compartir rápido.
**Arreglo:** quitarlo y activar `storage.publicAccessPrevention` en la organización.
**Lección:** cada hallazgo repetido pide una baranda.

## 2. La concesión anómala
**Qué pasó:** Event Threat Detection alertó de `roles/owner` dado a una cuenta externa a las 3 a. m.
**Causa:** credencial de un administrador robada.
**Arreglo:** revocar, rotar, investigar con Audit Logs; restricción de dominios.
**Lección:** la detección necesita a alguien que reciba la alerta.

## 3. Fatiga de alertas
**Qué pasó:** el canal de Café Andino recibía 400 hallazgos diarios y nadie leía.
**Causa:** notificación de todas las severidades.
**Arreglo:** solo CRITICAL/HIGH activos; el resto en un reporte semanal.
**Lección:** prioriza.

## 4. El mute que escondía un problema
**Qué pasó:** una regla de mute por categoría silenció un firewall abierto nuevo.
**Causa:** regla demasiado amplia.
**Arreglo:** mute por recurso concreto con revisión trimestral.
**Lección:** silencia lo mínimo.

## Resumen
| # | Hallazgo | Causa | Arreglo |
|---|---|---|---|
| 1 | Bucket público | `allUsers` | Org Policy |
| 2 | Concesión anómala | Credencial robada | Respuesta + dominios |
| 3 | Ruido | Todo notificado | Solo críticos |
| 4 | Oculto | Mute amplio | Mute puntual |
