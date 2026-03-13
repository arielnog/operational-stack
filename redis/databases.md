# Redis — Alocação de Databases

O Redis compartilhado usa **database numbers** para isolar dados entre aplicações. Cada app usa um número dedicado.

## Reservado

| DB | Uso |
|----|-----|
| **0** | Reservado (padrão) — não usar em produção |

## Alocação por app

| DB | App | Observações |
|----|-----|-------------|
| 1 | *minha_api* | Exemplo |
| 2 | *outra_app* | Exemplo |
| ... | ... | Registrar novas apps aqui |

## Conexão

```
redis://:SENHA@redis:6379/1
```

O `/1` no final indica o database number.

## Quando usar Redis dedicado

Use um Redis separado no compose da app apenas se:

- Exigir `noeviction` ou política incompatível com o compartilhado
- Tiver configuração específica que impacte outras apps
- O isolamento por database não for suficiente
