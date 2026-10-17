# Oracle OCI · Caso integrado · Runbook de diagnóstico · Troubleshooting (del propio runbook)

## Lista ordenada
1. **¿Las alarmas tienen datos?** Una alarma sin datos no dispara: revisa la consulta MQL y el namespace.
2. **¿La sonda prueba lo correcto?** Debe recorrer el flujo real (login → carrito → checkout de prueba).
3. **¿La guardia recibe?** Suscripciones confirmadas y prueba mensual.
4. **¿El triage tiene permisos?** «No se pudo comprobar» es un hallazgo.
5. **¿Las mitigaciones están probadas?** Revertir, escalar y drenar ensayados en no-prod.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Alarma nunca dispara | MQL o dimensiones erradas | Prueba la consulta en el explorador de métricas |
| Alarmas en cascada | Una por componente | Alarma compuesta por síntoma |
| Triage dice «desconocido» | Falta `read` | Política de lectura |
| Reversión lenta | Sin artefacto anterior listo | Conservar la versión previa desplegable |
| Nadie atiende | Suscripción pendiente | Confirmar y probar |
