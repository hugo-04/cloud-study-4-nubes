# Google Cloud · Storage · URLs firmadas · Casos reales

## 1. La URL reenviada
**Qué pasó:** un cliente de ModaLima reenvió el enlace de su comprobante; funcionó días después.
**Causa:** URL de 7 días incluida en el correo.
**Arreglo:** el correo lleva un enlace al portal; la URL se firma al hacer clic, por 10 minutos.
**Lección:** firma en el momento de usar.

## 2. «SignatureDoesNotMatch» en el navegador
**Qué pasó:** las subidas fallaban desde el navegador.
**Causa:** se firmó con `Content-Type: image/jpeg` y el navegador enviaba `image/jpg`.
**Arreglo:** el backend devuelve el tipo exacto y el frontend lo usa.
**Lección:** lo firmado debe coincidir al byte.

## 3. La llave para firmar
**Qué pasó:** un servicio de Café Andino guardaba una llave JSON solo para firmar URLs.
**Causa:** se desconocía `signBlob`.
**Arreglo:** firmar con la cuenta adjunta vía IAM Credentials; llave revocada.
**Lección:** también se firma sin llaves.

## 4. La foto que pisó otra
**Qué pasó:** dos subidas con el mismo nombre se reemplazaron.
**Causa:** la URL PUT no exigía inexistencia.
**Arreglo:** cabecera firmada `x-goog-if-generation-match: 0` y nombres con id único.
**Lección:** las precondiciones también se firman.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Enlace eterno | Vencimiento largo | Firmar al usar |
| 2 | Firma inválida | Cabecera distinta | Tipo exacto |
| 3 | Llave innecesaria | Desconocer signBlob | Firma sin llave |
| 4 | Objeto pisado | Sin precondición | Generation-match 0 |
