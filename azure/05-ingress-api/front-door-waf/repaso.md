# Azure · Front Door · Repaso

## Preguntas de repaso
1. ¿Qué es Front Door y qué lo diferencia de Application Gateway?
   - *Es global (borde de Microsoft, anycast, CDN y failover entre regiones); Application Gateway es regional y vive en tu VNet.*
2. Enumera la jerarquía de objetos.
   - *Perfil → endpoint → dominio personalizado → grupo de orígenes → origen → ruta → conjunto de reglas; la política WAF se enlaza con una política de seguridad.*
3. ¿Cómo decide a qué origen enviar?
   - *Solo sanos → mayor prioridad → dentro de la latencia adicional → por peso.*
4. ¿Por qué cuidar la ruta de la sonda?
   - *Cada POP sondea cada origen; una sonda pesada se multiplica por cientos.*
5. ¿Cómo evitas que atacantes se salten Front Door?
   - *Private Link (Premium) o restringir por `AzureFrontDoor.Backend` y validar `X-Azure-FDID`.*
6. ¿Para qué sirve `X-Azure-Ref`?
   - *Identificar una petición en los logs y soporte.*
7. ¿Cuándo cacheas y cuándo no?
   - *Estáticos sí (con purga); APIs dinámicas o con datos personales, no.*
8. Diferencias entre Standard y Premium.
   - *Premium añade reglas gestionadas del WAF, bots y Private Link a orígenes.*
9. ¿Qué causa un 503 y qué un 504?
   - *503: ningún origen sano; 504: el origen tardó más que el tiempo de espera.*
10. ¿Cómo validas un dominio personalizado?
    - *TXT `_dnsauth` + CNAME al endpoint (alias en el apex).*
11. ¿Qué es un subdomain takeover y cómo se previene?
    - *Reclamar un CNAME huérfano; inventario DNS y borrado de registros colgantes.*
12. ¿Cómo combinas Front Door con Application Gateway o APIM?
    - *Front Door global delante; el gateway/APIM regional como origen, con acceso restringido a Front Door.*

## Entrevista
- Diseña la entrada global de una API con dos regiones y WAF.
- ¿Cómo pruebas el failover sin afectar a los usuarios?
- ¿Qué pondrías en caché de un e-commerce y qué no?
- Explica cómo harías el origen accesible solo desde Front Door.

## Ejercicio práctico
1. Despliega el Terraform de [ejemplos/terraform](ejemplos/terraform/main.tf) con un origen de prueba.
2. Comprueba `x-cache` (MISS/HIT) en una ruta estática.
3. Apaga el origen principal y observa el cambio al respaldo.
4. Intenta llamar al origen directo; cierra el acceso y vuelve a probar.
