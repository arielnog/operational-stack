# Tailscale no ecossistema arnsolutions.tech

Oct 16, 2026 · @Ariel Nogueira

## Visão geral

O objetivo é um único tailnet com dois nós (VPS e iPhone; o Home Assistant entra numa etapa futura), em que o iPhone acessa tudo o que é administrativo sem nenhuma porta aberta na internet. O que é público (site do casamento, APIs, webhooks) continua saindo por Cloudflare + Traefik como hoje.

O iPhone é o único ponto que inicia conexões no tailnet; a VPS continua recebendo o tráfego público só pela Cloudflare.

Princípios:

- **Uma fase por vez, com validação no fim de cada uma.** Só avance quando o checkpoint passar.
- **Nunca feche um acesso antes de testar o novo.** A porta 22 pública só sai depois do SSH via tailnet funcionar.
- **Público e administrativo separados.** Público = Cloudflare. Administrativo = tailnet.
- **Menor privilégio.** Servidores não iniciam conexão com o iPhone nem com a rede de casa.

| Fase | Entrega | Risco | Tempo estimado |
| --- | --- | --- | --- |
| 0. Preparação | Conta, tags, MagicDNS, plano B | Baixo | 15 min |
| 1. iPhone | Celular no tailnet | Baixo | 5 min |
| 2. VPS | SSH via tailnet, porta 22 fechada | Médio (lockout) | 30 min |
| 3. Serviços internos | Grafana, Metabase etc. só via tailnet | Médio | 1–2 h |
| 4. ACLs | Regras de menor privilégio | Médio (corte de acesso) | 30 min |

## Fase 0 — Preparação

Antes de instalar qualquer coisa, deixe a conta, as tags e o plano B prontos. A tag precisa existir na política **antes** de um nó tentar usá-la, senão o `tailscale up` falha.

1. Crie a conta em login.tailscale.com (plano Personal, gratuito). Use um login que você não vai perder (Google ou GitHub com 2FA).
2. Em **DNS**, confirme que o **MagicDNS** está ativo e anote o nome do tailnet (`<algo>.ts.net`).
3. Em **Access controls**, adicione o dono das tags e uma regra de SSH para nós com tag, mantendo o resto da política padrão. Sem essa regra, a conexão da Fase 2.2 é recusada, porque a regra SSH padrão (autogroup:self) só cobre seus dispositivos pessoais, não nós com tag:

```json
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"]
  },
  "ssh": [
    // mantenha a regra padrão que já existe aqui e acrescente:
    {
      "action": "accept",
      "src":    ["autogroup:member"],
      "dst":    ["tag:server"],
      "users":  ["root", "autogroup:nonroot"]
    }
  ]
}
```

4. **Plano B da VPS:** abra o console web/VNC da VPS no painel da Hostinger e confirme que consegue logar por ele. É a saída se o SSH ficar inacessível.

**Checkpoint:** MagicDNS ativo, tags salvas sem erro na política, console da Hostinger testado.

## Fase 1 — iPhone

O iPhone entra primeiro porque é o cliente que vai validar todas as fases seguintes.

1. Instale o app **Tailscale** pela App Store.
2. Faça login com a mesma conta da Fase 0 e aceite o perfil de VPN do iOS.
3. No app, em **Settings**, deixe **Use Tailscale DNS** ligado.
4. Por enquanto, **não** ative VPN On Demand nem exit node. Isso fica para depois, quando tudo estiver estável.
5. Instale um cliente SSH para as próximas fases (Termius ou Blink Shell).

**Checkpoint:** o iPhone aparece em **Machines** no admin console com um IP `100.x.y.z`, e o app mostra o status *Connected*.

## Fase 2 — VPS (Hostinger)

O Tailscale vai no **host**, não em container. Assim o SSH e o Traefik ficam acessíveis pelo IP `100.x` sem mexer nas redes Docker (`traefik_public`, `infra_internal`, `infra_data`, `observability`).

