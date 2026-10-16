# Azure · 00 Fundamentos · Repaso

## Preguntas de repaso
1. ¿Cuál es la cadena de jerarquía de Azure, de arriba hacia abajo?
   - *Tenant → Management Group → Subscription → Resource Group → Recurso.*
2. ¿Qué pasa con una política puesta en un Management Group?
   - *Se hereda por todas las suscripciones, grupos y recursos que cuelgan.*
3. ¿Qué ocurre si ejecutas `az group delete` sobre un grupo?
   - *Se borran todos los recursos que contiene.*
4. ¿Qué diferencia hay entre HA y DR en Azure?
   - *HA = varias zonas de una región; DR = otra región.*
5. ¿Qué es ARM y por qué importa?
   - *Es la API por la que pasa todo (portal, CLI, Terraform); por eso todo es consistente.*
6. ¿Qué parte de la seguridad es siempre tuya aunque uses PaaS?
   - *Datos, accesos, qué es público, secretos.*
7. Nombra tres cosas que inflan la factura sin avisar.
   - *Tráfico de salida, IP públicas/balanceadores ociosos, discos sin adjuntar, clústeres encendidos, retención de logs.*
8. ¿Qué comando ejecutas antes de crear recursos para no equivocarte de suscripción?
   - *`az account show`.*

## Entrevista
- ¿Cómo organizarías suscripciones para una empresa con dev, qa y prod?
- ¿Por qué usar IaC en lugar del portal?
- ¿Cuándo eliges PaaS y cuándo AKS?
- Explica con tus palabras qué es un tenant y qué es una suscripción, y por qué no son lo mismo.
