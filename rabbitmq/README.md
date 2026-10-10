# RabbitMQ — vhosts e usuários por app

O RabbitMQ compartilhado isola as aplicações por **vhost**. Cada app tem um vhost e um usuário próprios,
com permissão só no seu vhost. O usuário administrador (`RABBITMQ_ADMIN_USER`) não é usado pelas apps.

## Alocação por app

| Vhost | Usuário | App | Observações |
|-------|---------|-----|-------------|
| notification-price | notification-price | notification-price | Entrada de promoções (telegram-reader) e de mensagens da Evolution (instância bot) |
| ... | ... | ... | Registrar novas apps aqui |

## Criar vhost e usuário de uma app

```bash
APP=notification-price
docker exec rabbitmq rabbitmqctl add_vhost "$APP"
docker exec rabbitmq rabbitmqctl add_user "$APP" '<senha forte>'
docker exec rabbitmq rabbitmqctl set_permissions -p "$APP" "$APP" '.*' '.*' '.*'
# Só se a app lê métricas pela API de gerenciamento (ex.: profundidade das filas):
docker exec rabbitmq rabbitmqctl set_user_tags "$APP" monitoring
```

## Conexão

```
amqp://USUARIO:SENHA@rabbitmq:5672/VHOST
```

A app (e quem publica para ela, como a Evolution) precisa estar na rede `infra_internal`.

## Painel de gerenciamento

Fica só na rede interna (porta 15672, sem rota no Traefik). Para abrir do seu computador:

```bash
ssh -L 15672:$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' rabbitmq):15672 usuario@vps
# depois: http://localhost:15672
```

## Filas

Prefira filas **quorum** (duráveis e replicáveis). Mensagens que precisam sobreviver a reinício devem ser
publicadas como persistentes.
