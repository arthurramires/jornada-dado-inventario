# Jornada do dado: inventário patrimonial

Trabalho da disciplina de Gestão e Governança de Dados (Residência TJMS, FACOM/UFMS).

**Equipe:** Arthur Bueno, Sueli Joboji, André Kley e Henrique Chinaglia.

Nosso projeto na residência é o módulo de Inventário do `sgm-php`, a reescrita do inventário patrimonial que hoje roda no SGM em Delphi. Aqui aplicamos a jornada vista em aula aos dados desse domínio: carga patrimonial das áreas, leituras feitas pelo app de coleta e a planilha de áreas da Coordenadoria.

Os dados são sintéticos. As comarcas existem em MS, mas áreas, circunscrições, números de patrimônio, valores e logins foram gerados por `scripts/gerar_fontes.py`. Nada saiu do banco do Tribunal.

## A pergunta

> Qual a taxa de localização dos bens no inventário anual, por região, comarca e exercício? E quanto em valor ficou sem ser encontrado?

É a pergunta do relatório de coleta que o módulo precisa entregar para a Coordenadoria de Inventário: quantos bens cada área tinha em carga, quantos foram localizados e quantos não.

- **Métrica derivada:** `taxa de localização = bens localizados na própria área / bens ativos em carga`. Nenhuma fonte traz essa taxa, e nenhuma fonte diz sequer se um bem foi localizado. Isso sai do cruzamento da carga (CSV) com as leituras (JSON), depois de normalizar o número de patrimônio, que cada fonte escreve de um jeito.
- **Recortes:** exercício, região (circunscrição), comarca e área. Como apoio: onde o bem foi encontrado e como foi lido (leitor, celular ou digitação).

## A resposta

`python scripts/consultar.py consultas/resposta.sql`

| Exercício | Bens em carga | Localizados | Em outra área | Não localizados | Taxa | Valor não localizado |
|---|---:|---:|---:|---:|---:|---:|
| 2025 | 1.382 | 1.144 | 114 | 124 | 82,8% | R$ 230.749,79 |
| 2026 | 1.427 | 1.196 | 106 | 125 | 83,8% | R$ 213.567,54 |

O que esse número diz ao gestor, olhando por comarca em 2026:

- **Rio Brilhante tem a pior taxa (49,5%, era 63,2%), mas não está perdendo bens.** 37 dos 91 bens foram lidos nas varas de Dourados. O problema é carga desatualizada, e a ação é regularizar transferência, não abrir apuração. Pelo critério do SGM antigo, que conta bem em outra área como localizado, Rio Brilhante apareceria com 90,1% e ninguém olharia para lá.
- **Corumbá e Aquidauana têm o problema oposto:** poucos bens fora do lugar e muitos que ninguém achou (30 e 16 bens, R$ 47,2 mil e R$ 32,0 mil). Aqui cabe busca dirigida.
- **Corumbá aparece em duas linhas** na consulta por região porque uma das áreas está sem região na planilha. Preferimos mostrar "Não informada" a sumir com 58 bens.

## Arquitetura

```text
data/raw/          areas.xlsx · carga_patrimonial.csv · leituras/*.json   o que a origem entregou
   │  src/ingest.py (pandas, sem regra de negócio)
   ▼
data/bronze/       Delta Lake, tudo como texto, uma versão por arquivo recebido
   │  dbt + DuckDB (source)
   ▼
data/silver/       Parquet: tipado, padronizado, sem repetição
data/quarentena/   Parquet: leituras que não casam com nenhum bem da carga
   │  dbt (ref)
   ▼
data/gold/         Parquet: fato_bem_inventariado + dim_area + dim_origem_leitura
   │
   ▼
consultas/         SQL sobre a Gold
```

O porquê de cada camada, do grão e das escolhas sobre dado ambíguo e dado inválido está em [DECISOES.md](DECISOES.md). Os defeitos de cada fonte, com contagem, estão em [docs/anomalias-das-fontes.md](docs/anomalias-das-fontes.md).

## Como executar

Precisa de Python 3.10 a 3.13. Recomendamos o Python 3.12, que é a versão usada na integração contínua. O Python 3.14 ainda não é compatível com as dependências do dbt fixadas neste projeto. Também é preciso acesso à internet na primeira execução (pip e a extensão `delta` do DuckDB, que o dbt baixa sozinho).

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt

