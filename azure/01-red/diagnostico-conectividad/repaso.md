# Azure · Diagnóstico de conectividad · Repaso

## Preguntas de repaso
1. ¿Qué significan las letras de RPDSI?
   - *Ruta, Permiso (de red), DNS, Servicio, Identidad.*
2. Un nombre resuelve a IP pública pese a haber Private Endpoint: ¿qué revisas?
   - *Que la zona privada esté enlazada a la VNet desde donde se consulta.*
3. ¿Qué diferencia hay entre un timeout y un `connection refused`?
   - *Timeout: los paquetes se pierden (ruta/firewall). Refused: llegas pero nadie escucha.*
4. ¿Qué te dice un 403 sobre la red?
   - *Que ya funcionó; el problema es de identidad (o del firewall del servicio).*
5. ¿Qué herramienta te dice qué regla de NSG negó un paquete?
   - *IP flow verify de Network Watcher.*
6. ¿Por qué se prueba desde el mismo lugar donde corre la app?
   - *Porque DNS, rutas y reglas dependen del origen.*
7. ¿Cuál es el primer escalón antes del DNS?
   - *Saber qué cambió.*
8. ¿Cuándo reintentar y cuándo no?
   - *Reintentar fallos transitorios; un error de DNS o de regla no se arregla reintentando.*

## Entrevista
- "Un pod no puede conectarse a la base de datos". ¿Qué haces, paso a paso?
- Diseña la red de una API con App Gateway, APIM, AKS y SQL, todo privado.
- ¿Cómo garantizas con políticas que nadie cree una base de datos con IP pública?
