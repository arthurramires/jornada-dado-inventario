# Decisões

As quatro decisões pedidas na atividade, com o que o código faz, por que e onde está. Os números são dos dados de `data/raw/`.

## 1. Arquitetura de armazenamento

Usamos Medallion com uma pasta a mais: **Bronze, Silver, Quarentena e Gold**, todas dentro de `data/`. `data/raw/` não conta como camada: é o que a origem entregou, antes do pipeline.

| Camada | Formato | Quem grava | O que tem |
|---|---|---|---|
| Bronze | Delta Lake | `src/ingest.py` | As três fontes como chegaram, tudo texto, mais `_arquivo_origem` e `_ingerido_em` |
| Silver | Parquet | dbt | Tipado, padronizado, sem repetição. Um modelo por fonte |
| Quarentena | Parquet | dbt | Leituras que não casam com nenhum bem da carga, com o motivo |
| Gold | Parquet | dbt | Estrela: `fato_bem_inventariado`, `dim_area`, `dim_origem_leitura` |

**Por que Delta só na Bronze.** A Bronze é a única camada que não dá para refazer a partir de código. As nossas fontes não são arquivos parados:

- a planilha de áreas é editada no lugar pela Coordenadoria. Se alguém corrige uma região hoje, a versão de ontem some;
- as leituras chegam em lotes durante a coleta. Em 2026 foram duas remessas, em 14/08 e 28/08.

Com Delta, cada arquivo recebido vira um commit, e o histórico responde "o que tínhamos no dia X" sem backup. Silver e Gold saem da Bronze com um `dbt build` de poucos segundos. Versionar essas camadas seria guardar duas vezes a mesma informação.

**Append para lote, overwrite para cadastro.** Leitura é evento: o lote novo se soma aos anteriores (`mode="append"`). Planilha de áreas e carga são fotografias: a versão nova substitui a anterior (`mode="overwrite"`), e a anterior continua no histórico.

**Idempotência pelo hash do arquivo.** Cada commit guarda o SHA-256 do arquivo de origem nos metadados do Delta. Se o arquivo já foi gravado, a ingestão não grava de novo. Assim `python -m src.pipeline` pode rodar quantas vezes for preciso sem criar versões falsas, e o histórico só cresce quando a origem muda. Para reconstruir do zero, `scripts/zerar.py` apaga as camadas e o pipeline refaz tudo a partir de `data/raw/`. Conferimos que a resposta sai idêntica antes e depois de zerar.

**Por que Silver separada da Gold.** O número de patrimônio chega de cinco jeitos (`123456`, `00123456`, `123.456`, `" 123456 "`, vazio), e a Gold e a Quarentena precisam do mesmo número normalizado. Na Silver essa regra existe uma vez só. Sem ela, estaria copiada nos dois modelos e um dia os dois discordariam.

**Por que Quarentena é pasta e não filtro.** Ver a decisão 4.

## 2. O grão

**Uma linha da `fato_bem_inventariado` é um bem ativo em carga de uma área, em um exercício de inventário.** A chave é `exercicio + numero_patrimonio`, garantida pelo teste `fato_um_bem_por_exercicio`.

Escolhemos o grão pelo que o gestor pergunta: quantos bens a área precisava encontrar e quantos encontrou. No grão de leitura, que é como os dados chegam, isso não dá certo por dois motivos:

- 140 bens foram lidos duas vezes e contariam dobrado;
- bem não localizado não tem leitura, então nem existiria como linha. E ele é justamente o que mais interessa.

**O que ficou de fora do grão:**

| O quê | Quantos | Onde ficou |
|---|---:|---|
| Bens com situação BAIXADO na carga | 22 (11 por exercício) | Silver. Bem baixado não é cobrado no inventário |
| Leituras que não casam com bem da carga | 24 | Quarentena |
| Leituras reenviadas pelo app | 12 | Descartadas na Silver (mesmo `id_leitura`) |
| Linhas repetidas no export da carga | 4 | Descartadas na Silver |
| Leituras anteriores de um bem lido mais de uma vez | 140 | Só a última vale. `quantidade_leituras` guarda quantas foram |
| Login do coletor | todas | Fica na Bronze. A pergunta não precisa, e dado pessoal que não é usado não circula |

**A taxa não fica gravada.** A fato tem indicadores 0/1 (`localizado_na_area`, `localizado_em_outra_area`, `nao_localizado`) e a consulta faz soma dividida por contagem. Percentual pronto por área não serviria: a taxa de uma região não é a média das taxas das comarcas.

**Estrela, e não tabela larga.** O motivo principal é que a área aparece em dois papéis na mesma linha:

- a área da carga, onde o bem deveria estar;
- a área da leitura, onde ele foi encontrado.

Numa tabela larga seriam dois conjuntos de colunas (nome, tipo, comarca, região) repetidos em cada bem. Com a `dim_area` é a mesma dimensão ligada duas vezes (`consultas/analise.sql`, bloco 4).

Pesou também que a área é a dimensão comum dos outros relatórios do módulo (acompanhamento, termo, pendências), e que a linha "Área não cadastrada" fica num lugar só. O custo é um join a mais na consulta.