python -m src.pipeline             # raw -> bronze (Delta)
cd dbt
dbt build                          # seed, silver, quarentena, gold e testes
cd ..
python scripts/consultar.py consultas/resposta.sql
```

O `.env` é opcional; sem ele valem os caminhos de `.env.example`.

O repositório já vem com `data/bronze/` preenchido, porque o histórico Delta faz parte da entrega. Num clone novo a ingestão reconhece cada arquivo pelo hash e não grava nada. Para ver as camadas nascendo do zero:

```bash
python scripts/zerar.py            # apaga bronze, silver, quarentena, gold e dbt/target (pede confirmação)
python -m src.pipeline
cd dbt && dbt build
```

O que esperar:

| Comando | Resultado |
|---|---|
| `python -m src.pipeline` | `areas` (14 linhas), `carga_patrimonial` (2.835) e `leituras_coleta` com 3 versões (1.341 + 660 + 735) |
| `dbt build` | 7 modelos, 1 seed, 41 testes: `PASS=48 WARN=1` |
| `pytest` | 6 testes da ingestão |

O único aviso do `dbt build` é de propósito: 12 linhas da carga apontam para a área 1205, que não existe mais na planilha. O teste avisa sem travar, e a fato leva esses bens para "Área não cadastrada".

## Outros comandos

```bash
python scripts/consultar.py consultas/bronze.sql  # o Bronze guardando os defeitos como chegaram
python scripts/time_travel.py                     # histórico do Delta e a mesma consulta na versão anterior e na atual
python scripts/time_travel.py --versao 0          # compara a versão 0 com a atual
python scripts/time_travel.py --tabela areas      # histórico da planilha de áreas
python scripts/consultar.py consultas/analise.sql # critério antigo x novo, para onde foram os bens, quarentena
cd dbt && dbt docs generate && dbt docs serve     # documentação e DAG em http://localhost:8080
cd dbt && dbt docs generate --static              # target/static_index.html, abre sem servidor
pytest
```

`scripts/gerar_fontes.py` recria `data/raw/` com a mesma semente. Só rode se quiser regenerar as fontes: se algum byte mudar, o hash muda e a ingestão grava versões novas.

## Integração contínua

`.github/workflows/pipeline.yml` roda a cada push e pull request num runner limpo, que é o critério de aceite executado de verdade. Os passos:

1. instala o `requirements.txt` e zera as camadas;
2. roda a ingestão e roda de novo, conferindo que a segunda não grava nada;
3. `dbt build` e `dbt docs generate`;
4. pytest, a consulta da resposta e o time travel.

A documentação do dbt fica disponível como artefato do run.

## Problemas comuns

| Mensagem | Causa | O que fazer |
|---|---|---|
| `ModuleNotFoundError: No module named 'src'` | rodou `python src/pipeline.py` | `python -m src.pipeline`, da raiz |
| `Invalid value for '--profiles-dir'` ou `No dbt_project.yml found` | dbt rodado fora de `dbt/` | `cd dbt` |
| `DeltaKernel InvalidTableLocationError ... Path does not exist` | Bronze vazio | `python -m src.pipeline` antes do `dbt build` |
| `Failed to download extension "delta"` | sem internet na primeira execução | rodar uma vez com internet; a extensão fica em cache |
| `Could not set lock on file ... analytics.duckdb` | outro programa com o banco aberto | fechar DBeaver, notebook ou outro dbt |
| `No files found that match the pattern "data/gold/...` | consulta antes do `dbt build` | rodar o `dbt build` |
| `OSError: [Errno 98] Address already in use` | porta 8080 ocupada | `dbt docs serve --port 8081` |
| `unsupported operand type(s) for \|` | Python anterior ao 3.10 | usar Python 3.10 ou mais novo |
| `mashumaro.exceptions.UnserializableField` ao iniciar o dbt | Python 3.14 | recriar o ambiente virtual com Python 3.12 ou 3.13 |

## Estrutura

```text
├── .github/workflows/pipeline.yml   CI: refaz tudo do zero a cada push
├── data/
│   ├── raw/                  fontes (versionadas)
│   ├── bronze/               Delta, gravado pela ingestão (versionado, é o histórico)
│   ├── silver/  quarentena/  gold/   Parquet gravado pelo dbt (gerado)
├── src/
│   ├── ingest.py             leitura de xlsx, csv e json; gravação Delta idempotente
│   └── pipeline.py           python -m src.pipeline
├── dbt/
│   ├── models/sources.yml    Bronze como source, lido com delta_scan
│   ├── models/silver/        stg_areas, stg_carga_patrimonial, stg_leituras
│   ├── models/quarentena/    qrt_leituras_rejeitadas
│   ├── models/gold/          fato_bem_inventariado, dim_area, dim_origem_leitura
│   ├── seeds/                de-para da origem de leitura
│   ├── macros/               nome_proprio (caixa de nomes de comarca)
│   └── tests/                testes singulares: grão, situação exclusiva, nenhuma leitura perdida
├── consultas/
│   ├── resposta.sql          a resposta da pergunta
│   ├── analise.sql           apoio para a apresentação
│   └── bronze.sql            o Bronze guardando os defeitos (não é a resposta)
├── scripts/                  gerar_fontes, zerar, time_travel, consultar
├── tests/                    pytest da ingestão
├── docs/anomalias-das-fontes.md
└── DECISOES.md
```
