-- KEYS[1] = clave de la ventana; ARGV[1] = segundos de vida de la ventana
-- INCR y EXPIRE como una sola operación atómica: sin esto una caída entre ambos deja un contador eterno.
local c = redis.call('INCR', KEYS[1])
if c == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
return c