A chave da `dim_area` é o próprio código da área no SGM, e não um hash. Existe uma origem só para área, o código é estável, e a linha `-1` fica legível. Se aparecer uma segunda origem de áreas, isso precisa ser revisto.

## 3. O dado ambíguo: bem lido em outra área conta como localizado?

É o nosso "REDE E INTERNET". Em 2026, **106 bens (7,4% da carga) foram lidos numa área diferente da área de carga.** O bem existe e alguém pôs a mão nele, mas não onde o SGM diz que ele está.

Há duas leituras possíveis, e as duas já existiram no Tribunal:

- **SGM antigo:** conta qualquer bem lido como inventariado, inclusive o que foi encontrado em outro local.
- **Módulo novo:** só conta como localizado quando a área da leitura é a área da carga.

A escolha muda o número inteiro (bloco 3 de `consultas/analise.sql`):

| | Critério do SGM antigo | Critério aplicado |
|---|---:|---:|
| Tribunal, 2025 | 91,0% | 82,8% |
| Tribunal, 2026 | 91,2% | 83,8% |
| Rio Brilhante, 2026 | 90,1% | 49,5% |

**Regra que o código aplica:** bem em outra área não conta como localizado. Ele vira uma situação própria, "Localizado em outra área", com indicador e coluna na resposta. Está em `fato_bem_inventariado.sql`.

**Por quê.** Bem em outra área é bem com carga errada. O responsável pela área assina o termo de um bem que não está com ele, e quem está com o bem não responde por ele. Contar como localizado esconde exatamente o problema que o inventário existe para achar.

Rio Brilhante é o caso: 37 dos 91 bens estão nas varas de Dourados. Pelo critério antigo a comarca teria 90% e ninguém olharia para lá. Pelo nosso tem 49,5%, e o motivo aparece junto: não é perda, é transferência que nunca foi registrada. Mantendo "em outra área" visível, quem preferir o critério antigo ainda consegue somar as duas colunas.

**Quem deveria decidir.** A Coordenadoria de Inventário, que é dona do processo e do termo de inventário, com a Secretaria de Material e Patrimônio. Não é decisão de desenvolvedor: muda o percentual de todas as áreas. No projeto real essa pergunta já apareceu e foi levada à preceptora, que fechou a favor do critério do módulo novo. Aqui seguimos a mesma regra e registramos a divergência com o legado.

**Outras escolhas menores que também mexem no número:**

| Situação | Regra aplicada | Onde |
|---|---|---|
| Bem lido duas vezes, em áreas diferentes (17 casos) | Vale a última leitura, como o fluxo de coleta faz quando o coletor escolhe ATUALIZAR | `fato_bem_inventariado.sql` |
| Área 1301 duplicada na planilha | Fica a linha com `atualizado_em` mais recente | `stg_areas.sql` |
| Origem `scanner` e `mobile_*` | Viram `celular` e `manual` pelo de-para (`scanner` é o nome antigo da câmera do celular) | `seeds/de_para_origem_leitura.csv` |
| Em 2025 o app gravava o leitor de código de barras como `manual` | Não reclassificamos. O número com 8 dígitos denuncia 675 leituras de leitor, mas inferir a origem seria inventar dado. O tipo de captura de 2025 não é comparável com o de 2026 | documentado aqui |

## 4. O destino do registro inválido

Não demos uma resposta única. O critério foi: **esse registro diz algo que alguém precisa resolver?**

| Caso | Quantos | Destino | Por quê |
|---|---:|---|---|
| Leitura de número que não está na carga do exercício | 18 | Quarentena, motivo `fora_da_carga` | É achado de inventário: plaqueta sem cadastro, bem que chegou sem tombamento ou número digitado errado. Alguém precisa ir até o bem |
| Leitura sem número de patrimônio | 6 | Quarentena, motivo `patrimonio_ausente` | Não dá para saber que bem é, mas o registro tem área, espaço físico, lote e horário para alguém voltar lá |
| Bem com área de carga que não existe na planilha (área 1205) | 12 linhas, 6 bens por exercício | Fica na fato, com a área "Área não cadastrada" (`-1`) | O bem existe e precisa ser cobrado. Descartar tiraria bens e valor do total sem ninguém saber |
| Área judicial sem região (1502) | 1 área, 58 bens em 2026 | "Não informada" | O bem está certo, o que falta é cadastro. Diferente de secretaria, que fica "Não se aplica" |
| Linha repetida no export e leitura reenviada pelo app | 4 e 12 | Descartadas | Não é registro inválido, é o mesmo registro duas vezes. Não há nada a tratar |

**Por que quarentena para as leituras, e não "Não informado".** Uma leitura sem bem não tem onde se pendurar na fato, porque o grão é o bem da carga. Criar um bem fictício para ela inflaria o total de bens em carga e baixaria a taxa de todo mundo.

**Por que não descartar.** São 24 leituras de trabalho de campo, e no módulo real esse é o caminho dos itens pendentes de aprovação (gestor, depois Coordenadoria). O teste singular `nenhuma_leitura_perdida` garante que toda leitura da Silver está na fato ou na quarentena. Se alguma sumir, o build falha.

**Quem decide o que fazer com a quarentena** é a Coordenadoria de Inventário: prazo para tratar, e se leitura corrigida volta como leitura nova ou como ajuste de carga.
