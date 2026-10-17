# AWS · CloudFront y WAF · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El Black Friday que no tumbó nada
**Qué pasó:** el catálogo de ModaLima recibía 40 veces su tráfico normal. **Solución:** imágenes y listados con TTL de cinco minutos en CloudFront y una clave de caché mínima; el origen vio una fracción del tráfico. **Lección:** la CDN absorbe los picos de lecturas.

## 2. Todos los usuarios veían el carrito de otro
**Qué pasó:** `/api/carrito` se cacheó porque la política incluía solo la ruta y no la cookie de sesión. **Solución:** `CachingDisabled` en `/api/*` y `Cache-Control: no-store` en las respuestas privadas. **Lección:** lo personal nunca se cachea en la CDN compartida.

## 3. Ataque de credenciales en `/login`
**Qué pasó:** miles de intentos por minuto desde muchas IP. **Solución:** WAF con regla por tasa específica para `/login`, reglas gestionadas de reputación de IP y Bot Control en Count primero. **Lección:** limita lo sensible y ensaya en Count.

## 4. El ALB atacado directamente
**Qué pasó:** los atacantes ignoraron la CDN y golpearon el DNS del ALB. **Solución:** SG del ALB solo admite la lista de prefijos de CloudFront y exige la cabecera secreta. **Lección:** de nada sirve el WAF si el origen está abierto.

## 5. Despliegue del front que seguía mostrando la versión vieja
**Qué pasó:** `index.html` y los `.js` tenían el mismo TTL largo. **Solución:** archivos con hash (inmutables, 1 año) y `index.html` con `no-cache`; invalidar solo `/index.html`. **Lección:** distingue lo versionado de lo que apunta a lo versionado.

## 6. Descargas privadas con caducidad
**Qué pasó:** los clientes de Café Andino descargaban facturas con enlaces públicos eternos. **Solución:** URLs firmadas de CloudFront con 10 minutos de vida y clave privada en Secrets Manager. **Lección:** privacidad = firma + caducidad corta.

| Problema | Solución |
|---|---|
| Picos de lectura | Caché con TTL y clave mínima |
| Datos de un usuario a otro | No cachear lo privado |
| Fuerza bruta | WAF por tasa + reglas de bots |
| Origen expuesto | Prefix list + cabecera secreta |
| Contenido viejo | Hash en archivos + invalidación puntual |
| Enlaces eternos | URLs firmadas cortas |