### 2.1 Instalar e subir

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh --advertise-tags=tag:server --hostname=vps
sudo tailscale set --snat-subnet-routes=false
```

O segundo comando é necessário para a Fase 3. Sem ele, o Tailscale faz masquerade do tráfego que o Docker redireciona para o container do Traefik: o Traefik passa a ver `172.20.0.1` em vez do IP `100.x` do iPhone, e o `tailnet-only` responde 403 para tudo. Use `tailscale set`, não `tailscale up`, para não ter que repetir as outras flags.

Abra o link de autenticação que aparece no terminal e aprove. Nós com tag têm o key expiry desativado automaticamente; confira em **Machines** que a VPS aparece sem data de expiração.

### 2.2 Testar o acesso novo (sem fechar nada ainda)

No iPhone, com o Tailscale conectado, abra o Termius e conecte em `root@vps` (ou no IP `100.x` da VPS). Teste também do seu notebook, se ele estiver no tailnet.

Use o usuário `root` e não configure senha nem chave no Termius: o Tailscale SSH autentica pela identidade do iPhone no tailnet.

**Se a conexão falhar** depois de `Remote server: SSH-2.0-Tailscale`, a rede está OK e o problema é autorização: falta a regra `ssh` com `dst: tag:server` da Fase 0, ou ela está em modo `check` (o Termius não lida bem com a reautenticação no navegador). Corrija a política e tente de novo.

**Alternativa sem Tailscale SSH:** rode `sudo tailscale set --ssh=false` na VPS. O `sshd` normal passa a responder no IP `100.x` com a sua chave de sempre, e o restante desta fase continua igual.

### 2.3 Firewall

Pré-requisitos (não pule nenhum):

1. SSH pelo tailnet testado e funcionando (2.2).
2. Senha do root definida (`sudo passwd root`) e login testado no **Browser terminal** do hPanel. Esse terminal é um console VNC: não depende da porta 22 nem do UFW, e é o plano B se o acesso pelo tailnet cair.
3. Uma sessão SSH aberta durante as mudanças. O UFW não derruba conexões já estabelecidas, então ela serve para desfazer qualquer erro.

```bash
# 1. Garantir o acesso pelo tailnet e as conexões diretas do Tailscale
sudo ufw allow in on tailscale0
sudo ufw allow 41641/udp

# 2. Listar as regras e localizar as da porta 22
#    Podem aparecer como ALLOW ou LIMIT, e existem em IPv4 e IPv6 (v6)
sudo ufw status numbered

# 3. Apagar as regras da porta 22 pelo número, sempre da MAIOR para a menor
#    (ao apagar uma regra, as de baixo sobem de número)
sudo ufw --force delete <N_maior>   # ex.: 22/tcp (v6)
sudo ufw --force delete <N_menor>   # ex.: 22/tcp

