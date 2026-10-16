// Subida directa desde el navegador con una SAS de escritura, en bloques paralelos.
// Flujo: 1) pide la SAS a tu API  2) PUT de bloques (Put Block)  3) Put Block List  4) confirma a tu API.
// Requiere CORS en el servicio Blob (origen, PUT, cabeceras x-ms-*).
// Sin dependencias: fetch + Blob.slice (navegadores modernos y Node 18+).

const TAMANO_BLOQUE = 8 * 1024 * 1024; // 8 MiB
const PARALELISMO = 4;

function idBloque(indice) {
  // Los ids de bloque deben tener la MISMA longitud dentro del blob y ir en base64.
  return btoa(String(indice).padStart(8, "0"));
}

async function pedirSas(apiBase, token, archivo) {
  const r = await fetch(`${apiBase}/archivos/solicitud-subida`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ contentType: archivo.type, tamanoDeclarado: archivo.size }),
  });
  if (!r.ok) throw new Error(`La API rechazó la subida: HTTP ${r.status}`);
  return r.json(); // { id, url, cabeceras, vence }
}

async function subirBloque(urlSas, indice, trozo, reintentos = 3) {
  const url = `${urlSas}&comp=block&blockid=${encodeURIComponent(idBloque(indice))}`;
  for (let intento = 1; ; intento++) {
    const r = await fetch(url, { method: "PUT", body: trozo });
    if (r.ok) return;
    // 5xx y 429 se reintentan con espera exponencial; el resto (403 SAS inválida, etc.) no
    if (intento >= reintentos || (r.status < 500 && r.status !== 429)) {
      throw new Error(`Bloque ${indice}: HTTP ${r.status}`);
    }
    await new Promise((ok) => setTimeout(ok, 500 * 2 ** intento));
  }
}

export async function subirArchivo(apiBase, token, archivo, alProgreso = () => {}) {
  const { id, url, cabeceras } = await pedirSas(apiBase, token, archivo);
  const total = Math.ceil(archivo.size / TAMANO_BLOQUE);
  let siguiente = 0;
  let hechos = 0;

  async function trabajador() {
    while (siguiente < total) {
      const i = siguiente++;
      await subirBloque(url, i, archivo.slice(i * TAMANO_BLOQUE, (i + 1) * TAMANO_BLOQUE));
      alProgreso(++hechos / total);
    }
  }
  await Promise.all(Array.from({ length: Math.min(PARALELISMO, total) }, trabajador));

  // Confirmar la lista de bloques: SOLO ahora existe el blob (y se emite BlobCreated)
  const lista =
    `<?xml version="1.0" encoding="utf-8"?><BlockList>` +
    Array.from({ length: total }, (_, i) => `<Latest>${idBloque(i)}</Latest>`).join("") +
    `</BlockList>`;
  const r = await fetch(`${url}&comp=blocklist`, {
    method: "PUT",
    headers: { "Content-Type": "application/xml", "x-ms-blob-content-type": cabeceras["Content-Type"] },
    body: lista,
  });
  if (!r.ok) throw new Error(`Put Block List: HTTP ${r.status}`);

  // Avisar a tu API: ella valida tamaño/tipo reales y encola el procesamiento
  const c = await fetch(`${apiBase}/archivos/${id}/confirmar`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!c.ok) throw new Error(`Confirmación rechazada: HTTP ${c.status}`);
  return c.json();
}
