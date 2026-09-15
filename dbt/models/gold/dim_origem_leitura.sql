{{ config(location='../data/gold/dim_origem_leitura.parquet') }}

select distinct
    origem_leitura,
    tipo_captura
from {{ ref('de_para_origem_leitura') }}
