# Google Cloud · Caso integrado · Landing zone · Casos reales

## 1. El solape con la oficina
**Qué pasó:** la nueva unidad de Café Andino eligió 10.10.0.0/16 y no podía hablar con la oficina de Lima.
**Causa:** la oficina usaba ese rango por la VPN, invisible en la VPC.
**Arreglo:** el planificador recibe también las redes locales.
**Lección:** lo que no está en la nube también ocupa.

## 2. Los pods sin direcciones
**Qué pasó:** el clúster GKE de la unidad no podía crecer.
**Causa:** el rango secundario de pods se solapaba y se achicó a mano.
**Arreglo:** contar rangos secundarios al planificar.
**Lección:** GKE pide más direcciones de las que parece.

## 3. Las llaves a personas
**Qué pasó:** al irse un desarrollador, seguía con acceso.
**Causa:** roles dados a usuarios.
**Arreglo:** grupos con dueños y revisión trimestral.
**Lección:** roles a grupos.

## 4. El apply «exitoso» incompleto
**Qué pasó:** el pipeline terminó bien, pero faltaba el vínculo a la VPC compartida.
**Causa:** un recurso se quitó del código sin querer.
**Arreglo:** verificador posterior que reporta lo faltante y lo que no pudo comprobar.
**Lección:** verifica el resultado, no el proceso.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Sin conexión | Solape local | Redes locales en el plan |
| 2 | Sin IP para pods | Secundarios | Contarlos |
| 3 | Acceso residual | Roles a personas | Grupos |
| 4 | Pieza faltante | Código cambiado | Verificador |
