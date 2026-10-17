# Google Cloud · Terraform · Módulos y entornos · Casos reales

## 1. El cambio que llegó solo a prod
**Qué pasó:** un cambio en el módulo de ModaLima apareció en el plan de prod sin que nadie lo pidiera.
**Causa:** `ref=main`.
**Arreglo:** etiquetas semánticas y promoción explícita.
**Lección:** versión fija por entorno.

## 2. Prod con cero instancias
**Qué pasó:** el servicio de pagos tenía arranque en frío en prod.
**Causa:** alguien copió las variables de dev.
**Arreglo:** validación en el módulo: `entorno == "prod"` ⇒ `min_instancias >= 1`.
**Lección:** codifica las reglas.

## 3. Dev borró algo de prod
**Qué pasó:** en Café Andino el pipeline de dev eliminó un tema de Pub/Sub de prod.
**Causa:** ambos entornos en el mismo proyecto y con la misma SA.
**Arreglo:** proyecto y SA por entorno.
**Lección:** el aislamiento real es el proyecto.

## 4. El «módulo dios»
**Qué pasó:** un módulo con 80 variables que nadie entendía.
**Causa:** cada caso especial se agregó como opción.
**Arreglo:** módulos pequeños compuestos.
**Lección:** simple y con propósito.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Cambio inesperado | `ref=main` | Etiquetas |
| 2 | Arranque en frío | Variables copiadas | Validación |
| 3 | Borrado cruzado | Mismo proyecto | Proyecto por entorno |
| 4 | Inmantenible | Módulo dios | Módulos pequeños |
