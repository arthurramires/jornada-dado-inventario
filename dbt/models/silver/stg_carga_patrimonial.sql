{{ config(location='../data/silver/stg_carga_patrimonial.parquet') }}

with fonte as (

    select * from {{ source('bronze', 'carga_patrimonial') }}

),

tipada as (

    select distinct
        try_cast(trim(exercicio) as integer) as exercicio,

        -- É o número da plaqueta. O export às vezes completa com zeros ("00123456") ou usa
        -- máscara ("123.456"). Guardamos só os dígitos, que é como o número também fica nas
        -- leituras; se os dois lados ficarem diferentes o join com a coleta não acha o bem.
        try_cast(nullif(regexp_replace(numero_patrimonio, '[^0-9]', '', 'g'), '') as bigint) as numero_patrimonio,

        trim(descricao_bem) as descricao_bem,
        try_cast(trim(codigo_area_carga) as integer) as codigo_area_carga,

        -- A maior parte vem em formato brasileiro ("1.234,56") e algumas linhas com ponto
        -- decimal ("1234.56"). Quando tem vírgula, a vírgula é o decimal e o ponto é milhar.
        case
            when valor_atual like '%,%'
                then try_cast(replace(replace(trim(valor_atual), '.', ''), ',', '.') as decimal(14, 2))
            else try_cast(trim(valor_atual) as decimal(14, 2))
        end as valor_atual,

        upper(trim(situacao_bem)) as situacao_bem

    from fonte

)

-- O export trouxe linhas repetidas. O distinct fica depois da tipagem para pegar também a
-- repetição que só difere na máscara do número ou na caixa da situação.
select *
from tipada
