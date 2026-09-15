# Defeitos das fontes

Os defeitos foram colocados de propósito pelo gerador (`scripts/gerar_fontes.py`), imitando o que vemos no SGM e no app de coleta. As contagens foram feitas nos arquivos de `data/raw/`, não no gerador.

## areas.xlsx (14 linhas para 13 áreas)

Planilha mantida à mão pela Coordenadoria de Patrimônio.

| # | Defeito | Onde | Tratado em |
|---|---|---|---|
| 1 | Código duplicado: 1301 aparece duas vezes, uma delas é uma linha antiga sem acento e sem região | linha 11 | `stg_areas.sql`: fica a de `atualizado_em` mais recente |
| 2 | `tipo_area` em seis grafias: `Judicial`, `JUDICIAL`, `judicial`, `judicial `, `Adm.`, `ADMINISTRATIVA` | 13 linhas | `stg_areas.sql`: `case` pelo começo da palavra |
| 3 | `comarca` com prefixo "Comarca de" (3), toda em maiúscula (3), minúscula ou com espaço (2) | 8 linhas | `stg_areas.sql`, macro `nome_proprio` |
| 4 | `regiao` em branco numa área judicial (1502, Corumbá) | 1 linha | `dim_area.sql`: "Não informada" |
| 5 | `comarca` e `regiao` em branco nas secretarias. Não é erro, secretaria não tem comarca | 2 linhas | `dim_area.sql`: "Não se aplica" |
| 6 | `atualizado_em` mistura célula de data com texto `dd/mm/aaaa` | 3 linhas em texto | `stg_areas.sql`: `coalesce` dos dois formatos |

## carga_patrimonial.csv (2.835 linhas)

Export do SGM com ponto e vírgula e codificação latin-1. A codificação é resolvida na ingestão; o resto, na Silver.

| # | Defeito | Linhas | Tratado em |
|---|---|---:|---|
| 7 | Número de patrimônio com zeros à esquerda (`00123456`) | 152 | `stg_carga_patrimonial.sql`: só dígitos |
| 8 | Número de patrimônio com máscara (`123.456`) | 141 | idem |
| 9 | Valor com ponto decimal (`1234.56`) no meio do formato brasileiro (`1.234,56`) | 282 | `stg_carga_patrimonial.sql`: vírgula manda |
| 10 | Situação `Ativo` em vez de `ATIVO` | 436 | `stg_carga_patrimonial.sql`: `upper(trim())` |
| 11 | Linhas repetidas | 4 | `stg_carga_patrimonial.sql`: `distinct` depois da tipagem |
| 12 | Área de carga 1205, que não existe na planilha | 12 | `fato_bem_inventariado.sql`: área `-1`. Teste `relationships` com `warn` na Silver |

Não é defeito: 22 bens com situação BAIXADO (11 por exercício). Ficam fora da fato por regra.

## leituras/*.json (2.736 leituras em 3 lotes)

Export do app de coleta. Cada arquivo tem um envelope (`sistema`, `exercicio`, `gerado_em`) e a lista `leituras`, com o local aninhado em `local.codigo_area` e `local.espaco_fisico`.

| # | Defeito | 2025 | 2026 parte 1 | 2026 parte 2 | Tratado em |
|---|---|---:|---:|---:|---|
| 13 | Número com zeros à esquerda (leitor de código de barras) | 675 | 372 | 357 | `stg_leituras.sql`: só dígitos |
| 14 | Número com espaços | 57 | 18 | 36 | idem |
| 15 | Número com máscara | 46 | 9 | 20 | idem |
| 16 | Número vazio | 3 | 3 | 0 | Quarentena, `patrimonio_ausente` |
| 17 | Número que não existe na carga do exercício | 9 | 3 | 6 | Quarentena, `fora_da_carga` |
| 18 | Data em `dd/mm/aaaa hh:mm` (backoffice) no meio do ISO | 110 | 32 | 42 | `stg_leituras.sql`: `coalesce` dos dois formatos |
| 19 | Origem `scanner`, nome antigo da câmera do celular | 506 | 0 | 0 | seed `de_para_origem_leitura` |
| 20 | Origem `mobile_celular` / `mobile_manual` (app PWA) | 0 | 78 | 122 | idem |
| 21 | Origem nula | 0 | 5 | 7 | `stg_leituras.sql`: `nao_informada` |
| 22 | Leitura reenviada: mesmo `id_leitura` na parte 1 e na parte 2 | 0 | 0 | 12 | `stg_leituras.sql`: fica a primeira chegada |

## Entre as fontes

Estes não aparecem olhando um arquivo sozinho.

| # | Situação | Quantos | O que fizemos |
|---|---|---:|---|
| 23 | Bem lido numa área diferente da área de carga | 114 em 2025, 106 em 2026 | Situação própria, não conta como localizado. Decisão 3 do `DECISOES.md` |
| 24 | Bem lido mais de uma vez no mesmo exercício | 140 (17 terminam em outra área) | Vale a última leitura |
| 25 | Em 2025 o leitor de código de barras foi gravado como `manual` | 675 leituras | Não tratado. Documentado: tipo de captura de 2025 não é comparável com 2026 |
| 26 | Bens da área extinta 1205 lidos nas varas de Dourados | 4 em 2025, 5 em 2026 | Entram como "em outra área", com área de carga "Área não cadastrada" |

## Como ver os defeitos

```bash
python -c "import duckdb; print(duckdb.sql(\"select * from read_csv('data/raw/carga_patrimonial.csv', delim=';', all_varchar=true, encoding='latin-1') where numero_patrimonio like '%.%' limit 5\"))"
python -c "import duckdb; print(duckdb.sql(\"select l.* from (select unnest(leituras) l from read_json('data/raw/leituras/leituras_2026_parte1.json')) where l.origem_leitura is null\"))"
```
