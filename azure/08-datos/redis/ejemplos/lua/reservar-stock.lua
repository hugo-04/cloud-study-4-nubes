-- Reserva atómica de stock: descuenta ARGV[1] unidades solo si alcanza (nunca queda negativo).
-- KEYS[1] = hash del producto (campo "disponible") | ARGV[1] = cantidad solicitada
-- Devuelve el stock restante, o -1 si no alcanza, o -2 si el producto no existe.
local disponible = redis.call('HGET', KEYS[1], 'disponible')
if not disponible then
  return -2
end
local pedido = tonumber(ARGV[1])
if tonumber(disponible) < pedido then
  return -1
end
return redis.call('HINCRBY', KEYS[1], 'disponible', -pedido)
