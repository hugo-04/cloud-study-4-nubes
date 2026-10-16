# Azure · Private Endpoint y DNS · Repaso

## Preguntas de repaso
1. ¿Qué crea Azure en tu subnet cuando creas un Private Endpoint?
   - *Una NIC con IP privada unida al servicio destino.*
2. ¿Por qué un PE sin enlace DNS no funciona?
   - *El nombre sigue resolviendo a la IP pública.*
3. ¿Qué hace el DNS zone group?
   - *Crea y mantiene el registro A del PE en la zona privada.*
4. ¿Cuántos PE necesito si uso Blob y Queue de la misma cuenta?
   - *Dos (uno por sub-recurso), cada uno con su zona.*
5. ¿Qué diferencia hay entre Service Endpoint y Private Endpoint?
   - *El SE sigue usando la IP pública; el PE da IP privada, alcanza on-premises y permite cerrar todo acceso público.*
6. ¿Qué IP usa `168.63.129.16`?
   - *Es el DNS virtual de la plataforma; los DNS propios deben reenviarle las zonas privadas.*
7. ¿Por qué no se conecta por IP al PE?
   - *El certificado TLS es válido para el nombre, no para la IP.*
8. ¿Cuándo cierras el acceso público del servicio?
   - *Después de verificar que el acceso privado funciona.*

## Entrevista
- Un pod devuelve 403 al leer un blob y `nslookup` muestra IP pública: explica qué pasa.
- Diseña el DNS para un hub-and-spoke con 5 spokes y una oficina conectada por VPN.
- ¿Cómo evitas, con políticas, que alguien cree un storage con acceso público?
