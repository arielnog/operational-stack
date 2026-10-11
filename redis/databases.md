# Redis — Alocação de Databases

O Redis compartilhado usa **database numbers** para isolar dados entre aplicações. Cada app usa um número dedicado.

## Reservado

| DB | Uso |
|----|-----|
| **0** | Reservado (padrão) — não usar em produção |

## Alocação por app

| DB | App | Observações |
|----|-----|-------------|
| 1 | notification-price | Filas (async-queue), dedupe de promos, índice de termos e rate limit |
| ... | ... | Registrar novas apps aqui |

## Conexão

```
redis://:SENHA@redis:6379/1
```

O `/1` no final indica o database number.

## Política de memória

O Redis compartilhado roda com `maxmemory 256mb`, `maxmemory-policy noeviction` e AOF
(`appendonly yes`, `appendfsync everysec`).

- Com a memória cheia, **escritas falham** com erro `OOM`. Nada é apagado automaticamente.
- Por isso, toda chave de cache precisa de TTL (`SET ... EX`, `EXPIRE`).
- Filas, índices e dados que não podem sumir podem ficar aqui com segurança.
- Monitore `used_memory` (`redis-cli -a SENHA info memory`) e suba o `maxmemory` se ficar perto do teto.

## Quando usar Redis dedicado

Use um Redis separado no compose da app apenas se:

- Depender de eviction automática (cache sem TTL que conta com LRU) ou de outra política incompatível com o compartilhado
- Tiver configuração específica que impacte outras apps
- O isolamento por database não for suficiente