# 4. Conferir: nenhuma regra de 22 deve sobrar, e tailscale0 continua liberado
sudo ufw status numbered
```

`ufw delete allow 22/tcp` só funciona se a regra for exatamente `ALLOW`. Regras criadas com `ufw limit` aparecem como `LIMIT` e precisam ser apagadas pelo número. Para desfazer, rode `sudo ufw limit 22/tcp` na sessão que ficou aberta (ou no Browser terminal).

Repita o mesmo no **firewall do painel da Hostinger**, removendo a regra da porta 22 se existir.

Atenção: portas publicadas pelo Docker (`ports:` no compose) **ignoram o UFW**. Isso não afeta o SSH, mas é por isso que a Fase 3 usa `ipAllowList` no Traefik em vez de confiar só no firewall.

As regras `DENY` do UFW para Postgres, Redis, Loki etc. também não protegem nada se essas portas estiverem publicadas pelo Docker. Confira:

```bash
docker ps --format '{{.Names}}\t{{.Ports}}' | grep 0.0.0.0
```

Qualquer porta diferente de 80 e 443 nessa lista está exposta na internet. Remova o `ports:` do serviço ou troque por `127.0.0.1:<porta>:<porta>`.

**Checkpoint:**

- `ssh root@<IP público>` de fora do tailnet → *timeout*.
- `ssh root@vps` pelo iPhone → entra.
- `tailscale status` na VPS mostra o iPhone.

## Fase 3 — Serviços internos da VPS via tailnet

Os painéis administrativos (Grafana, Metabase, Portainer etc.) passam a responder só para quem está no tailnet, com TLS válido e sem Cloudflare Access. Migre **um serviço por vez**, começando pelo Grafana.

### 3.1 Decidir o que fica público e o que vira interno

| Serviço | Destino | Motivo |
| --- | --- | --- |
| Site do casamento | Público (Cloudflare) | Convidados acessam |
| APIs e webhooks (Evolution API, bots) | Público (Cloudflare) | Chamados por terceiros |
| Grafana, Metabase | Interno (tailnet) | Só você usa |
| Portainer, painéis de banco, Traefik dashboard | Interno (tailnet) | Administrativo |

Ajuste a tabela com os serviços que você realmente roda.

### 3.2 DNS na Cloudflare

Para cada serviço interno, crie um registro **A** apontando para o IP `100.x` da VPS, com o proxy **desligado** (nuvem cinza):

- `grafana.int.arnsolutions.tech → 100.x.y.z`
- `metabase.int.arnsolutions.tech → 100.x.y.z`

O IP `100.x` só é alcançável de dentro do tailnet, então publicar o registro não expõe nada.

### 3.3 Certificado por DNS challenge

O Let's Encrypt não consegue chegar num IP `100.x`, então o HTTP challenge falha. Confirme que o resolver do Traefik usa o DNS da Cloudflare (crie um token com permissão *Zone → DNS → Edit*, se ainda não tiver):

```yaml
# traefik.yml (estático)
certificatesResolvers:
  cloudflare:
    acme:
      email: voce@arnsolutions.tech
      storage: /letsencrypt/acme.json
      dnsChallenge:
        provider: cloudflare
        resolvers:
          - 1.1.1.1:53
```

```yaml
# docker-compose do Traefik
environment:
  - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
```

### 3.4 Middleware de allowlist

Portas publicadas pelo Docker ignoram o UFW, e alguém pode bater no IP público com o header `Host: grafana.int...`. O middleware fecha essa brecha:

```yaml
# dynamic/middlewares.yml
http:
  middlewares:
    tailnet-only:
      ipAllowList:
        sourceRange:
          - 100.64.0.0/10
```

### 3.5 Labels do serviço (exemplo: Grafana)

```yaml
services:
  grafana:
    networks: [traefik_public, observability]
    labels:
      - traefik.enable=true
      - traefik.docker.network=traefik_public
      - traefik.http.routers.grafana-int.rule=Host(`grafana.int.arnsolutions.tech`)
      - traefik.http.routers.grafana-int.entrypoints=websecure
      - traefik.http.routers.grafana-int.tls.certresolver=cloudflare
      - traefik.http.routers.grafana-int.middlewares=tailnet-only@file
      - traefik.http.services.grafana.loadbalancer.server.port=3000
```

### 3.6 Desligar o caminho antigo

Depois de validar o novo endereço por uns dias: remova o router público antigo do serviço, apague o registro proxied correspondente na Cloudflare e remova a aplicação do Cloudflare Access.

**Checkpoint (por serviço):**

- iPhone com Tailscale → `https://grafana.int.arnsolutions.tech` abre com cadeado válido.
- iPhone sem Tailscale (4G) → não resolve ou dá timeout.
- `curl -k -H 'Host: grafana.int.arnsolutions.tech' https://<IP público>` de fora → **403**.

## Fase 4 — ACLs e endurecimento

A política padrão do Tailscale deixa todo nó falar com todo nó. A política abaixo deixa seus dispositivos pessoais acessarem tudo, mas impede que a VPS (exposta à internet) inicie conexão com o iPhone.

### 4.1 Política

Substitua a política em **Access controls**:

```json
{
  "tagOwners": {
    "tag:server": ["autogroup:admin"]
  },
  "acls": [
    { "action": "accept", "src": ["autogroup:member"], "dst": ["*:*"] }
  ],
  "ssh": [
    {
      "action": "accept",
      "src":    ["autogroup:member"],
      "dst":    ["tag:server"],
      "users":  ["root", "autogroup:nonroot"]
    }
  ],
  "tests": [
    { "src": "arielnog@github", "accept": ["tag:server:22", "tag:server:443"] },
    { "src": "tag:server", "deny": ["arielnog@github:443"] }
  ]
}
```

