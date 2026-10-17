# Google Cloud · IAM · Workload Identity Federation · Casos reales

## 1. El proveedor sin condición
**Qué pasó:** una revisión descubrió que cualquier repositorio de la plataforma de CI podía obtener tokens del proyecto de ModaLima.
**Causa:** proveedor OIDC sin condición.
**Arreglo:** `assertion.repository == 'modalima/infra'` y roles al `principalSet` de ese repositorio.
**Lección:** el emisor es compartido; la condición es tuya.

## 2. La rama de pruebas que desplegó a prod
**Qué pasó:** un cambio en una rama de trabajo se aplicó en producción.
**Causa:** la condición filtraba repositorio pero no rama.
**Arreglo:** pool de prod solo para `refs/heads/main` y entorno protegido; pool de no-prod para ramas.
**Lección:** separa entornos en la identidad, no en el script.

## 3. La llave en el secreto del CI
**Qué pasó:** Café Andino rotaba llaves JSON del CI cada 90 días y una se filtró en un log.
**Causa:** llaves de larga vida.
**Arreglo:** federación; llaves borradas y bloqueadas por política.
**Lección:** sin llaves no hay llave que filtrar.

## 4. «audience mismatch»
**Qué pasó:** el pipeline fallaba al intercambiar el token.
**Causa:** la audiencia del token no coincidía con la del proveedor.
**Arreglo:** usar la audiencia configurada (o la por defecto del proveedor) al pedir el token OIDC.
**Lección:** emisor y audiencia deben coincidir exactamente.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Acceso de terceros | Sin condición | Condición por repositorio |
| 2 | Despliegue indebido | Sin filtro de rama | Pools por entorno |
| 3 | Llave filtrada | Llaves JSON | Federación |
| 4 | Intercambio falla | Audiencia | Alinear audiencia |
