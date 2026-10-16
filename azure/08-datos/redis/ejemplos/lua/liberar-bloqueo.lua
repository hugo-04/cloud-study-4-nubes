-- Libera un bloqueo SOLO si todavía es nuestro (el valor coincide con el token de quien lo tomó).
-- KEYS[1] = clave del bloqueo | ARGV[1] = token del dueño
-- Devuelve 1 si lo liberó, 0 si ya no era nuestro (expiró y lo tomó otro).
if redis.call('GET', KEYS[1]) == ARGV[1] then
  return redis.call('DEL', KEYS[1])
else
  return 0
end