O que cada parte faz:

- **acls:** só dispositivos pessoais (`autogroup:member`) iniciam conexões. Nós com tag não têm regra de origem, então a VPS não inicia nada. As respostas às conexões que você abre continuam funcionando.
- **ssh `accept`:** entra direto, sem reautenticação. O modo `check` é mais rígido, mas exige abrir uma URL no navegador durante a conexão e costuma falhar no Termius; use-o só com um cliente que suporte esse fluxo.
- **tests:** a política é rejeitada ao salvar se as regras quebrarem o acesso dos seus dispositivos ao SSH e ao HTTPS da VPS (`accept`), ou se a VPS passar a conseguir iniciar conexão com eles (`deny`). O `src` dos testes precisa ser um usuário, grupo, tag ou host real; autogroups como `autogroup:member` dão erro `unknown user or host`.

### 4.2 Endurecimento extra

- Ative 2FA na conta usada para logar no Tailscale.
- Mantenha o Tailscale atualizado na VPS com `sudo tailscale set --auto-update` (já ativo). O repositório apt do script de instalação não entra no unattended-upgrades, então sem isso ele só atualiza com `apt upgrade` manual.
- Em **Settings → Device approval**, ative a aprovação manual de novos dispositivos.

**Checkpoint:** a política salva sem erro de teste. Na VPS, `tailscale debug netmap | grep -A4 '"SrcIPs"'` lista só os IPs dos seus dispositivos (não o range `100.64.0.0-...` inteiro), e do iPhone para a VPS tudo continua funcionando. Não use `tailscale ping` como teste: ele pode dar timeout com o iPhone em segundo plano mesmo sem ACL.

## Checklist final, rollback e troubleshooting

### Checklist

- [x] Fase 0: MagicDNS e tags configurados; console da Hostinger testado
- [x] Fase 1: iPhone no tailnet
- [x] Fase 2: SSH via tailnet funcionando; porta 22 pública fechada (UFW e painel Hostinger)
- [x] Fase 3: Grafana, Metabase e Traefik dashboard via `*.int.arnsolutions.tech`; Cloudflare Access antigo removido
  - [ ] Remover o router público `traefik.arnsolutions.tech` e o registro proxied na Cloudflare, depois de validar o `traefik.int`
- [x] Fase 4: política com ACLs salva e testes passando; 2FA no GitHub

### Rollback

| Situação | Como voltar |
| --- | --- |
| Perdeu o SSH da VPS | Console da Hostinger → `sudo ufw limit 22/tcp` |
| Tailscale quebrou algo na VPS | `sudo tailscale down` (o resto da VPS segue igual) |
| Serviço interno inacessível | Reative o router público antigo e o registro proxied na Cloudflare |
| ACL cortou acesso | Volte a política para a versão anterior no histórico do admin console |

### Troubleshooting

| Sintoma | Diagnóstico | Correção comum |
| --- | --- | --- |
| SSH falha após `SSH-2.0-Tailscale` | Sem regra `ssh` para `tag:server`, ou modo `check` | Regra `accept` com `dst: tag:server` (Fase 0) |
| Conexão lenta | `tailscale status` mostra `relay` | Libere `41641/udp` no UFW e no painel da Hostinger |
| `tailscale up` falha com tag | Tag não existe na política | Adicione em `tagOwners` (Fase 0) |
| `*.int` não resolve no iPhone | DNS do Tailscale desligado ou registro proxied | Ligue *Use Tailscale DNS*; deixe a nuvem cinza na Cloudflare |
| Certificado inválido no `*.int` | HTTP challenge em vez de DNS | Use o resolver `cloudflare` com `dnsChallenge` |
| 403 mesmo no tailnet | `ClientHost` no access log do Traefik é `172.20.0.1`, não `100.x` | `sudo tailscale set --snat-subnet-routes=false` na VPS (Fase 2.1) |

Comandos úteis: `tailscale status`, `tailscale ping <nó>`, `tailscale netcheck`, `tailscale debug prefs`.
