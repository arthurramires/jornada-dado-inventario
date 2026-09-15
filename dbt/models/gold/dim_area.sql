{{ config(location='../data/gold/dim_area.parquet') }}

select
    codigo_area as area_id,
    nome_area,
    tipo_area,
    -- Secretaria não pertence a comarca nem a circunscrição. "Não se aplica" é diferente de
    -- "Não informada": o primeiro está certo, o segundo é buraco na planilha que alguém precisa preencher.
    case when tipo_area = 'Administrativa' then 'Não se aplica' else coalesce(comarca, 'Não informada') end as comarca,
    case when tipo_area = 'Administrativa' then 'Não se aplica' else coalesce(regiao, 'Não informada') end as regiao
from {{ ref('stg_areas') }}

union all

-- Linha para bem cuja área de carga não existe mais na planilha (área extinta ou código errado).
-- Com ela o bem continua contando no inventário em vez de sumir no join.
select -1, 'Área não cadastrada', 'Não informado', 'Não informada', 'Não informada'
