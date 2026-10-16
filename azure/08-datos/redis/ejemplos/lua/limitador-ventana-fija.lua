-- Limitador de tasa por ventana fija: máximo ARGV[1] solicitudes cada ARGV[2] segundos por clave.
-- KEYS[1] = clave (por ejemplo, limite:api:C-001) | ARGV[1] = máximo | ARGV[2] = segundos de la ventana
-- Devuelve {permitido (1/0), usadas, segundos_restantes}
local usadas = redis.call('INCR', KEYS[1])
if usadas == 1 then
  redis.call('EXPIRE', KEYS[1], tonumber(ARGV[2]))
end
local ttl = redis.call('TTL', KEYS[1])
if ttl < 0 then            -- la clave quedó sin vencimiento (carrera rara): reponerlo
  redis.call('EXPIRE', KEYS[1], tonumber(ARGV[2]))
  ttl = tonumber(ARGV[2])
end
if usadas > tonumber(ARGV[1]) then
  return {0, usadas, ttl}
end
return {1, usadas, ttl}
