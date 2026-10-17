-- KEYS[1] = clave del candado; ARGV[1] = ficha del dueño
-- Solo borra si la ficha coincide: nunca sueltes el candado de otro.
if redis.call('GET', KEYS[1]) == ARGV[1] then
  return redis.call('DEL', KEYS[1])
end
return 0
