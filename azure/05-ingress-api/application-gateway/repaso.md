# Azure · Application Gateway · Repaso

## Preguntas de repaso
1. ¿Qué es Application Gateway y en qué capa trabaja?
   - *Balanceador L7 regional dentro de tu VNet, con WAF opcional.*
2. Nombra el camino de una petición: de qué piezas pasa.
   - *Frontend IP → listener → WAF → regla → configuración HTTP → pool (con la sonda vigilando).*
3. ¿Por qué necesita una subred dedicada y qué reglas de NSG exige?
   - *Instancias y autoescala gestionadas por Azure; permitir GatewayManager 65200–65535, AzureLoadBalancer y los puertos de los listeners.*
4. ¿Qué significa un 502 y cómo empiezas a investigarlo?
   - *Backend no sano o inalcanzable; con `show-backend-health`.*
5. ¿Qué hace la cabecera Host y por qué rompe cosas?
   - *El backend enruta/redirige según el host; si no coincide hay 404, redirecciones o cookies erróneas.*
6. Diferencia entre terminación de TLS y TLS extremo a extremo.
   - *En la primera el backend recibe HTTP; en la segunda hay un segundo TLS y hay que confiar en su certificado.*
7. ¿Cómo evitas certificados vencidos?
   - *Referencia a Key Vault sin versión, identidad administrada y alertas.*
8. ¿Detection vs Prevention?
   - *Detection registra; Prevention bloquea con 403. Empieza en Detection.*
9. ¿Cómo tratas un falso positivo?
   - *Revisar el log del WAF y excluir el campo/regla en esa ruta, sin apagar el WAF.*
10. ¿Cómo llega la IP del cliente al backend y qué problema tiene?
    - *`X-Forwarded-For` con puerto; hay que normalizarla y confiar solo en el gateway.*
11. ¿Cuándo no usarías Application Gateway?
    - *Entrada global (Front Door), políticas de API (APIM), Kubernetes con Gateway API (AGC), tráfico no HTTP.*
12. ¿Qué componentes de costo tiene?
    - *Tarifa fija por hora + unidades de capacidad + datos; WAF_v2 cuesta más.*

## Entrevista
- Diseña la entrada regional de una API con WAF y un App Service privado.
- ¿Cómo actualizas el certificado sin downtime?
- Tu gateway da 502 después de un despliegue: describe los pasos.
- ¿Cómo permites solo tráfico del gateway en el backend?

## Ejercicio práctico
1. Despliega el Terraform de [ejemplos/terraform](ejemplos/terraform/main.tf) y revisa *Backend health*.
2. Rompe la sonda (ruta inexistente) y observa el 502; arréglala.
3. Provoca un falso positivo con un cuerpo con `' OR 1=1` y crea una exclusión.
4. Cambia el certificado en Key Vault (nueva versión) y comprueba la rotación.
