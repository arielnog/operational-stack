# RabbitMQ — vhosts e usuários por app

O RabbitMQ compartilhado isola as aplicações por **vhost**. Cada app tem um vhost e um usuário próprios,
com permissão só no seu vhost. O usuário administrador (`RABBITMQ_ADMIN_USER`) não é usado pelas apps.

## Alocação por app

| Vhost | Usuário | App | Observações |
|-------|---------|-----|-------------|
| notification-price | notification-price | notification-price | Entrada de promoções (telegram-reader) e de mensagens da Evolution (instância bot) |
| ... | ... | ... | Registrar novas apps aqui |

## Criar vhost e usuário de uma app

Um **vhost** é um espaço isolado dentro do RabbitMQ, com filas e exchanges próprios (como um banco separado
no Postgres). O usuário da app só enxerga o vhost dela. A senha do usuário é nova e diferente da do
administrador; gere com `openssl rand -hex 24` (só hexadecimal, para não precisar escapar na URL de conexão).

Os comandos rodam na VPS, de qualquer pasta: `docker exec rabbitmq` executa dentro do container, e o
`rabbitmqctl` é a ferramenta de administração do RabbitMQ.

```bash
APP=notification-price

# Cria o vhost da app.
docker exec rabbitmq rabbitmqctl add_vhost "$APP"

# Cria o usuário da app, com a senha gerada.
docker exec rabbitmq rabbitmqctl add_user "$APP" 'SENHA_GERADA'

# Permissão para configurar, publicar e consumir (os três '.*'), só dentro do vhost da app.
docker exec rabbitmq rabbitmqctl set_permissions -p "$APP" "$APP" '.*' '.*' '.*'

# Só se a app lê estatísticas das filas pela API de gerenciamento (o notification-price lê).
docker exec rabbitmq rabbitmqctl set_user_tags "$APP" monitoring

# Confere as permissões.
docker exec rabbitmq rabbitmqctl list_permissions -p "$APP"
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
