{{ config(location='../data/silver/stg_areas.parquet') }}

with fonte as (

    select * from {{ source('bronze', 'areas') }}

),

tipada as (

    select
        try_cast(trim(codigo_area) as integer) as codigo_area,
        trim(regexp_replace(nome_area, '\s+', ' ', 'g')) as nome_area,

        -- A planilha é preenchida à mão e o tipo aparece como "JUDICIAL", "judicial ", "Adm.".
        -- No SGM só existem dois tipos de área, então basta olhar o começo da palavra.
        case
            when lower(trim(tipo_area)) like 'jud%' then 'Judicial'
            when lower(trim(tipo_area)) like 'adm%' then 'Administrativa'
        end as tipo_area,

        -- Tiramos o prefixo "Comarca de" e padronizamos maiúsculas e espaços. Sem isso,
        -- "Dourados", " dourados" e "Comarca de Dourados" viram três comarcas no group by.
        nullif({{ nome_proprio("regexp_replace(comarca, '^\\s*comarca\\s+de\\s+', '', 'i')") }}, '') as comarca,

        nullif(trim(regiao), '') as regiao,

        -- Parte das células é data de verdade (chega como "2026-02-10 00:00:00") e parte foi
        -- digitada como texto "03/03/2026".
        coalesce(
            try_cast(atualizado_em as timestamp)::date,
            try_strptime(trim(atualizado_em), '%d/%m/%Y')::date
        ) as atualizado_em

    from fonte

)

select
    codigo_area,
    nome_area,
    tipo_area,
    comarca,
    regiao,
    atualizado_em
from tipada
-- O código 1301 aparece duas vezes: uma linha antiga colada de um export do SGM (sem acento e
-- sem região) e a linha atual. Fica a mais recente pela coluna atualizado_em, porque a planilha
-- é mantida viva pela Coordenadoria. Com datas iguais a escolha seria arbitrária e precisaria
-- voltar para eles.
qualify row_number() over (partition by codigo_area order by atualizado_em desc) = 1
